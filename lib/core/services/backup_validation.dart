import 'dart:convert';
import 'package:path/path.dart' as p;

String validateBackupEntryName(String name) {
  if (name == 'vault.db' || name == 'secrets.enc' || name == 'meta.json')
    return name;
  if (!name.startsWith('files/'))
    throw const FormatException('Entrada de respaldo no admitida');
  final leaf = name.substring(6);
  if (leaf.isEmpty ||
      leaf == '.' ||
      leaf == '..' ||
      leaf.contains('/') ||
      leaf.contains('\\') ||
      leaf.contains(':') ||
      leaf.contains('\u0000')) {
    throw const FormatException('Ruta de respaldo no válida');
  }
  return name;
}

void validateBackupSecrets(Map<String, dynamic> secrets) {
  final key = secrets['aesKey'];
  final pin = secrets['pin'];
  if (key is! String ||
      base64Decode(key).length != 32 ||
      pin is! String ||
      pin.isEmpty) {
    throw const FormatException(
        'El respaldo no contiene claves de acceso válidas');
  }
  final method = secrets['authMethod'];
  if (method != null && !['pin', 'password', 'fingerprint'].contains(method)) {
    throw const FormatException('Método de acceso no válido');
  }
  if (method == 'password' &&
      (secrets['password'] is! String ||
          (secrets['password'] as String).isEmpty)) {
    throw const FormatException('Falta la contraseña de acceso');
  }
}

String relocateBackupPath(
    String oldPath, String vaultPath, Set<String> available) {
  final name = p.posix.basename(oldPath.replaceAll('\\', '/'));
  if (!available.contains(name))
    throw const FormatException('Faltan archivos en el respaldo');
  return p.join(vaultPath, name);
}
