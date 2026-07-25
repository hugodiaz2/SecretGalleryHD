import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/security/pin_service.dart';

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

  late final AnimationController _shakeController;
  late final AnimationController _dotController;
  late final AnimationController _titleController;

  late final Animation<double> _shakeAnimation;
  late final Animation<double> _dotScale;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;

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

    _titleController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _titleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _titleController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );
    _titleSlide = Tween<Offset>(
      begin: const Offset(0.0, -0.25),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _titleController,
        curve: Curves.easeOutCubic,
      ),
    );

    _titleController.forward();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _dotController.dispose();
    _titleController.dispose();
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

  Future<void> _onComplete() async {
    final pin = _entered.join();

    if (widget.mode == PinMode.unlock) {
      final ok = await _pinService.validatePin(pin);
      if (ok) {
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
              FadeTransition(
                opacity: _titleFade,
                child: SlideTransition(
                  position: _titleSlide,
                  child: _buildHeader(),
                ),
              ),

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

  // ── Header ────────────────────────────────────────────────
  Widget _buildHeader() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Ícono con glow
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 1200),
          builder: (_, v, child) {
            return Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF12122A),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3D5AFE).withOpacity(0.25 * v),
                    blurRadius: 30 * v,
                    spreadRadius: 4 * v,
                  ),
                  BoxShadow(
                    color: const Color(0xFF7C4DFF).withOpacity(0.15 * v),
                    blurRadius: 60 * v,
                    spreadRadius: 8 * v,
                  ),
                ],
                border: Border.all(
                  color: const Color(0xFF3D5AFE).withOpacity(0.3 * v),
                  width: 1.5,
                ),
              ),
              child: child,
            );
          },
          child: const Icon(
            Icons.lock_rounded,
            color: Colors.white,
            size: 40,
          ),
        ),

        const SizedBox(height: 24),

        // PRIVATE
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFF90CAF9),
              Color(0xFF7C4DFF),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: Text(
            'PRIVATE',
            style: GoogleFonts.poppins(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 8,
            ),
          ),
        ),

        const SizedBox(height: 4),

        // GALLERY HD
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'GALLERY',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w300,
                color: Colors.white38,
                letterSpacing: 10,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3D5AFE), Color(0xFF7C4DFF)],
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'HD',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        // Línea decorativa
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 1000),
          curve: Curves.easeOutCubic,
          builder: (_, v, __) {
            return Container(
              width: 70 * v,
              height: 1.5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    const Color(0xFF3D5AFE).withOpacity(v),
                    const Color(0xFF7C4DFF).withOpacity(v),
                    Colors.transparent,
                  ],
                ),
              ),
            );
          },
        ),
      ],
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

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 90),
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
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withOpacity(0.05),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
              width: 1,
            ),
          ),
          child: Center(child: widget.child),
        ),
      ),
    );
  }
}