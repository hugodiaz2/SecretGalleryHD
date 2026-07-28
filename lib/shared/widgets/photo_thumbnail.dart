import 'dart:typed_data';
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

  bool get _isVideo {
    final name = (widget.photo['original_name'] ?? '') as String;
    final ext = name.split('.').last.toLowerCase();
    return ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', 'flv']
        .contains(ext);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Uint8List? bytes;
    if (_isVideo) {
      // Generar miniatura del video
      bytes = await MediaService.instance.getVideoThumbnail(
        widget.photo['encrypted_path'],
        widget.photo['original_name'] ?? 'video.mp4',
      );
    } else {
      bytes = await MediaService.instance
          .getPhotoBytes(widget.photo['encrypted_path']);
    }

    if (mounted) {
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail
          _loading
              ? const ColoredBox(color: Color(0xFF2A2A2A))
              : !widget.showPreview // ← si está desactivado
        ? ColoredBox(
            color: const Color(0xFF2A2A2A),
            child: Center(
              child: Icon(
                _isVideo ? Icons.videocam_rounded : Icons.photo_outlined,
                color: Colors.white24,
                size: 24,
              ),
            ),
          )
              : _bytes != null
                  ? Image.memory(
                      _bytes!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const ColoredBox(
                        color: Color(0xFF2A2A2A),
                        child: Icon(Icons.broken_image,
                            color: Colors.white24, size: 24),
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

          // Ícono play para videos
          if (_isVideo && !_loading)
            Center(
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withOpacity(0.55),
                  border:
                      Border.all(color: Colors.white60, width: 1.5),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),

          // Overlay selección
          if (widget.isSelected)
            Container(color: Colors.blue.withOpacity(0.45)),

          // Check selección
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
                child: const Icon(Icons.check,
                    color: Colors.white, size: 13),
              ),
            ),
        ],
      ),
    );
  }
}