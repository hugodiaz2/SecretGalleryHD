import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'core/security/pin_service.dart';
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
  await ThemeService.instance.load();
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
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      if (LifecycleGuard.isSuppressed) {
        // La propia app abrió algo externo a propósito (compartir,
        // elegir un archivo de respaldo, etc.): no es el usuario saliendo.
        return;
      }

      final closeOnMinimize =
          await PrefsService.instance.getCloseOnMinimize();
      if (closeOnMinimize) {
        // SystemNavigator.pop() no siempre mata el proceso de forma
        // confiable una vez la app ya está en segundo plano; exit(0) sí
        // lo garantiza.
        exit(0);
      }

      // Se pide el método de acceso de nuevo siempre que la app vuelva
      // del segundo plano, sin importar el switch de arriba: minimizar
      // (o mandar la app a compartir, etc.) no debe dejar la sesión
      // abierta para quien retome el teléfono después.
      if (_unlocked) setState(() => _unlocked = false);
    }
  }

  // ── Aplicar settings al iniciar ──────────────────────────
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
      final maxBrightness =
          await PrefsService.instance.getMaxBrightness();
      if (maxBrightness) {
        await ScreenBrightness().setScreenBrightness(1.0);
      }
    } catch (e) {
      debugPrint('Error aplicando settings: $e');
    }
  }

  Future<void> _check() async {
    // Sin try/catch acá, una excepción al leer el almacenamiento seguro
    // (p. ej. clave de Keystore invalidada) dejaba _loading en true para
    // siempre: la app parecía cargar sin fin. Si algo falla, se asume
    // "sin PIN todavía" y se manda a configuración inicial.
    try {
      final has = await _pinService.hasPin();
      final camouflage =
          has && await PrefsService.instance.getCamouflageMode();
      final authMethod = await PrefsService.instance.getAuthMethod();
      setState(() {
        _hasPin = has;
        _camouflageMode = camouflage;
        _authMethod = authMethod;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error verificando estado de acceso: $e');
      if (mounted) {
        setState(() {
          _hasPin = false;
          _camouflageMode = false;
          _authMethod = AuthMethod.pin;
          _loading = false;
        });
      }
    }
  }

  // No navega con el Navigator a propósito: si se reemplaza la ruta de
  // AppEntry (pushReplacement) esta State se destruye, y con ella mueren
  // el listener de "agitar para cerrar" y el observer de "cerrar al
  // minimizar" — quedaban vivos solo mientras se veía la pantalla de
  // bloqueo. Con setState, AppEntry sigue montado toda la sesión.
  void _goToGallery() {
    if (mounted) setState(() => _unlocked = true);
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

    final Widget child;
    if (_unlocked) {
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
        AuthMethod.fingerprint =>
          FingerprintScreen(onSuccess: _goToGallery),
        AuthMethod.pin =>
          PinScreen(mode: PinMode.unlock, onSuccess: _goToGallery),
      };
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: KeyedSubtree(
        key: ValueKey(_unlocked ? 'gallery' : 'lock'),
        child: child,
      ),
    );
  }
}