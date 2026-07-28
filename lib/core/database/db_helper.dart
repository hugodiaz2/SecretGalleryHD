import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBHelper {
  static final DBHelper instance = DBHelper._internal();
  static Database? _db;
  DBHelper._internal();

  Future<Database> get database async {
    _db ??= await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final path = join(await getDatabasesPath(), 'secret_gallery_v3.db');
    return await openDatabase(path,
        version: 2, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS intruders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          encrypted_path TEXT NOT NULL,
          captured_at INTEGER NOT NULL
        )
      ''');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        parent_id INTEGER,
        cover_photo_path TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (parent_id) REFERENCES folders(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE photos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        folder_id INTEGER NOT NULL,
        original_name TEXT,
        encrypted_path TEXT NOT NULL,
        original_path TEXT,
        date_added INTEGER NOT NULL
      )
    ''');

    await db.execute('''
  CREATE TABLE trash (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    original_id INTEGER,
    folder_id INTEGER,
    original_name TEXT,
    encrypted_path TEXT NOT NULL,
    original_path TEXT,
    deleted_at INTEGER NOT NULL,
    type TEXT DEFAULT 'photo'
  )
''');

    await db.execute('''
  CREATE TABLE intruders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    encrypted_path TEXT NOT NULL,
    captured_at INTEGER NOT NULL
  )
''');
  }

  // ══════════════════════════════════════════
  // INTRUSOS
  // ══════════════════════════════════════════

  Future<int> insertIntruder(Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert('intruders', data);
  }

  Future<List<Map<String, dynamic>>> getIntruders() async {
    final db = await database;
    return await db.query('intruders', orderBy: 'captured_at DESC');
  }

  Future<int> getIntruderCount() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COUNT(*) as c FROM intruders');
    return (r.first['c'] as int?) ?? 0;
  }

  Future<void> deleteIntruder(int id) async {
    final db = await database;
    await db.delete('intruders', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllIntruders() async {
    final db = await database;
    await db.delete('intruders');
  }

  // ══════════════════════════════════════════
  // FOLDERS
  // ══════════════════════════════════════════

  Future<int> insertFolder(Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert('folders', data);
  }

  /// Carpetas raíz (parent_id IS NULL)
  Future<List<Map<String, dynamic>>> getRootFolders({String? search}) async {
    final db = await database;
    if (search != null && search.isNotEmpty) {
      return await db.query('folders',
          where: 'name LIKE ?',
          whereArgs: ['%$search%'],
          orderBy: 'name ASC');
    }
    return await db.query('folders',
        where: 'parent_id IS NULL', orderBy: 'name ASC');
  }

  /// Subcarpetas de una carpeta
  Future<List<Map<String, dynamic>>> getSubFolders(int parentId) async {
    final db = await database;
    return await db.query('folders',
        where: 'parent_id = ?',
        whereArgs: [parentId],
        orderBy: 'name ASC');
  }

  /// Toda la jerarquía como árbol plano (para el menú de mover)
  Future<List<Map<String, dynamic>>> getAllFoldersFlat() async {
    final db = await database;
    return await db.query('folders', orderBy: 'name ASC');
  }

  Future<Map<String, dynamic>?> getFolder(int id) async {
    final db = await database;
    final r = await db.query('folders', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : r.first;
  }

  Future<int> updateFolder(int id, Map<String, dynamic> data) async {
    final db = await database;
    return await db.update('folders', data,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteFolder(int id) async {
    final db = await database;
    await db.delete('folders', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<String>> getEncryptedPathsInFolder(int folderId) async {
    final db = await database;
    return await _getAllPhotoPathsInFolder(db, folderId);
  }

  Future<List<String>> _getAllPhotoPathsInFolder(
      Database db, int folderId) async {
    final paths = <String>[];
    final photos = await db.query('photos',
        where: 'folder_id = ?', whereArgs: [folderId]);
    for (final p in photos) {
      paths.add(p['encrypted_path'] as String);
    }
    final subs = await db.query('folders',
        where: 'parent_id = ?', whereArgs: [folderId]);
    for (final sub in subs) {
      final subPaths =
          await _getAllPhotoPathsInFolder(db, sub['id'] as int);
      paths.addAll(subPaths);
    }
    return paths;
  }

  // ── Portada de carpeta ───────────────────────────────────

  /// Guarda la portada manual de una carpeta
  Future<void> setCoverPhoto(int folderId, String encryptedPath) async {
    final db = await database;
    await db.update(
      'folders',
      {'cover_photo_path': encryptedPath},
      where: 'id = ?',
      whereArgs: [folderId],
    );
  }

  /// Obtiene la portada de una carpeta:
  /// 1. Portada manual si existe
  /// 2. Foto más reciente de la carpeta
  /// 3. Foto más reciente de subcarpetas (recursivo)
  Future<String?> getCoverPhoto(int folderId) async {
    final db = await database;

    // Revisar portada manual
    final folder = await db.query('folders',
        where: 'id = ?', whereArgs: [folderId], limit: 1);
    if (folder.isNotEmpty) {
      final cover = folder.first['cover_photo_path'] as String?;
      if (cover != null && cover.isNotEmpty) return cover;
    }

    // Foto más reciente directa
    final photos = await db.query('photos',
        where: 'folder_id = ?',
        whereArgs: [folderId],
        orderBy: 'date_added DESC',
        limit: 1);
    if (photos.isNotEmpty) {
      return photos.first['encrypted_path'] as String;
    }

    // Buscar en subcarpetas recursivamente
    final subs = await db.query('folders',
        where: 'parent_id = ?', whereArgs: [folderId]);
    for (final sub in subs) {
      final path = await getCoverPhoto(sub['id'] as int);
      if (path != null) return path;
    }

    return null;
  }

  // ══════════════════════════════════════════
  // PHOTOS
  // ══════════════════════════════════════════

  Future<int> insertPhoto(Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert('photos', data);
  }

  Future<List<Map<String, dynamic>>> getPhotosByFolder(int folderId) async {
    final db = await database;
    return await db.query('photos',
        where: 'folder_id = ?',
        whereArgs: [folderId],
        orderBy: 'date_added DESC');
  }

  Future<int> movePhoto(int photoId, int newFolderId) async {
    final db = await database;
    return await db.update(
        'photos', {'folder_id': newFolderId},
        where: 'id = ?', whereArgs: [photoId]);
  }

  Future<int> movePhotos(List<int> photoIds, int newFolderId) async {
    final db = await database;
    int count = 0;
    for (final id in photoIds) {
      count += await db.update(
          'photos', {'folder_id': newFolderId},
          where: 'id = ?', whereArgs: [id]);
    }
    return count;
  }

  Future<int> deletePhoto(int id) async {
    final db = await database;
    return await db.delete('photos', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> getPhotoCount(int folderId) async {
    final db = await database;
    final r = await db.rawQuery(
        'SELECT COUNT(*) as c FROM photos WHERE folder_id = ?', [folderId]);
    return (r.first['c'] as int?) ?? 0;
  }

  Future<int> getTotalPhotoCount(int folderId) async {
    int count = await getPhotoCount(folderId);
    final subs = await getSubFolders(folderId);
    for (final sub in subs) {
      count += await getTotalPhotoCount(sub['id'] as int);
    }
    return count;
  }

  Future<void> moveFolder(int folderId, int? newParentId) async {
    final db = await database;
    await db.update(
      'folders',
      {
        'parent_id': newParentId,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [folderId],
    );
  }

  /// Fotos de la pantalla principal (folder_id = 0)
  Future<List<Map<String, dynamic>>> getMainPhotos() async {
    final db = await database;
    return await db.query(
      'photos',
      where: 'folder_id = ?',
      whereArgs: [0],
      orderBy: 'date_added DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getAllPhotos() async {
    final db = await database;
    return await db.query(
      'photos',
      where: 'folder_id = ?',
      whereArgs: [0],
      orderBy: 'date_added DESC',
    );
  }

  Future<int> moveToTrash(Map<String, dynamic> photo) async {
  final db = await database;
  final now = DateTime.now().millisecondsSinceEpoch;

  // Limpiar portada si esta foto era portada de alguna carpeta
  await db.update(
    'folders',
    {'cover_photo_path': null},
    where: 'cover_photo_path = ?',
    whereArgs: [photo['encrypted_path']],
  );

  final id = await db.insert('trash', {
    'original_id': photo['id'],
    'folder_id': photo['folder_id'],
    'original_name': photo['original_name'],
    'encrypted_path': photo['encrypted_path'],
    'original_path': photo['original_path'],
    'deleted_at': now,
    'type': _getFileType(photo['original_name'] ?? ''),
  });
  await db.delete('photos',
      where: 'id = ?', whereArgs: [photo['id']]);
  return id;
}

String _getFileType(String name) {
  final ext = name.split('.').last.toLowerCase();
  if (['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'].contains(ext)) {
    return 'video';
  }
  return 'photo';
}

Future<List<Map<String, dynamic>>> getTrashItems() async {
  final db = await database;
  return await db.query('trash', orderBy: 'deleted_at DESC');
}

Future<int> getTrashCount() async {
  final db = await database;
  final r = await db.rawQuery('SELECT COUNT(*) as c FROM trash');
  return (r.first['c'] as int?) ?? 0;
}

Future<void> restoreFromTrash(Map<String, dynamic> item) async {
  final db = await database;
  // Verificar si la carpeta destino aún existe
  int folderId = item['folder_id'] as int? ?? 0;
  if (folderId != 0) {
    final folder = await db.query('folders',
        where: 'id = ?', whereArgs: [folderId], limit: 1);
    if (folder.isEmpty) {
      folderId = 0; // Si la carpeta ya no existe, restaurar a principal
    }
  }

  await db.insert('photos', {
    'folder_id': folderId,
    'original_name': item['original_name'],
    'encrypted_path': item['encrypted_path'],
    'original_path': item['original_path'],
    'date_added': DateTime.now().millisecondsSinceEpoch,
  });
  await db.delete('trash', where: 'id = ?', whereArgs: [item['id']]);
}

Future<void> deleteFromTrash(int id) async {
  final db = await database;
  await db.delete('trash', where: 'id = ?', whereArgs: [id]);
}

Future<void> emptyTrash() async {
  final db = await database;
  await db.delete('trash');
}

Future<void> clearCoverIfDeleted(String encryptedPath) async {
  final db = await database;
  await db.update(
    'folders',
    {'cover_photo_path': null},
    where: 'cover_photo_path = ?',
    whereArgs: [encryptedPath],
  );
}
}