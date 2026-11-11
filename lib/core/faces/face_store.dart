import 'dart:typed_data';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'face_matcher.dart';
import 'style_matcher.dart';

/// Huellas de rostros en una base propia (`sg_faces.db`), separada de la
/// bóveda: no modifica el esquema ni los datos de secret_gallery_v3.db y se
/// puede borrar sin perder fotos (solo habría que volver a analizar).
class FaceStore {
  FaceStore._();
  static final FaceStore instance = FaceStore._();

  static const fileName = 'sg_faces.db';
  static const modelId = 'facenet128-v1';
  static Database? _db;

  Future<Database> get _database async {
    _db ??= await openDatabase(
      join(await getDatabasesPath(), fileName),
      version: 3,
      onUpgrade: (db, from, _) async {
        if (from < 2) {
          await db.execute(
              'CREATE TABLE IF NOT EXISTS deep_scanned (path TEXT PRIMARY KEY)');
        }
        if (from < 3) await _createStyles(db);
      },
      onCreate: (db, _) async {
        await _createStyles(db);
        await db.execute(
            'CREATE TABLE deep_scanned (path TEXT PRIMARY KEY)');
        await db.execute('''
          CREATE TABLE scanned (
            path TEXT PRIMARY KEY,
            face_count INTEGER NOT NULL,
            model TEXT NOT NULL,
            scanned_at INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE faces (
            path TEXT NOT NULL,
            idx INTEGER NOT NULL,
            area REAL NOT NULL,
            embedding BLOB NOT NULL,
            PRIMARY KEY (path, idx)
          )''');
      },
    );
    return _db!;
  }

  static Future<void> _createStyles(Database db) => db.execute('''
    CREATE TABLE IF NOT EXISTS styles (
      path TEXT PRIMARY KEY,
      version TEXT NOT NULL,
      vec BLOB NOT NULL
    )''');

  /// Rutas con estilo ya calculado con la versión actual del descriptor.
  Future<Set<String>> styledPaths() async {
    final db = await _database;
    final rows = await db.query('styles',
        columns: ['path'], where: 'version = ?', whereArgs: [styleVersion]);
    return rows.map((r) => r['path'] as String).toSet();
  }

  Future<void> saveStyle(String path, Float32List vector) async {
    final db = await _database;
    await db.insert(
        'styles',
        {
          'path': path,
          'version': styleVersion,
          'vec': vector.buffer
              .asUint8List(vector.offsetInBytes, vector.lengthInBytes),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Descriptores de estilo guardados de las rutas indicadas.
  Future<Map<String, Float32List>> stylesFor(Iterable<String> paths) async {
    final db = await _database;
    final list = paths.toList();
    final out = <String, Float32List>{};
    for (var i = 0; i < list.length; i += 400) {
      final chunk = list.sublist(i, i + 400 > list.length ? list.length : i + 400);
      final marks = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
          'SELECT path, vec FROM styles WHERE version = ? AND path IN ($marks)',
          [styleVersion, ...chunk]);
      for (final r in rows) {
        final blob = Uint8List.fromList(r['vec'] as List<int>);
        out[r['path'] as String] = blob.buffer.asFloat32List();
      }
    }
    return out;
  }

  /// Rutas ya analizadas con el modelo actual.
  Future<Set<String>> scannedPaths() async {
    final db = await _database;
    final rows = await db.query('scanned',
        columns: ['path'], where: 'model = ?', whereArgs: [modelId]);
    return rows.map((r) => r['path'] as String).toSet();
  }

  /// Rutas que ya tuvieron el segundo intento (más resolución y tolerancia).
  Future<Set<String>> deepScannedPaths() async {
    final db = await _database;
    final rows = await db.query('deep_scanned', columns: ['path']);
    return rows.map((r) => r['path'] as String).toSet();
  }

  Future<void> saveScan(
      String path, List<({double area, Float32List vector})> faces,
      {bool deep = false}) async {
    final db = await _database;
    await db.transaction((txn) async {
      if (deep) {
        await txn.insert('deep_scanned', {'path': path},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.delete('faces', where: 'path = ?', whereArgs: [path]);
      await txn.insert(
          'scanned',
          {
            'path': path,
            'face_count': faces.length,
            'model': modelId,
            'scanned_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      for (var i = 0; i < faces.length; i++) {
        await txn.insert('faces', {
          'path': path,
          'idx': i,
          'area': faces[i].area,
          'embedding': faces[i].vector.buffer.asUint8List(
              faces[i].vector.offsetInBytes, faces[i].vector.lengthInBytes),
        });
      }
    });
  }

  /// Rostros guardados de las rutas indicadas (en lotes por el límite de SQLite).
  Future<List<StoredFace>> facesFor(Iterable<String> paths) async {
    final db = await _database;
    final list = paths.toList();
    final out = <StoredFace>[];
    for (var i = 0; i < list.length; i += 400) {
      final chunk = list.sublist(i, i + 400 > list.length ? list.length : i + 400);
      final marks = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery('''
        SELECT f.path AS path, f.area AS area, f.embedding AS embedding,
               s.face_count AS face_count
        FROM faces f JOIN scanned s ON s.path = f.path
        WHERE s.model = ? AND f.path IN ($marks)''', [modelId, ...chunk]);
      for (final r in rows) {
        final blob = Uint8List.fromList(r['embedding'] as List<int>);
        out.add(StoredFace(
          r['path'] as String,
          r['face_count'] as int,
          (r['area'] as num).toDouble(),
          blob.buffer.asFloat32List(),
        ));
      }
    }
    return out;
  }

  /// Número de rostros válidos por ruta analizada (0 = sin rostro visible).
  Future<Map<String, int>> faceCounts(Iterable<String> paths) async {
    final db = await _database;
    final list = paths.toList();
    final out = <String, int>{};
    for (var i = 0; i < list.length; i += 400) {
      final chunk = list.sublist(i, i + 400 > list.length ? list.length : i + 400);
      final marks = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
          'SELECT path, face_count FROM scanned WHERE model = ? AND path IN ($marks)',
          [modelId, ...chunk]);
      for (final r in rows) {
        out[r['path'] as String] = r['face_count'] as int;
      }
    }
    return out;
  }

  /// Quita registros de fotos que ya no existen en la bóveda.
  Future<void> prune(Set<String> existing) async {
    final db = await _database;
    final stale = <String>{};
    for (final table in ['scanned', 'styles']) {
      final rows = await db.query(table, columns: ['path']);
      stale.addAll(rows
          .map((r) => r['path'] as String)
          .where((p) => !existing.contains(p)));
    }
    if (stale.isEmpty) return;
    await db.transaction((txn) async {
      for (final p in stale) {
        await txn.delete('faces', where: 'path = ?', whereArgs: [p]);
        await txn.delete('scanned', where: 'path = ?', whereArgs: [p]);
        await txn.delete('deep_scanned', where: 'path = ?', whereArgs: [p]);
        await txn.delete('styles', where: 'path = ?', whereArgs: [p]);
      }
    });
  }

  Future<void> clear() async {
    final db = await _database;
    await db.delete('faces');
    await db.delete('scanned');
    await db.delete('deep_scanned');
    await db.delete('styles');
  }
}
