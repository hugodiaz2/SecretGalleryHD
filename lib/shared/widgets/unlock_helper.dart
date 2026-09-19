import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/media_service.dart';

bool _unlockDialogOpen = false;

Future<void> confirmUnlock(
    BuildContext context, List<Map<String, dynamic>> photos,
    {VoidCallback? onDone}) async {
  if (_unlockDialogOpen) return;
  _unlockDialogOpen = true;
  try {
    final count = photos.length;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.blue, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Las fotos dejarán de estar protegidas y serán visibles en la galería.',
                      style:
                          GoogleFonts.poppins(color: Colors.blue, fontSize: 11),
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
            icon: const Icon(Icons.lock_open, color: Colors.white, size: 16),
            label: Text('Desbloquear',
                style: GoogleFonts.poppins(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    final progress = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
            content: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Restaurando y verificando archivos...'),
        ])),
      ),
    );
    navigator.push(progress);
    var changed = false;
    String? message;
    try {
      final result = await MediaService.instance.unlockPhotos(photos);
      changed = result.completed.isNotEmpty;
      if (result.failed.isNotEmpty) {
        message = 'No se pudieron restaurar algunos archivos. Se conservan en privado.';
      } else if (result.cleanupWarnings.isNotEmpty) {
        message = 'No se pudieron limpiar algunos archivos temporales.';
      }
    } catch (e) {
      message = 'No se pudo restaurar: $e. Se conservan los archivos privados.';
    } finally {
      if (progress.isActive) navigator.removeRoute(progress);
    }
    if (!context.mounted) return;
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
    if (changed) onDone?.call();
  } finally {
    _unlockDialogOpen = false;
  }
}
