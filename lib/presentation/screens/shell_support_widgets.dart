import 'package:flutter/material.dart';

class HeaderCard extends StatelessWidget {
  const HeaderCard({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyLarge,
                  maxLines: compact ? null : 3,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.caption,
  });

  final String title;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 220),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 12),
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(caption, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class InfoMetric extends StatelessWidget {
  const InfoMetric({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140, maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2428),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF293037)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

class BuildMarkerSummary extends StatelessWidget {
  const BuildMarkerSummary({
    super.key,
    required this.buildMarker,
    required this.appVersionLabel,
    required this.catalogPathLabel,
    required this.visibleRecipeCount,
  });

  final String buildMarker;
  final String appVersionLabel;
  final String catalogPathLabel;
  final int visibleRecipeCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101417),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF293037)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Build $buildMarker',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          Text(appVersionLabel),
          const SizedBox(height: 6),
          Text(catalogPathLabel),
          const SizedBox(height: 6),
          Text('Visible cocktails: $visibleRecipeCount'),
        ],
      ),
    );
  }
}
