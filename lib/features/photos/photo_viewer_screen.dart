import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/database/db_helper.dart';
import '../../core/services/media_service.dart';
import '../../core/services/prefs_service.dart';
import '../../shared/widgets/folder_tree_sheet.dart';
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
              ],
            )
          : null,
      body: Stack(
        children: [
          GestureDetector(
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
          if (_showBars)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomBar(currentPhoto),
            ),
        ],
      ),
    );
  }

  // ── Barra de acciones inferior ───────────────────────────
  Widget _buildBottomBar(Map<String, dynamic> photo) {
    return Container(
      color: Colors.black54,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _barAction(Icons.share_outlined, 'Compartir',
                  () => _sharePhoto(photo)),
              _barAction(Icons.drive_file_move_outline, 'Mover',
                  () => _movePhoto(photo)),
              _barAction(Icons.lock_open_outlined, 'Desbloquear',
                  () => _unlockPhoto(photo)),
              _barAction(
                  Icons.delete_outline, 'Eliminar', () => _deletePhoto(photo)),
              _barAction(
                  Icons.info_outline, 'Información', () => _showInfo(photo)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 23),
            const SizedBox(height: 4),
            Text(label,
                style: GoogleFonts.poppins(
                    color: Colors.white70, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  // ── Compartir ─────────────────────────────────────────────
  Future<void> _sharePhoto(Map<String, dynamic> photo) async {
    final bytes =
        await MediaService.instance.getPhotoBytes(photo['encrypted_path']);
    if (bytes == null || !mounted) return;
    final tempDir = await getTemporaryDirectory();
    final name = (photo['original_name'] as String?) ?? 'archivo';
    final tempFile = File('${tempDir.path}/$name');
    await tempFile.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(tempFile.path)]);
  }

  // ── Mover a carpeta ───────────────────────────────────────
  Future<void> _movePhoto(Map<String, dynamic> photo) async {
    final dest = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          FolderTreeSheet(currentFolderId: photo['folder_id'] as int?),
    );
    if (dest == null || !mounted) return;
    await DBHelper.instance
        .movePhoto(photo['id'] as int, dest['id'] as int);
    if (mounted) Navigator.pop(context);
  }

  // ── Desbloquear ───────────────────────────────────────────
  void _unlockPhoto(Map<String, dynamic> photo) {
    confirmUnlock(
      context,
      [photo],
      onDone: () => Navigator.pop(context),
    );
  }

  // ── Eliminar / papelera ───────────────────────────────────
  Future<void> _deletePhoto(Map<String, dynamic> photo) async {
    final noTrash = await PrefsService.instance.getNoTrash();
    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Eliminar',
            style: GoogleFonts.poppins(color: Colors.white)),
        content: Text(
          noTrash
              ? '¿Eliminar este archivo permanentemente?'
              : '¿Mover este archivo a la papelera?',
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

    if (noTrash) {
      await MediaService.instance.deletePhoto(photo);
    } else {
      await DBHelper.instance.moveToTrash(photo);
    }
    if (mounted) Navigator.pop(context);
  }

  // ── Información ───────────────────────────────────────────
  Future<void> _showInfo(Map<String, dynamic> photo) async {
    int sizeBytes = 0;
    try {
      sizeBytes = await File(photo['encrypted_path'] as String).length();
    } catch (_) {}
    final sizeText = sizeBytes > 1024 * 1024
        ? '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    final date =
        DateTime.fromMillisecondsSinceEpoch(photo['date_added'] as int);
    final dateText =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

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
                (photo['original_name'] as String?) ?? '—'),
            _infoRow(Icons.calendar_today_outlined, 'Fecha', dateText),
            _infoRow(Icons.sd_storage_outlined, 'Tamaño', sizeText),
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