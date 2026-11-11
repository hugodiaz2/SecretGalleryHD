import 'dart:math' as math;
import 'dart:typed_data';
import 'face_matcher.dart';

/// Lógica pura (sin plugins) para reconocer el "estilo" de una foto sin usar
/// rostros: colores, brillo, composición, nitidez y orientación. Sirve para
/// fotos donde no hay rostro visible (paisajes, comida, capturas, objetos...).
///
/// El descriptor es pequeño (unas 85 cifras) y se calcula sobre una miniatura,
/// así que analizar una foto cuesta muy poco. Todo ocurre en el teléfono.

/// Cambia cuando cambia la forma de calcular el descriptor: invalida lo guardado.
const String styleVersion = 'style-v1';

/// Ancho/alto de la miniatura sobre la que se calcula el descriptor.
const int styleThumbSide = 64;

/// Mínimo de fotos de una carpeta para aprender su estilo.
const int minStyleSamples = 8;
const double minStyleThreshold = 0.45;
const double maxStyleThreshold = 0.8;

/// Una carpeta sin un estilo reconocible (fotos muy variadas) no se usa.
const double minStyleCohesion = 0.35;
const double styleMargin = 0.08;

const int _hueBins = 12;
const int _satBins = 4;
const int _valBins = 6;
const int _gridSide = 4;
const int _edgeBins = 6;

List<double> _sqrtNormalize(List<double> v, {bool hellinger = false}) {
  final out = List<double>.of(v);
  if (hellinger) {
    for (var i = 0; i < out.length; i++) {
      out[i] = math.sqrt(out[i]);
    }
  }
  var sum = 0.0;
  for (final x in out) {
    sum += x * x;
  }
  final norm = math.sqrt(sum);
  if (norm == 0) return out;
  for (var i = 0; i < out.length; i++) {
    out[i] /= norm;
  }
  return out;
}

List<double> _l1(List<double> v) {
  final total = v.fold<double>(0, (a, b) => a + b);
  if (total == 0) return v;
  return [for (final x in v) x / total];
}

/// Descriptor de estilo de una imagen RGBA de [width]x[height] píxeles.
/// [aspect] es la proporción ancho/alto de la foto original.
Float32List describeRgba(Uint8List rgba, int width, int height, double aspect) {
  final hue = List<double>.filled(_hueBins, 0);
  final sat = List<double>.filled(_satBins, 0);
  final val = List<double>.filled(_valBins, 0);
  final gridSum = List<double>.filled(_gridSide * _gridSide * 3, 0);
  final gridCount = List<double>.filled(_gridSide * _gridSide, 0);
  final gray = Float32List(width * height);

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final r = rgba[i] / 255.0;
      final g = rgba[i + 1] / 255.0;
      final b = rgba[i + 2] / 255.0;
      final maxC = math.max(r, math.max(g, b));
      final minC = math.min(r, math.min(g, b));
      final delta = maxC - minC;
      final s = maxC == 0 ? 0.0 : delta / maxC;

      sat[math.min(_satBins - 1, (s * _satBins).floor())]++;
      val[math.min(_valBins - 1, (maxC * _valBins).floor())]++;
      if (s > 0.15 && maxC > 0.15) {
        double h;
        if (maxC == r) {
          h = ((g - b) / delta) % 6;
        } else if (maxC == g) {
          h = (b - r) / delta + 2;
        } else {
          h = (r - g) / delta + 4;
        }
        // Los colores más vivos pesan más que los apagados.
        hue[math.min(_hueBins - 1, (h / 6 * _hueBins).floor())] += s * maxC;
      }

      final int row = math.min<int>(_gridSide - 1, y * _gridSide ~/ height);
      final int col = math.min<int>(_gridSide - 1, x * _gridSide ~/ width);
      final int cell = row * _gridSide + col;
      gridSum[cell * 3] += r;
      gridSum[cell * 3 + 1] += g;
      gridSum[cell * 3 + 2] += b;
      gridCount[cell]++;
      gray[y * width + x] = 0.299 * r + 0.587 * g + 0.114 * b;
    }
  }

  final grid = List<double>.filled(gridSum.length, 0);
  for (var c = 0; c < gridCount.length; c++) {
    if (gridCount[c] == 0) continue;
    for (var k = 0; k < 3; k++) {
      grid[c * 3 + k] = gridSum[c * 3 + k] / gridCount[c];
    }
  }

  // Bordes: cuánta textura/detalle hay y dónde.
  const edgeCuts = [0.02, 0.05, 0.1, 0.2, 0.4];
  final edge = List<double>.filled(_edgeBins, 0);
  final quad = List<double>.filled(4, 0);
  final quadCount = List<double>.filled(4, 0);
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final gx = gray[y * width + x + 1] - gray[y * width + x - 1];
      final gy = gray[(y + 1) * width + x] - gray[(y - 1) * width + x];
      final mag = math.sqrt(gx * gx + gy * gy);
      var bin = 0;
      while (bin < edgeCuts.length && mag >= edgeCuts[bin]) {
        bin++;
      }
      edge[bin]++;
      final q = (y * 2 ~/ height) * 2 + (x * 2 ~/ width);
      quad[q] += mag;
      quadCount[q]++;
    }
  }
  for (var q = 0; q < 4; q++) {
    quad[q] = quadCount[q] == 0 ? 0 : (quad[q] / quadCount[q] * 4).clamp(0.0, 1.0);
  }

  final portrait = ((0.9 - aspect) / 0.4).clamp(0.0, 1.0);
  final landscape = ((aspect - 1.1) / 0.4).clamp(0.0, 1.0);
  final orientation = [portrait, landscape, 1 - math.max(portrait, landscape)];

  final parts = <List<double>>[
    _sqrtNormalize(_l1(hue), hellinger: true).map((x) => x * 1.0).toList(),
    _sqrtNormalize(_l1(sat), hellinger: true).map((x) => x * 0.6).toList(),
    _sqrtNormalize(_l1(val), hellinger: true).map((x) => x * 0.8).toList(),
    _sqrtNormalize(grid).map((x) => x * 1.0).toList(),
    _sqrtNormalize(_l1(edge), hellinger: true).map((x) => x * 0.8).toList(),
    quad.map((x) => x * 0.5).toList(),
    orientation.map((x) => x * 0.5).toList(),
  ];
  return normalize([for (final p in parts) ...p]);
}

/// Promedio de varios descriptores (sirve como "estilo medio" de la bóveda).
Float32List meanVector(List<Float32List> items) {
  final sum = Float32List(items.first.length);
  for (final v in items) {
    for (var i = 0; i < sum.length; i++) {
      sum[i] += v[i];
    }
  }
  for (var i = 0; i < sum.length; i++) {
    sum[i] /= items.length;
  }
  return sum;
}

/// Resta el estilo medio para que la comparación resalte lo que distingue a
/// una carpeta de las demás, no lo que todas las fotos tienen en común.
Float32List centerVector(Float32List v, Float32List mean) {
  final out = List<double>.filled(v.length, 0);
  for (var i = 0; i < v.length; i++) {
    out[i] = v[i] - mean[i];
  }
  return normalize(out);
}

/// Estilo de una carpeta.
class StyleProfile {
  final int folderId;
  final Float32List centroid;
  final double threshold;
  final List<Float32List> members;
  const StyleProfile(this.folderId, this.centroid, this.threshold, this.members);
  int get samples => members.length;
}

/// Crea el estilo de una carpeta a partir de descriptores ya centrados, o null
/// si hay pocas fotos o son demasiado distintas entre sí para tener un estilo.
StyleProfile? buildStyleProfile(int folderId, List<Float32List> centered) {
  if (centered.length < minStyleSamples) return null;
  final sum = List<double>.filled(centered.first.length, 0);
  for (final v in centered) {
    for (var i = 0; i < sum.length; i++) {
      sum[i] += v[i];
    }
  }
  final center = normalize(sum);
  final own = centered.map((v) => similarity(v, center)).toList()..sort();
  final median = own[own.length ~/ 2];
  if (median < minStyleCohesion) return null;
  final p20 = own[(own.length * 0.2).floor()];
  final threshold =
      p20.clamp(minStyleThreshold, maxStyleThreshold).toDouble();
  return StyleProfile(folderId, center, threshold, centered);
}

/// Parecido de una foto (ya centrada) con una carpeta: mezcla del parecido
/// con el estilo medio y con las tres fotos más cercanas de la carpeta.
double styleScore(Float32List v, StyleProfile p) {
  final center = similarity(v, p.centroid);
  final sims = p.members.map((m) => similarity(v, m)).toList()
    ..sort((a, b) => b.compareTo(a));
  final top = sims.take(3).toList();
  final near = top.isEmpty ? 0.0 : top.reduce((a, b) => a + b) / top.length;
  return (center + near) / 2;
}

/// Mejor carpeta por estilo, o null si ninguna destaca con claridad.
FaceHit? matchStyle(Float32List v, List<StyleProfile> profiles) {
  FaceHit? best;
  double second = -1;
  for (final p in profiles) {
    final score = styleScore(v, p);
    if (score < p.threshold) continue;
    if (best == null || score > best.score) {
      if (best != null) second = best.score;
      best = FaceHit(p.folderId, score);
    } else if (score > second) {
      second = score;
    }
  }
  if (best == null) return null;
  if (second >= 0 && best.score - second < styleMargin) return null;
  return best;
}
