import 'dart:io';
import 'package:camera/camera.dart';
import '../database/db_helper.dart';
import 'crypto_service.dart';

/// Toma una foto silenciosa con la cámara frontal cuando se ingresa el
/// PIN incorrecto demasiadas veces. El permiso de cámara debe pedirse de
/// antemano (al activar el switch en Ajustes), nunca en el momento de la
/// captura: pedirlo aquí mostraría el diálogo del sistema y delataría al
/// intruso.
class IntruderService {
  static final IntruderService instance = IntruderService._();
  IntruderService._();

  final _crypto = CryptoService();
  final _db = DBHelper.instance;
  bool _capturing = false;

  Future<void> captureSilently() async {
    if (_capturing) return;
    _capturing = true;
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      controller = CameraController(
        front,
        ResolutionPreset.low,
        enableAudio: false,
      );
      await controller.initialize();
      final shot = await controller.takePicture();

      final encPath =
          await _crypto.encryptAndSave(File(shot.path), 'intruder.jpg');
      try {
        await File(shot.path).delete();
      } catch (_) {}

      await _db.insertIntruder({
        'encrypted_path': encPath,
        'captured_at': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {
      // Silencioso a propósito: sin cámara, sin permiso o cualquier otro
      // fallo no debe interrumpir ni delatar el intento de desbloqueo.
    } finally {
      await controller?.dispose();
      _capturing = false;
    }
  }
}
