import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../database/db_helper.dart';
import '../security/crypto_service.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class MediaService {
  static final MediaService instance = MediaService._();
  MediaService._();

  final _crypto = CryptoService();
  final _db = DBHelper.instance;

  static const _videoExtensions = [
    'mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', 'flv'
  ];

  /// Detecta si un archivo encriptado es un video a partir de su propio
  /// nombre (encryptAndSave lo guarda como `{timestamp}_{originalName}.enc`,
  /// así que la extensión original queda embebida en la ruta). Útil cuando
  /// solo se tiene `encrypted_path` y no el `original_name` por separado
  /// (por ejemplo, la portada de una carpeta).
  static bool isVideoPath(String encryptedPath) {
    final withoutEnc = encryptedPath.toLowerCase().endsWith('.enc')
        ? encryptedPath.substring(0, encryptedPath.length - 4)
        : encryptedPath;
    final ext = withoutEnc.split('.').last.toLowerCase();
    return _videoExtensions.contains(ext);
  }

  Future<bool> requestPermission() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth && !permission.hasAccess) {
      await PhotoManager.openSetting();
    }
    return permission.isAuth || permission.hasAccess;
  }

  // ── Álbumes de galería ───────────────────────────────────
  Future<List<AssetPathEntity>> getGalleryAlbums({
    RequestType type = RequestType.image,
  }) async {
    final albums = await PhotoManager.getAssetPathList(
      type: type,
      hasAll: true,
      onlyAll: false,
      filterOption: FilterOptionGroup(
        imageOption: const FilterOption(
          sizeConstraint: SizeConstraint(ignoreSize: true),
        ),
        videoOption: const FilterOption(
          sizeConstraint: SizeConstraint(ignoreSize: true),
        ),
        orders: [
          const OrderOption(
            type: OrderOptionType.createDate,
            asc: false,
          ),
        ],
      ),
    );

    albums.sort((a, b) {
      if (a.isAll) return -1;
      if (b.isAll) return 1;
      return a.name.compareTo(b.name);
    });

    return albums;
  }

  // ── Assets de un álbum ───────────────────────────────────
  Future<List<AssetEntity>> getAlbumAssets(AssetPathEntity album) async {
    final count = await album.assetCountAsync;
    if (count == 0) return [];
    return await album.getAssetListRange(start: 0, end: count);
  }

  // ── Todas las imágenes ───────────────────────────────────
  Future<List<AssetEntity>> getGalleryImages() async {
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      hasAll: true,
      onlyAll: true,
    );
    if (albums.isEmpty) return [];
    final count = await albums.first.assetCountAsync;
    if (count == 0) return [];
    return await albums.first.getAssetListRange(start: 0, end: count);
  }

  // ── Importar assets al vault ─────────────────────────────
  Future<void> importAssets({
    required List<AssetEntity> assets,
    required int folderId,
    required void Function(int current, int total) onProgress,
  }) async {
    await _ensureNomedia();

    for (int i = 0; i < assets.length; i++) {
      final asset = assets[i];
      final file = await asset.originFile;
      if (file == null) {
        onProgress(i + 1, assets.length);
        continue;
      }

      try {
        final encPath = await _crypto.encryptAndSave(
            file, asset.title ?? 'file_$i');

        await _db.insertPhoto({
          'folder_id': folderId,
          'original_name': asset.title ?? 'file_$i',
          'encrypted_path': encPath,
          'original_path': file.path,
          'date_added': DateTime.now().millisecondsSinceEpoch,
        });

        await PhotoManager.editor.deleteWithIds([asset.id]);
      } catch (e) {
        debugPrint('Error importando archivo $i: $e');
      }

      onProgress(i + 1, assets.length);
    }

    await PhotoManager.clearFileCache();
  }

  // ── Nomedia ──────────────────────────────────────────────
  Future<void> _ensureNomedia() async {
    final dir = await _getVaultDir();
    final nomedia = File(p.join(dir.path, '.nomedia'));
    if (!await nomedia.exists()) {
      await nomedia.create();
    }
  }

  Future<Directory> _getVaultDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, '.sg_vault'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ── Obtener bytes desencriptados ─────────────────────────
  Future<Uint8List?> getPhotoBytes(String encryptedPath) async {
    try {
      return await _crypto.decryptFile(encryptedPath);
    } catch (_) {
      return null;
    }
  }

  // ── Eliminar archivo encriptado del vault ────────────────
  Future<void> deleteEncryptedFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('Error eliminando archivo: $e');
    }
  }

  // ── Eliminar foto del vault ──────────────────────────────
  Future<void> deletePhoto(Map<String, dynamic> photo) async {
    await _db.clearCoverIfDeleted(photo['encrypted_path']);
    await deleteEncryptedFile(photo['encrypted_path']);
    await _db.deletePhoto(photo['id']);
  }

  // ── Eliminar carpeta y todo su contenido ─────────────────
  Future<void> deleteFolder(int folderId) async {
    final paths = await _db.getEncryptedPathsInFolder(folderId);
    for (final path in paths) {
      await deleteEncryptedFile(path);
    }
    await _db.deleteFolder(folderId);
  }

  // ── Desbloquear y restaurar a galería ───────────────────
  static const _unlockRelativePath = 'DCIM/Secret Gallery HD';

  bool _isVideoFile(String name) {
    final ext = name.split('.').last.toLowerCase();
    return ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'].contains(ext);
  }

  Future<void> unlockPhotos(List<Map<String, dynamic>> photos) async {
    for (final photo in photos) {
      try {
        final bytes =
            await _crypto.decryptFile(photo['encrypted_path']);

        final dir = Directory('/storage/emulated/0/$_unlockRelativePath');
        if (!await dir.exists()) await dir.create(recursive: true);

        final fileName = photo['original_name'] ??
            'file_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final destFile = File('${dir.path}/$fileName');
        await destFile.writeAsBytes(bytes);

        if (_isVideoFile(fileName)) {
          await PhotoManager.editor.saveVideo(
            destFile,
            title: fileName,
            relativePath: _unlockRelativePath,
          );
        } else {
          await PhotoManager.editor.saveImageWithPath(
            destFile.path,
            title: fileName,
            relativePath: _unlockRelativePath,
          );
        }

        await deleteEncryptedFile(photo['encrypted_path']);
        await _db.deletePhoto(photo['id']);
      } catch (e) {
        debugPrint('Error desbloqueando archivo: $e');
      }
    }
    await PhotoManager.clearFileCache();
  }

  // ── Miniatura de video ───────────────────────────────────
  Future<Uint8List?> getVideoThumbnail(
      String encryptedPath, String originalName) async {
    try {
      final bytes = await _crypto.decryptFile(encryptedPath);
      final tempDir = await getTemporaryDirectory();
      final tempPath = p.join(tempDir.path, 'thumb_$originalName');
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(bytes);

      final thumbnail = await VideoThumbnail.thumbnailData(
        video: tempFile.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 300,
        quality: 75,
      );

      await tempFile.delete().catchError((_) {});
      return thumbnail;
    } catch (e) {
      debugPrint('Error generando miniatura: $e');
      return null;
    }
  }
}