import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/media_service.dart';

Future<void> confirmUnlock(
    BuildContext context,
    List<Map<String, dynamic>> photos,
    {VoidCallback? onDone}) async {
  final count = photos.length;

  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.lock_open, color: Colors.blue, size: 22),
          const SizedBox(width: 8),
          Text('Desbloquear',
              style: GoogleFonts.poppins(
                  color: Colors.white, fontWeight: FontWeight.w600)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            count == 1
                ? 'Este archivo será desencriptado y restaurado en tu galería.'
                : 'Los $count archivos seleccionados serán desencriptados y restaurados en tu galería.',
            style: GoogleFonts.poppins(
                color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    color: Colors.blue, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Las fotos dejarán de estar protegidas y serán visibles en la galería.',
                    style: GoogleFonts.poppins(
                        color: Colors.blue, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Cancelar',
              style: GoogleFonts.poppins(color: Colors.white38)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          icon: const Icon(Icons.lock_open,
              color: Colors.white, size: 16),
          label: Text('Desbloquear',
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600)),
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );

  if (confirm != true || !context.mounted) return;

  // Progreso
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Colors.blue),
          const SizedBox(height: 16),
          Text('Restaurando a galería...',
              style: GoogleFonts.poppins(color: Colors.white70)),
        ],
      ),
    ),
  );

  await MediaService.instance.unlockPhotos(photos);

  if (context.mounted) {
    Navigator.pop(context); // cierra progreso
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1E1E1E),
        content: Row(
          children: [
            const Icon(Icons.check_circle,
                color: Colors.green, size: 18),
            const SizedBox(width: 8),
            Text(
              count == 1
                  ? 'Foto restaurada en galería'
                  : '$count fotos restauradas en galería',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ],
        ),
      ),
    );
    onDone?.call();
  }
}