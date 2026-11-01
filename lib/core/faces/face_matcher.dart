import 'dart:math' as math;
import 'dart:typed_data';

/// Lógica pura (sin plugins) para decidir a qué carpeta se parece un rostro.
/// Los vectores se normalizan, así que la similitud es el coseno (producto punto).

/// Rostro guardado de una foto ya analizada.
class StoredFace {
  final String path;
  final int faceCount; // rostros válidos en esa foto
  final double area; // fracción del cuadro que ocupa el rostro
  final Float32List embedding;
  const StoredFace(this.path, this.faceCount, this.area, this.embedding);
}

/// Huella de una persona dentro de una carpeta.
class FaceProfile {
  final int folderId;
  final Float32List centroid;
  final double threshold;
  final int samples;
  final List<Float32List> members; // rostros usados para el perfil
  const FaceProfile(
      this.folderId, this.centroid, this.threshold, this.samples, this.members);
}

class FaceHit {
  final int folderId;
  final double score;
  const FaceHit(this.folderId, this.score);
}

const int minProfileSamples = 3;
const double minThreshold = 0.5;
const double maxThreshold = 0.75;
const double minMargin = 0.03;

Float32List normalize(List<double> v) {
  var sum = 0.0;
  for (final x in v) {
    sum += x * x;
  }
  final norm = math.sqrt(sum);
  final out = Float32List(v.length);
  if (norm == 0) return out;
  for (var i = 0; i < v.length; i++) {
    out[i] = v[i] / norm;
  }
  return out;
}

double similarity(Float32List a, Float32List b) {
  final n = math.min(a.length, b.length);
  var dot = 0.0;
  for (var i = 0; i < n; i++) {
    dot += a[i] * b[i];
  }
  return dot;
}

Float32List _centroid(List<Float32List> items) {
  final sum = List<double>.filled(items.first.length, 0);
  for (final e in items) {
    for (var i = 0; i < sum.length; i++) {
      sum[i] += e[i];
    }
  }
  return normalize(sum);
}

/// Elige qué rostros de una carpeta enseñan a quién representa:
/// primero fotos con un solo rostro; si hay pocas, el rostro más grande de
/// cada foto. Las fotos grupales no contaminan el perfil.
List<Float32List> selectProfileEmbeddings(List<StoredFace> faces) {
  final solo = faces.where((f) => f.faceCount == 1).toList();
  if (solo.length >= minProfileSamples) {
    return solo.map((f) => f.embedding).toList();
  }
  final largest = <String, StoredFace>{};
  for (final f in faces) {
    final current = largest[f.path];
    if (current == null || f.area > current.area) largest[f.path] = f;
  }
  return largest.values.map((f) => f.embedding).toList();
}

/// Crea el perfil de una carpeta o null si no hay muestras suficientes.
/// Descarta rostros atípicos (otra persona en la carpeta) antes de promediar.
FaceProfile? buildProfile(int folderId, List<Float32List> embeddings) {
  if (embeddings.length < minProfileSamples) return null;
  var kept = List<Float32List>.of(embeddings);
  var center = _centroid(kept);
  for (var round = 0; round < 3; round++) {
    final sims = kept.map((e) => similarity(e, center)).toList()..sort();
    final median = sims[sims.length ~/ 2];
    final cut = math.max(0.4, median - 0.15);
    final next = kept.where((e) => similarity(e, center) >= cut).toList();
    if (next.length < minProfileSamples || next.length == kept.length) break;
    kept = next;
    center = _centroid(kept);
  }
  final own = kept.map((e) => similarity(e, center)).toList()..sort();
  final p10 = own[(own.length * 0.1).floor()];
  final threshold = (p10 - 0.05).clamp(minThreshold, maxThreshold).toDouble();
  return FaceProfile(folderId, center, threshold, kept.length, kept);
}

/// Mejor carpeta para un rostro, o null si ninguna coincide con claridad.
FaceHit? matchFace(Float32List face, List<FaceProfile> profiles,
    {Set<int> exclude = const {}}) {
  FaceHit? best;
  double second = -1;
  for (final p in profiles) {
    if (exclude.contains(p.folderId)) continue;
    final score = similarity(face, p.centroid);
    if (score < p.threshold) continue;
    if (best == null || score > best.score) {
      if (best != null) second = best.score;
      best = FaceHit(p.folderId, score);
    } else if (score > second) {
      second = score;
    }
  }
  if (best == null) return null;
  if (second >= 0 && best.score - second < minMargin) return null;
  return best;
}

const double relaxedThreshold = 0.62;
const double relaxedMargin = 0.05;

/// Parecido con los rostros concretos de la carpeta (promedio de los dos más
/// cercanos): sirve cuando el ángulo o la luz alejan al rostro del promedio.
double neighborScore(Float32List face, FaceProfile p) {
  final sims = p.members.map((m) => similarity(face, m)).toList()
    ..sort((a, b) => b.compareTo(a));
  if (sims.isEmpty) return -1;
  return sims.length > 1 ? (sims[0] + sims[1]) / 2 : sims[0];
}

/// Segundo intento, más tolerante que [matchFace]. Sus resultados son
/// "posibles" y deben revisarse antes de mover.
FaceHit? matchFaceRelaxed(Float32List face, List<FaceProfile> profiles) {
  FaceHit? best;
  double second = -1;
  for (final p in profiles) {
    final score = neighborScore(face, p);
    if (score < relaxedThreshold) continue;
    if (best == null || score > best.score) {
      if (best != null) second = best.score;
      best = FaceHit(p.folderId, score);
    } else if (score > second) {
      second = score;
    }
  }
  if (best == null) return null;
  if (second >= 0 && best.score - second < relaxedMargin) return null;
  return best;
}

/// Perfil reforzado con rostros que ya se asignaron con mucha seguridad.
FaceProfile augmentProfile(FaceProfile base, List<Float32List> extra) {
  if (extra.isEmpty) return base;
  return buildProfile(base.folderId, [...base.members, ...extra]) ?? base;
}
