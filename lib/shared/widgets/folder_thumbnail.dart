import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/db_helper.dart';
import '../../core/services/media_service.dart';

class FolderThumbnail extends StatefulWidget {
  final Map<String, dynamic> folder;
  final bool isSelected;
  final bool showPreview;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final void Function(Offset) onMenuTap;
  final VoidCallback? onCoverChanged;

  const FolderThumbnail({
    super.key,
    required this.folder,
    required this.isSelected,
    this.showPreview = true,
    required this.onTap,
    required this.onLongPress,
    required this.onMenuTap,
    this.onCoverChanged,
  });

  @override
  State<FolderThumbnail> createState() => _FolderThumbnailState();
}

class _FolderThumbnailState extends State<FolderThumbnail> {
  Uint8List? _coverBytes;
  bool _loading = true;
  String? _loadedCoverPath;
  Timer? _loadTimer;
  int _requestVersion = 0;

  @override
  void initState() {
    super.initState();
    _scheduleCover();
  }

  @override
  void didUpdateWidget(FolderThumbnail old) {
    super.didUpdateWidget(old);
    final oldPath = old.folder['cover_photo_path']?.toString();
    final newPath = widget.folder['cover_photo_path']?.toString();
    if (oldPath != newPath ||
        old.folder['id'] != widget.folder['id'] ||
        old.folder['total_count'] != widget.folder['total_count'] ||
        old.showPreview != widget.showPreview) {
      _scheduleCover();
    }
  }

  void _scheduleCover() {
    _loadTimer?.cancel();
    final version = ++_requestVersion;
    _coverBytes = null;
    _loadedCoverPath = null;
    _loading = widget.showPreview;
    if (!widget.showPreview) return;
    final path = widget.folder['cover_photo_path']?.toString();
    if (path != null) {
      _coverBytes = MediaService.instance
          .cachedThumbnail(path, video: MediaService.isVideoPath(path));
      if (_coverBytes != null) {
        _loadedCoverPath = path;
        _loading = false;
        return;
      }
    }
    void start() {
      if (!mounted || version != _requestVersion) return;
      if (Scrollable.recommendDeferredLoadingForContext(context)) {
        _loadTimer = Timer(const Duration(milliseconds: 32), start);
      } else {
        _loadCover();
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

  Future<void> _loadCover() async {
    final version = _requestVersion;
    bool needed() =>
        mounted && version == _requestVersion && widget.showPreview;
    final path =
        await DBHelper.instance.getCoverPhoto(widget.folder['id'] as int);
    if (!needed()) return;
    if (path == null) {
      if (!mounted) return;
      setState(() {
        _coverBytes = null;
        _loading = false;
        _loadedCoverPath = null;
      });
      return;
    }

    if (_loadedCoverPath == path && _coverBytes != null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final requestPath = path;
    final bytes = MediaService.isVideoPath(requestPath)
        ? await MediaService.instance
            .getVideoThumbnail(requestPath, 'cover_thumb.mp4', isNeeded: needed)
        : await MediaService.instance
            .getPhotoThumbnail(requestPath, isNeeded: needed);

    if (!needed()) {
      return;
    }

    if (mounted) {
      setState(() {
        _coverBytes = bytes;
        _loading = false;
        _loadedCoverPath = requestPath;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = (widget.folder['total_count'] as int?) ?? 0;
    final name = widget.folder['name'] as String;
    final accent = Theme.of(context).colorScheme.primary;
    final hasCover = widget.showPreview && !_loading && _coverBytes != null;

    Widget placeholder() => const ColoredBox(
          color: Color(0xFF242424),
          child: Center(
              child:
                  Icon(Icons.folder_outlined, color: Colors.white54, size: 30)),
        );

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(fit: StackFit.expand, children: [
          if (hasCover)
            RepaintBoundary(
              child: LayoutBuilder(builder: (context, constraints) {
                final dpr = MediaQuery.devicePixelRatioOf(context);
                return Image.memory(
                  _coverBytes!,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  cacheWidth:
                      (constraints.maxWidth * dpr).round().clamp(96, 384),
                  cacheHeight:
                      (constraints.maxHeight * dpr).round().clamp(96, 384),
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => placeholder(),
                );
              }),
            )
          else
            placeholder(),
          if (count > 0)
            Positioned(
              top: 0,
              left: 0,
              child: CustomPaint(
                size: const Size(40, 40),
                painter: _TriangleBadge(count.toString()),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: const Color(0x66000000),
              padding: const EdgeInsets.only(left: 6),
              child: Row(children: [
                Expanded(
                    child: Text(name,
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                Tooltip(
                  message: 'Opciones de carpeta',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) =>
                        widget.onMenuTap(details.globalPosition),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                      child:
                          Icon(Icons.more_vert, color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          if (widget.isSelected) ...[
            IgnorePointer(
                child: DecoratedBox(
                    decoration: BoxDecoration(
              border: Border.all(color: accent, width: 2),
              borderRadius: BorderRadius.circular(8),
            ))),
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 20,
                height: 20,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: accent),
                child: const Icon(Icons.check, color: Colors.white, size: 13),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _TriangleBadge extends CustomPainter {
  final String count;
  _TriangleBadge(this.count);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(0, size.height)
        ..close(),
      Paint()..color = const Color(0x66000000),
    );
    final label = TextPainter(
      text: TextSpan(
          text: count,
          style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, const Offset(3, 2));
  }

  @override
  bool shouldRepaint(_TriangleBadge oldDelegate) => oldDelegate.count != count;
}
