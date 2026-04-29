import 'package:cocktail_training/models/cocktail.dart';
import 'package:cocktail_training/models/ingredient.dart';
import 'package:cocktail_training/widgets/cocktail_image_frame.dart';
import 'package:cocktail_training/widgets/metric_chip.dart';
import 'package:cocktail_training/widgets/premium_backdrop.dart';
import 'package:cocktail_training/widgets/surface_section.dart';
import 'package:flutter/material.dart';

class CocktailDetailScreen extends StatelessWidget {
  const CocktailDetailScreen({super.key, required this.cocktail});

  final Cocktail cocktail;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PremiumBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton.filledTonal(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF1D252F), Color(0xFF12171E)],
                        ),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.18),
                        ),
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Hero(
                            tag: cocktail.imageHeroTag,
                            child: CocktailImageFrame(
                              cocktail: cocktail,
                              width: double.infinity,
                              height: 320,
                              borderRadius: const BorderRadius.all(
                                Radius.circular(24),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Text(
                            cocktail.category.toUpperCase(),
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  letterSpacing: 1.2,
                                ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            cocktail.name,
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            cocktail.description,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              MetricChip(
                                label: 'Build style',
                                value: cocktail.buildStyleLabel,
                              ),
                              MetricChip(
                                label: 'Glassware',
                                value: cocktail.glassware,
                              ),
                              MetricChip(
                                label: 'Garnish',
                                value: cocktail.garnish,
                              ),
                              MetricChip(
                                label: 'Style',
                                value: cocktail.isAlcoholFree
                                    ? 'Alcohol-Free'
                                    : 'Cocktail',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SurfaceSection(
                      eyebrow: 'Training spec',
                      title: 'What the team needs to remember',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DetailRow(
                            label: 'Category',
                            value: cocktail.category,
                          ),
                          const SizedBox(height: 12),
                          _DetailRow(
                            label: 'Build style',
                            value: cocktail.buildStyleLabel,
                          ),
                          const SizedBox(height: 12),
                          _DetailRow(
                            label: 'Glassware',
                            value: cocktail.glassware,
                          ),
                          const SizedBox(height: 12),
                          _DetailRow(label: 'Garnish', value: cocktail.garnish),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SurfaceSection(
                      eyebrow: 'Build',
                      title: 'Ingredients',
                      child: Column(
                        children: [
                          for (final ingredient in cocktail.ingredients) ...[
                            _IngredientRow(ingredient: ingredient),
                            if (ingredient != cocktail.ingredients.last)
                              const Divider(height: 28),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SurfaceSection(
                      eyebrow: 'Execution',
                      title: 'Method',
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < cocktail.methodSteps.length;
                            index++
                          ) ...[
                            _MethodStep(
                              stepNumber: index + 1,
                              text: cocktail.methodSteps[index],
                            ),
                            if (index < cocktail.methodSteps.length - 1)
                              const SizedBox(height: 14),
                          ],
                        ],
                      ),
                    ),
                    if (cocktail.notes.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      SurfaceSection(
                        eyebrow: 'Service notes',
                        title: 'Venue notes',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final note in cocktail.notes) ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Icon(
                                      Icons.circle,
                                      size: 8,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      note,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyLarge,
                                    ),
                                  ),
                                ],
                              ),
                              if (note != cocktail.notes.last)
                                const SizedBox(height: 12),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({required this.ingredient});

  final Ingredient ingredient;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ingredient.displayMeasure.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1B232C),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              ingredient.displayMeasure,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        if (ingredient.displayMeasure.isNotEmpty) const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ingredient.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (ingredient.note != null) ...[
                const SizedBox(height: 4),
                Text(
                  ingredient.note!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MethodStep extends StatelessWidget {
  const _MethodStep({required this.stepNumber, required this.text});

  final int stepNumber;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$stepNumber',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ),
      ],
    );
  }
}
