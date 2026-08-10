import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
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
  Future<File> exportBackup({
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
    final secretsEnc =
        _encryptWithPassword(password, Uint8List.fromList(utf8.encode(secretsJson)));

    final archive = Archive();
    archive.addFile(ArchiveFile('secrets.enc', secretsEnc.length, secretsEnc));

    onProgress?.call('Copiando base de datos...');
    final dbFile = File(await _dbPath());
    if (await dbFile.exists()) {
      final dbBytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile('vault.db', dbBytes.length, dbBytes));
    }

    final dir = await _vaultDir();
    final files = dir.listSync().whereType<File>().toList();
    for (int i = 0; i < files.length; i++) {
      onProgress?.call('Copiando fotos y videos... (${i + 1}/${files.length})');
      final bytes = await files[i].readAsBytes();
      archive.addFile(
          ArchiveFile('files/${p.basename(files[i].path)}', bytes.length, bytes));
    }

    final meta = jsonEncode({
      'exportedAt': DateTime.now().toIso8601String(),
      'fileCount': files.length,
    });
    archive.addFile(ArchiveFile('meta.json', meta.length, utf8.encode(meta)));

    onProgress?.call('Comprimiendo respaldo...');
    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw Exception('No se pudo comprimir el respaldo');
    }

    final tempDir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final outFile =
        File(p.join(tempDir.path, 'secret_gallery_backup_$stamp.sgbackup'));
    await outFile.writeAsBytes(zipBytes);
    return outFile;
  }

  // ── Restaurar ─────────────────────────────────────────────
  /// Reemplaza POR COMPLETO la bóveda actual (fotos, carpetas, PIN,
  /// contraseña y método de acceso) con el contenido del respaldo.
  Future<void> restoreBackup({
    required File backupFile,
    required String password,
    void Function(String status)? onProgress,
  }) async {
    onProgress?.call('Leyendo respaldo...');
    final bytes = await backupFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final secretsFile = archive.findFile('secrets.enc');
    if (secretsFile == null) {
      throw Exception('Este archivo no es un respaldo válido de Secret Gallery HD');
    }

    Map<String, dynamic> secrets;
    try {
      final decrypted = _decryptWithPassword(
          password, Uint8List.fromList(secretsFile.content as List<int>));
      secrets = jsonDecode(utf8.decode(decrypted)) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Contraseña de respaldo incorrecta');
    }

    onProgress?.call('Restaurando base de datos...');
    await DBHelper.instance.closeAndReset();
    final dbEntry = archive.findFile('vault.db');
    if (dbEntry != null) {
      final dbPath = await _dbPath();
      await File(dbPath).writeAsBytes(dbEntry.content as List<int>);
    }

    onProgress?.call('Restaurando fotos y videos...');
    final dir = await _vaultDir();
    for (final f in dir.listSync().whereType<File>()) {
      try {
        await f.delete();
      } catch (_) {}
    }
    for (final entry in archive.files) {
      if (!entry.isFile || !entry.name.startsWith('files/')) continue;
      final fileName = entry.name.substring('files/'.length);
      if (fileName.isEmpty) continue;
      final outFile = File(p.join(dir.path, fileName));
      await outFile.writeAsBytes(entry.content as List<int>);
    }

    onProgress?.call('Restaurando método de acceso...');
    final pin = secrets['pin'] as String?;
    if (pin != null && pin.isNotEmpty) {
      await PinService().savePin(pin);
    } else {
      await PinService().deletePin();
    }

    final pw = secrets['password'] as String?;
    if (pw != null && pw.isNotEmpty) {
      await PasswordService().savePassword(pw);
    } else {
      await PasswordService().deletePassword();
    }

    final aesKey = secrets['aesKey'] as String?;
    if (aesKey != null) {
      await CryptoService().setRawKeyBase64(aesKey);
    }

    final authName = secrets['authMethod'] as String?;
    final method = AuthMethod.values.firstWhere(
      (e) => e.name == authName,
      orElse: () => AuthMethod.pin,
    );
    await PrefsService.instance.saveAuthMethod(method);

    onProgress?.call('Listo');
  }
}
