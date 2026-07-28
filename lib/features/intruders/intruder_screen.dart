import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/db_helper.dart';
import '../../core/security/crypto_service.dart';
import '../../core/services/media_service.dart';
import '../../core/theme/app_colors.dart';

class IntruderScreen extends StatefulWidget {
  const IntruderScreen({super.key});

  @override
  State<IntruderScreen> createState() => _IntruderScreenState();
}

class _IntruderScreenState extends State<IntruderScreen> {
  final _db = DBHelper.instance;
  List<Map<String, dynamic>> _items = [];
  final Set<int> _selectedIds = {};
  bool _selecting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _db.getIntruders();
    setState(() => _items = items);
  }

  Future<void> _deleteSelected() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).extension<AppColors>()!.surface,
        title: Text('Eliminar',
            style: GoogleFonts.poppins(color: context.colors.textPrimary)),
        content: Text(
          '¿Eliminar ${_selectedIds.length} captura${_selectedIds.length == 1 ? '' : 's'}?',
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

    final toDelete =
        _items.where((i) => _selectedIds.contains(i['id'])).toList();
    for (final item in toDelete) {
      await MediaService.instance
          .deleteEncryptedFile(item['encrypted_path']);
      await _db.deleteIntruder(item['id']);
    }
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
    _load();
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).extension<AppColors>()!.surface,
        title: Text('Vaciar capturas',
            style: GoogleFonts.poppins(color: context.colors.textPrimary)),
        content: Text(
          'Se eliminarán todas las selfies de intrusos capturadas.',
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
    await _db.deleteAllIntruders();
    _load();
  }

  void _openViewer(Map<String, dynamic> item) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _IntruderViewer(item: item)),
    );
  }

  String _formatDate(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${d.day}/${d.month}/${d.year} $h:$m';
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
                ? '${_selectedIds.length} seleccionada${_selectedIds.length == 1 ? '' : 's'}'
                : 'Selfies de intrusos',
            style: GoogleFonts.poppins(
                color: context.colors.textPrimary, fontSize: 16),
          ),
          actions: [
            if (_selecting) ...[
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
              ),
            ] else if (_items.isNotEmpty) ...[
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined,
                    color: Colors.redAccent),
                tooltip: 'Vaciar',
                onPressed: _clearAll,
              ),
            ],
          ],
        ),
        body: _items.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.no_photography_outlined,
                        size: 72, color: context.colors.textFaint),
                    const SizedBox(height: 16),
                    Text(
                      'Sin capturas todavía',
                      style: GoogleFonts.poppins(
                          color: context.colors.textFaint, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Se toma una foto con la cámara frontal\nal fallar el PIN 3 veces seguidas',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          color: context.colors.textFaint, fontSize: 11),
                    ),
                  ],
                ),
              )
            : GridView.builder(
                padding: const EdgeInsets.all(2),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                  childAspectRatio: 0.72,
                ),
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final item = _items[i];
                  final id = item['id'] as int;
                  final isSelected = _selectedIds.contains(id);

                  return GestureDetector(
                    onTap: () {
                      if (_selecting) {
                        setState(() {
                          if (isSelected) {
                            _selectedIds.remove(id);
                            if (_selectedIds.isEmpty) _selecting = false;
                          } else {
                            _selectedIds.add(id);
                          }
                        });
                      } else {
                        _openViewer(item);
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
                        _IntruderThumb(item: item),
                        if (isSelected)
                          Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.4)),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            color: Colors.black54,
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(
                              _formatDate(item['captured_at'] as int),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 8),
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
    );
  }
}

class _IntruderThumb extends StatefulWidget {
  final Map<String, dynamic> item;
  const _IntruderThumb({required this.item});

  @override
  State<_IntruderThumb> createState() => _IntruderThumbState();
}

class _IntruderThumbState extends State<_IntruderThumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    CryptoService()
        .decryptFile(widget.item['encrypted_path'])
        .then((b) {
      if (mounted) setState(() => _bytes = b);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.colors.surfaceHigh,
      child: _bytes != null
          ? Image.memory(_bytes!, fit: BoxFit.cover)
          : Icon(Icons.person_outline, color: context.colors.textFaint),
    );
  }
}

class _IntruderViewer extends StatefulWidget {
  final Map<String, dynamic> item;
  const _IntruderViewer({required this.item});

  @override
  State<_IntruderViewer> createState() => _IntruderViewerState();
}

class _IntruderViewerState extends State<_IntruderViewer> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    CryptoService()
        .decryptFile(widget.item['encrypted_path'])
        .then((b) {
      if (mounted) setState(() => _bytes = b);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _bytes != null
            ? InteractiveViewer(child: Image.memory(_bytes!))
            : const CircularProgressIndicator(color: Colors.white38),
      ),
    );
  }
}
