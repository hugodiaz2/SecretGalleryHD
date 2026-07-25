import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/db_helper.dart';
import '../../core/services/media_service.dart';
import '../../core/services/prefs_service.dart';
import '../../shared/widgets/photo_thumbnail.dart';
import '../../shared/widgets/folder_thumbnail.dart';
import '../../shared/widgets/folder_tree_sheet.dart';
import '../../shared/widgets/unlock_helper.dart';
import '../../shared/widgets/cover_picker_sheet.dart';
import '../../shared/widgets/view_selector_sheet.dart';
import '../import/gallery_picker_screen.dart';
import '../photos/photo_viewer_screen.dart';
import '../photos/video_player_screen.dart';

class FolderDetailScreen extends StatefulWidget {
  final Map<String, dynamic> folder;
  const FolderDetailScreen({super.key, required this.folder});

  @override
  State<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends State<FolderDetailScreen> {
  final _db = DBHelper.instance;
  final _media = MediaService.instance;

  List<Map<String, dynamic>> _subFolders = [];
  List<Map<String, dynamic>> _photos = [];
  List<Map<String, dynamic>> _filteredSubFolders = [];
  List<Map<String, dynamic>> _filteredPhotos = [];

  bool _showSearch = false;
  String _search = '';
  final _searchCtrl = TextEditingController();

  GridViewType _viewType = GridViewType.grid3;

  bool _selectingPhotos = false;
  final Set<int> _selectedPhotoIds = {};

  bool _selectingFolders = false;
  final Set<int> _selectedFolderIds = {};

  bool get _isSelecting => _selectingPhotos || _selectingFolders;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final type = await PrefsService.instance.getGridType();
    setState(() => _viewType = type);
  }

  Future<void> _load() async {
    final subs = await _db.getSubFolders(widget.folder['id']);
    final photos = await _db.getPhotosByFolder(widget.folder['id']);
    final enriched = await Future.wait(subs.map((s) async {
      final count = await _db.getTotalPhotoCount(s['id']);
      final subsubs = await _db.getSubFolders(s['id']);
      return {...s, 'total_count': count, 'sub_count': subsubs.length};
    }));
    setState(() {
      _subFolders = enriched;
      _photos = photos;
      _filterContent();
    });
  }

  void _filterContent() {
    if (_search.isEmpty) {
      _filteredSubFolders = List.from(_subFolders);
      _filteredPhotos = List.from(_photos);
    } else {
      _filteredSubFolders = _subFolders
          .where((f) => (f['name'] as String)
              .toLowerCase()
              .contains(_search.toLowerCase()))
          .toList();
      _filteredPhotos = _photos
          .where((p) => (p['original_name'] ?? '')
              .toLowerCase()
              .contains(_search.toLowerCase()))
          .toList();
    }
  }

  // ── SUBCARPETAS ──────────────────────────────────────────

  Future<void> _createSubFolder() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Nueva subcarpeta',
            style: GoogleFonts.poppins(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Nombre',
            hintStyle: const TextStyle(color: Colors.white38),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF3D3D3D)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.blue),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar',
                style: GoogleFonts.poppins(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text('Crear',
                style: GoogleFonts.poppins(color: Colors.blue)),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _db.insertFolder({
        'name': name,
        'parent_id': widget.folder['id'],
        'created_at': now,
        'updated_at': now,
      });
      _load();
    }
  }

  Future<void> _renameFolder(Map<String, dynamic> folder) async {
    final ctrl = TextEditingController(text: folder['name']);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Renombrar',
            style: GoogleFonts.poppins(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF3D3D3D)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.blue),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar',
                style: GoogleFonts.poppins(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text('Guardar',
                style: GoogleFonts.poppins(color: Colors.blue)),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await _db.updateFolder(folder['id'], {
        'name': name,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      _load();
    }
  }

  Future<void> _deleteFolder(Map<String, dynamic> folder) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Eliminar',
            style: GoogleFonts.poppins(color: Colors.white)),
        content: Text(
          '¿Eliminar "${folder['name']}" y todo su contenido?',
          style: GoogleFonts.poppins(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: GoogleFonts.poppins(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Eliminar',
                style: GoogleFonts.poppins(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _media.deleteFolder(folder['id']);
      _load();
    }
  }

  Future<void> _moveSelectedFolders() async {
  final dest = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FolderTreeSheet(
      excludeFolderIds: [
        widget.folder['id'],
        ..._selectedFolderIds.toList(),
      ],
      currentFolderId: widget.folder['id'],
    ),
  );
  if (dest == null) return;
  for (final id in _selectedFolderIds) {
    await _db.updateFolder(id, {
      'parent_id': dest['id'],
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }
  setState(() {
    _selectingFolders = false;
    _selectedFolderIds.clear();
  });
  _load();
}

  Future<void> _deleteSelectedFolders() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Eliminar carpetas',
            style: GoogleFonts.poppins(color: Colors.white)),
        content: Text(
          '¿Eliminar ${_selectedFolderIds.length} carpeta${_selectedFolderIds.length == 1 ? '' : 's'} y todo su contenido?',
          style: GoogleFonts.poppins(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: GoogleFonts.poppins(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Eliminar',
                style: GoogleFonts.poppins(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    for (final id in _selectedFolderIds) {
      await _media.deleteFolder(id);
    }
    setState(() {
      _selectingFolders = false;
      _selectedFolderIds.clear();
    });
    _load();
  }

  void _toggleFolderSelect(int id) {
    setState(() {
      if (_selectedFolderIds.contains(id)) {
        _selectedFolderIds.remove(id);
        if (_selectedFolderIds.isEmpty) _selectingFolders = false;
      } else {
        _selectedFolderIds.add(id);
      }
    });
  }

  void _showFolderMenu(Map<String, dynamic> folder, Offset offset) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          offset.dx, offset.dy, offset.dx + 1, offset.dy + 1),
      color: const Color(0xFF2A2A2A),
      items: [
        PopupMenuItem(
          value: 'cover',
          child: Row(children: [
            const Icon(Icons.image_outlined,
                color: Colors.white70, size: 18),
            const SizedBox(width: 10),
            Text('Elegir portada',
                style: GoogleFonts.poppins(
                    color: Colors.white, fontSize: 13)),
          ]),
        ),
        PopupMenuItem(
          value: 'rename',
          child: Row(children: [
            const Icon(Icons.drive_file_rename_outline,
                color: Colors.white70, size: 18),
            const SizedBox(width: 10),
            Text('Renombrar',
                style: GoogleFonts.poppins(
                    color: Colors.white, fontSize: 13)),
          ]),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            const Icon(Icons.delete_outline,
                color: Colors.redAccent, size: 18),
            const SizedBox(width: 10),
            Text('Eliminar',
                style: GoogleFonts.poppins(
                    color: Colors.redAccent, fontSize: 13)),
          ]),
        ),
      ],
    );
    if (selected == 'cover') {
      final changed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => CoverPickerSheet(folderId: folder['id']),
      );
      if (changed == true) _load();
    }
    if (selected == 'rename') _renameFolder(folder);
    if (selected == 'delete') _deleteFolder(folder);
  }

  // ── FOTOS ────────────────────────────────────────────────

  void _togglePhotoSelect(int id) {
    setState(() {
      if (_selectedPhotoIds.contains(id)) {
        _selectedPhotoIds.remove(id);
        if (_selectedPhotoIds.isEmpty) _selectingPhotos = false;
      } else {
        _selectedPhotoIds.add(id);
      }
    });
  }

  Future<void> _moveSelectedPhotos() async {
  final dest = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FolderTreeSheet(
      excludeFolderIds: [widget.folder['id']], // excluye carpeta actual
      currentFolderId: widget.folder['id'],    // muestra dónde estás
    ),
  );
  if (dest == null) return;
  await _db.movePhotos(_selectedPhotoIds.toList(), dest['id']);
  setState(() {
    _selectingPhotos = false;
    _selectedPhotoIds.clear();
  });
  _load();
}

  Future<void> _deleteSelectedPhotos() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Eliminar fotos',
            style: GoogleFonts.poppins(color: Colors.white)),
        content: Text(
          '¿Eliminar ${_selectedPhotoIds.length} foto${_selectedPhotoIds.length == 1 ? '' : 's'}?',
          style: GoogleFonts.poppins(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: GoogleFonts.poppins(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Eliminar',
                style: GoogleFonts.poppins(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final toDelete = _photos
        .where((p) => _selectedPhotoIds.contains(p['id']))
        .toList();
    for (final p in toDelete) {
      await _media.deletePhoto(p);
    }
    setState(() {
      _selectingPhotos = false;
      _selectedPhotoIds.clear();
    });
    _load();
  }

  // ── HELPERS ──────────────────────────────────────────────

  int get _crossAxisCount {
    switch (_viewType) {
      case GridViewType.grid3: return 3;
      case GridViewType.grid4: return 4;
      case GridViewType.grid5: return 5;
      case GridViewType.grid6: return 6;
      default: return 3;
    }
  }

  void _applySort(String v) {
    setState(() {
      if (v == 'az') {
        _filteredSubFolders.sort((a, b) =>
            (a['name'] as String).compareTo(b['name'] as String));
        _filteredPhotos.sort((a, b) =>
            (a['original_name'] ?? '')
                .compareTo(b['original_name'] ?? ''));
      } else if (v == 'za') {
        _filteredSubFolders.sort((a, b) =>
            (b['name'] as String).compareTo(a['name'] as String));
        _filteredPhotos.sort((a, b) =>
            (b['original_name'] ?? '')
                .compareTo(a['original_name'] ?? ''));
      } else if (v == 'newest') {
        _filteredPhotos.sort((a, b) =>
            (b['date_added'] as int).compareTo(a['date_added'] as int));
      } else if (v == 'oldest') {
        _filteredPhotos.sort((a, b) =>
            (a['date_added'] as int).compareTo(b['date_added'] as int));
      }
    });
  }

  // ── BUILD ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isSelecting) {
          setState(() {
            _selectingPhotos = false;
            _selectingFolders = false;
            _selectedPhotoIds.clear();
            _selectedFolderIds.clear();
          });
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A1A),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              if (_isSelecting) {
                setState(() {
                  _selectingPhotos = false;
                  _selectingFolders = false;
                  _selectedPhotoIds.clear();
                  _selectedFolderIds.clear();
                });
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: _showSearch
              ? TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Buscar...',
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                  ),
                  onChanged: (v) {
                    _search = v;
                    setState(() => _filterContent());
                  },
                )
              : Text(
                  _isSelecting
                      ? _selectingFolders
                          ? '${_selectedFolderIds.length} carpeta${_selectedFolderIds.length == 1 ? '' : 's'}'
                          : '${_selectedPhotoIds.length} foto${_selectedPhotoIds.length == 1 ? '' : 's'}'
                      : widget.folder['name'],
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontSize: 16),
                ),
          actions: [
            // ── Selección carpetas ──
            if (_selectingFolders) ...[
              IconButton(
                icon: const Icon(Icons.drive_file_move_outline,
                    color: Colors.white),
                onPressed: _selectedFolderIds.isEmpty
                    ? null
                    : _moveSelectedFolders,
              ),
              IconButton(
                icon: const Icon(Icons.select_all, color: Colors.white),
                onPressed: () => setState(() => _selectedFolderIds
                    .addAll(_subFolders.map((f) => f['id'] as int))),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Colors.redAccent),
                onPressed: _selectedFolderIds.isEmpty
                    ? null
                    : _deleteSelectedFolders,
              ),
            ]
            // ── Selección fotos ──
            else if (_selectingPhotos) ...[
              IconButton(
                icon: const Icon(Icons.drive_file_move_outline,
                    color: Colors.white),
                onPressed: _selectedPhotoIds.isEmpty
                    ? null
                    : _moveSelectedPhotos,
              ),
              IconButton(
                icon: const Icon(Icons.lock_open_outlined,
                    color: Colors.blue),
                onPressed: _selectedPhotoIds.isEmpty
                    ? null
                    : () async {
                        final toUnlock = _photos
                            .where((p) =>
                                _selectedPhotoIds.contains(p['id']))
                            .toList();
                        await confirmUnlock(context, toUnlock,
                            onDone: () {
                          setState(() {
                            _selectingPhotos = false;
                            _selectedPhotoIds.clear();
                          });
                          _load();
                        });
                      },
              ),
              IconButton(
                icon: const Icon(Icons.select_all, color: Colors.white),
                onPressed: () => setState(() => _selectedPhotoIds
                    .addAll(_photos.map((p) => p['id'] as int))),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Colors.redAccent),
                onPressed: _selectedPhotoIds.isEmpty
                    ? null
                    : _deleteSelectedPhotos,
              ),
            ]
            // ── Modo normal ──
            else ...[
              IconButton(
                icon: Icon(
                  _showSearch ? Icons.close : Icons.search,
                  color: Colors.white,
                ),
                onPressed: () {
                  setState(() {
                    _showSearch = !_showSearch;
                    if (!_showSearch) {
                      _searchCtrl.clear();
                      _search = '';
                      _filterContent();
                    }
                  });
                },
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.sort, color: Colors.white),
                color: const Color(0xFF2A2A2A),
                onSelected: _applySort,
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'az',
                      child: Text('A → Z',
                          style: GoogleFonts.poppins(
                              color: Colors.white, fontSize: 13))),
                  PopupMenuItem(
                      value: 'za',
                      child: Text('Z → A',
                          style: GoogleFonts.poppins(
                              color: Colors.white, fontSize: 13))),
                  PopupMenuItem(
                      value: 'newest',
                      child: Text('Más recientes',
                          style: GoogleFonts.poppins(
                              color: Colors.white, fontSize: 13))),
                  PopupMenuItem(
                      value: 'oldest',
                      child: Text('Más antiguos',
                          style: GoogleFonts.poppins(
                              color: Colors.white, fontSize: 13))),
                ],
              ),
              // ✅ Mismo botón de vista que pantalla principal
              IconButton(
                icon: const Icon(Icons.grid_view, color: Colors.white),
                tooltip: 'Cambiar vista',
                onPressed: () {
                  showDialog(
                    context: context,
                    barrierColor: Colors.black54,
                    builder: (_) => ViewSelectorSheet(
                      current: _viewType,
                      onSelected: (type) async {
                        await PrefsService.instance.saveGridType(type);
                        setState(() => _viewType = type);
                      },
                    ),
                  );
                },
              ),
            ],
          ],
        ),

        body: _filteredSubFolders.isEmpty && _filteredPhotos.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.photo_outlined,
                        size: 64, color: Colors.white12),
                    const SizedBox(height: 12),
                    Text(
                      _search.isNotEmpty
                          ? 'Sin resultados para "$_search"'
                          : 'Sin contenido\nToca + para agregar',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          color: Colors.white24, fontSize: 14),
                    ),
                  ],
                ),
              )
            : _viewType == GridViewType.list
                ? _buildListView()
                : _buildGridView(),

        floatingActionButton: _isSelecting
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton(
                    heroTag: 'sub_add_photo',
                    onPressed: () async {
                      final r = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GalleryPickerScreen(
                              folderId: widget.folder['id']),
                        ),
                      );
                      if (r == true) _load();
                    },
                    backgroundColor: const Color(0xFF1565C0),
                    mini: true,
                    child: const Icon(Icons.add_photo_alternate_outlined,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(height: 10),
                  FloatingActionButton(
                    heroTag: 'sub_add_folder',
                    onPressed: _createSubFolder,
                    backgroundColor: Colors.white,
                    child: const Icon(Icons.add,
                        color: Colors.black, size: 28),
                  ),
                ],
              ),
      ),
    );
  }

  // ── GRID VIEW ────────────────────────────────────────────
  Widget _buildGridView() {
    final allItems = [
      ...(_filteredSubFolders.map((f) => {'type': 'folder', 'data': f})),
      ...(_filteredPhotos.map((p) => {'type': 'photo', 'data': p})),
    ];

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 100),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _crossAxisCount,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        childAspectRatio: 0.95,
      ),
      itemCount: allItems.length,
      itemBuilder: (_, i) {
        final item = allItems[i];
        if (item['type'] == 'folder') {
          final folder = item['data'] as Map<String, dynamic>;
          final id = folder['id'] as int;
          return FolderThumbnail(
            key: ValueKey('sub_folder_$id'),
            folder: folder,
            isSelected: _selectedFolderIds.contains(id),
            onTap: () {
              if (_selectingFolders) {
                _toggleFolderSelect(id);
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FolderDetailScreen(folder: folder),
                  ),
                ).then((_) => _load());
              }
            },
            onLongPress: () {
              setState(() {
                _selectingFolders = true;
                _selectedFolderIds.add(id);
              });
            },
            onMenuTap: (offset) => _showFolderMenu(folder, offset),
          );
        }

        final photo = item['data'] as Map<String, dynamic>;
        final id = photo['id'] as int;
        return PhotoThumbnail(
          key: ValueKey(photo['encrypted_path']),
          photo: photo,
          isSelected: _selectedPhotoIds.contains(id),
          onTap: () {
            if (_selectingPhotos) {
              _togglePhotoSelect(id);
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PhotoViewerScreen(
                    photos: _filteredPhotos,
                    initialIndex: i - _filteredSubFolders.length,
                  ),
                ),
              );
            }
          },
          onLongPress: () {
            setState(() {
              _selectingPhotos = true;
              _selectedPhotoIds.add(id);
            });
          },
        );
      },
    );
  }

  // ── LIST VIEW ────────────────────────────────────────────
  Widget _buildListView() {
    final allItems = [
      ...(_filteredSubFolders.map((f) => {'type': 'folder', 'data': f})),
      ...(_filteredPhotos.map((p) => {'type': 'photo', 'data': p})),
    ];

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 100),
      itemCount: allItems.length,
      itemBuilder: (_, i) {
        final item = allItems[i];

        if (item['type'] == 'folder') {
          final folder = item['data'] as Map<String, dynamic>;
          final id = folder['id'] as int;
          final isSelected = _selectedFolderIds.contains(id);
          final count = (folder['total_count'] as int?) ?? 0;
          final subs = (folder['sub_count'] as int?) ?? 0;

          return ListTile(
            tileColor: isSelected
                ? const Color(0xFF1A2A3A)
                : Colors.transparent,
            onTap: () {
              if (_selectingFolders) {
                _toggleFolderSelect(id);
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FolderDetailScreen(folder: folder),
                  ),
                ).then((_) => _load());
              }
            },
            onLongPress: () {
              setState(() {
                _selectingFolders = true;
                _selectedFolderIds.add(id);
              });
            },
            leading: Stack(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    subs > 0 ? Icons.folder_copy : Icons.folder,
                    color: const Color(0xFF1565C0),
                    size: 28,
                  ),
                ),
                if (isSelected)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.check,
                          color: Colors.white, size: 20),
                    ),
                  ),
              ],
            ),
            title: Text(
              folder['name'] as String,
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              '$count foto${count == 1 ? '' : 's'}${subs > 0 ? ' · $subs subcarpeta${subs == 1 ? '' : 's'}' : ''}',
              style: GoogleFonts.poppins(
                  color: Colors.white38, fontSize: 11),
            ),
            trailing: GestureDetector(
              onTapDown: (d) =>
                  _showFolderMenu(folder, d.globalPosition),
              child: const Icon(Icons.more_vert,
                  color: Colors.white38, size: 20),
            ),
          );
        }

        final photo = item['data'] as Map<String, dynamic>;
        final id = photo['id'] as int;
        final isSelected = _selectedPhotoIds.contains(id);

        return ListTile(
          tileColor: isSelected
              ? const Color(0xFF1A2A3A)
              : Colors.transparent,
          onTap: () {
            if (_selectingPhotos) {
              _togglePhotoSelect(id);
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PhotoViewerScreen(
                    photos: _filteredPhotos,
                    initialIndex: i - _filteredSubFolders.length,
                  ),
                ),
              );
            }
          },
          onLongPress: () {
            setState(() {
              _selectingPhotos = true;
              _selectedPhotoIds.add(id);
            });
          },
          leading: Stack(
            children: [
              _ListPhotoThumb(photo: photo),
              if (isSelected)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.check,
                        color: Colors.white, size: 20),
                  ),
                ),
            ],
          ),
          title: Text(
            photo['original_name'] ?? 'Foto',
            style: GoogleFonts.poppins(
                color: Colors.white, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            _formatDate(photo['date_added'] as int),
            style: GoogleFonts.poppins(
                color: Colors.white38, fontSize: 11),
          ),
        );
      },
    );
  }

  String _formatDate(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.day}/${d.month}/${d.year}';
  }
}

// ── Miniatura foto en lista ──────────────────────────────────
class _ListPhotoThumb extends StatefulWidget {
  final Map<String, dynamic> photo;
  const _ListPhotoThumb({required this.photo});

  @override
  State<_ListPhotoThumb> createState() => _ListPhotoThumbState();
}

class _ListPhotoThumbState extends State<_ListPhotoThumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    MediaService.instance
        .getPhotoBytes(widget.photo['encrypted_path'])
        .then((b) {
      if (mounted) setState(() => _bytes = b);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: _bytes != null
          ? Image.memory(_bytes!, fit: BoxFit.cover)
          : const Icon(Icons.photo, color: Colors.white24, size: 24),
    );
  }
}