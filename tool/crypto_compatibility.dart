// Generates disposable compatibility vectors with the existing Dart encoder.
// Run: dart run tool/crypto_compatibility.dart build/crypto_compatibility
import 'dart:io';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';

void main(List<String> args) {
  final dir = Directory(args.single)..createSync(recursive: true);
  final key = Key(Uint8List.fromList(List.generate(32, (i) => i)));
  // Exercise counter carry as well as padding and IO chunk boundaries.
  final iv = IV(Uint8List.fromList(List.generate(16, (i) => i == 15 ? 248 : 255)));
  File('${dir.path}/key.bin').writeAsBytesSync(key.bytes);
  File('${dir.path}/iv.bin').writeAsBytesSync(iv.bytes);
  for (final size in [1, 15, 16, 17, 31, 131071, 131072, 131073, 1048576]) {
    final bytes = Uint8List.fromList(List.generate(size, (i) => (i * 37 + 11) & 255));
    final encoded = Encrypter(AES(key)).encryptBytes(bytes, iv: iv);
    File('${dir.path}/$size.plain').writeAsBytesSync(bytes);
    File('${dir.path}/$size.dart.enc').writeAsBytesSync([...iv.bytes, ...encoded.bytes]);
  }
  stdout.writeln('Generated 9 Dart AES compatibility vectors.');
}