import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'core/security/pin_service.dart';
import 'core/security/crypto_service.dart';
import 'core/services/media_service.dart';
import 'core/services/backup_service.dart';
import 'core/services/prefs_service.dart';
import 'core/services/theme_service.dart';
import 'core/services/security_channel.dart';
import 'core/services/lifecycle_guard.dart';
import 'features/lock/pin_screen.dart';
import 'features/lock/password_screen.dart';
import 'features/lock/fingerprint_screen.dart';
import 'features/lock/access_method_screen.dart';
import 'features/albums/albums_screen.dart';
import 'features/camouflage/calculator_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  try {
    await ThemeService.instance.load();
  } catch (_) {
    // Render the access error screen even when secure preferences cannot be read.
  }
  runApp(const SecretGalleryApp());
}

class SecretGalleryApp extends StatelessWidget {
  const SecretGalleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeService.instance,
      builder: (context, _) => MaterialApp(
        title: 'Secret Gallery HD',
        debugShowCheckedModeBanner: false,
        theme: ThemeService.instance.themeData,
        // Keep every route and modal above the system navigation area.
        // SafeArea consumes these insets so nested SafeAreas do not double them.
        builder: (context, child) => ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: SafeArea(
            top:
                false, // AppBars and screen-level SafeAreas handle the status bar.
            child: ValueListenableBuilder<bool>(
              valueListenable: BackupService.busy,
              builder: (context, busy, _) => Stack(children: [
                child ?? const SizedBox.shrink(),
                if (busy)
                  const Positioned.fill(
                      child: Material(
                    color: Color(0xFF121212),
                    child: Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Procesando respaldo...',
                          style: TextStyle(color: Colors.white)),
                    ])),
                  )),
              ]),
            ),
          ),
        ),
        home: const AppEntry(),
      ),
    );
  }
}

class AppEntry extends StatefulWidget {
  const AppEntry({super.key});

  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> with WidgetsBindingObserver {
  final _pinService = PinService();
  bool _loading = true;
  bool _startupFailed = false;
  bool _hasPin = false;
  bool _camouflageMode = false;
  bool _unlocked = false;
  bool _choosingMethod = false;
  AuthMethod _authMethod = AuthMethod.pin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
    _applySettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── Cerrar al minimizar / re-bloqueo al volver ───────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state != AppLifecycleState.paused ||
        LifecycleGuard.isSuppressed ||
        !mounted) return;
    // Close every private route immediately, before any asynchronous preference read.
    if (_unlocked || _choosingMethod) {
      setState(() {
        _unlocked = false;
        _choosingMethod = false;
      });
      Navigator.of(context).popUntil((route) => route.isFirst);
      MediaService.instance.clearThumbnailCaches();
    }
    try {
      final method = await PrefsService.instance.getAuthMethod();
      final camouflage = await PrefsService.instance.getCamouflageMode();
      if (mounted)
        setState(() {
          _authMethod = method;
          _camouflageMode = camouflage;
        });
      if (await PrefsService.instance.getCloseOnMinimize()) exit(0);
    } catch (_) {
      // Failure to read an optional preference must never bypass the lock.
    }
  }

  Future<void> _applySettings() async {
    try {
      // Evitar capturas — FLAG_SECURE nativo (bloquea screenshots/grabación)
      final preventScreenshot =
          await PrefsService.instance.getPreventScreenshot();
      await SecurityChannel.setSecure(preventScreenshot);

      // Pantalla encendida
      final keepOn = await PrefsService.instance.getKeepScreenOn();
      if (keepOn) await WakelockPlus.enable();

      // Maximizar brillo
      final maxBrightness = await PrefsService.instance.getMaxBrightness();
      if (maxBrightness) {
        await ScreenBrightness().setScreenBrightness(1.0);
      }
    } catch (e) {
      debugPrint('Error aplicando settings: $e');
    }
  }

  Future<void> _check() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _startupFailed = false;
    });
    try {
      await BackupService.instance.recoverInterruptedRestore();
      final has = await _pinService.hasPin();
      if (!has && await CryptoService.hasProtectedFiles()) {
        throw StateError('Missing access credentials for an existing vault');
      }
      final camouflage = has && await PrefsService.instance.getCamouflageMode();
      final authMethod = await PrefsService.instance.getAuthMethod();
      if (!mounted) return;
      setState(() {
        _hasPin = has;
        _camouflageMode = camouflage;
        _authMethod = authMethod;
        _loading = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _startupFailed = true;
          _loading = false;
        });
    }
  }

  // No navega con el Navigator a propósito: si se reemplaza la ruta de
  // AppEntry (pushReplacement) esta State se destruye, y con ella mueren
  // el listener de "agitar para cerrar" y el observer de "cerrar al
  // minimizar" — quedaban vivos solo mientras se veía la pantalla de
  // bloqueo. Con setState, AppEntry sigue montado toda la sesión.
  Future<void> _goToGallery() async {
    if (BackupService.busy.value) return;
    final method = await PrefsService.instance.getAuthMethod();
    if (!mounted ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused)
      return;
    setState(() {
      _authMethod = method;
      _choosingMethod = false;
      _unlocked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A14),
        body: Center(
          child: CircularProgressIndicator(color: Colors.blue),
        ),
      );
    }

    if (_startupFailed) {
      return Scaffold(
          body: SafeArea(
              child: Center(
                  child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_outline, size: 40),
          const SizedBox(height: 16),
          const Text(
              'No se pudo leer el acceso seguro. Tus archivos no se han borrado. No desinstales la app ni borres sus datos.',
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: _check, child: const Text('Reintentar')),
        ]),
      ))));
    }
    final Widget child;
    if (_unlocked || _choosingMethod) {
      child = const AlbumsScreen();
    } else if (_camouflageMode) {
      child = CalculatorScreen(onUnlocked: _goToGallery);
    } else if (!_hasPin && !_choosingMethod) {
      // Primera vez: el PIN siempre se crea primero (queda como respaldo
      // de emergencia), y luego se ofrece elegir el método preferido.
      child = PinScreen(
        mode: PinMode.setup,
        onSuccess: () => setState(() {
          _hasPin = true;
          _choosingMethod = true;
        }),
      );
    } else if (_choosingMethod) {
      child = AccessMethodScreen(
        mode: AccessMethodScreenMode.onboarding,
        onDone: _goToGallery,
      );
    } else {
      child = switch (_authMethod) {
        AuthMethod.password =>
          PasswordScreen(mode: PasswordMode.unlock, onSuccess: _goToGallery),
        AuthMethod.fingerprint => FingerprintScreen(onSuccess: _goToGallery),
        AuthMethod.pin =>
          PinScreen(mode: PinMode.unlock, onSuccess: _goToGallery),
      };
    }

    return AnimatedSwitcher(
      duration: _unlocked ? const Duration(milliseconds: 350) : Duration.zero,
      child: KeyedSubtree(
        key: ValueKey(_unlocked ? 'gallery' : 'lock'),
        child: child,
      ),
    );
  }
}
