import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/security/pin_service.dart';
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
      title: 'Secret Gallery',
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

class _AppEntryState extends State<AppEntry> {
  final _pinService = PinService();
  bool _loading = true;
  bool _hasPin = false;

  @override
  void initState() {
    super.initState();
    _check();
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
        body: Center(child: CircularProgressIndicator()),
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