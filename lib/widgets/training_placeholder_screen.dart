import 'package:cocktail_training/widgets/metric_chip.dart';
import 'package:cocktail_training/widgets/premium_backdrop.dart';
import 'package:cocktail_training/widgets/surface_section.dart';
import 'package:flutter/material.dart';

class PlaceholderModule {
  const PlaceholderModule({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.metricLabel,
    required this.metricValue,
  });

  final String eyebrow;
  final String title;
  final String description;
  final String metricLabel;
  final String metricValue;
}

class TrainingPlaceholderScreen extends StatelessWidget {
  const TrainingPlaceholderScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.spotlightLabel,
    required this.spotlightValue,
    required this.modules,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String spotlightLabel;
  final String spotlightValue;
  final List<PlaceholderModule> modules;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PremiumBackdrop(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B232D),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.14,
                        ),
                      ),
                    ),
                    child: Icon(
                      icon,
                      color: theme.colorScheme.primary,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(title, style: theme.textTheme.headlineLarge),
                  const SizedBox(height: 12),
                  Text(subtitle, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 20),
                  MetricChip(label: spotlightLabel, value: spotlightValue),
                  const SizedBox(height: 22),
                  SurfaceSection(
                    eyebrow: 'Placeholder modules',
                    title: 'Planned experience',
                    child: Column(
                      children: [
                        for (final module in modules) ...[
                          _PlaceholderCard(module: module),
                          if (module != modules.last)
                            const SizedBox(height: 14),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard({required this.module});

  final PlaceholderModule module;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF171E26),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            module.eyebrow,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(module.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Text(
            module.description,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          MetricChip(label: module.metricLabel, value: module.metricValue),
        ],
      ),
    );
  }
}
