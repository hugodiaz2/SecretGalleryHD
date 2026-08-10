import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/lifecycle_guard.dart';
import '../../core/theme/app_colors.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  String _status = '';

  // ── Exportar ──────────────────────────────────────────────
  Future<void> _startExport() async {
    final password = await _askBackupPassword(confirm: true);
    if (password == null || !mounted) return;

    setState(() {
      _busy = true;
      _status = 'Preparando respaldo...';
    });

    try {
      final file = await BackupService.instance.exportBackup(
        password: password,
        onProgress: (s) {
          if (mounted) setState(() => _status = s);
        },
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await LifecycleGuard.run(() => Share.shareXFiles(
          [XFile(file.path)],
          text: 'Respaldo de Secret Gallery HD'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showError('No se pudo crear el respaldo: $e');
    }
  }

  // ── Restaurar ─────────────────────────────────────────────
  Future<void> _startRestore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).extension<AppColors>()!.surface,
        title: Text('¿Restaurar respaldo?',
            style: GoogleFonts.poppins(color: context.colors.textPrimary)),
        content: Text(
          'Esto reemplazará TODA tu bóveda actual (fotos, carpetas, PIN y '
          'contraseña) con el contenido del respaldo. No se puede deshacer.',
          style: GoogleFonts.poppins(color: context.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: GoogleFonts.poppins(color: context.colors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Continuar',
                style: GoogleFonts.poppins(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final result = await LifecycleGuard.run(
        () => FilePicker.platform.pickFiles(type: FileType.any));
    final path = result?.files.single.path;
    if (path == null || !mounted) return;

    final password = await _askBackupPassword(confirm: false);
    if (password == null || !mounted) return;

    setState(() {
      _busy = true;
      _status = 'Preparando restauración...';
    });

    try {
      await BackupService.instance.restoreBackup(
        backupFile: File(path),
        password: password,
        onProgress: (s) {
          if (mounted) setState(() => _status = s);
        },
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await _showRestoreDoneDialog();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showError('No se pudo restaurar: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  Future<void> _showRestoreDoneDialog() {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).extension<AppColors>()!.surface,
        title: Text('Restauración completa',
            style: GoogleFonts.poppins(color: context.colors.textPrimary)),
        content: Text(
          'Tu bóveda fue restaurada. La app necesita reiniciarse para '
          'aplicar los cambios.',
          style: GoogleFonts.poppins(color: context.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => exit(0),
            child: Text('Reiniciar ahora',
                style: GoogleFonts.poppins(
                    color: Theme.of(context).colorScheme.primary)),
          ),
        ],
      ),
    );
  }

  Future<String?> _askBackupPassword({required bool confirm}) async {
    final ctrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? error;

    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(context).extension<AppColors>()!.surface,
          title: Text(
              confirm ? 'Crea una contraseña de respaldo' : 'Contraseña del respaldo',
              style: GoogleFonts.poppins(color: context.colors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                confirm
                    ? 'Protege el archivo de respaldo. La vas a necesitar para restaurarlo, no la olvides.'
                    : 'Ingresa la contraseña que usaste al crear este respaldo.',
                style: GoogleFonts.poppins(
                    color: context.colors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(error!,
                      style: GoogleFonts.poppins(
                          color: Colors.redAccent, fontSize: 12)),
                ),
              TextField(
                controller: ctrl,
                obscureText: true,
                autofocus: true,
                style: TextStyle(color: context.colors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  labelStyle: TextStyle(color: context.colors.textMuted),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF3D3D3D)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        BorderSide(color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ),
              if (confirm) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: confirmCtrl,
                  obscureText: true,
                  style: TextStyle(color: context.colors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Confirmar contraseña',
                    labelStyle: TextStyle(color: context.colors.textMuted),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF3D3D3D)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancelar',
                  style: GoogleFonts.poppins(color: context.colors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary),
              onPressed: () {
                if (ctrl.text.length < 4) {
                  setDialogState(() => error = 'Mínimo 4 caracteres');
                  return;
                }
                if (confirm && ctrl.text != confirmCtrl.text) {
                  setDialogState(() => error = 'Las contraseñas no coinciden');
                  return;
                }
                Navigator.pop(ctx, ctrl.text);
              },
              child: Text('Continuar',
                  style: GoogleFonts.poppins(color: context.colors.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Theme.of(context).extension<AppColors>()!.surface,
        content: Row(children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: GoogleFonts.poppins(color: context.colors.textPrimary)),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return Scaffold(
        backgroundColor: context.colors.bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 20),
                Text(_status,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        color: context.colors.textSecondary, fontSize: 13)),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.colors.bg,
      appBar: AppBar(
        backgroundColor: context.colors.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Respaldo',
            style: GoogleFonts.poppins(
                color: context.colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    color: Theme.of(context).colorScheme.primary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tus fotos solo existen en este teléfono. Si lo pierdes, se '
                    'daña o desinstalas la app, se pierden para siempre. '
                    'Haz un respaldo periódicamente.',
                    style: GoogleFonts.poppins(
                        color: context.colors.textSecondary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _actionTile(
            icon: Icons.upload_outlined,
            iconColor: Colors.blue,
            title: 'Exportar respaldo',
            subtitle: 'Empaqueta todo en un archivo para guardar donde quieras',
            onTap: _startExport,
          ),
          const SizedBox(height: 10),
          _actionTile(
            icon: Icons.download_outlined,
            iconColor: Colors.orange,
            title: 'Restaurar respaldo',
            subtitle: 'Reemplaza tu bóveda actual con un archivo de respaldo',
            onTap: _startRestore,
          ),
        ],
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      tileColor: context.colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(title,
          style: GoogleFonts.poppins(
              color: context.colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: GoogleFonts.poppins(color: context.colors.textMuted, fontSize: 11)),
      trailing: Icon(Icons.chevron_right, color: context.colors.textMuted),
    );
  }
}
