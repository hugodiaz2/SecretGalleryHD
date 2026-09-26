import 'dart:io';
import 'vault_activity.dart';
import 'dart:math';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';
import 'package:pointycastle/digests/sha256.dart';
import '../security/crypto_service.dart';

abstract class TransferRepository {
  Future<Map<String, dynamic>?> findImported(String assetId, String digest);
  Future<int> insertPhoto(Map<String, dynamic> data);
  Future<Map<String, dynamic>?> photoForTransfer(int id);
  Future<String> prepareExport(int id, String proposedName);
  Future<void> rememberExport(int id, String assetId);
  Future<void> finishExport(int id, String encryptedPath);
}

abstract class TransferGallery {
  Future<bool> requestAccess();
  Future<File?> original(AssetEntity asset);
  Future<AssetEntity?> find(String id);
  Future<AssetEntity?> findByName(String name);
  Future<AssetEntity> publish(File source, String name, bool video);
  Future<List<String>> delete(List<String> ids);
}

class TransferResult {
  final List<String> completed = [];
  final Map<String, String> failed = {};
  final List<String> publicRetained = [];
  final List<String> cleanupWarnings = [];

  String get importMessage =>
      '${completed.length} archivo(s) guardados y verificados en privado. '
      '${publicRetained.length} original(es) siguen en la galería pública. '
      '${failed.length} archivo(s) no se pudieron importar.';
  String get exportMessage =>
      '${completed.length} archivo(s) restaurados en Secret. '
      '${failed.length} archivo(s) conservados en privado por un error.'
      '${cleanupWarnings.isEmpty ? '' : ' No se pudieron limpiar algunos archivos temporales o cifrados.'}';
}

/// One queue for imports and exports. Public files are never used as staging.
/// Dependencies are replaceable to test failures without a real photo library.
class MediaTransferService {
  MediaTransferService({
    required this.crypto,
    required this.repository,
    required this.gallery,
    required this.temporaryDirectory,
  });

  final CryptoService crypto;
  final TransferRepository repository;
  final TransferGallery gallery;
  final Future<Directory> Function() temporaryDirectory;
  Future<void> _tail = Future<void>.value();
  final Map<int, String> _uncommittedExports = {};

  Future<T> _exclusive<T>(Future<T> Function() action) {
    if (VaultActivity.backup) {
      return Future<T>.error(StateError('Espera a que termine el respaldo.'));
    }
    VaultActivity.transfers++;
    final next = _tail.then((_) async {
      try {
        return await action();
      } finally {
        VaultActivity.transfers--;
      }
    });
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  // The outer queue still serializes user operations. Inside each operation,
  // at most two photos overlap; videos drain the queue and run alone.
  Future<void> _forEachMedia<T>(Iterable<T> items, bool Function(T) isVideo,
      Future<void> Function(T) action) async {
    final pending = <Future<void>>[];
    for (final item in items) {
      if (isVideo(item)) {
        await Future.wait(pending);
        pending.clear();
        await action(item);
      } else {
        pending.add(action(item));
        if (pending.length == 2) {
          await Future.wait(pending);
          pending.clear();
        }
      }
    }
    await Future.wait(pending);
  }

  // Keep both photo slots busy even if one image takes longer than its peer.
  // Videos still wait for photo work to drain and run alone.
  Future<void> _forEachExport(Iterable<Map<String, dynamic>> photos,
      Future<void> Function(Map<String, dynamic>) action) async {
    final running = <Future<void>>{};
    for (final photo in photos) {
      if (_isVideoName(photo['original_name'] as String? ?? '')) {
        await Future.wait(running);
        await action(photo);
      } else {
        while (running.length >= 2) {
          await Future.any(running);
        }
        late final Future<void> task;
        task = action(photo).whenComplete(() => running.remove(task));
        running.add(task);
      }
    }
    await Future.wait(running);
  }

  static bool _isVideoName(String name) => const [
        '.mp4',
        '.mov',
        '.avi',
        '.mkv',
        '.webm',
        '.3gp',
        '.flv',
      ].contains(p.extension(name).toLowerCase());

  static List<AssetEntity> uniqueAssets(Iterable<AssetEntity> assets) {
    final seen = <String>{};
    return assets.where((asset) => seen.add(asset.id)).toList();
  }

  static String digestBytes(Uint8List bytes) =>
      _hex(SHA256Digest().process(bytes));

  static String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Future<String> digestFile(File file) => CryptoService.hashFile(file);

  Future<TransferResult> importAssets({
    required List<AssetEntity> assets,
    required int folderId,
    required void Function(int current, int total) onProgress,
  }) =>
      _exclusive(() async {
        final result = TransferResult();
        final unique = uniqueAssets(assets);
        if (!await gallery.requestAccess()) {
          throw StateError(
              'No hay permiso para acceder a las fotos seleccionadas.');
        }
        final verified = <String, String>{};
        var current = 0;
        await _forEachMedia(unique, (asset) => asset.type == AssetType.video,
            (asset) async {
          String? newPath;
          var registered = false;
          try {
            final source = await gallery.original(asset);
            if (source == null ||
                !await source.exists() ||
                await source.length() == 0) {
              throw StateError('El original no está disponible.');
            }
            final digest = await digestFile(source);
            final existing = await repository.findImported(asset.id, digest);
            if (existing != null) {
              // A cancelled public deletion can be retried without a second copy.
              final privateDigest = await crypto
                  .prepareExportFile(existing['encrypted_path'] as String);
              if (privateDigest != digest) {
                throw StateError(
                    'La copia privada existente no pasó la verificación.');
              }
            } else {
              final name = p.basename(asset.title ?? source.path);
              newPath = await crypto.encryptAndSave(source, name);
              final privateDigest = await crypto.prepareExportFile(newPath);
              if (privateDigest != digest) {
                throw StateError(
                    'La copia privada no coincide con el original.');
              }
              await repository.insertPhoto({
                'folder_id': folderId,
                'original_name': name,
                'encrypted_path': newPath,
                'original_path': source.path,
                'source_asset_id': asset.id,
                'source_digest': digest,
                'date_added': DateTime.now().millisecondsSinceEpoch,
              });
              registered = true;
            }
            verified[asset.id] = digest;
            result.completed.add(asset.id);
          } catch (e) {
            result.failed[asset.id] = e.toString();
            if (newPath != null && !registered) {
              try {
                await crypto.deleteEncryptedFile(newPath);
              } catch (_) {}
            }
          } finally {
            onProgress(++current, unique.length);
          }
        });

        // Re-read before the system deletion request: an edited public asset must
        // not be deleted just because an older version was imported successfully.
        final deletable = <String>[];
        for (final asset in unique.where((a) => verified.containsKey(a.id))) {
          try {
            final current = await gallery.original(asset);
            if (current != null &&
                await digestFile(current) == verified[asset.id]) {
              deletable.add(asset.id);
            }
          } catch (_) {
            /* Keep the public original on any verification error. */
          }
        }
        var deleted = <String>{};
        if (deletable.isNotEmpty) {
          try {
            deleted = (await gallery.delete(deletable)).toSet();
          } catch (_) {}
        }
        result.publicRetained
            .addAll(verified.keys.where((id) => !deleted.contains(id)));
        return result;
      });

  Future<TransferResult> unlockPhotos(List<Map<String, dynamic>> photos) =>
      _exclusive(() async {
        final result = TransferResult();
        if (!await gallery.requestAccess()) {
          throw StateError(
              'No hay permiso para restaurar y verificar la galería.');
        }
        final seen = <int>{};
        await _forEachExport(
            photos.where((photo) => seen.add(photo['id'] as int)),
            (requested) async {
          final id = requested['id'] as int;
          Directory? staging;
          try {
            // Ignore stale requests after a preceding queued export finished.
            final photo = await repository.photoForTransfer(id);
            if (photo == null) return;
            final path = photo['encrypted_path'] as String;
            String? digest;
            final previousId = photo['exported_asset_id'] as String? ??
                _uncommittedExports[id];
            AssetEntity? published;
            if (previousId != null) {
              published = await gallery.find(previousId);
              if (published == null) {
                throw StateError(
                    'No se puede verificar la exportación anterior. Revisa los permisos de galería.');
              }
            } else {
              var originalName =
                  p.basename(photo['original_name'] as String? ?? 'photo.jpg');
              if (originalName.isEmpty || originalName == '.')
                originalName = 'photo.jpg';
              final random = Random.secure();
              final token = List.generate(16, (_) => random.nextInt(256))
                  .map((b) => b.toRadixString(16).padLeft(2, '0'))
                  .join();
              final ext = p.extension(originalName).toLowerCase();
              // Persist the unique public name BEFORE insertion. If the process
              // dies after MediaStore writes but before its ID is saved, a retry
              // finds that same asset instead of creating a second one.
              final baseName = p
                  .basenameWithoutExtension(originalName)
                  .replaceFirst(RegExp(r'(_sg_[0-9a-f]{32})+$'), '');
              final resumingExport = photo['export_name'] != null;
              final name = await repository.prepareExport(
                  id, '${baseName}_sg_$token$ext');
              // Only interrupted exports can already exist publicly. A fresh
              // persisted random name needs no full-library search.
              if (resumingExport) {
                published = await gallery.findByName(name);
              }
              if (published == null) {
                staging =
                    await (await temporaryDirectory()).createTemp('sg_export_');
                final source = File(p.join(staging.path, name));
                digest = await crypto.prepareExportFile(path,
                    destinationPath: source.path);
                published = await gallery.publish(
                    source,
                    name,
                    const [
                      '.mp4',
                      '.mov',
                      '.avi',
                      '.mkv',
                      '.webm',
                      '.3gp',
                      '.flv'
                    ].contains(ext));
              }
              _uncommittedExports[id] = published.id;
            }
            // Persist the receipt before verification/removal so retries reuse it.
            await repository.rememberExport(id, published.id);
            _uncommittedExports.remove(id);
            digest ??= await crypto.prepareExportFile(path);
            final publicFile = await gallery.original(published);
            if (publicFile == null || await digestFile(publicFile) != digest) {
              throw StateError(
                  'No se pudo verificar la copia pública; se conserva la privada.');
            }
            await repository.finishExport(id, path);
            result.completed.add(id.toString());
            try {
              await crypto.deleteEncryptedFile(path);
            } catch (_) {
              result.cleanupWarnings.add(id.toString());
            }
          } catch (e) {
            result.failed[id.toString()] = e.toString();
          } finally {
            if (staging != null) {
              try {
                await staging.delete(recursive: true);
              } catch (_) {
                result.cleanupWarnings.add(id.toString());
              }
            }
          }
        });
        return result;
      });
}
