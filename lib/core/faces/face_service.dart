import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../services/media_service.dart';
import 'face_matcher.dart';

typedef FaceVector = ({double area, Float32List vector});

/// Detecta rostros (ML Kit) y calcula su huella (FaceNet, 128 valores).
/// Todo corre en el teléfono; nada se envía a internet.
class FaceService {
  FaceService._();
  static final FaceService instance = FaceService._();

  static const _modelAsset = 'assets/models/facenet.tflite';
  static const _inputSize = 160;
  static const _embeddingSize = 128;
  static const _maxSide = 960;
  static const _maxFacesPerPhoto = 8;
  static const _minFacePixels = 48;
  static const _maxYaw = 40.0;

  // Segundo intento para fotos donde no se encontró ningún rostro.
  static const _deepMaxSide = 1920;
  static const _deepMinFacePixels = 32;
  static const _deepMaxYaw = 60.0;

  Interpreter? _interpreter;
  FaceDetector? _detector;
  FaceDetector? _deepDetector;

  Future<void>? _loading;

  /// Varias fotos se analizan a la vez: el modelo debe cargarse una sola vez.
  Future<void> _ensureReady() {
    if (_interpreter != null) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    final interpreter = await Interpreter.fromAsset(_modelAsset,
        options: InterpreterOptions()..threads = 2);
    final input = interpreter.getInputTensor(0).shape;
    final output = interpreter.getOutputTensor(0).shape;
    if (input.length != 4 ||
        input[1] != _inputSize ||
        input[2] != _inputSize ||
        input[3] != 3 ||
        output.last != _embeddingSize) {
      interpreter.close();
      throw StateError('Modelo facial inesperado: $input -> $output');
    }
    _interpreter = interpreter;
    _detector = FaceDetector(
        options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.04,
    ));
    _deepDetector = FaceDetector(
        options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.02,
    ));
  }

  Future<void> dispose() async {
    _interpreter?.close();
    _interpreter = null;
    await _detector?.close();
    _detector = null;
    await _deepDetector?.close();
    _deepDetector = null;
  }

  /// Rostros válidos de una foto de la bóveda, o null si no se pudo leer.
  /// Lista vacía = sin rostro visible (de espaldas, tapado, muy pequeño...).
  Future<List<FaceVector>?> analyzePhoto(String encryptedPath,
      {bool deep = false}) async {
    await _ensureReady();
    final bytes = await MediaService.instance.getPhotoBytes(encryptedPath);
    if (bytes == null) return null;

    ui.Image? image;
    Directory? tempDir;
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final maxSide = deep ? _deepMaxSide : _maxSide;
      final longest = math.max(descriptor.width, descriptor.height);
      final codec = longest > maxSide
          ? await descriptor.instantiateCodec(
              targetWidth: descriptor.width >= descriptor.height ? maxSide : null,
              targetHeight: descriptor.height > descriptor.width ? maxSide : null)
          : await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      image = frame.image;
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();

      // ML Kit lee un archivo. Se escribe una copia reducida en el caché
      // privado de la app y se borra de inmediato.
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return null;
      tempDir = await (await getTemporaryDirectory()).createTemp('sg_face_');
      final file = File(p.join(tempDir.path, 'f.png'));
      await file.writeAsBytes(png.buffer.asUint8List(), flush: false);
      final faces = await (deep ? _deepDetector! : _detector!)
          .processImage(InputImage.fromFilePath(file.path));

      final minPixels = deep ? _deepMinFacePixels : _minFacePixels;
      final maxYaw = deep ? _deepMaxYaw : _maxYaw;
      final usable = faces.where((f) {
        final yaw = f.headEulerAngleY ?? 0;
        return f.boundingBox.width >= minPixels &&
            f.boundingBox.height >= minPixels &&
            yaw.abs() <= maxYaw;
      }).toList()
        ..sort((a, b) => (b.boundingBox.width * b.boundingBox.height)
            .compareTo(a.boundingBox.width * a.boundingBox.height));

      final total = (image.width * image.height).toDouble();
      final result = <FaceVector>[];
      for (final face in usable.take(_maxFacesPerPhoto)) {
        final vector = await _embed(image, face.boundingBox);
        if (vector == null) continue;
        result.add((
          area: face.boundingBox.width * face.boundingBox.height / total,
          vector: vector,
        ));
      }
      return result;
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      if (tempDir != null) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<Float32List?> _embed(ui.Image image, ui.Rect box) async {
    final side = math.max(box.width, box.height) * 1.1;
    final src = ui.Rect.fromCenter(center: box.center, width: side, height: side);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      image,
      src,
      ui.Rect.fromLTWH(0, 0, _inputSize.toDouble(), _inputSize.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    final crop = await picture.toImage(_inputSize, _inputSize);
    picture.dispose();
    final data = await crop.toByteData(format: ui.ImageByteFormat.rawRgba);
    crop.dispose();
    if (data == null) return null;
    final rgba = data.buffer.asUint8List();

    // Estandarización por imagen: (x - media) / desviación, como en el
    // preprocesado original del modelo.
    const n = _inputSize * _inputSize * 3;
    final pixels = Float32List(n);
    var j = 0;
    var sum = 0.0;
    for (var i = 0; i < rgba.length; i += 4) {
      pixels[j++] = rgba[i].toDouble();
      pixels[j++] = rgba[i + 1].toDouble();
      pixels[j++] = rgba[i + 2].toDouble();
    }
    for (final v in pixels) {
      sum += v;
    }
    final mean = sum / n;
    var sq = 0.0;
    for (final v in pixels) {
      sq += (v - mean) * (v - mean);
    }
    final std = math.max(math.sqrt(sq / n), 1 / math.sqrt(n));
    for (var i = 0; i < n; i++) {
      pixels[i] = (pixels[i] - mean) / std;
    }

    final input = pixels.reshape([1, _inputSize, _inputSize, 3]);
    final output = List.generate(1, (_) => List<double>.filled(_embeddingSize, 0));
    _interpreter!.run(input, output);
    final vector = normalize(output[0]);
    // Un vector nulo o con valores no numéricos no sirve para comparar.
    if (vector.any((v) => v.isNaN) || vector.every((v) => v == 0)) return null;
    return vector;
  }
}
