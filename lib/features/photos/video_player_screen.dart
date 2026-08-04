import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../../core/database/db_helper.dart';
import '../../core/services/media_service.dart';
import '../../core/services/prefs_service.dart';
import '../../shared/widgets/folder_tree_sheet.dart';
import '../../shared/widgets/unlock_helper.dart';

class VideoPlayerScreen extends StatefulWidget {
  final Map<String, dynamic> video;

  const VideoPlayerScreen({super.key, required this.video});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _loading = true;
  String? _error;
  File? _tempFile;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initVideo();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _chewieController?.dispose();
    _videoController?.dispose();
    _tempFile?.delete().catchError((_) {});
    super.dispose();
  }

  Future<void> _initVideo() async {
    try {
      final bytes = await MediaService.instance
          .getPhotoBytes(widget.video['encrypted_path']);

      if (bytes == null) {
        if (mounted) {
          setState(() {
          _error = 'No se pudo cargar el video';
          _loading = false;
        });
        }
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final fileName = widget.video['original_name'] ?? 'video.mp4';
      final tempPath = p.join(tempDir.path, 'tmp_$fileName');
      _tempFile = File(tempPath);
      await _tempFile!.writeAsBytes(bytes);

      _videoController = VideoPlayerController.file(_tempFile!);
      await _videoController!.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControlsOnInitialize: true,
        placeholder: Container(color: Colors.black),
        // Sin ChewieProgressColors para evitar errores de versión
      );

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
        _error = 'Error al reproducir: $e';
        _loading = false;
      });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.video['original_name'] ?? 'Video',
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.blue),
                  SizedBox(height: 16),
                  Text(
                    'Cargando video...',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.redAccent, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: GoogleFonts.poppins(
                            color: Colors.white54, fontSize: 13),
                        textAlign: TextAlign.center,
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
                        child: Text(
                          'Reintentar',
                          style: GoogleFonts.poppins(color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                )
              : SafeArea(
                  bottom: false,
                  child: Chewie(controller: _chewieController!),
                ),
      bottomNavigationBar:
          (!_loading && _error == null) ? _buildBottomBar() : null,
    );
  }

  // ── Barra de acciones inferior ───────────────────────────
  Widget _buildBottomBar() {
    return Container(
      color: Colors.black,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _barAction(Icons.share_outlined, 'Compartir', _shareVideo),
              _barAction(
                  Icons.drive_file_move_outline, 'Mover', _moveVideo),
              _barAction(
                  Icons.lock_open_outlined, 'Desbloquear', _unlockVideo),
              _barAction(Icons.delete_outline, 'Eliminar', _deleteVideo),
              _barAction(Icons.info_outline, 'Información', _showInfo),
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
  Future<void> _shareVideo() async {
    _videoController?.pause();
    if (_tempFile == null || !mounted) return;
    await Share.shareXFiles([XFile(_tempFile!.path)]);
  }

  // ── Mover a carpeta ───────────────────────────────────────
  Future<void> _moveVideo() async {
    _videoController?.pause();
    final dest = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          FolderTreeSheet(currentFolderId: widget.video['folder_id'] as int?),
    );
    if (dest == null || !mounted) return;
    await DBHelper.instance
        .movePhoto(widget.video['id'] as int, dest['id'] as int);
    if (mounted) Navigator.pop(context);
  }

  // ── Desbloquear ───────────────────────────────────────────
  void _unlockVideo() {
    _videoController?.pause();
    confirmUnlock(
      context,
      [widget.video],
      onDone: () => Navigator.pop(context),
    );
  }

  // ── Eliminar / papelera ───────────────────────────────────
  Future<void> _deleteVideo() async {
    _videoController?.pause();
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

    if (noTrash) {
      await MediaService.instance.deletePhoto(widget.video);
    } else {
      await DBHelper.instance.moveToTrash(widget.video);
    }
    if (mounted) Navigator.pop(context);
  }

  // ── Información ───────────────────────────────────────────
  Future<void> _showInfo() async {
    _videoController?.pause();
    int sizeBytes = 0;
    try {
      sizeBytes =
          await File(widget.video['encrypted_path'] as String).length();
    } catch (_) {}
    final sizeText = sizeBytes > 1024 * 1024
        ? '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    final date =
        DateTime.fromMillisecondsSinceEpoch(widget.video['date_added'] as int);
    final dateText =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final durationText = _videoController != null
        ? _formatDuration(_videoController!.value.duration)
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