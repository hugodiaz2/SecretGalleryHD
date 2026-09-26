import 'dart:async';
import 'package:secret_gallery/core/services/vault_activity.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_gallery/core/services/backup_service.dart';
import 'package:secret_gallery/core/services/backup_validation.dart';
import 'package:secret_gallery/core/services/thumbnail_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('backup is refused while a transfer is still running', () async {
    VaultActivity.transfers = 1;
    try {
      await expectLater(
          BackupService.instance.restoreBackup(
              backupFile: File('unused.sgbackup'), password: 'test'),
          throwsStateError);
      expect(BackupService.busy.value, isFalse);
      expect(VaultActivity.backup, isFalse);
    } finally {
      VaultActivity.transfers = 0;
    }
  });
  test('backup rejects paths outside its flat vault directory', () {
    for (final name in [
      'files/../x',
      'files/..\\x',
      '/files/x',
      'files/C:x',
      'files/sub/x',
      'files/',
      'files/..'
    ]) {
      expect(() => validateBackupEntryName(name), throwsFormatException);
    }
    expect(validateBackupEntryName('files/photo.enc'), 'files/photo.enc');
    expect(validateBackupEntryName('vault.db'), 'vault.db');
  });
  test('backup requires a usable key and matching access credentials', () {
    final valid = {
      'aesKey': base64Encode(List.filled(32, 7)),
      'pin': '1234',
      'authMethod': 'pin'
    };
    expect(() => validateBackupSecrets(valid), returnsNormally);
    expect(
        () => validateBackupSecrets({
              ...valid,
              'aesKey': base64Encode([1])
            }),
        throwsFormatException);
    expect(() => validateBackupSecrets({...valid, 'pin': null}),
        throwsFormatException);
    expect(() => validateBackupSecrets({...valid, 'authMethod': 'password'}),
        throwsFormatException);
  });
  test(
      'restored paths refer to the current installation and require every file',
      () {
    final result = relocateBackupPath(
        '/old/device/.sg_vault/photo.enc', '/new/vault', {'photo.enc'});
    expect(result.replaceAll('\\', '/'), '/new/vault/photo.enc');
    expect(
        () =>
            relocateBackupPath('/old/missing.enc', '/new/vault', {'photo.enc'}),
        throwsFormatException);
  });
  test('video thumbnail queue runs one producer and skips disposed cells',
      () async {
    final cache = ThumbnailCache(maxConcurrent: 1);
    final gate = Completer<Uint8List?>();
    var secondStarted = false;
    final first = cache.load('first', () => gate.future);
    final second = cache.load('second', () async {
      secondStarted = true;
      return Uint8List(1);
    });
    final skipped = cache.load(
        'disposed', () async => throw StateError('must not run'),
        isNeeded: () => false);
    expect(secondStarted, isFalse);
    gate.complete(Uint8List.fromList([1]));
    await first;
    expect(await skipped, isNull);
    expect(await second, isNotNull);
    expect(secondStarted, isTrue);
  });
  test('incomplete or unsafe backup never replaces existing vault data',
      () async {
    final root = await Directory.systemTemp.createTemp('sg_restore_test_');
    final vault = await Directory('${root.path}/.sg_vault').create();
    final original =
        await File('${vault.path}/photo.enc').writeAsBytes([1, 2, 3]);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    const sqlite = MethodChannel('com.tekartik.sqflite');
    messenger.setMockMethodCallHandler(paths, (_) async => root.path);
    messenger.setMockMethodCallHandler(sqlite, (call) async {
      if (call.method == 'getDatabasesPath') return root.path;
      throw StateError('Invalid backup must not open the active database');
    });
    try {
      for (final entry in ['secrets.enc', 'files/../escape']) {
        final archive = Archive()..addFile(ArchiveFile(entry, 3, [1, 2, 3]));
        final file = await File('${root.path}/bad.sgbackup')
            .writeAsBytes(ZipEncoder().encode(archive)!);
        await expectLater(
            BackupService.instance
                .restoreBackup(backupFile: file, password: 'test'),
            throwsFormatException);
        expect(await original.readAsBytes(), [1, 2, 3]);
        expect(BackupService.busy.value, isFalse);
        expect(await File('${root.path}/escape').exists(), isFalse);
      }
    } finally {
      messenger.setMockMethodCallHandler(paths, null);
      messenger.setMockMethodCallHandler(sqlite, null);
      await root.delete(recursive: true);
    }
  });
}
