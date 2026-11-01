import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/database/db_helper.dart';
import '../../core/faces/face_service.dart';
import '../../core/faces/face_suggester.dart';
import '../../core/services/prefs_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/folder_tree_sheet.dart';
import '../../shared/widgets/photo_thumbnail.dart';

/// Analiza las fotos sueltas de Inicio y propone a qué carpeta van según los
/// rostros de las fotos que ya tienes en cada carpeta. Mover es siempre una
/// acción explícita del usuario.
class FaceSuggestScreen extends StatefulWidget {
  /// Carpeta cuyas fotos sueltas se clasifican; 0 = Inicio.
  final int folderId;
  const FaceSuggestScreen({super.key, this.folderId = 0});

  @override
  State<FaceSuggestScreen> createState() => _FaceSuggestScreenState();
}

class _FaceSuggestScreenState extends State<FaceSuggestScreen> {
  bool _cancelled = false;
  bool _running = true;
  String _stage = 'Preparando';
  int _done = 0;
  int _total = 0;
  String? _error;
  FaceSuggestResult? _result;
  bool _showPreview = true;
  bool _moving = false;
  bool _moved = false;

  /// Por carpeta: fotos desmarcadas por el usuario (las "posibles" empiezan así).
  final Map<int, Set<int>> _unchecked = {};

  /// Fotos con rostro que siguen sin carpeta: se mueven a mano.
  List<Map<String, dynamic>> _unmatched = [];
  final Set<int> _manualSelected = {};

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _cancelled = true;
    FaceService.instance.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _running = true;
      _error = null;
      _result = null;
      _cancelled = false;
      _startedAt = null;
      _startDone = null;
      _unchecked.clear();
      _manualSelected.clear();
    });
    // El análisis se detiene si la pantalla se apaga y la app se bloquea.
    WakelockPlus.enable();
    try {
      _showPreview = await PrefsService.instance.getShowPhotoPreview();
      final result = await FaceSuggester(
        scopeFolderId: widget.folderId,
        onProgress: (stage, done, total) {
          if (!mounted) return;
          setState(() {
            _stage = stage;
            _done = done;
            _total = total;
            _startedAt ??= DateTime.now();
            _startDone ??= done;
          });
        },
        isCancelled: () => _cancelled || !mounted,
      ).run();
      if (!mounted) return;
      setState(() {
        _result = result;
        _unmatched = result == null ? [] : List.of(result.unmatched);
        _running = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo analizar: $e';
        _running = false;
      });
    } finally {
      WakelockPlus.disable();
    }
  }

  DateTime? _startedAt;
  int? _startDone;

  /// Tiempo restante estimado con el ritmo real de esta sesión.
  String? _eta() {
    final start = _startedAt, base = _startDone;
    if (start == null || base == null || _total <= 0) return null;
    final processed = _done - base;
    if (processed < 8) return null;
    final seconds = DateTime.now().difference(start).inSeconds;
    if (seconds <= 0) return null;
    final remaining = ((_total - _done) * seconds / processed).round();
    if (remaining < 60) return 'menos de 1 min';
    if (remaining < 3600) return 'aprox. ${(remaining / 60).ceil()} min';
    final h = remaining ~/ 3600;
    final m = ((remaining % 3600) / 60).ceil();
    return 'aprox. $h h $m min';
  }

  void _stop() {
    _cancelled = true;
    Navigator.pop(context, _moved);
  }

  Future<void> _move(FaceSuggestion group) async {
    final skip = _unchecked[group.folderId] ?? {};
    final ids = group.photos
        .map((m) => m.photo['id'] as int)
        .where((id) => !skip.contains(id))
        .toList();
    if (ids.isEmpty || _moving) return;
    setState(() => _moving = true);
    try {
      await DBHelper.instance.movePhotos(ids, group.folderId);
      if (!mounted) return;
      final moved = ids.toSet();
      setState(() {
        _moved = true;
        // Quita lo movido de todos los grupos y los grupos vacíos.
        for (final g in _result!.suggestions) {
          g.photos.removeWhere((m) => moved.contains(m.photo['id']));
        }
        _result!.suggestions.removeWhere((g) => g.photos.isEmpty);
        _unmatched.removeWhere((p) => moved.contains(p['id']));
        _manualSelected.removeAll(moved);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudieron mover las fotos. No se cambió nada.')));
      }
    } finally {
      if (mounted) setState(() => _moving = false);
    }
  }

  /// Mueve a mano las fotos elegidas de la sección "sin carpeta parecida".
  Future<void> _moveManual() async {
    if (_manualSelected.isEmpty || _moving) return;
    final dest = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FolderTreeSheet(currentFolderId: widget.folderId),
    );
    if (dest == null || !mounted) return;
    final ids = _manualSelected.toList();
    setState(() => _moving = true);
    try {
      await DBHelper.instance.movePhotos(ids, dest['id'] as int);
      if (!mounted) return;
      final moved = ids.toSet();
      setState(() {
        _moved = true;
        _unmatched.removeWhere((p) => moved.contains(p['id']));
        _manualSelected.removeAll(moved);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudieron mover las fotos. No se cambió nada.')));
      }
    } finally {
      if (mounted) setState(() => _moving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stop();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back), onPressed: _stop),
          title: Text('Sugerir carpetas',
              style: GoogleFonts.poppins(
                  fontSize: 17, color: context.colors.textPrimary)),
          actions: [
            if (!_running)
              IconButton(
                tooltip: 'Volver a analizar',
                icon: const Icon(Icons.refresh),
                onPressed: _start,
              ),
          ],
        ),
        body: _running
            ? _buildProgress()
            : _error != null
                ? _message(Icons.error_outline, _error!)
                : _buildResult(),
      ),
    );
  }

  Widget _message(IconData icon, String text, {String? detail}) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: context.colors.textMuted),
              const SizedBox(height: 14),
              Text(text,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      color: context.colors.textPrimary, fontSize: 15)),
              if (detail != null) ...[
                const SizedBox(height: 8),
                Text(detail,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        color: context.colors.textMuted, fontSize: 12.5)),
              ],
            ],
          ),
        ),
      );

  Widget _buildProgress() {
    final value = _total > 0 ? _done / _total : null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.face_retouching_natural,
                size: 52, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 18),
            Text(_stage,
                style: GoogleFonts.poppins(
                    fontSize: 15, color: context.colors.textPrimary)),
            const SizedBox(height: 14),
            LinearProgressIndicator(value: value),
            const SizedBox(height: 10),
            Text(
              _total > 0
                  ? '$_done de $_total fotos${_eta() == null ? '' : ' · falta ${_eta()}'}'
                  : 'Revisando tu bóveda…',
              style: GoogleFonts.poppins(
                  fontSize: 12.5, color: context.colors.textMuted),
            ),
            const SizedBox(height: 6),
            Text(
              'Todo ocurre en tu teléfono. La primera vez tarda más; después solo se analizan fotos nuevas.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 11.5, color: context.colors.textMuted),
            ),
            const SizedBox(height: 18),
            TextButton(onPressed: _stop, child: const Text('Cancelar')),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    final result = _result;
    if (result == null) return const SizedBox.shrink();
    if (result.learnedFolders == 0) {
      return _message(
        Icons.folder_off_outlined,
        'Aún no hay rostros que aprender',
        detail: widget.folderId == 0
            ? 'Necesito carpetas con al menos 3 fotos donde aparezca la persona, '
                'por ejemplo una carpeta con tu nombre.'
            : 'Las subcarpetas de esta carpeta necesitan al menos 3 fotos '
                'donde aparezca la persona.',
      );
    }
    if (result.homePhotos == 0) {
      return _message(
          Icons.photo_library_outlined,
          widget.folderId == 0
              ? 'No hay fotos sueltas en Inicio para sugerir'
              : 'Esta carpeta no tiene fotos sueltas para sugerir');
    }
    final summary = <String>[
      if (result.noMatch > 0) '${result.noMatch} sin carpeta parecida',
      if (result.noFace > 0) '${result.noFace} sin rostro visible',
      if (result.unreadable > 0) '${result.unreadable} no se pudieron leer',
    ].join(' · ');
    if (result.suggestions.isEmpty && _unmatched.isEmpty) {
      return _message(
        Icons.search_off,
        _moved ? 'No quedan sugerencias' : 'No encontré coincidencias claras',
        detail: summary.isEmpty ? null : summary,
      );
    }
    final footer = <String>[
      if (result.noFace > 0) '${result.noFace} sin rostro visible',
      if (result.unreadable > 0) '${result.unreadable} no se pudieron leer',
    ].join(' · ');
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              for (final group in result.suggestions) _buildGroup(group),
            ]),
          ),
        ),
        if (_unmatched.isNotEmpty) ..._buildManualSection(),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
            child: footer.isEmpty
                ? null
                : Text('Sin sugerencia: $footer',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: context.colors.textMuted)),
          ),
        ),
      ],
    );
  }

  // ── Fotos con rostro sin carpeta parecida: mover a mano ──
  List<Widget> _buildManualSection() {
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
        sliver: SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.colors.surface,
              border: Border.all(color: context.colors.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sin carpeta parecida (${_unmatched.length})',
                    style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textPrimary)),
                const SizedBox(height: 4),
                Text(
                  'Tienen rostro, pero no se parecen a ninguna carpeta. '
                  'Selecciona las que quieras y elige una carpeta.',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: context.colors.textMuted),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _manualSelected.isEmpty || _moving ? null : _moveManual,
                    icon: const Icon(Icons.drive_file_move_outline),
                    label: Text(_manualSelected.isEmpty
                        ? 'Elige fotos para mover'
                        : 'Mover ${_manualSelected.length} a…'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverGrid.builder(
          itemCount: _unmatched.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4, crossAxisSpacing: 6, mainAxisSpacing: 6),
          itemBuilder: (_, i) {
            final photo = _unmatched[i];
            final id = photo['id'] as int;
            return PhotoThumbnail(
              key: ValueKey('manual-$id'),
              photo: photo,
              showPreview: _showPreview,
              isSelected: _manualSelected.contains(id),
              onTap: () => setState(() {
                if (!_manualSelected.remove(id)) _manualSelected.add(id);
              }),
            );
          },
        ),
      ),
    ];
  }

  Widget _buildGroup(FaceSuggestion group) {
    // Las coincidencias "posibles" empiezan desmarcadas: se revisan primero.
    final skip = _unchecked.putIfAbsent(group.folderId, () => {
          for (final m in group.photos)
            if (m.uncertain) m.photo['id'] as int
        });
    final selected =
        group.photos.where((m) => !skip.contains(m.photo['id'])).length;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: context.colors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(group.folderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textPrimary)),
              ),
              Text('${group.photos.length} fotos',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: context.colors.textMuted)),
            ],
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: group.photos.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4, crossAxisSpacing: 6, mainAxisSpacing: 6),
            itemBuilder: (_, i) {
              final match = group.photos[i];
              final id = match.photo['id'] as int;
              return Stack(
                fit: StackFit.expand,
                children: [
                  PhotoThumbnail(
                    key: ValueKey('${group.folderId}-$id'),
                    photo: match.photo,
                    showPreview: _showPreview,
                    isSelected: !skip.contains(id),
                    onTap: () => setState(() {
                      if (!skip.remove(id)) skip.add(id);
                    }),
                  ),
                  Positioned(
                    left: 3,
                    bottom: 3,
                    child: IgnorePointer(
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: match.uncertain
                              ? Colors.orange.shade800.withOpacity(0.85)
                              : Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                            '${match.uncertain ? 'posible ' : ''}${(match.score * 100).round()}%',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10)),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: selected == 0 || _moving ? null : () => _move(group),
              icon: const Icon(Icons.drive_file_move_outline),
              label: Text('Mover $selected a ${group.folderName}',
                  overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ),
    );
  }
}
