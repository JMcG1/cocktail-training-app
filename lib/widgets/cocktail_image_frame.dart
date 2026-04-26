import 'dart:ui';

import 'package:cocktail_training/models/cocktail.dart';
import 'package:flutter/material.dart';

class CocktailImageFrame extends StatelessWidget {
  const CocktailImageFrame({
    super.key,
    required this.cocktail,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.fit = BoxFit.contain,
  });

  final Cocktail cocktail;
  final double? width;
  final double? height;
  final BorderRadius borderRadius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cocktail.hasImage)
              Image.asset(
                cocktail.imageAssetPath!,
                fit: BoxFit.cover,
              )
            else
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF2B3440),
                      Color(0xFF151A21),
                    ],
                  ),
                ),
              ),

            if (cocktail.hasImage)
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  color: const Color(0xAA0A0E13),
                ),
              ),

            if (cocktail.hasImage)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Image.asset(
                  cocktail.imageAssetPath!,
                  fit: fit,
                  alignment: Alignment.center,
                  errorBuilder: (context, error, stackTrace) =>
                      _ImageFallback(cocktail: cocktail),
                ),
              )
            else
              _ImageFallback(cocktail: cocktail),

            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x00000000),
                    Color(0x660A0E13),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({required this.cocktail});

  final Cocktail cocktail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: const Color(0x2AF4ECDD),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          cocktail.category == 'Shooters'
              ? Icons.wine_bar_outlined
              : Icons.local_bar,
          color: const Color(0xFFF4ECDD),
        ),
      ),
    );
  }
}