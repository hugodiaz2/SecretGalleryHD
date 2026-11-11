import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/media_service.dart';
import '../../core/database/db_helper.dart';

bool _unlockDialogOpen = false;

/// Pregunta si restaurar en la galería y qué hacer con el archivo privado:
/// eliminarlo de la bóveda o dejarlo ahí. Devuelve true solo si los archivos
/// restaurados salieron de la bóveda (así el visor sabe que ya no existen).
Future<bool> confirmUnlock(
    BuildContext context, List<Map<String, dynamic>> photos,
    {VoidCallback? onDone, bool preserveFolders = false}) async {
  if (_unlockDialogOpen) return false;
  _unlockDialogOpen = true;
  try {
    final count = photos.length;

    // true = eliminar de la bóveda, false = que se quede, null = cancelar.
    final removeFromVault = await showDialog<bool>(
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
            Text(
              count == 1
                  ? '¿Quieres eliminarlo de la bóveda o que se quede?'
                  : '¿Quieres eliminarlos de la bóveda o que se queden?',
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
            if (preserveFolders) ...[
              const SizedBox(height: 12),
              Text(
                'Se conservarán la carpeta y todas sus subcarpetas. Si eliges eliminar, solo los archivos desbloqueados saldrán de la bóveda; si alguno no puede desbloquearse, permanecerá en su carpeta.',
                style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
              ),
            ],
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
                      'La copia restaurada dejará de estar protegida y será visible en la galería.',
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
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar',
                style: GoogleFonts.poppins(color: Colors.white38)),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.blue),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.lock_outline, color: Colors.blue, size: 16),
            label: Text('Que se quede',
                style: GoogleFonts.poppins(
                    color: Colors.blue, fontWeight: FontWeight.w600)),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.delete_outline, color: Colors.white, size: 16),
            label: Text('Eliminar',
                style: GoogleFonts.poppins(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (removeFromVault == null || !context.mounted) return false;
    final keepInVault = !removeFromVault;

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
      final result = await MediaService.instance
          .unlockPhotos(photos, keepInVault: keepInVault);
      changed = result.completed.isNotEmpty;
      if (result.failed.isNotEmpty) {
        message =
            'No se pudieron restaurar algunos archivos. Se conservan en privado.';
      } else if (result.cleanupWarnings.isNotEmpty) {
        message = 'No se pudieron limpiar algunos archivos temporales.';
      }
    } catch (e) {
      message = 'No se pudo restaurar: $e. Se conservan los archivos privados.';
    } finally {
      if (progress.isActive) navigator.removeRoute(progress);
    }
    if (!context.mounted) return changed && !keepInVault;
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } else if (changed && keepInVault) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Restaurado en la galería. Se conserva en la bóveda.')));
    }
    if (changed) onDone?.call();
    return changed && !keepInVault;
  } finally {
    _unlockDialogOpen = false;
  }
}

Future<void> confirmUnlockFolders(BuildContext context, Iterable<int> folderIds,
    {VoidCallback? onDone}) async {
  try {
    final photos =
        await DBHelper.instance.getPhotosInFolders(folderIds.toList());
    if (!context.mounted) return;
    if (photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Estas carpetas no contienen archivos.')));
      return;
    }
    await confirmUnlock(context, photos, onDone: onDone, preserveFolders: true);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo leer el contenido de las carpetas.')));
    }
  }
}
