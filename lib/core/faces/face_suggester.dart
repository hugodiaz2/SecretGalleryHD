import 'dart:typed_data';
import '../database/db_helper.dart';
import '../services/media_service.dart';
import 'face_matcher.dart';
import 'face_service.dart';
import 'face_store.dart';

class PhotoMatch {
  final Map<String, dynamic> photo;
  final double score;

  /// true si solo coincidió en el segundo intento (más tolerante): conviene
  /// revisarla antes de mover.
  final bool uncertain;
  const PhotoMatch(this.photo, this.score, {this.uncertain = false});
}

class FaceSuggestion {
  final int folderId;
  final String folderName;
  final List<PhotoMatch> photos;
  FaceSuggestion(this.folderId, this.folderName, this.photos);
}

class FaceSuggestResult {
  final List<FaceSuggestion> suggestions;
  final int learnedFolders; // carpetas con huella suficiente
  final int homePhotos; // fotos sueltas revisadas
  final int noFace; // sin rostro visible
  final int noMatch; // con rostro pero sin carpeta parecida
  final int unreadable; // no se pudieron leer
  final List<Map<String, dynamic>> unmatched; // con rostro, sin carpeta
  const FaceSuggestResult({
    required this.unmatched,
    required this.suggestions,
    required this.learnedFolders,
    required this.homePhotos,
    required this.noFace,
    required this.noMatch,
    required this.unreadable,
  });
}

/// Sugiere carpetas para las fotos sueltas de Inicio. Solo lee: no mueve,
/// edita ni borra nada de la bóveda.
class FaceSuggester {
  FaceSuggester({
    this.scopeFolderId = 0,
    required this.onProgress,
    required this.isCancelled,
  });

  /// Carpeta cuyas fotos sueltas se clasifican (0 = Inicio).
  final int scopeFolderId;
  final void Function(String stage, int done, int total) onProgress;

  /// Ids de todas las carpetas que cuelgan de [scope], a cualquier profundidad.
  /// Para Inicio son todas las carpetas.
  static Set<int> _descendants(List<Map<String, dynamic>> folders, int scope) {
    if (scope == 0) return {for (final f in folders) f['id'] as int};
    final children = <int, List<int>>{};
    for (final f in folders) {
      final parent = f['parent_id'] as int?;
      if (parent != null) children.putIfAbsent(parent, () => []).add(f['id'] as int);
    }
    final out = <int>{};
    final queue = [scope];
    while (queue.isNotEmpty) {
      for (final child in children[queue.removeLast()] ?? const <int>[]) {
        if (out.add(child)) queue.add(child);
      }
    }
    return out;
  }
  final bool Function() isCancelled;

  static const _workers = 3;

  /// Para aprender a una persona bastan unas decenas de fotos de su carpeta.
  static const maxLearnPerFolder = 60;

  /// De cada carpeta toma, como mucho, [maxLearnPerFolder] fotos en total
  /// (contando las ya analizadas), repartidas a lo largo de la carpeta para
  /// tener ángulos y momentos distintos.
  static List<Map<String, dynamic>> _sampleForLearning(
      List<Map<String, dynamic>> inFolders, Set<String> scanned) {
    final byFolder = <int, List<Map<String, dynamic>>>{};
    for (final r in inFolders) {
      byFolder.putIfAbsent(r['folder_id'] as int, () => []).add(r);
    }
    final pick = <Map<String, dynamic>>[];
    for (final photos in byFolder.values) {
      final done = photos.where((r) => scanned.contains(r['encrypted_path'])).length;
      final need = maxLearnPerFolder - done;
      final todo =
          photos.where((r) => !scanned.contains(r['encrypted_path'])).toList();
      if (need <= 0 || todo.isEmpty) continue;
      if (todo.length <= need) {
        pick.addAll(todo);
      } else {
        final step = todo.length / need;
        for (var i = 0; i < need; i++) {
          pick.add(todo[(i * step).floor()]);
        }
      }
    }
    return pick;
  }

  static bool _isPhoto(Map<String, dynamic> row) =>
      !MediaService.isVideoPath(row['encrypted_path'] as String);

  Future<FaceSuggestResult?> run() async {
    final db = DBHelper.instance;
    final store = FaceStore.instance;

    final folders = await db.getAllFoldersFlat();
    final all = (await db.getAllPhotos()).where(_isPhoto).toList();
    await store.prune(all.map((r) => r['encrypted_path'] as String).toSet());

    // Fotos sueltas de la carpeta de trabajo (Inicio = 0) y, como destinos
    // posibles, las carpetas que cuelgan de ella.
    final targets = _descendants(folders, scopeFolderId);
    final home = all.where((r) => r['folder_id'] == scopeFolderId).toList();
    final inFolders = all.where((r) => targets.contains(r['folder_id'])).toList();

    // 1) Analizar lo que falta (carpetas primero: de ahí se aprende).
    final scanned = await store.scannedPaths();
    final pending = [
      ..._sampleForLearning(inFolders, scanned),
      ...home.where((r) => !scanned.contains(r['encrypted_path'])),
    ];
    var unreadable = 0;
    final failed = <String>{};

    // Varias fotos a la vez: el descifrado, la decodificación y ML Kit
    // trabajan fuera del hilo de la interfaz y se solapan entre sí.
    Future<void> scanAll(
        List<Map<String, dynamic>> items, String stage, bool deep) async {
      var done = 0;
      var next = 0;
      onProgress(stage, 0, items.length);
      Future<void> worker() async {
        while (!isCancelled()) {
          final index = next++;
          if (index >= items.length) return;
          final path = items[index]['encrypted_path'] as String;
          final faces = await FaceService.instance.analyzePhoto(path, deep: deep);
          if (faces == null) {
            unreadable++;
            failed.add(path);
          } else {
            await store.saveScan(path, faces, deep: deep);
          }
          onProgress(stage, ++done, items.length);
        }
      }

      await Future.wait(List.generate(_workers, (_) => worker()));
    }

    await scanAll(pending, 'Analizando rostros', false);
    if (isCancelled()) return null;

    // 1b) Segundo intento para fotos sin rostro: más resolución y tolerancia
    // a rostros pequeños o de perfil. Una sola vez por foto.
    final homePaths = home.map((r) => r['encrypted_path'] as String).toList();
    final firstCounts = await store.faceCounts(homePaths);
    final deepDone = await store.deepScannedPaths();
    final retry = home.where((r) {
      final path = r['encrypted_path'] as String;
      return !failed.contains(path) &&
          firstCounts[path] == 0 &&
          !deepDone.contains(path);
    }).toList();
    if (retry.isNotEmpty) {
      await scanAll(retry, 'Segundo intento con rostros difíciles', true);
      if (isCancelled()) return null;
    }
    onProgress('Buscando coincidencias', 1, 1);

    // 2) Huella por carpeta (solo sus fotos directas).
    final byFolder = <int, List<String>>{};
    for (final r in inFolders) {
      byFolder
          .putIfAbsent(r['folder_id'] as int, () => [])
          .add(r['encrypted_path'] as String);
    }
    final profiles = <FaceProfile>[];
    for (final entry in byFolder.entries) {
      final faces = await store.facesFor(entry.value);
      final profile = buildProfile(entry.key, selectProfileEmbeddings(faces));
      if (profile != null) profiles.add(profile);
    }
    final thresholds = {for (final p in profiles) p.folderId: p.threshold};

    // 3) Primera pasada: coincidencias claras.
    final counts = await store.faceCounts(homePaths);
    final homeFaces = <String, List<StoredFace>>{};
    for (final f in await store.facesFor(homePaths)) {
      homeFaces.putIfAbsent(f.path, () => []).add(f);
    }
    final names = {for (final f in folders) f['id'] as int: f['name'] as String};
    final grouped = <int, List<PhotoMatch>>{};
    final confident = <int, List<Float32List>>{};
    final retryPhotos = <Map<String, dynamic>>[];
    var noFace = 0;
    for (final photo in home) {
      final path = photo['encrypted_path'] as String;
      if (failed.contains(path)) continue;
      final faces = homeFaces[path];
      if (faces == null || faces.isEmpty) {
        if ((counts[path] ?? 0) == 0) noFace++;
        continue;
      }
      final best = <int, double>{};
      for (final face in faces) {
        final hit = matchFace(face.embedding, profiles);
        if (hit == null) continue;
        if (hit.score > (best[hit.folderId] ?? -1)) best[hit.folderId] = hit.score;
        if (hit.score >= (thresholds[hit.folderId] ?? 1) + 0.08) {
          confident.putIfAbsent(hit.folderId, () => []).add(face.embedding);
        }
      }
      if (best.isEmpty) {
        retryPhotos.add(photo);
        continue;
      }
      best.forEach((folderId, score) {
        grouped.putIfAbsent(folderId, () => []).add(PhotoMatch(photo, score));
      });
    }

    // 4) Segundo intento con las que no coincidieron: perfiles reforzados con
    // las coincidencias más seguras y comparación contra rostros concretos.
    final profiles2 = [
      for (final p in profiles) augmentProfile(p, confident[p.folderId] ?? const [])
    ];
    final unmatched = <Map<String, dynamic>>[];
    for (final photo in retryPhotos) {
      final faces = homeFaces[photo['encrypted_path']]!;
      final best = <int, double>{};
      final sure = <int>{};
      for (final face in faces) {
        final strict = matchFace(face.embedding, profiles2);
        final hit = strict ?? matchFaceRelaxed(face.embedding, profiles2);
        if (hit == null) continue;
        if (strict != null) sure.add(hit.folderId);
        if (hit.score > (best[hit.folderId] ?? -1)) best[hit.folderId] = hit.score;
      }
      if (best.isEmpty) {
        unmatched.add(photo);
        continue;
      }
      best.forEach((folderId, score) {
        grouped.putIfAbsent(folderId, () => []).add(
            PhotoMatch(photo, score, uncertain: !sure.contains(folderId)));
      });
    }

    // Dentro de cada grupo, primero las seguras.
    final suggestions = grouped.entries
        .where((e) => names.containsKey(e.key))
        .map((e) => FaceSuggestion(
            e.key,
            names[e.key]!,
            e.value
              ..sort((a, b) {
                if (a.uncertain != b.uncertain) return a.uncertain ? 1 : -1;
                return b.score.compareTo(a.score);
              })))
        .toList()
      ..sort((a, b) => b.photos.length.compareTo(a.photos.length));

    return FaceSuggestResult(
      suggestions: suggestions,
      learnedFolders: profiles.length,
      homePhotos: home.length,
      noFace: noFace,
      noMatch: unmatched.length,
      unreadable: unreadable,
      unmatched: unmatched,
    );
  }
}
