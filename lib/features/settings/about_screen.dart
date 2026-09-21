import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(title: const Text('Acerca de')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.border),
            ),
            child: Column(children: [
              Icon(Icons.shield_outlined, size: 48, color: accent),
              const SizedBox(height: 12),
              Text('Secret Gallery HD',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary)),
              const SizedBox(height: 8),
              Text('Un espacio privado para tus fotos y videos personales.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary, height: 1.5)),
            ]),
          ),
          const SizedBox(height: 20),
          _section(
              context,
              Icons.phone_android,
              'Tus archivos permanecen en tu dispositivo',
              'La bóveda guarda tus fotos y videos en el almacenamiento privado de la aplicación. '
                  'No publica ni sube automáticamente el contenido de la bóveda a nuestros servidores. '
                  'Tú decides cuándo compartir un archivo, desbloquearlo o exportar un respaldo.'),
          _section(
              context,
              Icons.lock_outline,
              'Cómo se protegen tus fotos',
              'Al ocultar un archivo, la aplicación crea una copia cifrada y comprueba su contenido '
                  'antes de solicitar la eliminación del original de la galería. '
                  'Si no autorizas esa eliminación o no se completa, el original puede seguir visible fuera de la bóveda. '
                  'Los archivos guardados en la papelera de la app también permanecen cifrados.'),
          _section(
              context,
              Icons.fingerprint,
              'Controla el acceso',
              'Configura un PIN, una contraseña o la huella digital disponible en tu dispositivo. '
                  'En Configuración también puedes activar Evitar espionaje para bloquear capturas de pantalla '
                  'en los dispositivos compatibles. El modo camuflaje cambia la apariencia de entrada a la app; '
                  'no sustituye la protección de acceso.'),
          _section(
              context,
              Icons.lock_open_outlined,
              'Qué ocurre al compartir o desbloquear',
              'Para mostrar o reproducir tus archivos, la aplicación los descifra durante su uso. '
                  'Al desbloquearlos, vuelven a la galería del teléfono y dejan de estar protegidos por la bóveda. '
                  'Al compartirlos, la aplicación que elijas recibe una copia. '
                  'Ocultar una foto no elimina otras copias que ya existan en servicios de nube, chats u otros dispositivos.'),
          _section(
              context,
              Icons.backup_outlined,
              'Respalda lo que quieres conservar',
              'Puedes crear un respaldo protegido con una contraseña y elegir dónde guardarlo. '
                  'Conserva esa contraseña y el respaldo en un lugar seguro. '
                  'Desinstalar la app, borrar sus datos o perder el teléfono puede hacer que pierdas el acceso '
                  'a tus archivos si no tienes un respaldo recuperable.'),
          _section(
              context,
              Icons.verified_user_outlined,
              'Privacidad con información clara',
              'Esta aplicación está pensada para proteger tu contenido personal. '
                  'Ninguna aplicación puede garantizar seguridad absoluta: la protección también depende '
                  'del bloqueo de tu teléfono, de mantenerlo actualizado y de con quién compartes el acceso o los archivos.'),
        ],
      ),
    );
  }

  Widget _section(
      BuildContext context, IconData icon, String title, String body) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
              child: Text(title,
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary))),
        ]),
        const SizedBox(height: 8),
        Text(body,
            style: TextStyle(
                fontSize: 13, height: 1.6, color: colors.textSecondary)),
      ]),
    );
  }
}
