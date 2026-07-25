import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/media_service.dart';
import '../../shared/widgets/unlock_helper.dart';
import 'video_player_screen.dart';

class PhotoViewerScreen extends StatefulWidget {
  final List<Map<String, dynamic>> photos;
  final int initialIndex;

  const PhotoViewerScreen({
    super.key,
    required this.photos,
    required this.initialIndex,
  });

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;
  bool _showBars = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleBars() => setState(() => _showBars = !_showBars);

  bool _isVideo(Map<String, dynamic> photo) {
    final name = (photo['original_name'] ?? '') as String;
    final ext = name.split('.').last.toLowerCase();
    return ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', 'flv']
        .contains(ext);
  }

  void _openVideoPlayer(Map<String, dynamic> photo) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(video: photo),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentPhoto = widget.photos[_currentIndex];
    final currentIsVideo = _isVideo(currentPhoto);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _showBars
          ? AppBar(
              backgroundColor: Colors.black54,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              title: Row(
                children: [
                  if (currentIsVideo)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.videocam_rounded,
                          color: Colors.white54, size: 18),
                    ),
                  Text(
                    '${_currentIndex + 1} / ${widget.photos.length}',
                    style: GoogleFonts.poppins(
                        color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
              actions: [
                if (currentIsVideo)
                  IconButton(
                    icon: const Icon(Icons.play_circle_outline,
                        color: Colors.white),
                    tooltip: 'Reproducir',
                    onPressed: () => _openVideoPlayer(currentPhoto),
                  ),
                IconButton(
                  icon: const Icon(Icons.lock_open_outlined,
                      color: Colors.white),
                  tooltip: 'Desbloquear',
                  onPressed: () => confirmUnlock(
                    context,
                    [currentPhoto],
                    onDone: () => Navigator.pop(context),
                  ),
                ),
              ],
            )
          : null,
      body: GestureDetector(
        onTap: _toggleBars,
        child: PageView.builder(
          controller: _pageController,
          itemCount: widget.photos.length,
          onPageChanged: (i) => setState(() => _currentIndex = i),
          itemBuilder: (_, i) {
            final photo = widget.photos[i];
            if (_isVideo(photo)) {
              return _VideoThumbPage(
                photo: photo,
                onPlayTap: () => _openVideoPlayer(photo),
                autoOpen: i == widget.initialIndex,
              );
            }
            return _ZoomablePhoto(photo: photo);
          },
        ),
      ),
    );
  }
}

// ── Página thumbnail de video ────────────────────────────────
class _VideoThumbPage extends StatefulWidget {
  final Map<String, dynamic> photo;
  final VoidCallback onPlayTap;
  final bool autoOpen;

  const _VideoThumbPage({
    required this.photo,
    required this.onPlayTap,
    this.autoOpen = false,
  });

  @override
  State<_VideoThumbPage> createState() => _VideoThumbPageState();
}

class _VideoThumbPageState extends State<_VideoThumbPage> {
  Uint8List? _thumbBytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadThumb();
    if (widget.autoOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onPlayTap();
      });
    }
  }

  Future<void> _loadThumb() async {
    final bytes = await MediaService.instance.getVideoThumbnail(
      widget.photo['encrypted_path'],
      widget.photo['original_name'] ?? 'video.mp4',
    );
    if (mounted) {
      setState(() {
        _thumbBytes = bytes;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.photo['original_name'] ?? 'Video') as String;

    return GestureDetector(
      onTap: widget.onPlayTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Miniatura del video
          _loading
              ? const ColoredBox(color: Colors.black)
              : _thumbBytes != null
                  ? Image.memory(
                      _thumbBytes!,
                      fit: BoxFit.contain,
                    )
                  : Container(
                      color: const Color(0xFF1A1A2E),
                      child: const Center(
                        child: Icon(Icons.videocam_rounded,
                            color: Colors.white24, size: 64),
                      ),
                    ),

          // Overlay oscuro
          Container(color: Colors.black.withOpacity(0.25)),

          // Botón play central
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.6),
                border:
                    Border.all(color: Colors.white70, width: 2),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 50,
              ),
            ),
          ),

          // Nombre del video
          Positioned(
            bottom: 60,
            left: 16,
            right: 16,
            child: Text(
              name,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                shadows: [
                  Shadow(color: Colors.black, blurRadius: 4)
                ],
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Foto con zoom ────────────────────────────────────────────
class _ZoomablePhoto extends StatefulWidget {
  final Map<String, dynamic> photo;
  const _ZoomablePhoto({required this.photo});

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await MediaService.instance
        .getPhotoBytes(widget.photo['encrypted_path']);
    if (mounted) {
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white30));
    }
    if (_bytes == null) {
      return const Center(
          child: Icon(Icons.broken_image,
              color: Colors.white24, size: 64));
    }
    return InteractiveViewer(
      minScale: 0.8,
      maxScale: 5.0,
      child: Center(
        child: Image.memory(
          _bytes!,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.broken_image,
                color: Colors.white24, size: 64),
          ),
        ),
      ),
    );
  }
}