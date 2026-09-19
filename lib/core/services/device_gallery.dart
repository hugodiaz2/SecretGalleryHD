import 'dart:io';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'lifecycle_guard.dart';
import 'media_transfer_service.dart';

class DeviceGallery implements TransferGallery {
  static const _channel = MethodChannel('secret_gallery/media');
  int? _cachedSdk;

  Future<int> _androidSdk() async {
    final cached = _cachedSdk;
    if (cached != null) return cached;
    final sdk = await _channel.invokeMethod<int>('sdkInt');
    if (sdk == null)
      throw StateError('No se pudo consultar la versión de Android.');
    _cachedSdk = sdk;
    return sdk;
  }

  @override
  Future<bool> requestAccess() => LifecycleGuard.run(() async {
        final permission = await PhotoManager.requestPermissionExtend();
        if (!permission.hasAccess) return false;
        if (Platform.isAndroid) {
          final sdk = await _androidSdk();
          if (sdk <= 28 && !await Permission.storage.request().isGranted) {
            return false;
          }
        }
        return true;
      });

  @override
  Future<File?> original(AssetEntity asset) => asset.originFile;

  @override
  Future<AssetEntity?> find(String id) => AssetEntity.fromId(id);

  @override
  Future<AssetEntity?> findByName(String name) async {
    final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common, hasAll: true, onlyAll: true);
    if (albums.isEmpty) return null;
    final album = albums.first;
    final count = await album.assetCountAsync;
    for (var start = 0; start < count; start += 200) {
      final page = await album.getAssetListRange(
          start: start, end: start + 200 < count ? start + 200 : count);
      for (final asset in page) {
        if (asset.title == name) return asset;
      }
    }
    return null;
  }

  @override
  Future<AssetEntity> publish(File source, String name, bool video) async {
    if (Platform.isAndroid) {
      final sdk = await _androidSdk();
      if (sdk <= 28) {
        // Legacy Android needs a single public copy followed by a scan, not
        // a scan plus an insert. Modern Android uses MediaStore exclusively.
        final id = await _channel.invokeMethod<String>('publishLegacy', {
          'source': source.path,
          'name': name,
        });
        final asset = id == null ? null : await find(id);
        if (asset == null) {
          throw StateError('No se pudo registrar el archivo público.');
        }
        return asset;
      }
    }
    return video
        ? PhotoManager.editor
            .saveVideo(source, title: name, relativePath: 'DCIM/Secret')
        : PhotoManager.editor.saveImageWithPath(source.path,
            title: name, relativePath: 'DCIM/Secret');
  }

  @override
  Future<List<String>> delete(List<String> ids) =>
      LifecycleGuard.run(() => PhotoManager.editor.deleteWithIds(ids));
}
