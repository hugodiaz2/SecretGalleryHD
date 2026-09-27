import '../../core/services/gallery_order.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/db_helper.dart';
import '../../core/services/media_service.dart';
import '../../core/theme/app_colors.dart';

class FolderTreeSheet extends StatefulWidget {
  // Selected folders cannot be moved into themselves or their descendants.
  final List<int> excludeFolderIds;
  final int? currentFolderId;

  const FolderTreeSheet({
    super.key,
    this.excludeFolderIds = const [],
    this.currentFolderId,
  });

  @override
  State<FolderTreeSheet> createState() => _FolderTreeSheetState();
}

class _FolderTreeSheetState extends State<FolderTreeSheet> {
  final _searchCtrl = TextEditingController();
  final Map<int, Map<String, dynamic>> _byId = {};
  final Map<int?, List<Map<String, dynamic>>> _children = {};
  final Set<int> _blocked = {};
  final Map<int, Future<String?>> _covers = {};
  int? _parentId;
  bool _loading = true;
  bool _failed = false;
  bool _searching = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final folders = await DBHelper.instance.getAllFoldersFlat();
      if (!mounted) return;
      _byId.clear();
      _children.clear();
      _blocked.clear();
      for (final folder in folders) {
        _byId[folder['id'] as int] = folder;
        (_children[folder['parent_id'] as int?] ??= []).add(folder);
      }
      // Older callers include the current parent in exclusions. It remains
      // browsable so its other children are still valid destinations.
      final pending = widget.excludeFolderIds
          .where((id) => id != widget.currentFolderId)
          .toList();
      while (pending.isNotEmpty) {
        final id = pending.removeLast();
        if (!_blocked.add(id)) continue;
        pending.addAll((_children[id] ?? []).map((f) => f['id'] as int));
      }
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  List<Map<String, dynamic>> get _visibleFolders {
    final query = _query.trim().toLowerCase();
    final source = query.isEmpty
        ? (_children[_parentId] ?? <Map<String, dynamic>>[])
        : _byId.values;
    return source.where((folder) {
      return !_blocked.contains(folder['id']) &&
          (query.isEmpty ||
              (folder['name'] as String).toLowerCase().contains(query));
    }).toList()
      ..sort((a, b) => compareGalleryNames(a['name'] as String, b['name'] as String));
  }

  String _path(int? id) {
    final names = <String>[];
    final visited = <int>{};
    while (id != null && visited.add(id)) {
      final folder = _byId[id];
      if (folder == null) break;
      names.add(folder['name'] as String);
      id = folder['parent_id'] as int?;
    }
    return ['Inicio', ...names.reversed].join(' / ');
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _query = '';
    _searching = false;
    FocusScope.of(context).unfocus();
  }

  void _open(Map<String, dynamic> folder) {
    setState(() {
      _clearSearch();
      _parentId = folder['id'] as int;
    });
  }

  void _back() {
    if (_searching) {
      setState(_clearSearch);
    } else if (_parentId != null) {
      setState(() => _parentId = _byId[_parentId]?['parent_id'] as int?);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = Theme.of(context).colorScheme.primary;
    final destination = _parentId == null
        ? <String, dynamic>{'id': 0, 'name': 'Inicio', 'is_root': true}
        : _byId[_parentId];
    final canMove = !_searching &&
        !_loading &&
        !_failed &&
        destination != null &&
        destination['id'] != (widget.currentFolderId ?? 0) &&
        !_blocked.contains(_parentId);
    final folders = _visibleFolders;
    return PopScope(
      canPop: _parentId == null && !_searching,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: LayoutBuilder(builder: (context, constraints) {
        final keyboard = MediaQuery.viewInsetsOf(context).bottom;
        final available = (constraints.maxHeight - keyboard)
            .clamp(0.0, constraints.maxHeight)
            .toDouble();
        final height = (MediaQuery.sizeOf(context).height * 0.82)
            .clamp(0.0, available)
            .toDouble();
        return Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: SizedBox(
            height: height,
            child: Material(
              color: colors.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: Column(children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: colors.border,
                        borderRadius: BorderRadius.circular(4)),
                  ),
                  Row(children: [
                    IconButton(
                        onPressed: _back,
                        tooltip: _parentId == null && !_searching
                            ? 'Cerrar'
                            : 'Regresar',
                        icon: const Icon(Icons.arrow_back)),
                    Expanded(
                        child: Text('Mover a carpeta',
                            style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary))),
                    IconButton(
                      tooltip:
                          _searching ? 'Cerrar búsqueda' : 'Buscar carpeta',
                      onPressed: () => setState(() {
                        if (_searching) {
                          _clearSearch();
                        } else {
                          _searching = true;
                        }
                      }),
                      icon: Icon(_searching ? Icons.search_off : Icons.search),
                    ),
                    IconButton(
                        tooltip: 'Cancelar',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close)),
                  ]),
                  if (_searching)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: TextField(
                        controller: _searchCtrl,
                        autofocus: true,
                        onChanged: (value) => setState(() => _query = value),
                        decoration: InputDecoration(
                          hintText: 'Buscar en todas las carpetas',
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                          _query.trim().isNotEmpty
                              ? 'Resultados de búsqueda'
                              : _path(_parentId),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: colors.textSecondary, fontSize: 12)),
                    ),
                  ),
                  Expanded(
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _failed
                              ? Center(
                                  child: TextButton.icon(
                                      onPressed: _load,
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('Reintentar carga')))
                              : folders.isEmpty
                                  ? Center(
                                      child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Text(
                                          _query.trim().isNotEmpty
                                              ? 'No se encontraron carpetas'
                                              : _parentId == null
                                                  ? 'No hay carpetas disponibles'
                                                  : 'Esta carpeta no tiene subcarpetas.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: colors.textMuted)),
                                    ))
                                  : LayoutBuilder(
                                      builder: (context, gridConstraints) {
                                      const columns = 4;
                                      final width = (gridConstraints.maxWidth -
                                              24 -
                                              (columns - 1) * 8) /
                                          columns;
                                      return GridView.builder(
                                        key: ValueKey('$_parentId:$_query'),
                                        padding: const EdgeInsets.fromLTRB(
                                            12, 2, 12, 12),
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: columns,
                                          crossAxisSpacing: 8,
                                          mainAxisSpacing: 8,
                                          mainAxisExtent: width +
                                              MediaQuery.textScalerOf(context)
                                                  .scale(34),
                                        ),
                                        itemCount: folders.length,
                                        itemBuilder: (context, index) {
                                          final folder = folders[index];
                                          final id = folder['id'] as int;
                                          final isCurrent =
                                              id == widget.currentFolderId;
                                          final hasChildren =
                                              (_children[id] ?? []).isNotEmpty;
                                          return Tooltip(
                                            message: _path(id),
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              onTap: () => _open(folder),
                                              child: Column(children: [
                                                AspectRatio(
                                                  aspectRatio: 1,
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: colors.surfaceHigh,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10),
                                                      border: Border.all(
                                                          color: isCurrent
                                                              ? accent
                                                              : colors.border),
                                                    ),
                                                    child: ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              9),
                                                      child: _DestinationCover(
                                                        key: ValueKey(id),
                                                        cover: _covers.putIfAbsent(
                                                            id,
                                                            () => DBHelper
                                                                .instance
                                                                .getCoverPhoto(
                                                                    id)),
                                                        hasChildren:
                                                            hasChildren,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(folder['name'] as String,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                        color:
                                                            colors.textPrimary,
                                                        fontSize: 10)),
                                              ]),
                                            ),
                                          );
                                        },
                                      );
                                    })),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: canMove
                            ? () => Navigator.pop(context, destination)
                            : null,
                        icon: const Icon(Icons.drive_file_move_outline),
                        label: Text(_parentId == widget.currentFolderId &&
                                _parentId != null
                            ? 'Esta es la carpeta actual'
                            : _parentId == null
                                ? (widget.currentFolderId == null ||
                                        widget.currentFolderId == 0
                                    ? 'Ya estás en Inicio'
                                    : 'Mover a Inicio')
                                : 'Mover aquí'),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Uses the shared small-thumbnail cache, without retaining full originals.
class _DestinationCover extends StatefulWidget {
  final Future<String?> cover;
  final bool hasChildren;

  const _DestinationCover(
      {super.key, required this.cover, required this.hasChildren});

  @override
  State<_DestinationCover> createState() => _DestinationCoverState();
}

class _DestinationCoverState extends State<_DestinationCover> {
  Uint8List? _bytes;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(Duration.zero, _start);
  }

  void _start() {
    if (!mounted) return;
    if (Scrollable.recommendDeferredLoadingForContext(context)) {
      _timer = Timer(const Duration(milliseconds: 32), _start);
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final path = await widget.cover;
      if (!mounted || path == null || path.isEmpty) return;
      final media = MediaService.instance;
      final video = MediaService.isVideoPath(path);
      final cached = media.cachedThumbnail(path, video: video);
      final bytes = cached ??
          (video
              ? await media.getVideoThumbnail(path, 'cover.mp4',
                  isNeeded: () => mounted)
              : await media.getPhotoThumbnail(path, isNeeded: () => mounted));
      if (mounted && bytes != null) setState(() => _bytes = bytes);
    } catch (_) {
      // A missing or unreadable cover must not prevent choosing a destination.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _fallback(BuildContext context) => Center(
        child: Icon(
            widget.hasChildren
                ? Icons.folder_copy_outlined
                : Icons.folder_outlined,
            size: 32,
            color: Theme.of(context).colorScheme.primary),
      );

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) return _fallback(context);
    return LayoutBuilder(builder: (context, constraints) {
      final size =
          (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
              .round()
              .clamp(64, 384);
      return Image.memory(
        _bytes!,
        fit: BoxFit.cover,
        cacheWidth: size,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, __, ___) => _fallback(context),
      );
    });
  }
}
