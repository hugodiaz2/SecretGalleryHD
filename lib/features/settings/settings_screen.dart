import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/db_helper.dart';
import '../../core/security/pin_service.dart';
import '../../core/services/prefs_service.dart';
import 'package:flutter_windowmanager/flutter_windowmanager.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../trash/trash_screen.dart';

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

  // Stats
  int _totalPhotos = 0;
  int _totalVideos = 0;
  int _trashCount = 0;

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
      _totalPhotos = photos;
      _totalVideos = videos;
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
        await PrefsService.instance.saveIntruderSelfie(value);
        setState(() => _intruderSelfie = value);
        break;
      case 'preventScreenshot':
  await PrefsService.instance.savePreventScreenshot(value);
  if (value) {
    await FlutterWindowManager.addFlags(
        FlutterWindowManager.FLAG_SECURE);
  } else {
    await FlutterWindowManager.clearFlags(
        FlutterWindowManager.FLAG_SECURE);
  }
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
        await PrefsService.instance.saveDarkMode(value);
        setState(() => _darkMode = value);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0F0F),
        body: Center(
            child: CircularProgressIndicator(color: Colors.blue)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F0F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Configuración',
            style: GoogleFonts.poppins(
                color: Colors.white,
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
            trailing: const Icon(Icons.chevron_right,
                color: Colors.white38),
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
          _buildTile(
            icon: Icons.lock_outline,
            iconColor: Colors.blue,
            title: 'Cambiar PIN',
            subtitle: 'Modifica tu PIN de acceso',
            trailing: const Icon(Icons.chevron_right,
                color: Colors.white38),
            onTap: _showChangePinDialog,
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
            subtitle: 'Toma foto al ingresar PIN incorrecto',
            value: _intruderSelfie,
            onChanged: (v) => _toggle('intruderSelfie', v),
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
            trailing: const Icon(Icons.chevron_right,
                color: Colors.white38),
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
                    backgroundColor: const Color(0xFF1E1E1E),
                    title: Text('¿Sin papelera?',
                        style:
                            GoogleFonts.poppins(color: Colors.white)),
                    content: Text(
                      'Los archivos eliminados no podrán recuperarse.',
                      style: GoogleFonts.poppins(
                          color: Colors.white70),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text('Cancelar',
                            style: GoogleFonts.poppins(
                                color: Colors.white38)),
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
            child: Text('Private Gallery HD v1.0.0',
                style: GoogleFonts.poppins(
                    color: Colors.white12, fontSize: 11)),
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
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF7C4DFF)],
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
                  color: Colors.white70, fontSize: 12)),
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
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(height: 4),
        Text(value,
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
        Text(label,
            style: GoogleFonts.poppins(
                color: Colors.white70, fontSize: 11)),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title.toUpperCase(),
          style: GoogleFonts.poppins(
              color: Colors.white38,
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
      tileColor: const Color(0xFF1A1A1A),
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
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: GoogleFonts.poppins(
              color: Colors.white38, fontSize: 11)),
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
      tileColor: const Color(0xFF1A1A1A),
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
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: GoogleFonts.poppins(
              color: Colors.white38, fontSize: 11)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF1565C0),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF1565C0).withOpacity(0.3);
          }
          return Colors.white12;
        }),
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
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text('Cambiar PIN',
              style: GoogleFonts.poppins(color: Colors.white)),
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
                      GoogleFonts.poppins(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0)),
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
                      backgroundColor: const Color(0xFF1E1E1E),
                      content: Row(children: [
                        const Icon(Icons.check_circle,
                            color: Colors.green, size: 18),
                        const SizedBox(width: 8),
                        Text('PIN actualizado',
                            style: GoogleFonts.poppins(
                                color: Colors.white)),
                      ]),
                    ),
                  );
                }
              },
              child: Text('Guardar',
                  style: GoogleFonts.poppins(color: Colors.white)),
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
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38),
        counterStyle: const TextStyle(color: Colors.white24),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF3D3D3D)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: Color(0xFF1565C0)),
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
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Paleta de colores',
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: colors
                  .map((color) => GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white24, width: 2),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}