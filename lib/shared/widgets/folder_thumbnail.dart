import 'dart:typed_data';
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

  @override
  void initState() {
    super.initState();
    _loadCover();
  }

  @override
  void didUpdateWidget(FolderThumbnail old) {
    super.didUpdateWidget(old);
    if (old.folder['cover_photo_path'] !=
        widget.folder['cover_photo_path']) {
      _loadCover();
    }
  }

  Future<void> _loadCover() async {
  setState(() => _loading = true);
  final path =
      await DBHelper.instance.getCoverPhoto(widget.folder['id'] as int);
  if (path != null) {
    final bytes = await MediaService.instance.getPhotoBytes(path);
    if (mounted) setState(() => _coverBytes = bytes);
  } else {
    // ✅ Limpiar bytes si no hay portada
    if (mounted) setState(() => _coverBytes = null);
  }
  if (mounted) setState(() => _loading = false);
}

  @override
  Widget build(BuildContext context) {
    final count = (widget.folder['total_count'] as int?) ?? 0;
    final subs = (widget.folder['sub_count'] as int?) ?? 0;
    final name = widget.folder['name'] as String;
    final isSelected = widget.isSelected;

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF1A2A3A)
              : const Color(0xFF1E1E1E),
          border: isSelected
              ? Border.all(color: Colors.blue, width: 2)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Área de imagen/icono ──
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Fondo / miniatura
                  _loading
                      ? Container(color: const Color(0xFF2A2A2A))
                       : !widget.showPreview // ← si está desactivado
        ? Container(color: const Color(0xFF2A2A2A))
                      : _coverBytes != null
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.memory(
                                  _coverBytes!,
                                  fit: BoxFit.cover,
                                ),
                                Container(
                                  color: Colors.black.withOpacity(0.3),
                                ),
                              ],
                            )
                          : Container(color: const Color(0xFF2A2A2A)),

                  // Icono candado/carpeta centrado
                  Center(
                    child: Icon(
                      _coverBytes != null
                          ? (subs > 0
                              ? Icons.folder_copy
                              : Icons.folder)
                          : Icons.lock_rounded,
                      color: _coverBytes != null
                          ? Colors.white.withOpacity(0.85)
                          : isSelected
                              ? Colors.blue
                              : Colors.white54,
                      size: 30,
                      shadows: _coverBytes != null
                          ? const [
                              Shadow(
                                  color: Colors.black54, blurRadius: 8)
                            ]
                          : null,
                    ),
                  ),

                  // Badge triángulo con conteo
                  if (count > 0)
                    Positioned(
                      top: 0,
                      left: 0,
                      child: CustomPaint(
                        size: const Size(40, 40),
                        painter: _TriangleBadge(count.toString()),
                      ),
                    ),

                  // Check de selección
                  if (isSelected)
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
            ),

            // ── Nombre y menú ──
            Container(
              color: const Color(0xFF0F0F0F),
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subs > 0)
                          Text(
                            '$subs subcarpeta${subs == 1 ? '' : 's'}',
                            style: GoogleFonts.poppins(
                              color: Colors.white38,
                              fontSize: 8,
                            ),
                          ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTapDown: (d) =>
                        widget.onMenuTap(d.globalPosition),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(
                        Icons.more_vert,
                        color: Colors.white54,
                        size: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
      Paint()..color = const Color(0xFF1565C0),
    );
    (TextPainter(
      text: TextSpan(
        text: count,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout())
        .paint(canvas, const Offset(2, 1));
  }

  @override
  bool shouldRepaint(_TriangleBadge o) => o.count != count;
}