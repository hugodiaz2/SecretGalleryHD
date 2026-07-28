import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/security/biometric_service.dart';
import '../../core/security/pin_service.dart';
import '../../core/services/theme_service.dart';
import 'lock_header.dart';
import 'pin_screen.dart';

/// Pantalla de desbloqueo por huella dactilar. No tiene "modo setup": la
/// huella ya está enrolada a nivel del sistema operativo, solo se pide
/// confirmarla. Si falla o no hay huella disponible, ofrece caer de
/// vuelta al PIN (si el usuario ya tiene uno guardado).
class FingerprintScreen extends StatefulWidget {
  final VoidCallback onSuccess;

  const FingerprintScreen({super.key, required this.onSuccess});

  @override
  State<FingerprintScreen> createState() => _FingerprintScreenState();
}

class _FingerprintScreenState extends State<FingerprintScreen>
    with SingleTickerProviderStateMixin {
  final _pinService = PinService();
  bool _authenticating = false;
  bool _hasPinFallback = false;
  String _subtitle = 'Toca el sensor para continuar';

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    )..repeat(reverse: true);
    _checkFallback();
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkFallback() async {
    final has = await _pinService.hasPin();
    if (mounted) setState(() => _hasPinFallback = has);
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _subtitle = 'Verificando...';
    });

    final available = await BiometricService.instance.isAvailable();
    if (!available) {
      if (mounted) {
        setState(() {
          _authenticating = false;
          _subtitle = 'Huella no disponible en este dispositivo';
        });
      }
      return;
    }

    final ok = await BiometricService.instance.authenticate();
    if (!mounted) return;
    if (ok) {
      HapticFeedback.heavyImpact();
      widget.onSuccess();
    } else {
      setState(() {
        _authenticating = false;
        _subtitle = 'No se pudo verificar, toca para reintentar';
      });
    }
  }

  void _useFallback() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PinScreen(
          mode: PinMode.unlock,
          onSuccess: widget.onSuccess,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final accent = ThemeService.instance.accentColor;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0A0A14),
              Color(0xFF0D0D1F),
              Color(0xFF080812),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              SizedBox(height: size.height * 0.08),
              const LockHeader(),
              const Spacer(),
              GestureDetector(
                onTap: _authenticate,
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (_, child) {
                    final v = _authenticating ? _pulseController.value : 0.0;
                    return Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withOpacity(0.08),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withOpacity(0.25 * v),
                            blurRadius: 30 * v,
                            spreadRadius: 6 * v,
                          ),
                        ],
                        border: Border.all(
                          color: accent.withOpacity(0.4),
                          width: 1.5,
                        ),
                      ),
                      child: child,
                    );
                  },
                  child: Icon(Icons.fingerprint, color: accent, size: 64),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 20,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _subtitle,
                    key: ValueKey(_subtitle),
                    style: GoogleFonts.poppins(
                        color: Colors.white38, fontSize: 12),
                  ),
                ),
              ),
              const Spacer(),
              if (_hasPinFallback)
                TextButton(
                  onPressed: _useFallback,
                  child: Text(
                    'Usar PIN en su lugar',
                    style: GoogleFonts.poppins(
                        color: Colors.white24, fontSize: 13),
                  ),
                ),
              SizedBox(height: size.height * 0.04),
            ],
          ),
        ),
      ),
    );
  }
}
