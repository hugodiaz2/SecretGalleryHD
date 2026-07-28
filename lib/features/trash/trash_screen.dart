import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/db_helper.dart';
import '../../core/services/media_service.dart';
import '../../core/services/prefs_service.dart';
import '../../core/theme/app_colors.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  final _db = DBHelper.instance;
  List<Map<String, dynamic>> _items = [];
  final Set<int> _selectedIds = {};
  bool _selecting = false;
  GridViewType _viewType = GridViewType.grid3;

  @override
  void initState() {
    super.initState();
    _load();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final type = await PrefsService.instance.getGridType();
    setState(() => _viewType = type);
  }

  Future<void> _load() async {
    final items = await _db.getTrashItems();
    setState(() => _items = items);
  }

  int get _crossAxisCount {
    switch (_viewType) {
      case GridViewType.grid3: return 3;
      case GridViewType.grid4: return 4;
      case GridViewType.grid5: return 5;
      case GridViewType.grid6: return 6;
      default: return 3;
    }
  }

  bool _isVideo(String? name) {
    if (name == null) return false;
    final ext = name.split('.').last.toLowerCase();
    return ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'].contains(ext);
  }

  Future<void> _restoreSelected() async {
    final toRestore = _items
        .where((i) => _selectedIds.contains(i['id']))
        .toList();
    for (final item in toRestore) {
      await _db.restoreFromTrash(item);
    }
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
    _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).extension<AppColors>()!.surface,
          content: Row(children: [
            const Icon(Icons.restore, color: Colors.green, size: 18),
            const SizedBox(width: 8),
            Text(
              '${toRestore.length} archivo${toRestore.length == 1 ? '' : 's'} restaurado${toRestore.length == 1 ? '' : 's'}',
              style: GoogleFonts.poppins(color: context.colors.textPrimary),
            ),
          ]),
        ),
      );
    }
  }

  Future<void> _deleteSelected() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).extension<AppColors>()!.surface,
        title: Text('Eliminar permanentemente',
            style: GoogleFonts.poppins(color: context.colors.textPrimary)),
        content: Text(
          '¿Eliminar ${_selectedIds.length} archivo${_selectedIds.length == 1 ? '' : 's'} permanentemente? Esta acción no se puede deshacer.',
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

    final toDelete = _items
        .where((i) => _selectedIds.contains(i['id']))
        .toList();
    for (final item in toDelete) {
      await MediaService.instance
          .deleteEncryptedFile(item['encrypted_path']);
      await _db.deleteFromTrash(item['id']);
    }
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
    _load();
  }

  Future<void> _emptyTrash() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).extension<AppColors>()!.surface,
        title: Text('Vaciar papelera',
            style: GoogleFonts.poppins(color: context.colors.textPrimary)),
        content: Text(
          'Se eliminarán permanentemente todos los archivos de la papelera.',
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
            child: Text('Vaciar',
                style: GoogleFonts.poppins(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    for (final item in _items) {
      await MediaService.instance
          .deleteEncryptedFile(item['encrypted_path']);
    }
    await _db.emptyTrash();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_selecting) {
          setState(() {
            _selecting = false;
            _selectedIds.clear();
          });
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: context.colors.bg,
        appBar: AppBar(
          backgroundColor: context.colors.bg,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: context.colors.textPrimary),
            onPressed: () {
              if (_selecting) {
                setState(() {
                  _selecting = false;
                  _selectedIds.clear();
                });
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: Text(
            _selecting
                ? '${_selectedIds.length} seleccionado${_selectedIds.length == 1 ? '' : 's'}'
                : 'Papelera',
            style: GoogleFonts.poppins(
                color: context.colors.textPrimary, fontSize: 16),
          ),
          actions: [
            if (_selecting) ...[
              IconButton(
                icon: const Icon(Icons.restore, color: Colors.green),
                tooltip: 'Restaurar',
                onPressed:
                    _selectedIds.isEmpty ? null : _restoreSelected,
              ),
              IconButton(
                icon: Icon(Icons.select_all, color: context.colors.textPrimary),
                onPressed: () => setState(() => _selectedIds
                    .addAll(_items.map((i) => i['id'] as int))),
              ),
              IconButton(
                icon: const Icon(Icons.delete_forever,
                    color: Colors.redAccent),
                onPressed:
                    _selectedIds.isEmpty ? null : _deleteSelected,
              ),
            ] else if (_items.isNotEmpty) ...[
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined,
                    color: Colors.redAccent),
                tooltip: 'Vaciar papelera',
                onPressed: _emptyTrash,
              ),
            ],
          ],
        ),
        body: _items.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.delete_outline,
                        size: 72, color: context.colors.textGhost),
                    const SizedBox(height: 16),
                    Text(
                      'La papelera está vacía',
                      style: GoogleFonts.poppins(
                          color: context.colors.textFaint, fontSize: 14),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  // Info banner
                  Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: context.colors.textGhost, width: 1),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: context.colors.textMuted, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_items.length} archivo${_items.length == 1 ? '' : 's'} en papelera · Mantén presionado para seleccionar',
                            style: GoogleFonts.poppins(
                                color: context.colors.textMuted, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Grid
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(2),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _crossAxisCount,
                        mainAxisSpacing: 2,
                        crossAxisSpacing: 2,
                        childAspectRatio: 0.72,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final item = _items[i];
                        final id = item['id'] as int;
                        final isSelected = _selectedIds.contains(id);
                        final isVideo =
                            _isVideo(item['original_name']);

                        return GestureDetector(
                          onTap: () {
                            if (_selecting) {
                              setState(() {
                                if (isSelected) {
                                  _selectedIds.remove(id);
                                  if (_selectedIds.isEmpty) {
                                    _selecting = false;
                                  }
                                } else {
                                  _selectedIds.add(id);
                                }
                              });
                            } else {
                              _showItemOptions(item);
                            }
                          },
                          onLongPress: () {
                            setState(() {
                              _selecting = true;
                              _selectedIds.add(id);
                            });
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _TrashThumb(item: item),
                              if (isVideo)
                                Center(
                                  child: Icon(
                                    Icons.play_circle_outline,
                                    color: context.colors.textSecondary,
                                    size: 28,
                                  ),
                                ),
                              if (isSelected)
                                Container(
                                    color: Theme.of(context).colorScheme.primary.withOpacity(0.4)),
                              if (isSelected)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                    child: const Icon(Icons.check,
                                        color: Colors.white, size: 13),
                                  ),
                                ),
                              // Overlay de eliminado
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  color: Colors.black54,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 3),
                                  child: Text(
                                    _formatDate(
                                        item['deleted_at'] as int),
                                    style: TextStyle(
                                        color: context.colors.textPrimary.withOpacity(0.54),
                                        fontSize: 8),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _showItemOptions(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: context.colors.textFaint,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Text(
              item['original_name'] ?? 'Archivo',
              style: GoogleFonts.poppins(
                  color: context.colors.textPrimary.withOpacity(0.54), fontSize: 12),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.restore, color: Colors.green),
              title: Text('Restaurar',
                  style: GoogleFonts.poppins(color: context.colors.textPrimary)),
              onTap: () async {
                Navigator.pop(context);
                await _db.restoreFromTrash(item);
                _load();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: Theme.of(context).extension<AppColors>()!.surface,
                      content: Text('Archivo restaurado',
                          style:
                              GoogleFonts.poppins(color: context.colors.textPrimary)),
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever,
                  color: Colors.redAccent),
              title: Text('Eliminar permanentemente',
                  style:
                      GoogleFonts.poppins(color: Colors.redAccent)),
              onTap: () async {
                Navigator.pop(context);
                await MediaService.instance
                    .deleteEncryptedFile(item['encrypted_path']);
                await _db.deleteFromTrash(item['id']);
                _load();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _formatDate(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.day}/${d.month}/${d.year}';
  }
}

// ── Miniatura en papelera ────────────────────────────────────
class _TrashThumb extends StatefulWidget {
  final Map<String, dynamic> item;
  const _TrashThumb({required this.item});

  @override
  State<_TrashThumb> createState() => _TrashThumbState();
}

class _TrashThumbState extends State<_TrashThumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    MediaService.instance
        .getPhotoBytes(widget.item['encrypted_path'])
        .then((b) {
      if (mounted) setState(() => _bytes = b);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _bytes != null
        ? Image.memory(_bytes!, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => ColoredBox(
                color: context.colors.surfaceHigh,
                child: Icon(Icons.broken_image,
                    color: context.colors.textFaint, size: 24)))
        : ColoredBox(color: context.colors.surfaceHigh);
  }
}