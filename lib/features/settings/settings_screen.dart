import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/db_helper.dart';
import '../../core/security/pin_service.dart';
import '../../core/security/password_service.dart';
import '../../core/security/biometric_service.dart';
import '../../core/services/prefs_service.dart';
import '../../core/services/theme_service.dart';
import '../../core/services/security_channel.dart';
import '../../core/theme/app_colors.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../trash/trash_screen.dart';
import '../intruders/intruder_screen.dart';
import '../lock/password_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;

  // Toggles
  bool _closeOnMinimize = false;
  bool _shakeToClose = false;
  bool _intruderSelfie = false;
  bool _preventScreenshot = true;
  bool _keepScreenOn = false;
  bool _maximizeBrightness = false;
  bool _maximizeImages = false;
  bool _noTrash = false;
  bool _darkMode = true;
  bool _camouflageMode = false;
  AuthMethod _authMethod = AuthMethod.pin;
  bool _hasPassword = false;

  // Stats
  int _totalPhotos = 0;
  int _totalVideos = 0;
  int _trashCount = 0;
  int _intruderCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final prefs = await PrefsService.instance.loadAll();
    final db = DBHelper.instance;

    // Stats reales
    final allPhotos = await db.getAllPhotos();
    final trash = await db.getTrashCount();
    final intruders = await db.getIntruderCount();
    final authMethod = await PrefsService.instance.getAuthMethod();
    final hasPassword = await PasswordService().hasPassword();
    int photos = 0;
    int videos = 0;
    for (final p in allPhotos) {
      final name = (p['original_name'] ?? '') as String;
      final ext = name.split('.').last.toLowerCase();
      if (['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'].contains(ext)) {
        videos++;
      } else {
        photos++;
      }
    }

    setState(() {
      _closeOnMinimize = prefs['closeOnMinimize'] as bool;
      _shakeToClose = prefs['shakeToClose'] as bool;
      _intruderSelfie = prefs['intruderSelfie'] as bool;
      _preventScreenshot = prefs['preventScreenshot'] as bool;
      _keepScreenOn = prefs['keepScreenOn'] as bool;
      _maximizeBrightness = prefs['maxBrightness'] as bool;
      _maximizeImages = prefs['maximizeImages'] as bool;
      _noTrash = prefs['noTrash'] as bool;
      _darkMode = prefs['darkMode'] as bool;
      _camouflageMode = prefs['camouflageMode'] as bool;
      _authMethod = authMethod;
      _hasPassword = hasPassword;
      _totalPhotos = photos;
      _totalVideos = videos;
      _intruderCount = intruders;
      _trashCount = trash;
      _loading = false;
    });
  }

  Future<void> _toggle(String key, bool value) async {
    switch (key) {
      case 'closeOnMinimize':
        await PrefsService.instance.saveCloseOnMinimize(value);
        setState(() => _closeOnMinimize = value);
        break;
      case 'shakeToClose':
        await PrefsService.instance.saveShakeToClose(value);
        setState(() => _shakeToClose = value);
        break;
      case 'intruderSelfie':
        if (value) {
          final status = await Permission.camera.request();
          if (!status.isGranted) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: Theme.of(context)
                      .extension<AppColors>()!
                      .surface,
                  content: Text(
                    'Se necesita permiso de cámara para esta función',
                    style: GoogleFonts.poppins(color: context.colors.textPrimary),
                  ),
                ),
              );
            }
            return;
          }
        }
        await PrefsService.instance.saveIntruderSelfie(value);
        setState(() => _intruderSelfie = value);
        break;
      case 'preventScreenshot':
  await PrefsService.instance.savePreventScreenshot(value);
  await SecurityChannel.setSecure(value);
  setState(() => _preventScreenshot = value);
  break;
      case 'keepScreenOn':
  await PrefsService.instance.saveKeepScreenOn(value);
  if (value) {
    await WakelockPlus.enable();
  } else {
    await WakelockPlus.disable();
  }
  setState(() => _keepScreenOn = value);
  break;
      case 'maxBrightness':
  await PrefsService.instance.saveMaxBrightness(value);
  if (value) {
    await ScreenBrightness().setScreenBrightness(1.0);
  } else {
    await ScreenBrightness().resetScreenBrightness();
  }
  setState(() => _maximizeBrightness = value);
  break;
      case 'maximizeImages':
        await PrefsService.instance.saveMaximizeImages(value);
        setState(() => _maximizeImages = value);
        break;
      case 'noTrash':
        await PrefsService.instance.saveNoTrash(value);
        setState(() => _noTrash = value);
        break;
      case 'darkMode':
        await ThemeService.instance.setDarkMode(value);
        setState(() => _darkMode = value);
        break;
      case 'camouflageMode':
        await PrefsService.instance.saveCamouflageMode(value);
        setState(() => _camouflageMode = value);
        break;
    }
  }

  // ── Método de acceso ────────────────────────────────────
  Future<void> _switchToPin() async {
    if (_authMethod == AuthMethod.pin) return;
    await PrefsService.instance.saveAuthMethod(AuthMethod.pin);
    if (mounted) setState(() => _authMethod = AuthMethod.pin);
  }

  Future<void> _switchToPassword() async {
    if (_authMethod == AuthMethod.password) return;

    if (!_hasPassword) {
      final created = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (routeContext) => PasswordScreen(
            mode: PasswordMode.setup,
            onSuccess: () => Navigator.of(routeContext).pop(true),
          ),
        ),
      );
      if (created != true) return;
      if (mounted) setState(() => _hasPassword = true);
    }

    await PrefsService.instance.saveAuthMethod(AuthMethod.password);
    if (mounted) setState(() => _authMethod = AuthMethod.password);
  }

  Future<void> _switchToFingerprint() async {
    if (_authMethod == AuthMethod.fingerprint) return;

    final available = await BiometricService.instance.isAvailable();
    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor:
                Theme.of(context).extension<AppColors>()!.surface,
            content: Text(
              'Tu dispositivo no tiene huella dactilar configurada',
              style: GoogleFonts.poppins(color: context.colors.textPrimary),
            ),
          ),
        );
      }
      return;
    }

    final confirmed = await BiometricService.instance.authenticate(
      reason: 'Confirma tu huella para activarla como método de acceso',
    );
    if (!confirmed) return;

    await PrefsService.instance.saveAuthMethod(AuthMethod.fingerprint);
    if (mounted) setState(() => _authMethod = AuthMethod.fingerprint);
  }

  void _showChangePasswordDialog() {
    final passwordService = PasswordService();
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(context).extension<AppColors>()!.surface,
          title: Text('Cambiar contraseña',
              style: GoogleFonts.poppins(color: context.colors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent, width: 1),
                  ),
                  child: Text(error!,
                      style: GoogleFonts.poppins(
                          color: Colors.redAccent, fontSize: 12)),
                ),
              _passwordDialogField('Contraseña actual', currentCtrl),
              const SizedBox(height: 12),
              _passwordDialogField('Nueva contraseña', newCtrl),
              const SizedBox(height: 12),
              _passwordDialogField('Confirmar contraseña', confirmCtrl),
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
              onPressed: () async {
                final current = currentCtrl.text;
                final newPw = newCtrl.text;
                final confirm = confirmCtrl.text;

                if (newPw.length < 4) {
                  setDialogState(
                      () => error = 'Mínimo 4 caracteres');
                  return;
                }
                final valid = await passwordService.validatePassword(current);
                if (!valid) {
                  setDialogState(
                      () => error = 'Contraseña actual incorrecta');
                  return;
                }
                if (newPw != confirm) {
                  setDialogState(
                      () => error = 'Las contraseñas nuevas no coinciden');
                  return;
                }
                await passwordService.savePassword(newPw);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor:
                          Theme.of(context).extension<AppColors>()!.surface,
                      content: Row(children: [
                        const Icon(Icons.check_circle,
                            color: Colors.green, size: 18),
                        const SizedBox(width: 8),
                        Text('Contraseña actualizada',
                            style: GoogleFonts.poppins(
                                color: context.colors.textPrimary)),
                      ]),
                    ),
                  );
                }
              },
              child: Text('Guardar',
                  style: GoogleFonts.poppins(color: context.colors.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _passwordDialogField(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      obscureText: true,
      style: TextStyle(color: context.colors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: context.colors.textMuted),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF3D3D3D)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: context.colors.bg,
        body: Center(
            child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
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
        title: Text('Configuración',
            style: GoogleFonts.poppins(
                color: context.colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        children: [
          // ── ESTADÍSTICAS ──────────────────────────────
          _buildStatsCard(),
          const SizedBox(height: 8),

          // ── PAPELERA ──────────────────────────────────
          _buildSectionHeader('Papelera'),
          _buildTile(
            icon: Icons.delete_outline,
            iconColor: Colors.redAccent,
            title: 'Papelera',
            subtitle: '$_trashCount archivos eliminados',
            trailing: Icon(Icons.chevron_right,
                color: context.colors.textMuted),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const TrashScreen()),
              );
              _loadAll(); // recargar stats al volver
            },
          ),
          const SizedBox(height: 8),

          // ── SEGURIDAD ─────────────────────────────────
          _buildSectionHeader('Seguridad'),
          _buildSectionHeader('Método de acceso'),
          _buildAuthMethodTile(
            icon: Icons.dialpad,
            title: 'PIN',
            subtitle: 'Código numérico de 4 dígitos',
            isSelected: _authMethod == AuthMethod.pin,
            onTap: _switchToPin,
          ),
          _buildAuthMethodTile(
            icon: Icons.password_outlined,
            title: 'Contraseña',
            subtitle: 'Texto alfanumérico',
            isSelected: _authMethod == AuthMethod.password,
            onTap: _switchToPassword,
          ),
          _buildAuthMethodTile(
            icon: Icons.fingerprint,
            title: 'Huella dactilar',
            subtitle: 'Usa la huella registrada en el teléfono',
            isSelected: _authMethod == AuthMethod.fingerprint,
            onTap: _switchToFingerprint,
          ),
          _buildTile(
            icon: Icons.lock_outline,
            iconColor: Colors.blue,
            title: 'Cambiar PIN',
            subtitle: 'Modifica tu PIN de acceso',
            trailing: Icon(Icons.chevron_right,
                color: context.colors.textMuted),
            onTap: _showChangePinDialog,
          ),
          if (_hasPassword)
            _buildTile(
              icon: Icons.password_outlined,
              iconColor: Colors.blue,
              title: 'Cambiar contraseña',
              subtitle: 'Modifica tu contraseña de acceso',
              trailing: Icon(Icons.chevron_right,
                  color: context.colors.textMuted),
              onTap: _showChangePasswordDialog,
            ),
          _buildSwitchTile(
            icon: Icons.minimize,
            iconColor: Colors.orange,
            title: 'Cerrar al minimizar',
            subtitle: 'Cierra la app al minimizarse',
            value: _closeOnMinimize,
            onChanged: (v) => _toggle('closeOnMinimize', v),
          ),
          _buildSwitchTile(
            icon: Icons.vibration,
            iconColor: Colors.purple,
            title: 'Agitar para cerrar',
            subtitle: 'Cierra la app al agitar el dispositivo',
            value: _shakeToClose,
            onChanged: (v) => _toggle('shakeToClose', v),
          ),
          _buildSwitchTile(
            icon: Icons.camera_front_outlined,
            iconColor: Colors.green,
            title: 'Selfie para intrusos',
            subtitle: 'Toma foto al ingresar PIN incorrecto 3 veces',
            value: _intruderSelfie,
            onChanged: (v) => _toggle('intruderSelfie', v),
          ),
          _buildTile(
            icon: Icons.photo_camera_back_outlined,
            iconColor: Colors.green,
            title: 'Selfies capturadas',
            subtitle: '$_intruderCount captura${_intruderCount == 1 ? '' : 's'}',
            trailing:
                Icon(Icons.chevron_right, color: context.colors.textMuted),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const IntruderScreen()),
              );
              _loadAll();
            },
          ),
          const SizedBox(height: 8),

          // ── CAMUFLAJE ─────────────────────────────────
          _buildSectionHeader('Camuflaje'),
          _buildSwitchTile(
            icon: Icons.calculate_outlined,
            iconColor: Colors.indigo,
            title: 'Modo camuflaje',
            subtitle: 'La app se abre como una calculadora',
            value: _camouflageMode,
            onChanged: (v) async {
              if (v) {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor:
                        Theme.of(context).extension<AppColors>()!.surface,
                    title: Text('¿Activar modo camuflaje?',
                        style: GoogleFonts.poppins(
                            color: context.colors.textPrimary)),
                    content: Text(
                      'La app se mostrará como una calculadora normal. '
                      'Para entrar a la galería, escribe tu PIN en la '
                      'calculadora como si fuera un número y presiona "=".',
                      style: GoogleFonts.poppins(
                          color: context.colors.textSecondary),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text('Cancelar',
                            style: GoogleFonts.poppins(
                                color: context.colors.textMuted)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text('Activar',
                            style: GoogleFonts.poppins(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) _toggle('camouflageMode', true);
              } else {
                _toggle('camouflageMode', false);
              }
            },
          ),
          const SizedBox(height: 8),

          // ── DISEÑO ────────────────────────────────────
          _buildSectionHeader('Diseño y estilo'),
          _buildSwitchTile(
            icon: Icons.dark_mode_outlined,
            iconColor: Colors.blueGrey,
            title: 'Modo oscuro',
            subtitle: 'Interfaz con fondo oscuro',
            value: _darkMode,
            onChanged: (v) => _toggle('darkMode', v),
          ),
          _buildTile(
            icon: Icons.palette_outlined,
            iconColor: Colors.pink,
            title: 'Paleta de colores',
            subtitle: 'Personaliza los colores de la app',
            trailing: Icon(Icons.chevron_right,
                color: context.colors.textMuted),
            onTap: _showColorPicker,
          ),
          const SizedBox(height: 8),

          // ── AJUSTES AVANZADOS ─────────────────────────
          _buildSectionHeader('Ajustes avanzados'),
          _buildSwitchTile(
            icon: Icons.security,
            iconColor: Colors.red,
            title: 'Evitar espionaje',
            subtitle: 'Bloquea capturas de pantalla',
            value: _preventScreenshot,
            onChanged: (v) => _toggle('preventScreenshot', v),
          ),
          _buildSwitchTile(
            icon: Icons.screen_lock_rotation,
            iconColor: Colors.teal,
            title: 'Mantener pantalla encendida',
            subtitle: 'No apaga la pantalla al ver fotos/videos',
            value: _keepScreenOn,
            onChanged: (v) => _toggle('keepScreenOn', v),
          ),
          _buildSwitchTile(
            icon: Icons.brightness_high_outlined,
            iconColor: Colors.amber,
            title: 'Maximizar brillo',
            subtitle: 'Brillo al máximo al abrir la app',
            value: _maximizeBrightness,
            onChanged: (v) => _toggle('maxBrightness', v),
          ),
          _buildSwitchTile(
            icon: Icons.fit_screen,
            iconColor: Colors.cyan,
            title: 'Maximizar visualización',
            subtitle:
                'Ajusta imágenes de baja resolución a pantalla completa',
            value: _maximizeImages,
            onChanged: (v) => _toggle('maximizeImages', v),
          ),
          _buildSwitchTile(
            icon: Icons.delete_forever_outlined,
            iconColor: Colors.deepOrange,
            title: 'Sin papelera',
            subtitle: 'Elimina archivos permanentemente sin papelera',
            value: _noTrash,
            onChanged: (v) async {
              if (v) {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: Theme.of(context).extension<AppColors>()!.surface,
                    title: Text('¿Sin papelera?',
                        style:
                            GoogleFonts.poppins(color: context.colors.textPrimary)),
                    content: Text(
                      'Los archivos eliminados no podrán recuperarse.',
                      style: GoogleFonts.poppins(
                          color: context.colors.textSecondary),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text('Cancelar',
                            style: GoogleFonts.poppins(
                                color: context.colors.textMuted)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text('Activar',
                            style: GoogleFonts.poppins(
                                color: Colors.deepOrange)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) _toggle('noTrash', v);
              } else {
                _toggle('noTrash', v);
              }
            },
          ),

          const SizedBox(height: 40),
          Center(
            child: Text('Secret Gallery HD v1.0.0',
                style: GoogleFonts.poppins(
                    color: context.colors.textGhost, fontSize: 11)),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Archivos protegidos',
              style: GoogleFonts.poppins(
                  color: context.colors.textSecondary, fontSize: 12)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _statItem(
                      Icons.photo_outlined, '$_totalPhotos', 'Fotos')),
              Expanded(
                  child: _statItem(Icons.videocam_outlined,
                      '$_totalVideos', 'Videos')),
              Expanded(
                  child: _statItem(Icons.delete_outline,
                      '$_trashCount', 'Papelera')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: context.colors.textPrimary, size: 24),
        const SizedBox(height: 4),
        Text(value,
            style: GoogleFonts.poppins(
                color: context.colors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
        Text(label,
            style: GoogleFonts.poppins(
                color: context.colors.textSecondary, fontSize: 11)),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title.toUpperCase(),
          style: GoogleFonts.poppins(
              color: context.colors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5)),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget trailing,
    required VoidCallback onTap,
  }) {
    return ListTile(
      tileColor: context.colors.surface,
      onTap: onTap,
      leading: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(title,
          style: GoogleFonts.poppins(
              color: context.colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: GoogleFonts.poppins(
              color: context.colors.textMuted, fontSize: 11)),
      trailing: trailing,
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required void Function(bool) onChanged,
  }) {
    return ListTile(
      tileColor: context.colors.surface,
      leading: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(title,
          style: GoogleFonts.poppins(
              color: context.colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: GoogleFonts.poppins(
              color: context.colors.textMuted, fontSize: 11)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: Theme.of(context).colorScheme.primary,
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Theme.of(context).colorScheme.primary.withOpacity(0.3);
          }
          return context.colors.textGhost;
        }),
      ),
    );
  }

  Widget _buildAuthMethodTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final accent = Theme.of(context).colorScheme.primary;
    return ListTile(
      tileColor: context.colors.surface,
      onTap: onTap,
      leading: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: isSelected ? accent.withOpacity(0.15) : context.colors.surfaceHigh,
          borderRadius: BorderRadius.circular(10),
          border: isSelected ? Border.all(color: accent, width: 1) : null,
        ),
        child: Icon(icon, color: isSelected ? accent : context.colors.textMuted, size: 20),
      ),
      title: Text(title,
          style: GoogleFonts.poppins(
              color: context.colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: GoogleFonts.poppins(
              color: context.colors.textMuted, fontSize: 11)),
      trailing: Icon(
        isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
        color: isSelected ? accent : context.colors.textFaint,
        size: 20,
      ),
    );
  }

  void _showChangePinDialog() {
    final pinService = PinService();
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(context).extension<AppColors>()!.surface,
          title: Text('Cambiar PIN',
              style: GoogleFonts.poppins(color: context.colors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.redAccent, width: 1),
                  ),
                  child: Text(error!,
                      style: GoogleFonts.poppins(
                          color: Colors.redAccent, fontSize: 12)),
                ),
              _pinField('PIN actual', currentCtrl),
              const SizedBox(height: 12),
              _pinField('Nuevo PIN', newCtrl),
              const SizedBox(height: 12),
              _pinField('Confirmar PIN', confirmCtrl),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancelar',
                  style:
                      GoogleFonts.poppins(color: context.colors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary),
              onPressed: () async {
                final current = currentCtrl.text.trim();
                final newPin = newCtrl.text.trim();
                final confirm = confirmCtrl.text.trim();

                if (current.length != 4 ||
                    newPin.length != 4 ||
                    confirm.length != 4) {
                  setDialogState(() =>
                      error = 'Todos los PINs deben tener 4 dígitos');
                  return;
                }
                final valid = await pinService.validatePin(current);
                if (!valid) {
                  setDialogState(
                      () => error = 'PIN actual incorrecto');
                  return;
                }
                if (newPin != confirm) {
                  setDialogState(
                      () => error = 'Los PINs nuevos no coinciden');
                  return;
                }
                await pinService.savePin(newPin);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: Theme.of(context).extension<AppColors>()!.surface,
                      content: Row(children: [
                        const Icon(Icons.check_circle,
                            color: Colors.green, size: 18),
                        const SizedBox(width: 8),
                        Text('PIN actualizado',
                            style: GoogleFonts.poppins(
                                color: context.colors.textPrimary)),
                      ]),
                    ),
                  );
                }
              },
              child: Text('Guardar',
                  style: GoogleFonts.poppins(color: context.colors.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pinField(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 4,
      style: TextStyle(color: context.colors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: context.colors.textMuted),
        counterStyle: TextStyle(color: context.colors.textFaint),
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
    );
  }

  void _showColorPicker() {
    final colors = [
      Colors.blue, Colors.purple, Colors.teal,
      Colors.green, Colors.orange, Colors.red,
      Colors.pink, Colors.indigo,
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final selected = ThemeService.instance.accentColor;
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Paleta de colores',
                    style: GoogleFonts.poppins(
                        color: context.colors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Se aplica a toda la app al instante',
                    style: GoogleFonts.poppins(
                        color: context.colors.textMuted, fontSize: 11)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: colors.map((color) {
                    final isSelected =
                        color.toARGB32() == selected.toARGB32();
                    return GestureDetector(
                      onTap: () async {
                        await ThemeService.instance.setAccentColor(color);
                        setSheetState(() {});
                      },
                      child: Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: isSelected
                                  ? context.colors.textPrimary
                                  : context.colors.textFaint,
                              width: isSelected ? 3 : 2),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 20)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }
}