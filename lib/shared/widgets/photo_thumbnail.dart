import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/services/media_service.dart';

class PhotoThumbnail extends StatefulWidget {
  final Map<String, dynamic> photo;
  final bool isSelected;
  final bool showPreview;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const PhotoThumbnail({
    required Key key,
    required this.photo,
    this.isSelected = false,
    this.showPreview = true,
    this.onTap,
    this.onLongPress,
  }) : super(key: key);

  @override
  State<PhotoThumbnail> createState() => _PhotoThumbnailState();
}

class _PhotoThumbnailState extends State<PhotoThumbnail> {
  Uint8List? _bytes;
  bool _loading = true;
  String? _loadedPath;
  Timer? _loadTimer;
  int _requestVersion = 0;

  @override
  void didUpdateWidget(PhotoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPath = oldWidget.photo['encrypted_path']?.toString();
    final newPath = widget.photo['encrypted_path']?.toString();
    if (oldPath != newPath || oldWidget.showPreview != widget.showPreview) {
      _scheduleLoad();
    }
  }

  bool get _isVideo {
    final name = (widget.photo['original_name'] ?? '') as String;
    final ext = name.split('.').last.toLowerCase();
    return ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', 'flv'].contains(ext);
  }

  @override
  void initState() {
    super.initState();
    _scheduleLoad();
  }

  void _scheduleLoad() {
    _loadTimer?.cancel();
    final version = ++_requestVersion;
    _bytes = null;
    _loadedPath = null;
    _loading = widget.showPreview;
    if (!widget.showPreview) return;
    final path = widget.photo['encrypted_path']?.toString();
    if (path != null) {
      _bytes = MediaService.instance.cachedThumbnail(path, video: _isVideo);
      if (_bytes != null) {
        _loadedPath = path;
        _loading = false;
        return;
      }
    }
    void start() {
      if (!mounted || version != _requestVersion) return;
      if (Scrollable.recommendDeferredLoadingForContext(context)) {
        _loadTimer = Timer(const Duration(milliseconds: 32), start);
      } else {
        _load();
      }
    }

    _loadTimer = Timer(Duration.zero, start);
  }

  @override
  void dispose() {
    _requestVersion++;
    _loadTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final version = _requestVersion;
    bool needed() =>
        mounted && version == _requestVersion && widget.showPreview;
    final path = widget.photo['encrypted_path']?.toString();
    if (path == null || path.isEmpty) {
      if (mounted) {
        setState(() {
          _bytes = null;
          _loading = false;
          _loadedPath = path;
        });
      }
      return;
    }

    if (_loadedPath == path && _bytes != null) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }

    final requestPath = path;
    Uint8List? bytes;
    if (_isVideo) {
      bytes = await MediaService.instance.getVideoThumbnail(
        requestPath,
        widget.photo['original_name'] ?? 'video.mp4',
        isNeeded: needed,
      );
    } else {
      bytes = await MediaService.instance
          .getPhotoThumbnail(requestPath, isNeeded: needed);
    }

    if (!needed() ||
        requestPath != widget.photo['encrypted_path']?.toString()) {
      return;
    }

    setState(() {
      _bytes = bytes;
      _loading = false;
      _loadedPath = requestPath;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final widthPx = (constraints.maxWidth * dpr).round().clamp(96, 384);
        final heightPx = (constraints.maxHeight * dpr).round().clamp(96, 384);

        return GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _loading
                  ? const ColoredBox(color: Color(0xFF2A2A2A))
                  : !widget.showPreview
                      ? ColoredBox(
                          color: const Color(0xFF2A2A2A),
                          child: Center(
                            child: Icon(
                              _isVideo
                                  ? Icons.videocam_rounded
                                  : Icons.photo_outlined,
                              color: Colors.white24,
                              size: 24,
                            ),
                          ),
                        )
                      : _bytes != null
                          ? RepaintBoundary(
                              child: Image.memory(
                                _bytes!,
                                fit: BoxFit.cover,
                                alignment: Alignment.center,
                                gaplessPlayback: true,
                                cacheWidth: widthPx,
                                cacheHeight: heightPx,
                                filterQuality: FilterQuality.low,
                                errorBuilder: (_, __, ___) => const ColoredBox(
                                  color: Color(0xFF2A2A2A),
                                  child: Icon(Icons.broken_image,
                                      color: Colors.white24, size: 24),
                                ),
                              ),
                            )
                          : ColoredBox(
                              color: const Color(0xFF1A1A2E),
                              child: Center(
                                child: Icon(
                                  _isVideo
                                      ? Icons.videocam_rounded
                                      : Icons.broken_image,
                                  color: Colors.white24,
                                  size: 24,
                                ),
                              ),
                            ),
              if (_isVideo && !_loading)
                Center(
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withOpacity(0.55),
                      border: Border.all(color: Colors.white60, width: 1.5),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              if (widget.isSelected)
                Container(color: Colors.blue.withOpacity(0.45)),
              if (widget.isSelected)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.blue,
                    ),
                    child:
                        const Icon(Icons.check, color: Colors.white, size: 13),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
