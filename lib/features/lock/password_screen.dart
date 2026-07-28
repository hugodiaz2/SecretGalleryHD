import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/security/password_service.dart';
import '../../core/security/intruder_service.dart';
import '../../core/services/prefs_service.dart';
import '../../core/services/theme_service.dart';
import 'lock_header.dart';

enum PasswordMode { setup, unlock }

class PasswordScreen extends StatefulWidget {
  final PasswordMode mode;
  final VoidCallback onSuccess;

  const PasswordScreen(
      {super.key, required this.mode, required this.onSuccess});

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen>
    with SingleTickerProviderStateMixin {
  final _passwordService = PasswordService();
  final _pwCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscure = true;
  bool _error = false;
  String? _errorText;
  int _failedAttempts = 0;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -12.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -12.0, end: 12.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 12.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: 0.0), weight: 1),
    ]).animate(_shakeController);
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _pwCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _triggerIntruderCapture() {
    PrefsService.instance.getIntruderSelfie().then((enabled) {
      if (enabled) IntruderService.instance.captureSilently();
    });
  }

  Future<void> _shakeError(String message) async {
    HapticFeedback.heavyImpact();
    setState(() {
      _error = true;
      _errorText = message;
    });
    await _shakeController.forward(from: 0);
    if (mounted) setState(() => _error = false);
  }

  Future<void> _submit() async {
    final password = _pwCtrl.text;
    if (password.isEmpty) return;

    if (widget.mode == PasswordMode.unlock) {
      final ok = await _passwordService.validatePassword(password);
      if (ok) {
        HapticFeedback.heavyImpact();
        if (mounted) widget.onSuccess();
      } else {
        _failedAttempts++;
        if (_failedAttempts >= 3 && _failedAttempts % 3 == 0) {
          _triggerIntruderCapture();
        }
        _pwCtrl.clear();
        await _shakeError('Contraseña incorrecta');
      }
      return;
    }

    // Modo setup
    if (password.length < 4) {
      await _shakeError('Mínimo 4 caracteres');
      return;
    }
    if (password != _confirmCtrl.text) {
      await _shakeError('Las contraseñas no coinciden');
      return;
    }
    await _passwordService.savePassword(password);
    HapticFeedback.heavyImpact();
    if (mounted) widget.onSuccess();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final accent = ThemeService.instance.accentColor;

    return Scaffold(
      resizeToAvoidBottomInset: true,
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
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: size.height - 40),
              child: Column(
                children: [
                  SizedBox(height: size.height * 0.06),
                  const LockHeader(),
                  SizedBox(height: size.height * 0.05),
                  Text(
                    widget.mode == PasswordMode.setup
                        ? 'Crea tu contraseña'
                        : 'Ingresa tu contraseña',
                    style: GoogleFonts.poppins(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 20),
                  AnimatedBuilder(
                    animation: _shakeAnimation,
                    builder: (_, child) => Transform.translate(
                      offset: Offset(_error ? _shakeAnimation.value : 0, 0),
                      child: child,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        children: [
                          _passwordField(
                            controller: _pwCtrl,
                            hint: 'Contraseña',
                            accent: accent,
                            autofocus: true,
                          ),
                          if (widget.mode == PasswordMode.setup) ...[
                            const SizedBox(height: 14),
                            _passwordField(
                              controller: _confirmCtrl,
                              hint: 'Confirmar contraseña',
                              accent: accent,
                              onSubmit: (_) => _submit(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 20,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _errorText != null
                          ? Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _errorText!,
                                key: ValueKey(_errorText),
                                style: GoogleFonts.poppins(
                                  color: const Color(0xFFFF5252),
                                  fontSize: 12,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(
                          widget.mode == PasswordMode.setup
                              ? 'Guardar'
                              : 'Entrar',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: size.height * 0.06),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String hint,
    required Color accent,
    bool autofocus = false,
    void Function(String)? onSubmit,
  }) {
    return TextField(
      controller: controller,
      obscureText: _obscure,
      autofocus: autofocus,
      style: GoogleFonts.poppins(color: Colors.white, fontSize: 15),
      onSubmitted: onSubmit ?? (_) => _submit(),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(color: Colors.white24, fontSize: 14),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: Colors.white38,
            size: 20,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}
