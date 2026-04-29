import 'package:cocktail_training/models/cocktail.dart';
import 'package:cocktail_training/widgets/cocktail_image_frame.dart';
import 'package:flutter/material.dart';

class CocktailCard extends StatelessWidget {
  const CocktailCard({super.key, required this.cocktail, required this.onTap});

  final Cocktail cocktail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleParts = <String>[
      cocktail.buildStyleLabel,
      cocktail.glassware,
      if (cocktail.isAlcoholFree) 'Alcohol-free',
    ].where((item) => item.trim().isNotEmpty).toList(growable: false);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xAA171E26),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cocktail.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitleParts.join('  •  '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            cocktail.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Text(
                                'Open recipe spec',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.arrow_forward_ios,
                                size: 14,
                                color: theme.colorScheme.primary,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Hero(
                      tag: cocktail.imageHeroTag,
                      child: CocktailImageFrame(
                        cocktail: cocktail,
                        width: 84,
                        height: 104,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(22),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CocktailTag(label: cocktail.category),
                    _CocktailTag(
                      label: '${cocktail.ingredients.length} ingredients',
                    ),
                    if (cocktail.garnish.trim().isNotEmpty)
                      _CocktailTag(label: 'Garnish: ${cocktail.garnish}'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CocktailTag extends StatelessWidget {
  const _CocktailTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2832),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontSize: 12,
          color: const Color(0xFFE5D9C9),
        ),
      ),
    );
  }
}
