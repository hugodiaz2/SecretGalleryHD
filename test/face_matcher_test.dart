import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_gallery/core/faces/face_matcher.dart';

Float32List _identity(int seed) {
  final r = math.Random(seed);
  return normalize(List.generate(128, (_) => r.nextDouble() * 2 - 1));
}

/// Misma "persona" con variación (otro ángulo, luz...).
Float32List _variant(Float32List base, int seed, {double noise = 0.25}) {
  final r = math.Random(seed);
  return normalize(
      List.generate(128, (i) => base[i] + (r.nextDouble() * 2 - 1) * noise * 0.18));
}

void main() {
  final hugo = _identity(1);
  final ana = _identity(2);

  test('sin muestras suficientes no hay perfil', () {
    expect(buildProfile(1, [hugo, _variant(hugo, 1)]), isNull);
  });

  test('reconoce a la misma persona y rechaza a otra', () {
    final profile = buildProfile(
        10, List.generate(8, (i) => _variant(hugo, 100 + i)))!;
    expect(matchFace(_variant(hugo, 999), [profile])?.folderId, 10);
    expect(matchFace(ana, [profile]), isNull);
  });

  test('ignora un rostro ajeno dentro de la carpeta al aprender', () {
    final embeddings = [
      ...List.generate(8, (i) => _variant(hugo, 200 + i)),
      ana, // otra persona colada en la carpeta
    ];
    final profile = buildProfile(10, embeddings)!;
    expect(similarity(profile.centroid, hugo), greaterThan(0.9));
    expect(matchFace(_variant(hugo, 321), [profile]), isNotNull);
  });

  test('escoge la carpeta correcta entre varias personas', () {
    final profiles = [
      buildProfile(1, List.generate(6, (i) => _variant(hugo, 300 + i)))!,
      buildProfile(2, List.generate(6, (i) => _variant(ana, 400 + i)))!,
    ];
    expect(matchFace(_variant(ana, 555), profiles)?.folderId, 2);
    expect(matchFace(_variant(hugo, 556), profiles)?.folderId, 1);
    expect(matchFace(_identity(77), profiles), isNull);
  });

  test('carpetas casi idénticas son ambiguas y no se sugiere ninguna', () {
    final same = List.generate(6, (i) => _variant(hugo, 600 + i));
    final profiles = [buildProfile(1, same)!, buildProfile(2, same)!];
    expect(matchFace(_variant(hugo, 700), profiles), isNull);
  });

  test('el umbral queda acotado', () {
    final profile =
        buildProfile(1, List.generate(6, (i) => _variant(hugo, 800 + i)))!;
    expect(profile.threshold, inInclusiveRange(minThreshold, maxThreshold));
  });

  test('el perfil usa fotos de un solo rostro antes que fotos grupales', () {
    final faces = [
      for (var i = 0; i < 4; i++)
        StoredFace('solo$i', 1, 0.3, _variant(hugo, 900 + i)),
      StoredFace('grupo', 3, 0.1, ana),
    ];
    expect(selectProfileEmbeddings(faces).length, 4);
  });

  test('con pocas fotos solitarias toma el rostro más grande de cada foto', () {
    final faces = [
      StoredFace('a', 2, 0.30, _variant(hugo, 1)),
      StoredFace('a', 2, 0.05, ana),
      StoredFace('b', 2, 0.25, _variant(hugo, 2)),
      StoredFace('b', 2, 0.04, ana),
      StoredFace('c', 1, 0.20, _variant(hugo, 3)),
    ];
    final chosen = selectProfileEmbeddings(faces);
    expect(chosen.length, 3);
    for (final e in chosen) {
      expect(similarity(e, hugo), greaterThan(0.8));
    }
  });

  group('segundo intento', () {
    // Misma persona vista de frente y de perfil: dos grupos de rostros.
    final side = normalize(
        List.generate(128, (i) => hugo[i] * 0.55 + _identity(9)[i] * 0.83));
    final members = [
      ...List.generate(5, (i) => _variant(hugo, 1000 + i)),
      ...List.generate(5, (i) => _variant(side, 1100 + i)),
    ];

    test('un rostro cercano a un ángulo concreto coincide por vecinos', () {
      final profile = buildProfile(1, members)!;
      final probe = _variant(side, 1200);
      expect(neighborScore(probe, profile), greaterThan(relaxedThreshold));
      expect(matchFaceRelaxed(probe, [profile])?.folderId, 1);
    });

    test('un desconocido no coincide ni con el criterio tolerante', () {
      final profile = buildProfile(1, members)!;
      expect(matchFaceRelaxed(_identity(555), [profile]), isNull);
      expect(matchFaceRelaxed(ana, [profile]), isNull);
    });

    test('reforzar el perfil conserva la carpeta y suma muestras', () {
      final base = buildProfile(
          3, List.generate(4, (i) => _variant(hugo, 1300 + i)))!;
      final stronger = augmentProfile(
          base, List.generate(3, (i) => _variant(hugo, 1400 + i)));
      expect(stronger.folderId, 3);
      expect(stronger.members.length, greaterThan(base.members.length));
      expect(augmentProfile(base, const []), same(base));
    });
  });
}
