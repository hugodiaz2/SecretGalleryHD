import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Encabezado animado compartido por las pantallas de bloqueo
/// (PIN, contraseña, huella dactilar): ícono con glow + logo "SECRET
/// GALLERY HD" con entrada de fade + slide.
class LockHeader extends StatefulWidget {
  const LockHeader({super.key});

  @override
  State<LockHeader> createState() => _LockHeaderState();
}

class _LockHeaderState extends State<LockHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0.0, -0.25),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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

            // SECRET
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
                'SECRET',
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
        ),
      ),
    );
  }
}
