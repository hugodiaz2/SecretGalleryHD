import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'core/security/pin_service.dart';
import 'core/services/prefs_service.dart';
import 'core/services/theme_service.dart';
import 'core/services/security_channel.dart';
import 'features/lock/pin_screen.dart';
import 'features/lock/password_screen.dart';
import 'features/lock/fingerprint_screen.dart';
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
  AuthMethod _authMethod = AuthMethod.pin;
  StreamSubscription? _shakeSubscription;
  DateTime? _lastShake;

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
    _shakeSubscription?.cancel();
    super.dispose();
  }

  // ── Cerrar al minimizar ──────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      final closeOnMinimize =
          await PrefsService.instance.getCloseOnMinimize();
      if (closeOnMinimize) {
        SystemNavigator.pop();
      }
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

      // Agitar para cerrar
      await _initShakeDetector();
    } catch (e) {
      debugPrint('Error aplicando settings: $e');
    }
  }

  // ── Detector de agitación ────────────────────────────────
  Future<void> _initShakeDetector() async {
    final shakeToClose = await PrefsService.instance.getShakeToClose();
    if (!shakeToClose) return;

    _shakeSubscription =
        accelerometerEventStream().listen((AccelerometerEvent event) {
      final acceleration = sqrt(
          event.x * event.x + event.y * event.y + event.z * event.z);
      if (acceleration > 20) {
        final now = DateTime.now();
        if (_lastShake == null ||
            now.difference(_lastShake!) >
                const Duration(seconds: 2)) {
          _lastShake = now;
          SystemNavigator.pop();
        }
      }
    });
  }

  Future<void> _check() async {
    final has = await _pinService.hasPin();
    final camouflage = has && await PrefsService.instance.getCamouflageMode();
    final authMethod = await PrefsService.instance.getAuthMethod();
    setState(() {
      _hasPin = has;
      _camouflageMode = camouflage;
      _authMethod = authMethod;
      _loading = false;
    });
  }

  void _goToGallery() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AlbumsScreen()),
    );
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
    if (_camouflageMode) {
      return const CalculatorScreen();
    }

    // Sin PIN aún (primera vez): siempre pasa por la configuración de PIN.
    if (!_hasPin) {
      return PinScreen(mode: PinMode.setup, onSuccess: _goToGallery);
    }

    switch (_authMethod) {
      case AuthMethod.password:
        return PasswordScreen(
            mode: PasswordMode.unlock, onSuccess: _goToGallery);
      case AuthMethod.fingerprint:
        return FingerprintScreen(onSuccess: _goToGallery);
      case AuthMethod.pin:
        return PinScreen(mode: PinMode.unlock, onSuccess: _goToGallery);
    }
  }
}