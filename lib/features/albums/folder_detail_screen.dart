import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/db_helper.dart';
import '../../core/services/media_service.dart';
import '../../core/services/prefs_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/photo_thumbnail.dart';
import '../../shared/widgets/folder_thumbnail.dart';
import '../../shared/widgets/folder_tree_sheet.dart';
import '../../shared/widgets/unlock_helper.dart';
import '../../shared/widgets/cover_picker_sheet.dart';
import '../../shared/widgets/design_sheet.dart';
import '../import/gallery_picker_screen.dart';
import '../photos/photo_viewer_screen.dart';
import '../photos/video_player_screen.dart';

class FolderDetailScreen extends StatefulWidget {
  final Map<String, dynamic> folder;
  final bool showPhotoPreview;
  final bool showFolderPreview;

  const FolderDetailScreen({
    super.key,
    required this.folder,
    this.showPhotoPreview = true,
    this.showFolderPreview = true,
  });

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
  String _currentSort = 'newest';
  bool _narrowBorders = false;
  bool _showPhotoPreview = true;
  bool _showFolderPreview = true;

  bool _selectingPhotos = false;
  final Set<int> _selectedPhotoIds = {};

  bool _selectingFolders = false;
  final Set<int> _selectedFolderIds = {};

  bool get _isSelecting => _selectingPhotos || _selectingFolders;

  bool _isVideo(Map<String, dynamic> photo) {
    final name = (photo['original_name'] ?? '') as String;
    final ext = name.split('.').last.toLowerCase();
    return ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', 'flv'].contains(ext);
  }

  @override
  void initState() {
    super.initState();
    _showPhotoPreview = widget.showPhotoPreview;
    _showFolderPreview = widget.showFolderPreview;
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
    final sort = await PrefsService.instance.getSort();
    final narrow = await PrefsService.instance.getNarrowBorders();
    final photoPreview = await PrefsService.instance.getShowPhotoPreview();
    final folderPreview = await PrefsService.instance.getShowFolderPreview();
    setState(() {
      _viewType = type;
      _currentSort = sort;
      _narrowBorders = narrow;
      _showPhotoPreview = photoPreview;
      _showFolderPreview = folderPreview;
    });
  }

  Future<int> _fileSize(String path) async {
    final f = File(path);
    return await f.exists() ? await f.length() : 0;
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
    if (_currentSort != 'newest') await _applySort(_currentSort);
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

  void _showDesignSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DesignSheet(
        currentViewType: _viewType,
        currentSort: _currentSort,
        currentNarrowBorders: _narrowBorders,
        currentShowPhotoPreview: _showPhotoPreview,
        currentShowFolderPreview: _showFolderPreview,
        onViewChanged: (type) async {
          await PrefsService.instance.saveGridType(type);
          setState(() => _viewType = type);
        },
        onSortChanged: (sort) async {
          await PrefsService.instance.saveSort(sort);
          _applySort(sort);
        },
        onNarrowBordersChanged: (v) {
          PrefsService.instance.saveNarrowBorders(v);
          setState(() => _narrowBorders = v);
        },
        onPhotoPreviewChanged: (v) {
          PrefsService.instance.saveShowPhotoPreview(v);
          setState(() => _showPhotoPreview = v);
        },
        onFolderPreviewChanged: (v) {
          PrefsService.instance.saveShowFolderPreview(v);
          setState(() => _showFolderPreview = v);
        },
      ),
    );
  }

  // ── SUBCARPETAS ──────────────────────────────────────────

  Future<void> _createSubFolder() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).extension<AppColors>()!.surface,
        title: Text('Nueva subcarpeta',
            style: GoogleFonts.poppins(color: context.colors.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: context.colors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Nombre',
            hintStyle: TextStyle(color: context.colors.textMuted),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF3D3D3D)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar',
                style: GoogleFonts.poppins(color: context.colors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text('Crear',
                style: GoogleFonts.poppins(color: Theme.of(context).colorScheme.primary)),
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
        backgroundColor: Theme.of(context).extension<AppColors>()!.surface,
        title: Text('Renombrar',
            style: GoogleFonts.poppins(color: context.colors.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: context.colors.textPrimary),
          decoration: InputDecoration(
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF3D3D3D)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar',
                style: GoogleFonts.poppins(color: context.colors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text('Guardar',
                style: GoogleFonts.poppins(color: Theme.of(context).colorScheme.primary)),
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
        backgroundColor: Theme.of(context).extension<AppColors>()!.surface,
        title: Text('Eliminar',
            style: GoogleFonts.poppins(color: context.colors.textPrimary)),
        content: Text(
          '¿Eliminar "${folder['name']}" y todo su contenido?',
          style: GoogleFonts.poppins(color: context.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: GoogleFonts.poppins(color: context.colors.textMuted)),
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
          ..._selectedFolderIds,
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
        backgroundColor: Theme.of(context).extension<AppColors>()!.surface,
        title: Text('Eliminar carpetas',
            style: GoogleFonts.poppins(color: context.colors.textPrimary)),
        content: Text(
          '¿Eliminar ${_selectedFolderIds.length} carpeta${_selectedFolderIds.length == 1 ? '' : 's'} y todo su contenido?',
          style: GoogleFonts.poppins(color: context.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: GoogleFonts.poppins(color: context.colors.textMuted)),
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
      color: context.colors.surfaceHigh,
      items: [
        PopupMenuItem(
          value: 'cover',
          child: Row(children: [
            Icon(Icons.image_outlined,
                color: context.colors.textSecondary, size: 18),
            const SizedBox(width: 10),
            Text('Elegir portada',
                style: GoogleFonts.poppins(
                    color: context.colors.textPrimary, fontSize: 13)),
          ]),
        ),
        PopupMenuItem(
          value: 'rename',
          child: Row(children: [
            Icon(Icons.drive_file_rename_outline,
                color: context.colors.textSecondary, size: 18),
            const SizedBox(width: 10),
            Text('Renombrar',
                style: GoogleFonts.poppins(
                    color: context.colors.textPrimary, fontSize: 13)),
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
        excludeFolderIds: [widget.folder['id']],
        currentFolderId: widget.folder['id'],
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
    final noTrash = await PrefsService.instance.getNoTrash();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).extension<AppColors>()!.surface,
        title: Text('Eliminar fotos',
            style: GoogleFonts.poppins(color: context.colors.textPrimary)),
        content: Text(
          noTrash
              ? '¿Eliminar ${_selectedPhotoIds.length} foto${_selectedPhotoIds.length == 1 ? '' : 's'} permanentemente?'
              : '¿Mover ${_selectedPhotoIds.length} foto${_selectedPhotoIds.length == 1 ? '' : 's'} a la papelera?',
          style: GoogleFonts.poppins(color: context.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: GoogleFonts.poppins(color: context.colors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              noTrash ? 'Eliminar' : 'Mover a papelera',
              style: GoogleFonts.poppins(
                  color: noTrash ? Colors.redAccent : Colors.orange),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final toDelete = _photos
        .where((p) => _selectedPhotoIds.contains(p['id']))
        .toList();

    for (final p in toDelete) {
      if (noTrash) {
        await _media.deletePhoto(p);
      } else {
        await _db.moveToTrash(p);
      }
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

  Future<void> _applySort(String v) async {
    _currentSort = v;

    if (v == 'size_desc') {
      final folderSizes = <int, int>{};
      for (final f in _filteredSubFolders) {
        final paths = await _db.getEncryptedPathsInFolder(f['id'] as int);
        int total = 0;
        for (final path in paths) {
          total += await _fileSize(path);
        }
        folderSizes[f['id'] as int] = total;
      }
      final photoSizes = <String, int>{};
      for (final p in _filteredPhotos) {
        photoSizes[p['encrypted_path'] as String] =
            await _fileSize(p['encrypted_path'] as String);
      }
      if (!mounted) return;
      setState(() {
        _filteredSubFolders.sort((a, b) => (folderSizes[b['id']] ?? 0)
            .compareTo(folderSizes[a['id']] ?? 0));
        _filteredPhotos.sort((a, b) => (photoSizes[b['encrypted_path']] ?? 0)
            .compareTo(photoSizes[a['encrypted_path']] ?? 0));
      });
      return;
    }

    setState(() {
      if (v == 'az') {
        _filteredSubFolders.sort((a, b) =>
            (a['name'] as String).compareTo(b['name'] as String));
        _filteredPhotos.sort((a, b) =>
            (a['original_name'] ?? '').compareTo(b['original_name'] ?? ''));
      } else if (v == 'za') {
        _filteredSubFolders.sort((a, b) =>
            (b['name'] as String).compareTo(a['name'] as String));
        _filteredPhotos.sort((a, b) =>
            (b['original_name'] ?? '').compareTo(a['original_name'] ?? ''));
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
        backgroundColor: context.colors.bg,
        appBar: AppBar(
          backgroundColor: context.colors.surface,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: context.colors.textPrimary),
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
                  style: TextStyle(color: context.colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Buscar...',
                    hintStyle: TextStyle(color: context.colors.textMuted),
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
                      color: context.colors.textPrimary, fontSize: 16),
                ),
          actions: [
            // ── Selección carpetas ──
            if (_selectingFolders) ...[
              IconButton(
                icon: Icon(Icons.drive_file_move_outline,
                    color: context.colors.textPrimary),
                onPressed: _selectedFolderIds.isEmpty
                    ? null
                    : _moveSelectedFolders,
              ),
              IconButton(
                icon: Icon(Icons.select_all, color: context.colors.textPrimary),
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
                icon: Icon(Icons.drive_file_move_outline,
                    color: context.colors.textPrimary),
                onPressed: _selectedPhotoIds.isEmpty
                    ? null
                    : _moveSelectedPhotos,
              ),
              IconButton(
                icon: Icon(Icons.lock_open_outlined,
                    color: Theme.of(context).colorScheme.primary),
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
                icon: Icon(Icons.select_all, color: context.colors.textPrimary),
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
                  color: context.colors.textPrimary,
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
              // ✅ Botón diseño
              IconButton(
                icon: Icon(Icons.tune, color: context.colors.textPrimary),
                tooltip: 'Diseño',
                onPressed: _showDesignSheet,
              ),
            ],
          ],
        ),

        body: _filteredSubFolders.isEmpty && _filteredPhotos.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.photo_outlined,
                        size: 64, color: context.colors.textGhost),
                    const SizedBox(height: 12),
                    Text(
                      _search.isNotEmpty
                          ? 'Sin resultados para "$_search"'
                          : 'Sin contenido\nToca + para agregar',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          color: context.colors.textFaint, fontSize: 14),
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
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    mini: true,
                    child: const Icon(Icons.add_photo_alternate_outlined,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(height: 10),
                  FloatingActionButton(
                    heroTag: 'sub_add_folder',
                    onPressed: _createSubFolder,
                    backgroundColor: context.colors.textPrimary,
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
    final spacing = _narrowBorders ? 1.0 : 2.0;
    final allItems = [
      ...(_filteredSubFolders.map((f) => {'type': 'folder', 'data': f})),
      ...(_filteredPhotos.map((p) => {'type': 'photo', 'data': p})),
    ];

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
          _narrowBorders ? 1 : 2,
          _narrowBorders ? 1 : 2,
          _narrowBorders ? 1 : 2,
          100),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _crossAxisCount,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childAspectRatio: 0.72,
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
            showPreview: _showFolderPreview, // ✅
            onTap: () {
              if (_selectingFolders) {
                _toggleFolderSelect(id);
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FolderDetailScreen(
                      folder: folder,
                      showPhotoPreview: _showPhotoPreview,   // ✅
                      showFolderPreview: _showFolderPreview, // ✅
                    ),
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
          showPreview: _showPhotoPreview, // ✅
          onTap: () {
            if (_selectingPhotos) {
              _togglePhotoSelect(id);
            } else {
              if (_isVideo(photo)) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VideoPlayerScreen(video: photo),
                  ),
                );
              } else {
                final onlyPhotos = _filteredPhotos
                    .where((p) => !_isVideo(p))
                    .toList();
                final photoIndex = onlyPhotos.indexWhere((p) =>
                    p['encrypted_path'] == photo['encrypted_path']);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PhotoViewerScreen(
                      photos: onlyPhotos,
                      initialIndex: photoIndex >= 0 ? photoIndex : 0,
                    ),
                  ),
                ).then((_) => _load());
              }
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
                ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
                : Colors.transparent,
            onTap: () {
              if (_selectingFolders) {
                _toggleFolderSelect(id);
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FolderDetailScreen(
                      folder: folder,
                      showPhotoPreview: _showPhotoPreview,
                      showFolderPreview: _showFolderPreview,
                    ),
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
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: context.colors.surfaceHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    subs > 0 ? Icons.folder_copy : Icons.folder,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                ),
                if (isSelected)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.check,
                          color: Colors.white, size: 20),
                    ),
                  ),
              ],
            ),
            title: Text(folder['name'] as String,
                style: GoogleFonts.poppins(
                    color: context.colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            subtitle: Text(
              '$count foto${count == 1 ? '' : 's'}${subs > 0 ? ' · $subs subcarpeta${subs == 1 ? '' : 's'}' : ''}',
              style: GoogleFonts.poppins(
                  color: context.colors.textMuted, fontSize: 11),
            ),
            trailing: GestureDetector(
              onTapDown: (d) =>
                  _showFolderMenu(folder, d.globalPosition),
              child: Icon(Icons.more_vert,
                  color: context.colors.textMuted, size: 20),
            ),
          );
        }

        final photo = item['data'] as Map<String, dynamic>;
        final id = photo['id'] as int;
        final isSelected = _selectedPhotoIds.contains(id);

        return ListTile(
          tileColor: isSelected
              ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
              : Colors.transparent,
          onTap: () {
            if (_selectingPhotos) {
              _togglePhotoSelect(id);
            } else {
              if (_isVideo(photo)) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VideoPlayerScreen(video: photo),
                  ),
                );
              } else {
                final onlyPhotos = _filteredPhotos
                    .where((p) => !_isVideo(p))
                    .toList();
                final photoIndex = onlyPhotos.indexWhere((p) =>
                    p['encrypted_path'] == photo['encrypted_path']);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PhotoViewerScreen(
                      photos: onlyPhotos,
                      initialIndex: photoIndex >= 0 ? photoIndex : 0,
                    ),
                  ),
                ).then((_) => _load());
              }
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
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
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
            style: GoogleFonts.poppins(color: context.colors.textPrimary, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            _formatDate(photo['date_added'] as int),
            style: GoogleFonts.poppins(
                color: context.colors.textMuted, fontSize: 11),
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
      width: 48, height: 48,
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: _bytes != null
          ? Image.memory(_bytes!, fit: BoxFit.cover)
          : Icon(Icons.photo, color: context.colors.textFaint, size: 24),
    );
  }
}