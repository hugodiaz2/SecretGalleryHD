import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../../core/database/db_helper.dart';
import '../../core/services/media_service.dart';
import '../../core/services/prefs_service.dart';
import '../../core/services/lifecycle_guard.dart';
import '../../shared/widgets/folder_tree_sheet.dart';
import '../../shared/widgets/unlock_helper.dart';
import 'slideshow_screen.dart';

/// Reproductor de videos de una carpeta. Deslizar de lado cambia de video;
/// solo el video visible se descifra y reproduce.
class VideoPlayerScreen extends StatefulWidget {
  final Map<String, dynamic> video;
  final List<Map<String, dynamic>>? videos;

  const VideoPlayerScreen({super.key, required this.video, this.videos});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final List<Map<String, dynamic>> _videos;
  late final PageController _pageController;
  late int _index;

  @override
  void initState() {
    super.initState();
    final list = widget.videos;
    _videos = (list == null || list.isEmpty) ? [widget.video] : list;
    final start = _videos.indexWhere(
        (v) => v['encrypted_path'] == widget.video['encrypted_path']);
    _index = start >= 0 ? start : 0;
    _pageController = PageController(initialPage: _index);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Presentación automática de los videos desde el actual; al salir queda
  /// en el último que se reprodujo.
  Future<void> _startSlideshow() async {
    final lastId = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (_) => SlideshowScreen(
          items: List<Map<String, dynamic>>.of(_videos),
          initialIndex: _index,
        ),
      ),
    );
    if (!mounted) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    final i = _videos.indexWhere((v) => v['id'] == lastId);
    if (i >= 0 && i != _index && _pageController.hasClients) {
      _pageController.jumpToPage(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        itemCount: _videos.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => _VideoPage(
          key: ValueKey(_videos[i]['encrypted_path']),
          video: _videos[i],
          active: i == _index,
          counter: _videos.length > 1 ? '${i + 1} / ${_videos.length}' : null,
          onSlideshow: _startSlideshow,
        ),
      ),
    );
  }
}

class _VideoPage extends StatefulWidget {
  final Map<String, dynamic> video;
  final bool active;
  final String? counter;
  final VoidCallback? onSlideshow;

  const _VideoPage({
    super.key,
    required this.video,
    required this.active,
    this.counter,
    this.onSlideshow,
  });

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _error;
  File? _tempFile;
  Directory? _playbackDirectory;
  bool _showControls = true;
  Timer? _hideTimer;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    if (widget.active) _initVideo();
  }

  @override
  void didUpdateWidget(_VideoPage old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _initVideo();
    } else if (!widget.active && old.active) {
      _release();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _generation++;
    _controller?.dispose();
    _cleanupPlayback();
    super.dispose();
  }

  Future<void> _cleanupPlayback() async {
    final directory = _playbackDirectory;
    _playbackDirectory = null;
    _tempFile = null;
    if (directory == null) return;
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {}
  }

  /// Libera el reproductor y el temporal descifrado al salir de la página.
  void _release() {
    _generation++;
    _hideTimer?.cancel();
    final controller = _controller;
    _controller = null;
    controller?.dispose();
    _cleanupPlayback();
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _showControls = true;
      });
    }
  }

  Future<void> _initVideo() async {
    final generation = ++_generation;
    bool stale() => !mounted || generation != _generation;
    Directory? directory;
    VideoPlayerController? controller;
    try {
      directory = await (await getTemporaryDirectory()).createTemp('sg_play_');
      _playbackDirectory = directory;
      final fileName =
          p.basename(widget.video['original_name'] as String? ?? 'video.mp4');
      final tempFile = File(p.join(directory.path, fileName));
      await MediaService.instance.preparePrivateVideo(
          widget.video['encrypted_path'] as String, tempFile.path);
      if (stale()) return;
      _tempFile = tempFile;
      controller = VideoPlayerController.file(tempFile);
      await controller.initialize();
      if (stale()) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      controller.addListener(_onVideoTick);
      await controller.play();
      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
        });
        _scheduleHide();
      }
    } catch (e) {
      await controller?.dispose();
      if (_controller == controller) _controller = null;
      if (!stale()) {
        await _cleanupPlayback();
        setState(() {
          _error = 'Error al reproducir: $e';
          _loading = false;
        });
      }
    }
  }

  bool _wasPlaying = true;

  void _onVideoTick() {
    final playing = _controller?.value.isPlaying ?? false;
    if (playing != _wasPlaying && mounted) {
      _wasPlaying = playing;
      // Al pausar o terminar los controles quedan visibles.
      setState(() {});
      if (playing) _scheduleHide();
    }
  }

  bool get _playing => _controller?.value.isPlaying ?? false;
  bool get _controlsVisible => _showControls || !_playing;

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    _hideTimer?.cancel();
    setState(() => _showControls = !_controlsVisible);
    if (_showControls) _scheduleHide();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      if (c.value.position >= c.value.duration) c.seekTo(Duration.zero);
      c.play();
      _scheduleHide();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: _buildVideo()),
        if (!_loading && _error == null)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_controlsVisible,
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: _buildControls(),
              ),
            ),
          )
        else
          // Mientras carga o falla solo queda el botón de atrás.
          Positioned(top: 0, left: 0, child: _buildBackButton()),
      ],
    );
  }

  Widget _buildVideo() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _error!,
                style: GoogleFonts.poppins(color: Colors.white54, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _initVideo();
              },
              child: Text('Reintentar',
                  style: GoogleFonts.poppins(color: Colors.blue)),
            ),
          ],
        ),
      );
    }
    final controller = _controller;
    if (_loading || controller == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white30));
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      child: Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  Widget _circle(Widget child) => Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          shape: BoxShape.circle,
        ),
        child: child,
      );

  Widget _buildBackButton() => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: _circle(IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          )),
        ),
      );

  // ── Controles únicos: atrás, menú, play/pausa y avance ───
  Widget _buildControls() {
    final controller = _controller!;
    return Stack(
      children: [
        // Los toques en zonas vacías llegan al video por debajo.
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                _circle(IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                )),
                const Spacer(),
                if (widget.counter != null)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Text(widget.counter!,
                        style: GoogleFonts.poppins(
                            color: Colors.white, fontSize: 13)),
                  ),
                if (widget.onSlideshow != null) ...[
                  _circle(IconButton(
                    icon: const Icon(Icons.slideshow_rounded,
                        color: Colors.white),
                    tooltip: 'Presentación',
                    onPressed: _openSlideshow,
                  )),
                  const SizedBox(width: 8),
                ],
                _circle(_buildMenu()),
              ],
            ),
          ),
        ),
        Center(
          child: GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.55),
              ),
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 46,
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: _buildSeekBar(controller),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSeekBar(VideoPlayerController controller) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (_, value, __) {
        final total = value.duration.inMilliseconds;
        final position = value.position.inMilliseconds.clamp(0, total > 0 ? total : 1);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Row(
            children: [
              Text(_formatDuration(value.position),
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 12)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: position.toDouble(),
                    max: total > 0 ? total.toDouble() : 1,
                    onChangeStart: (_) => _hideTimer?.cancel(),
                    onChanged: (v) =>
                        controller.seekTo(Duration(milliseconds: v.round())),
                    onChangeEnd: (_) {
                      if (_playing) _scheduleHide();
                    },
                  ),
                ),
              ),
              Text(_formatDuration(value.duration),
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 12)),
            ],
          ),
        );
      },
    );
  }

  void _openSlideshow() {
    // La presentación reproduce su propia copia; esta se detiene.
    _controller?.pause();
    widget.onSlideshow?.call();
  }

  Widget _buildMenu() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.white),
      color: const Color(0xFF1E1E1E),
      onOpened: () => _controller?.pause(),
      onSelected: (v) {
        switch (v) {
          case 'slideshow':
            _openSlideshow();
          case 'share':
            _shareVideo();
          case 'move':
            _moveVideo();
          case 'unlock':
            _unlockVideo();
          case 'delete':
            _deleteVideo();
          case 'info':
            _showInfo();
        }
      },
      itemBuilder: (_) => [
        if (widget.onSlideshow != null)
          _menuItem('slideshow', Icons.slideshow_rounded, 'Presentación'),
        _menuItem('share', Icons.share_outlined, 'Compartir'),
        _menuItem('move', Icons.drive_file_move_outline, 'Mover'),
        _menuItem('unlock', Icons.lock_open_outlined, 'Desbloquear'),
        _menuItem('delete', Icons.delete_outline, 'Eliminar'),
        _menuItem('info', Icons.info_outline, 'Información'),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String v, IconData icon, String label) =>
      PopupMenuItem<String>(
        value: v,
        child: Row(children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(width: 12),
          Text(label, style: GoogleFonts.poppins(color: Colors.white)),
        ]),
      );

  // ── Compartir ─────────────────────────────────────────────
  Future<void> _shareVideo() async {
    _controller?.pause();
    if (_tempFile == null || !mounted) return;
    await LifecycleGuard.run(() => Share.shareXFiles([XFile(_tempFile!.path)]));
  }

  // ── Mover a carpeta ───────────────────────────────────────
  Future<void> _moveVideo() async {
    _controller?.pause();
    final dest = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          FolderTreeSheet(currentFolderId: widget.video['folder_id'] as int?),
    );
    if (dest == null || !mounted) return;
    try {
      await DBHelper.instance
          .movePhoto(widget.video['id'] as int, dest['id'] as int);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo completar la acción. Inténtalo de nuevo.')));
      }
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  // ── Desbloquear ───────────────────────────────────────────
  Future<void> _unlockVideo() async {
    _controller?.pause();
    // Solo se sale del reproductor si el video ya no está en la bóveda.
    final removed = await confirmUnlock(context, [widget.video]);
    if (removed && mounted) Navigator.pop(context);
  }

  // ── Eliminar / papelera ───────────────────────────────────
  Future<void> _deleteVideo() async {
    _controller?.pause();
    final noTrash = await PrefsService.instance.getNoTrash();
    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title:
            Text('Eliminar', style: GoogleFonts.poppins(color: Colors.white)),
        content: Text(
          noTrash
              ? '¿Eliminar este video permanentemente?'
              : '¿Mover este video a la papelera?',
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
            child: Text(
              noTrash ? 'Eliminar' : 'Mover a papelera',
              style: GoogleFonts.poppins(
                  color: noTrash ? Colors.redAccent : Colors.orange),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      if (noTrash) {
        await MediaService.instance.deletePhoto(widget.video);
      } else {
        await DBHelper.instance.moveToTrash(widget.video);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo completar la acción. Inténtalo de nuevo.')));
      }
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  // ── Información ───────────────────────────────────────────
  Future<void> _showInfo() async {
    _controller?.pause();
    int sizeBytes = 0;
    try {
      sizeBytes = await File(widget.video['encrypted_path'] as String).length();
    } catch (_) {}
    final sizeText = sizeBytes > 1024 * 1024
        ? '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    final date =
        DateTime.fromMillisecondsSinceEpoch(widget.video['date_added'] as int);
    final dateText =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final durationText = _controller != null
        ? _formatDuration(_controller!.value.duration)
        : '—';

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Información',
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            _infoRow(Icons.description_outlined, 'Nombre',
                (widget.video['original_name'] as String?) ?? '—'),
            _infoRow(Icons.calendar_today_outlined, 'Fecha', dateText),
            _infoRow(Icons.sd_storage_outlined, 'Tamaño', sizeText),
            _infoRow(Icons.timer_outlined, 'Duración', durationText),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 18),
          const SizedBox(width: 12),
          Text(label,
              style: GoogleFonts.poppins(color: Colors.white38, fontSize: 12)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return '${duration.inHours}:$m:$s';
    }
    return '$m:$s';
  }
}
