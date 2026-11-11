import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/services/media_service.dart';
import '../../core/services/prefs_service.dart';

/// Presentación automática de fotos y videos a pantalla completa.
///
/// Las fotos se muestran durante el intervalo elegido; los videos se
/// reproducen completos y al terminar se pasa al siguiente elemento.
/// Devuelve (con `Navigator.pop`) el `id` del último elemento mostrado para
/// que el visor se quede en esa misma foto.
class SlideshowScreen extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final int initialIndex;

  const SlideshowScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
  });

  @override
  State<SlideshowScreen> createState() => _SlideshowScreenState();
}

class _SlideshowScreenState extends State<SlideshowScreen>
    with SingleTickerProviderStateMixin {
  static const _intervals = [2, 3, 4, 5, 8, 10, 15, 30];
  static const _fade = Duration(milliseconds: 700);

  /// Orden de reproducción: índices sobre [widget.items].
  late List<int> _order;
  late int _pos;

  /// Aumenta en cada cambio para que una diapositiva repetida (lista de un
  /// solo elemento en bucle) se vuelva a montar y reinicie.
  int _step = 0;

  bool _playing = true;
  bool _loop = true;
  bool _shuffle = false;
  bool _muted = false;
  bool _showControls = true;
  int _seconds = 4;

  /// La presentación llegó al final sin repetir y quedó detenida.
  bool _ended = false;

  /// La foto actual ya está en pantalla y su tiempo puede empezar a correr.
  bool _photoReady = false;

  late final AnimationController _progress;
  Timer? _hideTimer;

  Map<String, dynamic> get _current => widget.items[_order[_pos]];
  bool get _currentIsVideo => _isVideo(_current);

  static bool _isVideo(Map<String, dynamic> item) {
    final path = item['encrypted_path'] as String? ?? '';
    final name = (item['original_name'] ?? '') as String;
    return MediaService.isVideoPath(path) ||
        MediaService.isVideoPath(name.isEmpty ? path : name);
  }

  @override
  void initState() {
    super.initState();
    _order = List<int>.generate(widget.items.length, (i) => i);
    _pos = widget.initialIndex.clamp(0, max(0, widget.items.length - 1));
    _progress = AnimationController(
      vsync: this,
      duration: Duration(seconds: _seconds),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) _next(auto: true);
      });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    // Los controles se ven al inicio y se ocultan solos.
    _scheduleHide();
    PrefsService.instance.getSlideshowSeconds().then((s) {
      if (!mounted) return;
      setState(() => _seconds = s);
      _progress.duration = Duration(seconds: s);
      _restartPhotoTimer();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _progress.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Respeta la opción global de "Pantalla encendida".
    PrefsService.instance.getKeepScreenOn().then((keepOn) {
      if (!keepOn) WakelockPlus.disable();
    });
    super.dispose();
  }

  // ── Navegación ────────────────────────────────────────────
  void _goTo(int pos) {
    _progress.stop();
    _progress.value = 0;
    setState(() {
      _pos = pos;
      _step++;
      _photoReady = false;
      _ended = false;
    });
  }

  void _next({bool auto = false}) {
    if (!mounted || widget.items.isEmpty) return;
    if (_pos < _order.length - 1) {
      _goTo(_pos + 1);
    } else if (_loop) {
      if (_shuffle) _reshuffle(keepCurrent: false);
      _goTo(0);
    } else if (auto) {
      // Fin de la presentación: se detiene y muestra los controles.
      _hideTimer?.cancel();
      setState(() {
        _playing = false;
        _ended = true;
        _showControls = true;
      });
    } else {
      _goTo(_pos);
    }
  }

  void _prev() {
    if (_pos > 0) {
      _goTo(_pos - 1);
    } else if (_loop) {
      _goTo(_order.length - 1);
    } else {
      _goTo(0);
    }
  }

  void _reshuffle({bool keepCurrent = true}) {
    final current = _order[_pos];
    final rest = List<int>.generate(widget.items.length, (i) => i)
      ..shuffle(Random());
    if (keepCurrent) {
      rest.remove(current);
      _order = [current, ...rest];
      _pos = 0;
    } else {
      _order = rest;
    }
  }

  // ── Temporizador de fotos ─────────────────────────────────
  void _onPhotoReady() {
    if (!mounted) return;
    _photoReady = true;
    _restartPhotoTimer();
    _prefetchNext();
  }

  void _restartPhotoTimer() {
    if (!_photoReady || _currentIsVideo) return;
    if (_playing) {
      _progress.forward();
    } else {
      _progress.stop();
    }
  }

  /// Descifra con antelación la siguiente foto para que la transición no
  /// muestre una pantalla de carga.
  void _prefetchNext() {
    if (_order.length < 2) return;
    final nextPos = (_pos + 1) % _order.length;
    final next = widget.items[_order[nextPos]];
    final path = next['encrypted_path'] as String?;
    if (path == null) return;
    if (_isVideo(next)) {
      MediaService.instance
          .getVideoThumbnail(path, next['original_name'] ?? 'video.mp4');
    } else {
      MediaService.instance.getPhotoBytes(path);
    }
  }

  // ── Controles ─────────────────────────────────────────────
  void _togglePlay() {
    if (_ended) {
      // Reanudar tras el final vuelve a empezar desde el primero.
      setState(() => _playing = true);
      _goTo(0);
      _scheduleHide();
      return;
    }
    setState(() => _playing = !_playing);
    _restartPhotoTimer();
    _scheduleHide();
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_showControls) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing) setState(() => _showControls = false);
    });
  }

  void _setSeconds(int s) {
    setState(() => _seconds = s);
    PrefsService.instance.saveSlideshowSeconds(s);
    // Conserva la fracción ya transcurrida de la foto actual.
    _progress.duration = Duration(seconds: s);
    if (_progress.isAnimating) _progress.forward();
    _scheduleHide();
  }

  Future<void> _pickInterval() async {
    _hideTimer?.cancel();
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tiempo por foto',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Los videos se reproducen completos.',
                  style:
                      GoogleFonts.poppins(color: Colors.white38, fontSize: 12)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in _intervals)
                    ChoiceChip(
                      label: Text('$s s'),
                      selected: s == _seconds,
                      onSelected: (_) => Navigator.pop(ctx, s),
                      labelStyle: GoogleFonts.poppins(
                          color: s == _seconds ? Colors.black : Colors.white),
                      selectedColor: Colors.white,
                      backgroundColor: Colors.white10,
                      showCheckmark: false,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) {
      _setSeconds(picked);
    } else {
      _scheduleHide();
    }
  }

  void _close() => Navigator.pop(context, _current['id']);

  // ── UI ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const Scaffold(backgroundColor: Colors.black);
    }
    final item = _current;
    final isVideo = _isVideo(item);
    final slide = isVideo
        ? _SlideVideo(
            key: ValueKey('v$_step'),
            video: item,
            playing: _playing,
            muted: _muted,
            onFinished: () => _next(auto: true),
          )
        : _SlidePhoto(
            key: ValueKey('p$_step'),
            photo: item,
            onReady: _onPhotoReady,
          );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
                onHorizontalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v < -250) _next();
                  if (v > 250) _prev();
                },
                child: AnimatedSwitcher(
                  duration: _fade,
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(
                      scale: Tween(begin: 1.04, end: 1.0).animate(anim),
                      child: child,
                    ),
                  ),
                  layoutBuilder: (current, previous) => Stack(
                    fit: StackFit.expand,
                    children: [...previous, if (current != null) current],
                  ),
                  child: slide,
                ),
              ),
            ),
            // Barra de progreso de la foto actual (siempre visible, discreta).
            if (!isVideo)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: AnimatedBuilder(
                    animation: _progress,
                    builder: (_, __) => LinearProgressIndicator(
                      value: _progress.value,
                      minHeight: 2,
                      backgroundColor: Colors.white10,
                      valueColor:
                          const AlwaysStoppedAnimation(Colors.white70),
                    ),
                  ),
                ),
              ),
            Positioned(top: 0, left: 0, right: 0, child: _fadeIn(_topBar())),
            Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _fadeIn(_bottomBar(isVideo))),
          ],
        ),
      ),
    );
  }

  Widget _fadeIn(Widget child) => IgnorePointer(
        ignoring: !_showControls,
        child: AnimatedOpacity(
          opacity: _showControls ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: child,
        ),
      );

  Widget _pill({required Widget child, EdgeInsets? padding}) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(28),
        ),
        child: child,
      );

  Widget _topBar() => SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(
            children: [
              _pill(
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: 'Salir de la presentación',
                  onPressed: _close,
                ),
              ),
              const Spacer(),
              _pill(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Text(
                  '${_pos + 1} / ${_order.length}',
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _bottomBar(bool isVideo) {
    Widget btn(IconData icon, String tip, VoidCallback onTap,
            {bool active = true, double size = 24}) =>
        IconButton(
          onPressed: onTap,
          tooltip: tip,
          icon: Icon(icon,
              size: size, color: active ? Colors.white : Colors.white38),
        );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: _pill(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              btn(Icons.shuffle_rounded, 'Aleatorio', () {
                setState(() {
                  _shuffle = !_shuffle;
                  if (_shuffle) {
                    _reshuffle();
                  } else {
                    final current = _order[_pos];
                    _order = List<int>.generate(widget.items.length, (i) => i);
                    _pos = current;
                  }
                });
                _scheduleHide();
              }, active: _shuffle),
              btn(Icons.skip_previous_rounded, 'Anterior', () {
                _prev();
                _scheduleHide();
              }),
              btn(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                _playing ? 'Pausar' : 'Reproducir',
                _togglePlay,
                size: 34,
              ),
              btn(Icons.skip_next_rounded, 'Siguiente', () {
                _next();
                _scheduleHide();
              }),
              btn(Icons.repeat_rounded, 'Repetir', () {
                setState(() => _loop = !_loop);
                _scheduleHide();
              }, active: _loop),
              if (isVideo)
                btn(
                    _muted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    _muted ? 'Activar sonido' : 'Silenciar', () {
                  setState(() => _muted = !_muted);
                  _scheduleHide();
                })
              else
                TextButton(
                  onPressed: _pickInterval,
                  child: Text('${_seconds}s',
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Diapositiva de foto ──────────────────────────────────────
class _SlidePhoto extends StatefulWidget {
  final Map<String, dynamic> photo;
  final VoidCallback onReady;

  const _SlidePhoto({super.key, required this.photo, required this.onReady});

  @override
  State<_SlidePhoto> createState() => _SlidePhotoState();
}

class _SlidePhotoState extends State<_SlidePhoto> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await MediaService.instance
        .getPhotoBytes(widget.photo['encrypted_path'] as String);
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _loading = false;
    });
    // Una foto ilegible no debe detener la presentación: también cuenta.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white24));
    }
    if (_bytes == null) {
      return const Center(
          child: Icon(Icons.broken_image, color: Colors.white24, size: 64));
    }
    return ColoredBox(
      color: Colors.black,
      child: Image.memory(
        _bytes!,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image, color: Colors.white24, size: 64),
        ),
      ),
    );
  }
}

// ── Diapositiva de video ─────────────────────────────────────
class _SlideVideo extends StatefulWidget {
  final Map<String, dynamic> video;
  final bool playing;
  final bool muted;
  final VoidCallback onFinished;

  const _SlideVideo({
    super.key,
    required this.video,
    required this.playing,
    required this.muted,
    required this.onFinished,
  });

  @override
  State<_SlideVideo> createState() => _SlideVideoState();
}

class _SlideVideoState extends State<_SlideVideo> {
  VideoPlayerController? _controller;
  Directory? _tempDir;
  Uint8List? _thumb;
  bool _failed = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    final path = widget.video['encrypted_path'] as String;
    _thumb = MediaService.instance.cachedThumbnail(path, video: true);
    if (_thumb == null) {
      MediaService.instance
          .getVideoThumbnail(
              path, widget.video['original_name'] as String? ?? 'video.mp4')
          .then((b) {
        if (mounted && _controller == null) setState(() => _thumb = b);
      });
    }
    _init();
  }

  @override
  void didUpdateWidget(_SlideVideo old) {
    super.didUpdateWidget(old);
    final c = _controller;
    if (c == null) return;
    if (widget.playing != old.playing) {
      widget.playing ? c.play() : c.pause();
    }
    if (widget.muted != old.muted) c.setVolume(widget.muted ? 0 : 1);
  }

  @override
  void dispose() {
    final c = _controller;
    _controller = null;
    c?.removeListener(_onTick);
    c?.dispose();
    _deleteDir(_tempDir);
    _tempDir = null;
    super.dispose();
  }

  static Future<void> _deleteDir(Directory? dir) async {
    if (dir == null) return;
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  Future<void> _init() async {
    VideoPlayerController? controller;
    try {
      final dir = await (await getTemporaryDirectory()).createTemp('sg_slide_');
      if (!mounted) {
        await dir.delete(recursive: true);
        return;
      }
      _tempDir = dir;
      final name =
          p.basename(widget.video['original_name'] as String? ?? 'video.mp4');
      final file = File(p.join(dir.path, name));
      await MediaService.instance
          .preparePrivateVideo(widget.video['encrypted_path'] as String,
              file.path);
      if (!mounted) {
        await _deleteDir(dir);
        return;
      }
      controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setVolume(widget.muted ? 0 : 1);
      controller.addListener(_onTick);
      setState(() => _controller = controller);
      if (widget.playing) await controller.play();
    } catch (_) {
      await controller?.dispose();
      if (!mounted) return;
      setState(() => _failed = true);
      // Un video que no se puede abrir se salta tras una breve pausa.
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _finish();
      });
    }
  }

  void _onTick() {
    final v = _controller?.value;
    if (v == null || !v.isInitialized || v.duration == Duration.zero) return;
    if (!v.isPlaying && v.position >= v.duration) _finish();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c != null) {
      return ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: c.value.aspectRatio,
                child: VideoPlayer(c),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: 2,
                  child: VideoProgressIndicator(
                    c,
                    allowScrubbing: false,
                    padding: EdgeInsets.zero,
                    colors: const VideoProgressColors(
                      playedColor: Colors.white70,
                      bufferedColor: Colors.white24,
                      backgroundColor: Colors.white10,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_thumb != null)
            Image.memory(_thumb!, fit: BoxFit.contain, gaplessPlayback: true),
          Center(
            child: _failed
                ? const Icon(Icons.error_outline,
                    color: Colors.white38, size: 48)
                : const CircularProgressIndicator(color: Colors.white38),
          ),
        ],
      ),
    );
  }
}
