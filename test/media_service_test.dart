import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:secret_gallery/core/security/crypto_service.dart';
import 'package:secret_gallery/core/services/media_transfer_service.dart';

AssetEntity asset(String id, {String title = 'photo.jpg', int type = 1}) =>
    AssetEntity(id: id, typeInt: type, width: 10, height: 10, title: title);

class FakeCrypto extends CryptoService {
  FakeCrypto(this.root);
  final Directory root;
  int writes = 0;
  bool corrupt = false;
  bool failWrite = false;
  @override
  Future<String> encryptAndSave(File source, String originalName) async {
    if (failWrite) throw const FileSystemException('full');
    final file = File('${root.path}/private_${writes++}.enc');
    await file.writeAsBytes(corrupt ? [0] : await source.readAsBytes());
    return file.path;
  }

  @override
  Future<String> prepareExportFile(String encryptedPath,
      {String? destinationPath}) async {
    final bytes = await decryptFile(encryptedPath);
    if (bytes.isEmpty) throw StateError('Empty private file');
    if (destinationPath != null) {
      await File(destinationPath).writeAsBytes(bytes, flush: true);
    }
    return MediaTransferService.digestBytes(bytes);
  }

  @override
  Future<Uint8List> decryptFile(String encryptedPath) =>
      File(encryptedPath).readAsBytes();
}

class FakeRepository implements TransferRepository {
  final Map<int, Map<String, dynamic>> rows = {};
  int nextId = 1;
  bool failInsert = false;
  bool failFinish = false;
  bool failReceipt = false;
  @override
  Future<Map<String, dynamic>?> findImported(String id, String digest) async {
    for (final row in rows.values) {
      if (row['source_asset_id'] == id && row['source_digest'] == digest) {
        return row;
      }
    }
    return null;
  }

  @override
  Future<int> insertPhoto(Map<String, dynamic> data) async {
    if (failInsert) throw StateError('database unavailable');
    final id = nextId++;
    rows[id] = {...data, 'id': id};
    return id;
  }

  @override
  Future<Map<String, dynamic>?> photoForTransfer(int id) async => rows[id];
  @override
  Future<String> prepareExport(int id, String proposedName) async {
    return rows[id]!['export_name'] ??= proposedName;
  }

  @override
  Future<void> rememberExport(int id, String assetId) async {
    if (failReceipt) throw StateError('receipt failed');
    rows[id]!['exported_asset_id'] = assetId;
  }

  @override
  Future<void> finishExport(int id, String encryptedPath) async {
    if (failFinish) throw StateError('commit failed');
    rows.remove(id);
  }
}

class FakeGallery implements TransferGallery {
  FakeGallery(this.root);
  final Directory root;
  final Map<String, File> files = {};
  final Map<String, AssetEntity> assets = {};
  final List<String> deletionRequests = [];
  bool permitted = true;
  bool cancelDelete = false;
  bool failPublish = false;
  bool failAfterPublish = false;
  bool corruptPublish = false;
  int publishes = 0;
  bool? lastVideo;
  Future<void> Function(List<String>)? beforeDelete;
  @override
  Future<bool> requestAccess() async => permitted;
  @override
  Future<File?> original(AssetEntity asset) async => files[asset.id];
  @override
  Future<AssetEntity?> find(String id) async => assets[id];
  @override
  Future<AssetEntity?> findByName(String name) async {
    for (final item in assets.values) {
      if (item.title == name) return item;
    }
    return null;
  }

  @override
  Future<AssetEntity> publish(File source, String name, bool video) async {
    if (failPublish) throw StateError('publish failed');
    // Export input must be private staging, never a second public DCIM file.
    expect(source.parent.path, contains('sg_export_'));
    final id = 'export_${publishes++}';
    lastVideo = video;
    final output = File('${root.path}/$id');
    await output
        .writeAsBytes(corruptPublish ? [0] : await source.readAsBytes());
    files[id] = output;
    final created = assets[id] = asset(id, title: name, type: video ? 2 : 1);
    if (failAfterPublish) {
      throw StateError('Interrupted after public insertion');
    }
    return created;
  }

  @override
  Future<List<String>> delete(List<String> ids) async {
    await beforeDelete?.call(ids);
    deletionRequests.addAll(ids);
    if (cancelDelete) return [];
    for (final id in ids) {
      await files.remove(id)!.delete();
      assets.remove(id);
    }
    return ids;
  }

  Future<AssetEntity> add(String id, List<int> bytes,
      {String title = 'photo.jpg'}) async {
    final file = File('${root.path}/$id');
    await file.writeAsBytes(bytes);
    files[id] = file;
    return assets[id] = asset(id, title: title);
  }
}

void main() {
  late Directory root;
  late FakeCrypto crypto;
  late FakeRepository repository;
  late FakeGallery gallery;
  late MediaTransferService service;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sg_test_');
    crypto = FakeCrypto(root);
    repository = FakeRepository();
    gallery = FakeGallery(root);
    service = MediaTransferService(
        crypto: crypto,
        repository: repository,
        gallery: gallery,
        temporaryDirectory: () async => root);
  });
  tearDown(() async => root.delete(recursive: true));

  Future<TransferResult> hide(List<AssetEntity> assets) =>
      service.importAssets(assets: assets, folderId: 0, onProgress: (_, __) {});

  for (final count in [1, 4, 10]) {
    test('$count photos: hide -> unlock -> hide, exactly one copy per asset',
        () async {
      final selected = <AssetEntity>[];
      for (var i = 0; i < count; i++) {
        // Identical titles are intentionally allowed; identity is the asset ID.
        selected.add(await gallery.add('source_$i', [1, 2, i]));
      }
      gallery.beforeDelete = (ids) async {
        for (final id in ids) {
          final original = gallery.files[id]!;
          final row = await repository.findImported(
              id, await MediaTransferService.digestFile(original));
          expect(row, isNotNull);
          expect(await crypto.decryptFile(row!['encrypted_path']),
              await original.readAsBytes());
        }
      };
      final hidden = await hide(selected);
      expect(hidden.completed, hasLength(count));
      expect(gallery.assets, isEmpty);
      final exported =
          await service.unlockPhotos(repository.rows.values.toList());
      expect(exported.failed, isEmpty);
      expect(exported.completed, hasLength(count));
      expect(gallery.assets, hasLength(count));
      expect(gallery.publishes, count);
      expect(repository.rows, isEmpty);
      final rehidden = await hide(gallery.assets.values.toList());
      expect(rehidden.completed, hasLength(count));
      expect(repository.rows, hasLength(count));
      expect(gallery.assets, isEmpty);
      expect(root.listSync().whereType<Directory>(), isEmpty);
    });
  }

  test('ID deduplication preserves different assets with the same title', () {
    expect(
        MediaTransferService.uniqueAssets([asset('1'), asset('1'), asset('2')])
            .map((a) => a.id),
        ['1', '2']);
  });

  test('duplicate selections and concurrent imports create one private copy',
      () async {
    final source = await gallery.add('1', [4, 5, 6]);
    gallery.cancelDelete = true;
    await Future.wait([
      hide([source, source]),
      hide([source])
    ]);
    expect(crypto.writes, 1);
    expect(repository.rows, hasLength(1));
    expect(gallery.assets, hasLength(1));
  });

  test(
      'cancelled public deletion retains both and retry reuses verified private copy',
      () async {
    final source = await gallery.add('1', [7, 8, 9]);
    gallery.cancelDelete = true;
    final first = await hide([source]);
    expect(first.publicRetained, ['1']);
    gallery.cancelDelete = false;
    final retry = await hide([source]);
    expect(retry.publicRetained, isEmpty);
    expect(crypto.writes, 1);
    expect(repository.rows, hasLength(1));
    expect(gallery.assets, isEmpty);
  });

  for (final failure in ['write', 'verification', 'database']) {
    test('import $failure failure never deletes the public original', () async {
      final source = await gallery.add('1', [7, 8, 9]);
      crypto.failWrite = failure == 'write';
      crypto.corrupt = failure == 'verification';
      repository.failInsert = failure == 'database';
      final result = await hide([source]);
      expect(result.failed.keys, ['1']);
      expect(result.completed, isEmpty);
      expect(gallery.deletionRequests, isEmpty);
      expect(await gallery.files['1']!.readAsBytes(), [7, 8, 9]);
      expect(repository.rows, isEmpty);
      expect(
          root
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.enc')),
          isEmpty);
    });
  }

  test(
      'partial import reports a missing source and still safely imports others',
      () async {
    final valid = await gallery.add('valid', [4, 5, 6]);
    final progress = <int>[];
    final result = await service.importAssets(
        assets: [asset('missing'), valid],
        folderId: 3,
        onProgress: (current, total) {
          progress.add(current);
          expect(total, 2);
        });
    expect(result.failed.keys, ['missing']);
    expect(result.completed, ['valid']);
    expect(progress, [1, 2]);
    expect(repository.rows.values.single['folder_id'], 3);
  });

  test('permission denial leaves files and records unchanged', () async {
    final source = await gallery.add('1', [7]);
    gallery.permitted = false;
    await expectLater(hide([source]), throwsStateError);
    expect(gallery.deletionRequests, isEmpty);
    expect(repository.rows, isEmpty);
  });

  test('concurrent duplicate export requests publish only once', () async {
    await hide([
      await gallery.add('1', [1, 2, 3])
    ]);
    final photo = repository.rows.values.single;
    await Future.wait([
      service.unlockPhotos([photo, photo]),
      service.unlockPhotos([photo])
    ]);
    expect(gallery.publishes, 1);
    expect(gallery.assets, hasLength(1));
  });

  for (final failure in ['publish', 'verification', 'receipt', 'commit']) {
    test(
        'export $failure failure retains private copy; retry does not republish',
        () async {
      await hide([
        await gallery.add('1', [1, 2, 3])
      ]);
      final photo = repository.rows.values.single;
      final privatePath = photo['encrypted_path'] as String;
      gallery.failPublish = failure == 'publish';
      gallery.corruptPublish = failure == 'verification';
      repository.failReceipt = failure == 'receipt';
      repository.failFinish = failure == 'commit';
      final first = await service.unlockPhotos([photo]);
      expect(first.failed, hasLength(1));
      expect(await File(privatePath).readAsBytes(), [1, 2, 3]);
      expect(repository.rows, hasLength(1));
      gallery.failPublish = false;
      gallery.corruptPublish = false;
      repository.failReceipt = false;
      repository.failFinish = false;
      if (failure == 'verification') {
        await gallery.files.values.single.writeAsBytes([1, 2, 3]);
      }
      final retry = await service.unlockPhotos([photo]);
      expect(retry.failed, isEmpty);
      expect(gallery.publishes, 1);
      expect(repository.rows, isEmpty);
      expect(await File(privatePath).exists(), isFalse);
      expect(root.listSync().whereType<Directory>(), isEmpty);
    });
  }

  test('persisted export receipt survives a new service instance', () async {
    await hide([
      await gallery.add('1', [1, 2, 3])
    ]);
    final photo = repository.rows.values.single;
    repository.failFinish = true;
    await service.unlockPhotos([photo]);
    repository.failFinish = false;
    final restarted = MediaTransferService(
        crypto: crypto,
        repository: repository,
        gallery: gallery,
        temporaryDirectory: () async => root);
    final retry = await restarted.unlockPhotos([photo]);
    expect(retry.failed, isEmpty);
    expect(gallery.publishes, 1);
  });

  test(
      'interruption after public insertion and restart does not create a duplicate',
      () async {
    await hide([
      await gallery.add('1', [1, 2, 3])
    ]);
    final photo = repository.rows.values.single;
    gallery.failAfterPublish = true;
    final first = await service.unlockPhotos([photo]);
    expect(first.failed, hasLength(1));
    expect(photo['exported_asset_id'], isNull);
    expect(photo['export_name'], isNotNull);
    gallery.failAfterPublish = false;
    final restarted = MediaTransferService(
        crypto: crypto,
        repository: repository,
        gallery: gallery,
        temporaryDirectory: () async => root);
    final second = await restarted.unlockPhotos([photo]);
    expect(second.failed, isEmpty);
    expect(gallery.publishes, 1);
    expect(repository.rows, isEmpty);
  });
  test('video export follows the same single-publication path', () async {
    await hide([
      await gallery.add('1', [1, 2, 3], title: 'video.mp4')
    ]);
    final result = await service.unlockPhotos(repository.rows.values.toList());
    expect(result.failed, isEmpty);
    expect(gallery.lastVideo, isTrue);
    expect(gallery.publishes, 1);
  });
}
