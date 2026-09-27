import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute, ValueNotifier;
import 'backup_validation.dart';
import 'vault_activity.dart';
import 'media_service.dart';
import 'package:archive/archive_io.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import '../security/crypto_service.dart';
import '../security/pin_service.dart';
import '../security/password_service.dart';
import 'prefs_service.dart';

/// Empaqueta toda la bóveda (fotos encriptadas + base de datos + claves
/// de acceso) en un solo archivo que se puede compartir a Drive, WhatsApp,
/// el PC, etc. — y restaurarla después en cualquier instalación de la app.
///
/// El paquete va protegido con una contraseña de respaldo (distinta del
/// PIN/contraseña de la app): sin ella, el archivo no sirve de nada.
class BackupService {
  static final BackupService instance = BackupService._();
  BackupService._();
  static final busy = ValueNotifier<bool>(false);

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    if (busy.value || VaultActivity.transfers > 0) {
      throw StateError(
          'Espera a que termine la operación de archivos en curso.');
    }
    VaultActivity.backup = true;
    busy.value = true;
    try {
      return await action();
    } finally {
      VaultActivity.backup = false;
      busy.value = false;
    }
  }

  Future<File> exportBackup(
          {required String password, void Function(String)? onProgress}) =>
      _exclusive(
          () => _exportBackup(password: password, onProgress: onProgress));

  Future<void> restoreBackup(
          {required File backupFile,
          required String password,
          void Function(String)? onProgress}) =>
      _exclusive(() => _restoreBackup(
          backupFile: backupFile, password: password, onProgress: onProgress));

  static const _restoreJournalKey = 'sg_restore_rollback';
  static const _journalStorage = FlutterSecureStorage();

  Future<void> recoverInterruptedRestore() async {
    final encoded = await _journalStorage.read(key: _restoreJournalKey);
    if (encoded == null) return;
    final journal = jsonDecode(encoded) as Map<String, dynamic>;
    final documents = await getApplicationDocumentsDirectory();
    final stage = Directory(journal['stage'] as String);
    if (!p.isWithin(documents.path, stage.path) ||
        !p.basename(stage.path).startsWith('sg_restore_') ||
        !await stage.exists()) {
      throw StateError('No se puede localizar la copia de recuperación');
    }
    await DBHelper.instance.closeAndReset();
    final dbPath = await _dbPath();
    final previousDb = File(p.join(stage.path, 'previous.db'));
    if (await previousDb.exists()) {
      await deleteDatabase(dbPath);
      await previousDb.copy(dbPath);
    } else if (journal['hadDatabase'] == false) {
      await deleteDatabase(dbPath);
    }
    final previousVault = Directory(p.join(stage.path, 'previous_vault'));
    final vault = Directory(p.join(documents.path, '.sg_vault'));
    if (await previousVault.exists()) {
      if (await vault.exists()) await vault.delete(recursive: true);
      await vault.create();
      await for (final entry in previousVault.list(followLinks: false)) {
        if (entry is File)
          await entry.copy(p.join(vault.path, p.basename(entry.path)));
      }
    }
    await _applySecrets(Map<String, dynamic>.from(journal['secrets'] as Map));
    MediaService.instance.clearThumbnailCaches();
    await _journalStorage.delete(key: _restoreJournalKey);
    await stage.delete(recursive: true);
  }

  Future<Directory> _vaultDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, '.sg_vault'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<String> _dbPath() async {
    return p.join(await getDatabasesPath(), DBHelper.dbFileName);
  }

  // ── Cifrado con contraseña (PBKDF2 + AES) ────────────────
  Uint8List _deriveKey(String password, Uint8List salt) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, 100000, 32));
    return pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
  }

  Uint8List _randomBytes(int n) {
    final rnd = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => rnd.nextInt(256)));
  }

  Uint8List _encryptWithPassword(String password, Uint8List plain) {
    final salt = _randomBytes(16);
    final iv = _randomBytes(16);
    final keyBytes = _deriveKey(password, salt);
    final encrypter = enc.Encrypter(enc.AES(enc.Key(keyBytes)));
    final encrypted = encrypter.encryptBytes(plain, iv: enc.IV(iv));

    final out = BytesBuilder();
    out.add(salt);
    out.add(iv);
    out.add(encrypted.bytes);
    return out.toBytes();
  }

  Uint8List _decryptWithPassword(String password, Uint8List combined) {
    final salt = Uint8List.fromList(combined.sublist(0, 16));
    final iv = Uint8List.fromList(combined.sublist(16, 32));
    final cipherBytes = Uint8List.fromList(combined.sublist(32));
    final keyBytes = _deriveKey(password, salt);
    final encrypter = enc.Encrypter(enc.AES(enc.Key(keyBytes)));
    final decrypted =
        encrypter.decryptBytes(enc.Encrypted(cipherBytes), iv: enc.IV(iv));
    return Uint8List.fromList(decrypted);
  }

  // ── Exportar ──────────────────────────────────────────────
  Future<File> _exportBackup({
    required String password,
    void Function(String status)? onProgress,
  }) async {
    onProgress?.call('Reuniendo claves de acceso...');
    final pin = await PinService().rawPin();
    final pw = await PasswordService().rawPassword();
    final authMethod = await PrefsService.instance.getAuthMethod();
    final aesKey = await CryptoService().rawKeyBase64();

    final secretsJson = jsonEncode({
      'pin': pin,
      'password': pw,
      'authMethod': authMethod.name,
      'aesKey': aesKey,
    });
    final secretsEnc = _encryptWithPassword(
        password, Uint8List.fromList(utf8.encode(secretsJson)));

    onProgress?.call('Preparando una copia coherente de la base de datos...');
    await DBHelper.instance.database;
    await DBHelper.instance.closeAndReset();
    final temp = await (await getTemporaryDirectory()).createTemp('sg_backup_');
    try {
      final database =
          await File(await _dbPath()).copy(p.join(temp.path, 'vault.db'));
      final dir = await _vaultDir();
      final files = await dir
          .list(followLinks: false)
          .where((e) => e is File)
          .cast<File>()
          .toList();
      final output = p.join(temp.path,
          'secret_gallery_${DateTime.now().millisecondsSinceEpoch}.sgbackup');
      onProgress?.call('Escribiendo respaldo...');
      await compute(_writeBackup, (
        output: output,
        database: database.path,
        secrets: secretsEnc,
        files: files.map((file) => file.path).toList(),
      ));
      await database.delete();
      return File(output);
    } catch (_) {
      await temp.delete(recursive: true);
      rethrow;
    }
  }

  // ── Restaurar ─────────────────────────────────────────────
  /// Reemplaza POR COMPLETO la bóveda actual (fotos, carpetas, PIN,
  /// contraseña y método de acceso) con el contenido del respaldo.
  Future<void> _restoreBackup({
    required File backupFile,
    required String password,
    void Function(String status)? onProgress,
  }) async {
    onProgress?.call('Validando respaldo antes de reemplazar datos...');
    final documents = await getApplicationDocumentsDirectory();
    final stage = await documents.createTemp('sg_restore_');
    final stagedVault = await Directory(p.join(stage.path, 'files')).create();
    final currentVault = await _vaultDir();
    final stagedDb = File(p.join(stage.path, 'vault.db'));
    bool keepRecovery = false;
    try {
      final secrets = await compute(_extractBackup, (
        archive: backupFile.path,
        stage: stage.path,
        password: password,
      ));
      validateBackupSecrets(secrets);
      final dbPath = await _dbPath();
      final available =
          (await stagedVault.list().where((e) => e is File).toList())
              .map((e) => p.basename(e.path))
              .toSet();
      final candidate =
          await openDatabase(stagedDb.path, singleInstance: false);
      try {
        final version = await candidate.getVersion();
        if (version < 1 || version > 6)
          throw const FormatException('Versión de respaldo no compatible');
        final check = await candidate.rawQuery('PRAGMA quick_check');
        if (check.length != 1 || check.first.values.first != 'ok')
          throw const FormatException('Base de datos dañada');
        await candidate.transaction((txn) async {
          for (final table in ['photos', 'trash', 'intruders', 'folders']) {
            final rows = await txn.query(table);
            for (final row in rows) {
              final changes = <String, dynamic>{};
              final column =
                  table == 'folders' ? 'cover_photo_path' : 'encrypted_path';
              final path = row[column] as String?;
              if (path != null && path.isNotEmpty) {
                changes[column] =
                    relocateBackupPath(path, currentVault.path, available);
              }
              for (final field in ['folder_payload', 'photo_payload']) {
                final payload = row[field] as String?;
                if (payload == null) continue;
                final data = jsonDecode(payload) as Map<String, dynamic>;
                void remap(Map<String, dynamic> record, String key) {
                  final old = record[key] as String?;
                  if (old != null && old.isNotEmpty)
                    record[key] =
                        relocateBackupPath(old, currentVault.path, available);
                }

                if (field == 'photo_payload') {
                  remap(data, 'encrypted_path');
                } else {
                  for (final photo in data['photos'] as List) {
                    remap(photo as Map<String, dynamic>, 'encrypted_path');
                  }
                  for (final folder in data['folders'] as List) {
                    remap(folder as Map<String, dynamic>, 'cover_photo_path');
                  }
                }
                changes[field] = jsonEncode(data);
              }
              if (changes.isNotEmpty)
                await txn.update(table, changes,
                    where: 'id = ?', whereArgs: [row['id']]);
            }
          }
        });
      } finally {
        await candidate.close();
      }

      final oldSecrets = <String, dynamic>{
        'pin': await PinService().rawPin(),
        'password': await PasswordService().rawPassword(),
        'authMethod': (await PrefsService.instance.getAuthMethod()).name,
        'aesKey': await CryptoService().rawKeyBase64(),
      };
      final oldDb = File(p.join(stage.path, 'previous.db'));
      final oldVault = Directory(p.join(stage.path, 'previous_vault'));
      await _journalStorage.write(
          key: _restoreJournalKey,
          value: jsonEncode({
            'stage': stage.path,
            'hadDatabase': await File(dbPath).exists(),
            'secrets': oldSecrets,
          }));
      bool movedVault = false;
      bool movedDb = false;
      bool installedVault = false;
      bool installedDb = false;
      try {
        await DBHelper.instance.closeAndReset();
        onProgress?.call('Instalando respaldo validado...');
        if (await File(dbPath).exists()) {
          await File(dbPath).rename(oldDb.path);
          movedDb = true;
        }
        await currentVault.rename(oldVault.path);
        movedVault = true;
        await stagedVault.rename(currentVault.path);
        installedVault = true;
        await stagedDb.rename(dbPath);
        installedDb = true;
        await _applySecrets(secrets);
        await DBHelper.instance
            .database; // Run migrations before considering installation complete.
        MediaService.instance.clearThumbnailCaches();
      } catch (_) {
        await DBHelper.instance.closeAndReset();
        try {
          if (installedDb) await deleteDatabase(dbPath);
          if (movedDb) await oldDb.rename(dbPath);
          if (installedVault)
            await Directory(currentVault.path).delete(recursive: true);
          if (movedVault) await oldVault.rename(currentVault.path);
          await _applySecrets(oldSecrets);
          await _journalStorage.delete(key: _restoreJournalKey);
          MediaService.instance.clearThumbnailCaches();
        } catch (_) {
          keepRecovery = true;
          throw StateError(
              'No se pudo completar la recuperación. Conserva los datos de la aplicación para recuperar la copia anterior.');
        }
        rethrow;
      }
      try {
        await _journalStorage.delete(key: _restoreJournalKey);
      } catch (_) {
        keepRecovery = true;
        rethrow;
      }
      onProgress?.call('Listo');
    } finally {
      if (!keepRecovery && await stage.exists())
        await stage.delete(recursive: true);
    }
  }

  Future<void> _applySecrets(Map<String, dynamic> secrets) async {
    final pin = secrets['pin'] as String?;
    if (pin == null || pin.isEmpty) {
      await PinService().deletePin();
    } else {
      await PinService().savePin(pin);
    }
    final password = secrets['password'] as String?;
    if (password == null || password.isEmpty) {
      await PasswordService().deletePassword();
    } else {
      await PasswordService().savePassword(password);
    }
    await CryptoService().setRawKeyBase64(secrets['aesKey'] as String);
    await PrefsService.instance.saveAuthMethod(AuthMethod.values.firstWhere(
        (method) => method.name == secrets['authMethod'],
        orElse: () => AuthMethod.pin));
  }
}

Future<void> _writeBackup(
    ({
      String output,
      String database,
      Uint8List secrets,
      List<String> files
    }) job) async {
  final encoder = ZipFileEncoder()
    ..create(job.output, level: ZipFileEncoder.STORE);
  try {
    encoder.addArchiveFile(
        ArchiveFile('secrets.enc', job.secrets.length, job.secrets));
    await encoder.addFile(File(job.database), 'vault.db', ZipFileEncoder.STORE);
    for (final path in job.files) {
      await encoder.addFile(
          File(path), 'files/${p.basename(path)}', ZipFileEncoder.STORE);
    }
    final meta = utf8.encode(jsonEncode({
      'exportedAt': DateTime.now().toIso8601String(),
      'fileCount': job.files.length
    }));
    encoder.addArchiveFile(ArchiveFile('meta.json', meta.length, meta));
  } finally {
    await encoder.close();
  }
}

Map<String, dynamic> _extractBackup(
    ({String archive, String stage, String password}) job) {
  final input = InputFileStream(job.archive);
  try {
    final archive = ZipDecoder().decodeBuffer(input);
    final seen = <String>{};
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      validateBackupEntryName(entry.name);
      if (!seen.add(entry.name))
        throw const FormatException('Entradas duplicadas en el respaldo');
    }
    final secretsEntry = archive.findFile('secrets.enc');
    if (secretsEntry == null ||
        !seen.contains('vault.db') ||
        secretsEntry.size > 1024 * 1024) {
      throw const FormatException('Respaldo incompleto');
    }
    final clear = BackupService.instance._decryptWithPassword(
        job.password, Uint8List.fromList(secretsEntry.content as List<int>));
    final secrets = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    validateBackupSecrets(secrets);
    for (final entry in archive.files) {
      if (!entry.isFile ||
          entry.name == 'secrets.enc' ||
          entry.name == 'meta.json') continue;
      final output = OutputFileStream(p.join(job.stage, entry.name));
      try {
        entry.writeContent(output);
      } finally {
        output.closeSync();
      }
    }
    return secrets;
  } finally {
    input.closeSync();
  }
}
