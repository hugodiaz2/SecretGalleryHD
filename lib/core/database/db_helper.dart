import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../services/media_transfer_service.dart';

class DBHelper implements TransferRepository {
  static final DBHelper instance = DBHelper._internal();
  static Database? _db;
  DBHelper._internal();

  static const dbFileName = 'secret_gallery_v3.db';

  Future<Database> get database async {
    _db ??= await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final path = join(await getDatabasesPath(), dbFileName);
    return await openDatabase(path,
        version: 4, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  /// Cierra la conexión activa y limpia la instancia en caché. Se usa al
  /// restaurar un respaldo, para poder reemplazar el archivo .db en disco
  /// sin que sqflite siga escribiendo sobre el manejador viejo.
  Future<void> closeAndReset() async {
    await _db?.close();
    _db = null;
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE trash ADD COLUMN folder_payload TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE photos ADD COLUMN source_asset_id TEXT');
      await db.execute('ALTER TABLE photos ADD COLUMN source_digest TEXT');
      await db.execute('ALTER TABLE photos ADD COLUMN exported_asset_id TEXT');
      await db.execute('ALTER TABLE photos ADD COLUMN export_name TEXT');
      await db.execute(
          'CREATE INDEX photos_source ON photos(source_asset_id, source_digest)');
    }
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
        source_asset_id TEXT,
        source_digest TEXT,
        exported_asset_id TEXT,
        export_name TEXT,
        date_added INTEGER NOT NULL
      )
    ''');

    await db.execute(
        'CREATE INDEX photos_source ON photos(source_asset_id, source_digest)');

    await db.execute('''
  CREATE TABLE trash (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    original_id INTEGER,
    folder_id INTEGER,
    original_name TEXT,
    encrypted_path TEXT NOT NULL,
    original_path TEXT,
    deleted_at INTEGER NOT NULL,
    folder_payload TEXT,
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
          where: 'name LIKE ?', whereArgs: ['%$search%'], orderBy: 'name ASC');
    }
    return await db.query('folders',
        where: 'parent_id IS NULL', orderBy: 'name ASC');
  }

  /// Subcarpetas de una carpeta
  Future<List<Map<String, dynamic>>> getSubFolders(int parentId) async {
    final db = await database;
    return await db.query('folders',
        where: 'parent_id = ?', whereArgs: [parentId], orderBy: 'name ASC');
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
    return await db.update('folders', data, where: 'id = ?', whereArgs: [id]);
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
    final photos =
        await db.query('photos', where: 'folder_id = ?', whereArgs: [folderId]);
    for (final p in photos) {
      paths.add(p['encrypted_path'] as String);
    }
    final subs = await db
        .query('folders', where: 'parent_id = ?', whereArgs: [folderId]);
    for (final sub in subs) {
      final subPaths = await _getAllPhotoPathsInFolder(db, sub['id'] as int);
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
    final subs = await db
        .query('folders', where: 'parent_id = ?', whereArgs: [folderId]);
    for (final sub in subs) {
      final path = await getCoverPhoto(sub['id'] as int);
      if (path != null) return path;
    }

    return null;
  }

  // ══════════════════════════════════════════
  // PHOTOS
  // ══════════════════════════════════════════

  @override
  Future<Map<String, dynamic>?> findImported(
      String assetId, String digest) async {
    final rows = await (await database).query('photos',
        where: 'source_asset_id = ? AND source_digest = ?',
        whereArgs: [assetId, digest],
        limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<Map<String, dynamic>?> photoForTransfer(int id) async {
    final rows = await (await database)
        .query('photos', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<String> prepareExport(int id, String proposedName) async {
    return (await database).transaction((txn) async {
      final rows =
          await txn.query('photos', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) throw StateError('El registro privado ya no existe.');
      final existing = rows.first['export_name'] as String?;
      if (existing != null) return existing;
      await txn.update('photos', {'export_name': proposedName},
          where: 'id = ?', whereArgs: [id]);
      return proposedName;
    });
  }

  @override
  Future<void> rememberExport(int id, String assetId) async {
    final count = await (await database).update(
        'photos', {'exported_asset_id': assetId},
        where: 'id = ?', whereArgs: [id]);
    if (count != 1) throw StateError('El registro privado ya no existe.');
  }

  @override
  Future<void> finishExport(int id, String encryptedPath) async {
    await (await database).transaction((txn) async {
      await txn.update('folders', {'cover_photo_path': null},
          where: 'cover_photo_path = ?', whereArgs: [encryptedPath]);
      final count = await txn.delete('photos',
          where: 'id = ? AND encrypted_path = ?',
          whereArgs: [id, encryptedPath]);
      if (count != 1) {
        throw StateError('El registro privado cambió durante la exportación.');
      }
    });
  }

  @override
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
    return await db.update('photos', {'folder_id': newFolderId},
        where: 'id = ?', whereArgs: [photoId]);
  }

  Future<int> movePhotos(List<int> photoIds, int newFolderId) async {
    final db = await database;
    int count = 0;
    for (final id in photoIds) {
      count += await db.update('photos', {'folder_id': newFolderId},
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

  Future<Map<String, dynamic>> _folderSnapshot(
      DatabaseExecutor db, int root) async {
    final folders = <Map<String, dynamic>>[];
    final photos = <Map<String, dynamic>>[];
    final pending = <int>[root];
    final seen = <int>{};
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (!seen.add(id)) continue;
      final rows = await db.query('folders', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) continue;
      folders.add(rows.first);
      photos.addAll(
          await db.query('photos', where: 'folder_id = ?', whereArgs: [id]));
      final children = await db.query('folders',
          columns: ['id'], where: 'parent_id = ?', whereArgs: [id]);
      pending.addAll(children.map((f) => f['id'] as int));
    }
    return {'folders': folders, 'photos': photos};
  }

  Future<List<Map<String, dynamic>>> getPhotosInFolders(
      Iterable<int> ids) async {
    final db = await database;
    return db.transaction((txn) async {
      final photos = <int, Map<String, dynamic>>{};
      for (final id in ids) {
        final snapshot = await _folderSnapshot(txn, id);
        for (final photo in snapshot['photos'] as List<Map<String, dynamic>>) {
          photos[photo['id'] as int] = photo;
        }
      }
      return photos.values.toList();
    });
  }

  Future<void> moveFolderToTrash(int folderId) async {
    final db = await database;
    await db.transaction((txn) async {
      final snapshot = await _folderSnapshot(txn, folderId);
      final folders = snapshot['folders'] as List<Map<String, dynamic>>;
      if (folders.isEmpty) return;
      await txn.insert('trash', {
        'original_id': folderId,
        'folder_id': folders.first['parent_id'],
        'original_name': folders.first['name'],
        'encrypted_path': '',
        'type': 'folder',
        'deleted_at': DateTime.now().millisecondsSinceEpoch,
        'folder_payload': jsonEncode(snapshot),
      });
      for (final photo in snapshot['photos'] as List<Map<String, dynamic>>) {
        await txn.update('folders', {'cover_photo_path': null},
            where: 'cover_photo_path = ?',
            whereArgs: [photo['encrypted_path']]);
      }
      for (final folder in folders.reversed) {
        await txn.delete('photos',
            where: 'folder_id = ?', whereArgs: [folder['id']]);
        await txn.delete('folders', where: 'id = ?', whereArgs: [folder['id']]);
      }
    });
  }

  List<String> trashPaths(Map<String, dynamic> item) {
    if (item['type'] != 'folder') return [item['encrypted_path'] as String];
    final snapshot =
        jsonDecode(item['folder_payload'] as String) as Map<String, dynamic>;
    return (snapshot['photos'] as List)
        .map((p) => p['encrypted_path'] as String)
        .toSet()
        .toList();
  }

  Future<void> _restoreFolderFromTrash(int trashId) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows =
          await txn.query('trash', where: 'id = ?', whereArgs: [trashId]);
      if (rows.isEmpty) return;
      final snapshot = jsonDecode(rows.first['folder_payload'] as String)
          as Map<String, dynamic>;
      final remap = <int, int>{};
      for (final raw in snapshot['folders'] as List) {
        final folder = Map<String, dynamic>.from(raw as Map);
        final oldId = folder.remove('id') as int;
        final parent = folder['parent_id'] as int?;
        if (remap.containsKey(parent)) {
          folder['parent_id'] = remap[parent];
        } else if (parent != null) {
          final existing = await txn.query('folders',
              columns: ['id'], where: 'id = ?', whereArgs: [parent]);
          if (existing.isEmpty) folder['parent_id'] = null;
        }
        final collision = await txn.query('folders',
            columns: ['id'], where: 'id = ?', whereArgs: [oldId]);
        if (collision.isEmpty) folder['id'] = oldId;
        remap[oldId] = await txn.insert('folders', folder);
      }
      for (final raw in snapshot['photos'] as List) {
        final photo = Map<String, dynamic>.from(raw as Map)..remove('id');
        photo['folder_id'] = remap[photo['folder_id']]!;
        await txn.insert('photos', photo);
      }
      await txn.delete('trash', where: 'id = ?', whereArgs: [trashId]);
    });
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
    await db.delete('photos', where: 'id = ?', whereArgs: [photo['id']]);
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
    if (item['type'] == 'folder') {
      await _restoreFolderFromTrash(item['id'] as int);
      return;
    }
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
