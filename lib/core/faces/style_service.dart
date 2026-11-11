import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../services/media_service.dart';
import 'style_matcher.dart';

/// Calcula el descriptor de estilo de una foto de la bóveda. Decodifica una
/// miniatura de [styleThumbSide] píxeles; no escribe nada en disco.
class StyleService {
  StyleService._();
  static final StyleService instance = StyleService._();

  /// Descriptor de la foto, o null si no se pudo leer.
  Future<Float32List?> describePhoto(String encryptedPath) async {
    final bytes = await MediaService.instance.getPhotoBytes(encryptedPath);
    if (bytes == null) return null;
    ui.Image? image;
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width, h = descriptor.height;
      if (w <= 0 || h <= 0) {
        descriptor.dispose();
        buffer.dispose();
        return null;
      }
      final scale = styleThumbSide / math.max(w, h);
      final codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (w * scale).round()),
        targetHeight: math.max(1, (h * scale).round()),
      );
      final frame = await codec.getNextFrame();
      image = frame.image;
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      return describeRgba(
          data.buffer.asUint8List(), image.width, image.height, w / h);
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
    }
  }
}
