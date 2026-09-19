import 'dart:io';
import 'dart:ui' as ui;
import 'thumbnail_cache.dart';
import 'device_gallery.dart';
import 'media_transfer_service.dart';
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
  final _transfers = MediaTransferService(
    crypto: CryptoService(),
    repository: DBHelper.instance,
    gallery: DeviceGallery(),
    temporaryDirectory: getTemporaryDirectory,
  );
  final Map<String, Uint8List> _photoBytesCache = {};
  final _thumbnails = ThumbnailCache();

  static const int _maxOriginalBytes = 32 * 1024 * 1024;
  int _originalBytes = 0;

  static const _videoExtensions = [
    'mp4',
    'mov',
    'avi',
    'mkv',
    'webm',
    '3gp',
    'flv'
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

  Future<bool> requestPermission() => DeviceGallery().requestAccess();

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

    final filtered =
        {for (final album in albums) album.id: album}.values.toList();

    filtered.sort((a, b) {
      if (a.isAll) return -1;
      if (b.isAll) return 1;
      return a.name.compareTo(b.name);
    });

    return filtered;
  }

  // ── Assets de un álbum ───────────────────────────────────
  Future<List<AssetEntity>> getAlbumAssets(AssetPathEntity album) async {
    final count = await album.assetCountAsync;
    if (count == 0) return [];
    return MediaTransferService.uniqueAssets(
        await album.getAssetListRange(start: 0, end: count));
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
    final assets = await albums.first.getAssetListRange(start: 0, end: count);
    return MediaTransferService.uniqueAssets(assets);
  }

  // ── Importar assets al vault ─────────────────────────────
  Future<TransferResult> importAssets({
    required List<AssetEntity> assets,
    required int folderId,
    required void Function(int current, int total) onProgress,
  }) async {
    await _ensureNomedia();
    final result = await _transfers.importAssets(
        assets: assets, folderId: folderId, onProgress: onProgress);
    clearThumbnailCaches();
    return result;
  }

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

  void clearThumbnailCaches() {
    _photoBytesCache.clear();
    _originalBytes = 0;
    _thumbnails.clear();
  }

  // ── Obtener bytes desencriptados ─────────────────────────
  Future<Uint8List?> getPhotoBytes(String encryptedPath) async {
    final key = encryptedPath;
    final cached = _photoBytesCache.remove(key);
    if (cached != null) {
      _photoBytesCache[key] = cached;
      return cached;
    }

    try {
      final bytes = await _crypto.decryptFile(encryptedPath);
      if (bytes.lengthInBytes <= _maxOriginalBytes) {
        final old = _photoBytesCache.remove(key);
        if (old != null) _originalBytes -= old.lengthInBytes;
        while (_photoBytesCache.isNotEmpty &&
            (_originalBytes + bytes.lengthInBytes > _maxOriginalBytes ||
                _photoBytesCache.length >= 4)) {
          _originalBytes -= _photoBytesCache
              .remove(_photoBytesCache.keys.first)!
              .lengthInBytes;
        }
        _photoBytesCache[key] = bytes;
        _originalBytes += bytes.lengthInBytes;
      }
      return bytes;
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
  Future<TransferResult> unlockPhotos(List<Map<String, dynamic>> photos) async {
    final result = await _transfers.unlockPhotos(photos);
    clearThumbnailCaches();
    return result;
  }

  Uint8List? cachedThumbnail(String path, {required bool video}) =>
      _thumbnails.peek('${video ? 'video' : 'photo'}:$path');

  Future<Uint8List?> getPhotoThumbnail(String encryptedPath,
          {bool Function()? isNeeded}) =>
      _thumbnails.load('photo:$encryptedPath', () async {
        final bytes = await _crypto.decryptFile(encryptedPath);
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        ui.ImageDescriptor? descriptor;
        ui.Codec? codec;
        ui.Image? image;
        try {
          descriptor = await ui.ImageDescriptor.encoded(buffer);
          final largest = descriptor.width > descriptor.height
              ? descriptor.width
              : descriptor.height;
          final scale = largest > 512 ? 512 / largest : 1.0;
          codec = await descriptor.instantiateCodec(
            targetWidth: (descriptor.width * scale).round().clamp(1, 512),
            targetHeight: (descriptor.height * scale).round().clamp(1, 512),
          );
          image = (await codec.getNextFrame()).image;
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          return data?.buffer
              .asUint8List(data.offsetInBytes, data.lengthInBytes);
        } finally {
          image?.dispose();
          codec?.dispose();
          descriptor?.dispose();
          buffer.dispose();
        }
      }, isNeeded: isNeeded);

  Future<Uint8List?> getVideoThumbnail(
          String encryptedPath, String originalName,
          {bool Function()? isNeeded}) =>
      _thumbnails.load('video:$encryptedPath', () async {
        final bytes = await _crypto.decryptFile(encryptedPath);
        final tempDir =
            await (await getTemporaryDirectory()).createTemp('sg_thumb_');
        try {
          final tempFile = File(p.join(tempDir.path, p.basename(originalName)));
          await tempFile.writeAsBytes(bytes);
          return await VideoThumbnail.thumbnailData(
            video: tempFile.path,
            imageFormat: ImageFormat.JPEG,
            maxWidth: 320,
            quality: 65,
          );
        } finally {
          await tempDir.delete(recursive: true);
        }
      }, isNeeded: isNeeded);
}
