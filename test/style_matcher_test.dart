import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_gallery/core/faces/style_matcher.dart';

const _w = 64, _h = 48;

Uint8List _image(void Function(int x, int y, math.Random r, List<int> rgb) paint,
    int seed) {
  final r = math.Random(seed);
  final out = Uint8List(_w * _h * 4);
  final rgb = [0, 0, 0];
  for (var y = 0; y < _h; y++) {
    for (var x = 0; x < _w; x++) {
      paint(x, y, r, rgb);
      final i = (y * _w + x) * 4;
      out[i] = rgb[0].clamp(0, 255);
      out[i + 1] = rgb[1].clamp(0, 255);
      out[i + 2] = rgb[2].clamp(0, 255);
      out[i + 3] = 255;
    }
  }
  return out;
}

// Mar: azules, cielo claro arriba y agua oscura abajo, pocos detalles.
Float32List _sea(int seed) => describeRgba(
    _image((x, y, r, c) {
      final n = r.nextInt(12);
      if (y < _h ~/ 2) {
        c..[0] = 150 + n..[1] = 190 + n..[2] = 240;
      } else {
        c..[0] = 20 + n..[1] = 70 + n..[2] = 150 + n;
      }
    }, seed),
    _w, _h, 4 / 3);

// Atardecer: naranjas y rojos, degradado vertical.
Float32List _sunset(int seed) => describeRgba(
    _image((x, y, r, c) {
      final n = r.nextInt(12);
      c..[0] = 240 - y ~/ 2 + n..[1] = 120 - y + n..[2] = 40 + n;
    }, seed),
    _w, _h, 4 / 3);

// Captura de texto: fondo blanco con muchas líneas finas negras, vertical.
Float32List _text(int seed) => describeRgba(
    _image((x, y, r, c) {
      final ink = (y % 4 == 0 && x % 9 != 0 && r.nextInt(10) > 1) ? 30 : 245;
      c..[0] = ink..[1] = ink..[2] = ink;
    }, seed),
    _w, _h, 0.5);

Float32List _noise(int seed) => describeRgba(
    _image((x, y, r, c) {
      c..[0] = r.nextInt(256)..[1] = r.nextInt(256)..[2] = r.nextInt(256);
    }, seed),
    _w, _h, 1);

void main() {
  test('el descriptor es estable y normalizado', () {
    final a = _sea(1), b = _sea(1);
    expect(a, b);
    var sum = 0.0;
    for (final v in a) {
      sum += v * v;
    }
    expect(sum, closeTo(1, 1e-4));
    expect(a.any((v) => v.isNaN), isFalse);
  });

  test('una foto casi uniforme no rompe el descriptor', () {
    final flat = describeRgba(Uint8List(_w * _h * 4), _w, _h, 1);
    expect(flat.any((v) => v.isNaN), isFalse);
  });

  group('con carpetas de estilo distinto', () {
    late Float32List mean;
    late List<StyleProfile> profiles;
    Float32List c(Float32List v) => centerVector(v, mean);

    setUp(() {
      final sea = [for (var i = 0; i < 12; i++) _sea(i)];
      final sunset = [for (var i = 0; i < 12; i++) _sunset(100 + i)];
      final text = [for (var i = 0; i < 12; i++) _text(200 + i)];
      mean = meanVector([...sea, ...sunset, ...text]);
      profiles = [
        buildStyleProfile(1, sea.map(c).toList())!,
        buildStyleProfile(2, sunset.map(c).toList())!,
        buildStyleProfile(3, text.map(c).toList())!,
      ];
    });

    test('cada foto nueva va a la carpeta de su estilo', () {
      expect(matchStyle(c(_sea(900)), profiles)?.folderId, 1);
      expect(matchStyle(c(_sunset(901)), profiles)?.folderId, 2);
      expect(matchStyle(c(_text(902)), profiles)?.folderId, 3);
    });

    test('una foto de otro estilo no se sugiere', () {
      expect(matchStyle(c(_noise(903)), profiles), isNull);
    });

    test('el estilo se afina al subir más fotos a la carpeta', () {
      // Con pocas fotos no hay estilo; con las suficientes, sí.
      final few = [for (var i = 0; i < minStyleSamples - 1; i++) c(_sea(i))];
      expect(buildStyleProfile(1, few), isNull);
      final enough = [...few, c(_sea(50))];
      expect(buildStyleProfile(1, enough), isNotNull);
    });
  });

  test('una carpeta de fotos sin nada en común no tiene estilo', () {
    final items = [for (var i = 0; i < 20; i++) _noise(i)];
    final m = meanVector(items);
    expect(buildStyleProfile(9, items.map((v) => centerVector(v, m)).toList()),
        isNull);
  });
}
