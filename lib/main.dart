import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_windowmanager/flutter_windowmanager.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'core/security/pin_service.dart';
import 'core/services/prefs_service.dart';
import 'features/lock/pin_screen.dart';
import 'features/albums/albums_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const SecretGalleryApp());
}

class SecretGalleryApp extends StatelessWidget {
  const SecretGalleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Private Gallery HD',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A1A2E),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
        useMaterial3: true,
      ),
      home: const AppEntry(),
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

  // ── Aplicar todos los settings al iniciar ────────────────
  Future<void> _applySettings() async {
    try {
      // Evitar capturas de pantalla
      final preventScreenshot =
          await PrefsService.instance.getPreventScreenshot();
      if (preventScreenshot) {
        await FlutterWindowManager.addFlags(
            FlutterWindowManager.FLAG_SECURE);
      }

      // Mantener pantalla encendida
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
    setState(() {
      _hasPin = has;
      _loading = false;
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
    return PinScreen(
      mode: _hasPin ? PinMode.unlock : PinMode.setup,
      onSuccess: () => Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AlbumsScreen()),
      ),
    );
  }
}