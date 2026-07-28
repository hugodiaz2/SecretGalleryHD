import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/security/pin_service.dart';
import '../../core/security/intruder_service.dart';
import '../../core/services/prefs_service.dart';
import '../../core/services/theme_service.dart';
import 'lock_header.dart';

enum PinMode { setup, unlock }

class PinScreen extends StatefulWidget {
  final PinMode mode;
  final VoidCallback onSuccess;

  const PinScreen({super.key, required this.mode, required this.onSuccess});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> with TickerProviderStateMixin {
  final _pinService = PinService();
  final List<String> _entered = [];
  final int _pinLength = 4;
  String _firstPin = '';
  String _subtitle = '';
  bool _isConfirming = false;
  bool _error = false;
  int _failedAttempts = 0;

  late final AnimationController _shakeController;
  late final AnimationController _dotController;

  late final Animation<double> _shakeAnimation;
  late final Animation<double> _dotScale;

  @override
  void initState() {
    super.initState();

    _subtitle = widget.mode == PinMode.setup
        ? 'Crea tu PIN de acceso'
        : 'Ingresa tu PIN';

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

    _dotController = AnimationController(
      duration: const Duration(milliseconds: 180),
      vsync: this,
    );
    _dotScale = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _dotController, curve: Curves.easeOut),
    );

  }

  @override
  void dispose() {
    _shakeController.dispose();
    _dotController.dispose();
    super.dispose();
  }

  void _onKey(String digit) {
    if (_entered.length >= _pinLength) return;
    HapticFeedback.lightImpact();
    setState(() => _entered.add(digit));
    _dotController.forward(from: 0).then((_) => _dotController.reverse());
    if (_entered.length == _pinLength) {
      Future.delayed(const Duration(milliseconds: 200), _onComplete);
    }
  }

  void _onDelete() {
    if (_entered.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _entered.removeLast());
  }

  void _triggerIntruderCapture() {
    PrefsService.instance.getIntruderSelfie().then((enabled) {
      if (enabled) IntruderService.instance.captureSilently();
    });
  }

  Future<void> _onComplete() async {
    final pin = _entered.join();

    if (widget.mode == PinMode.unlock) {
      final ok = await _pinService.validatePin(pin);
      if (ok) {
        _failedAttempts = 0;
        HapticFeedback.heavyImpact();
        if (mounted) widget.onSuccess();
      } else {
        HapticFeedback.heavyImpact();
        _failedAttempts++;
        if (_failedAttempts >= 3 && _failedAttempts % 3 == 0) {
          _triggerIntruderCapture();
        }
        if (!mounted) return;
        setState(() {
          _error = true;
          _entered.clear();
        });
        await _shakeController.forward(from: 0);
        if (!mounted) return;
        setState(() {
          _error = false;
          _subtitle = 'PIN incorrecto, intenta de nuevo';
        });
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _subtitle = 'Ingresa tu PIN');
      }
      return;
    }

    // Modo setup
    if (!_isConfirming) {
      _firstPin = pin;
      setState(() {
        _entered.clear();
        _isConfirming = true;
        _subtitle = 'Confirma tu PIN';
      });
    } else {
      if (pin == _firstPin) {
        await _pinService.savePin(pin);
        HapticFeedback.heavyImpact();
        if (mounted) widget.onSuccess();
      } else {
        HapticFeedback.heavyImpact();
        if (!mounted) return;
        setState(() {
          _error = true;
          _entered.clear();
        });
        await _shakeController.forward(from: 0);
        if (!mounted) return;
        setState(() {
          _error = false;
          _firstPin = '';
          _isConfirming = false;
          _subtitle = 'Los PINs no coinciden';
        });
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _subtitle = 'Crea tu PIN de acceso');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

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
              SizedBox(height: size.height * 0.05),

              // Header animado
              const LockHeader(),

              SizedBox(height: size.height * 0.05),

              // Dots con shake
              AnimatedBuilder(
                animation: _shakeAnimation,
                builder: (_, child) => Transform.translate(
                  offset: Offset(_error ? _shakeAnimation.value : 0, 0),
                  child: child,
                ),
                child: _buildDots(),
              ),

              const SizedBox(height: 14),

              // Subtítulo
              SizedBox(
                height: 20,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _subtitle,
                    key: ValueKey(_subtitle),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: _error
                          ? const Color(0xFFFF5252)
                          : Colors.white38,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // Teclado
              _buildKeypad(size),

              SizedBox(height: size.height * 0.02),

              // Botón volver
              SizedBox(
                height: 40,
                child: _isConfirming
                    ? TextButton(
                        onPressed: () => setState(() {
                          _entered.clear();
                          _firstPin = '';
                          _isConfirming = false;
                          _subtitle = 'Crea tu PIN de acceso';
                        }),
                        child: Text(
                          'Volver',
                          style: GoogleFonts.poppins(
                              color: Colors.white24, fontSize: 13),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              SizedBox(height: size.height * 0.02),
            ],
          ),
        ),
      ),
    );
  }


  // ── Dots ─────────────────────────────────────────────────
  Widget _buildDots() {
    return AnimatedBuilder(
      animation: _dotScale,
      builder: (_, __) {
        return SizedBox(
          height: 28,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(_pinLength, (i) {
              final filled = i < _entered.length;
              final isLast = filled && i == _entered.length - 1;
              final dotSize = isLast
                  ? (18.0 * _dotScale.value).clamp(14.0, 22.0)
                  : filled
                      ? 18.0
                      : 14.0;

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 14),
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _error
                      ? const Color(0xFFFF5252)
                      : filled
                          ? Colors.white
                          : Colors.transparent,
                  border: Border.all(
                    color: _error
                        ? const Color(0xFFFF5252)
                        : filled
                            ? Colors.white
                            : Colors.white24,
                    width: 1.5,
                  ),
                  boxShadow: filled && !_error
                      ? [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 1,
                          )
                        ]
                      : null,
                ),
              );
            }),
          ),
        );
      },
    );
  }

  // ── Keypad ───────────────────────────────────────────────
  Widget _buildKeypad(Size size) {
    final btnSize = (size.width - 80) / 3;
    final btnHeight = btnSize * 0.63;

    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'del'],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: rows.map((row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map((key) {
                if (key.isEmpty) {
                  return SizedBox(width: btnSize, height: btnHeight);
                }
                if (key == 'del') {
                  return _KeyBtn(
                    width: btnSize,
                    height: btnHeight,
                    onTap: _onDelete,
                    child: const Icon(
                      Icons.backspace_outlined,
                      color: Colors.white60,
                      size: 22,
                    ),
                  );
                }
                return _KeyBtn(
                  width: btnSize,
                  height: btnHeight,
                  onTap: () => _onKey(key),
                  child: Text(
                    key,
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.w400,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Botón del teclado ────────────────────────────────────────
class _KeyBtn extends StatefulWidget {
  final double width;
  final double height;
  final VoidCallback onTap;
  final Widget child;

  const _KeyBtn({
    required this.width,
    required this.height,
    required this.onTap,
    required this.child,
  });

  @override
  State<_KeyBtn> createState() => _KeyBtnState();
}

class _KeyBtnState extends State<_KeyBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Color _glowColor;

  @override
  void initState() {
    super.initState();
    _glowColor = ThemeService.instance.accentColor;
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 280),
      vsync: this,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.87).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) {
          final t = _ctrl.value;
          return Transform.scale(
            scale: _scale.value,
            child: Container(
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Color.lerp(Colors.white.withOpacity(0.05),
                    _glowColor.withOpacity(0.35), t),
                border: Border.all(
                  color: Color.lerp(Colors.white.withOpacity(0.08),
                      _glowColor, t)!,
                  width: 1 + t,
                ),
                boxShadow: t == 0
                    ? null
                    : [
                        BoxShadow(
                          color: _glowColor.withOpacity(0.5 * t),
                          blurRadius: 20 * t,
                          spreadRadius: 1.5 * t,
                        ),
                      ],
              ),
              child: child,
            ),
          );
        },
        child: Center(child: widget.child),
      ),
    );
  }
}