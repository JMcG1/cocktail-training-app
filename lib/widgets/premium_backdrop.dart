import 'package:flutter/material.dart';

class PremiumBackdrop extends StatelessWidget {
  const PremiumBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0F141A), Color(0xFF0A0E13)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -10,
            child: _GlowOrb(
              size: 220,
              colors: [
                const Color(0xFFD9A35F).withValues(alpha: 0.18),
                Colors.transparent,
              ],
            ),
          ),
          Positioned(
            top: 180,
            left: -80,
            child: _GlowOrb(
              size: 260,
              colors: [
                const Color(0xFF7DA388).withValues(alpha: 0.12),
                Colors.transparent,
              ],
            ),
          ),
          Positioned(
            bottom: -110,
            right: -40,
            child: _GlowOrb(
              size: 260,
              colors: [
                const Color(0xFFB57962).withValues(alpha: 0.11),
                Colors.transparent,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.colors});

  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }
}
