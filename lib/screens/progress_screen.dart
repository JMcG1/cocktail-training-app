import 'package:cocktail_training/models/cocktail.dart';
import 'package:cocktail_training/models/training_progress.dart';
import 'package:cocktail_training/services/training_progress_service.dart';
import 'package:cocktail_training/widgets/metric_chip.dart';
import 'package:cocktail_training/widgets/premium_backdrop.dart';
import 'package:cocktail_training/widgets/surface_section.dart';
import 'package:flutter/material.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, required this.cocktails});

  final List<Cocktail> cocktails;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  final TrainingProgressService _progressService = TrainingProgressService.instance;

  TrainingProgress? _progress;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    try {
      final progress = await _progressService.loadProgress();
      if (!mounted) {
        return;
      }
      setState(() {
        _progress = progress;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Progress data could not be loaded.';
        _loading = false;
      });
    }
  }

  Future<void> _confirmReset() async {
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141A21),
          title: const Text('Reset training progress?'),
          content: const Text(
            'This clears local study and quiz history on this device for the current account.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );

    if (shouldReset != true) {
      return;
    }

    await _progressService.resetProgress();
    await _loadProgress();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PremiumBackdrop(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Progress', style: theme.textTheme.headlineLarge),
                  const SizedBox(height: 10),
                  Text(
                    'Track recall, spot weak drinks, and keep your daily training rhythm moving.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 22),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_error != null)
                    _ProgressMessage(
                      title: 'Progress unavailable',
                      message: _error!,
                    )
                  else
                    _ProgressContent(
                      cocktails: widget.cocktails,
                      progress: _progress ?? TrainingProgress.empty(),
                      onResetProgress: _confirmReset,
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

class _ProgressContent extends StatelessWidget {
  const _ProgressContent({
    required this.cocktails,
    required this.progress,
    required this.onResetProgress,
  });

  final List<Cocktail> cocktails;
  final TrainingProgress progress;
  final VoidCallback onResetProgress;

  @override
  Widget build(BuildContext context) {
    final studiedCount = progress.studiedCocktailIds.length;
    final completion = cocktails.isEmpty ? 0 : studiedCount / cocktails.length;
    final strongestTopic = _strongestTopicLabel(progress);
    final weakestTopic = _weakestTopicLabel(progress);
    final streakDays = _calculateStreak(progress.trainingDayKeys);
    final weakCocktails = _weakCocktails(cocktails, progress);
    final recentResults = progress.recentQuizResults.take(5).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SurfaceSection(
          eyebrow: 'Snapshot',
          title: 'Training totals',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  MetricChip(label: 'Studied', value: '$studiedCount / ${cocktails.length}'),
                  MetricChip(label: 'Quiz answers', value: '${progress.totalQuizQuestions}'),
                  MetricChip(label: 'Accuracy', value: '${(progress.accuracy * 100).round()}%'),
                  MetricChip(label: 'Sessions', value: '${progress.totalSessions}'),
                ],
              ),
              const SizedBox(height: 18),
              _MetricRow(
                label: 'Study completion',
                value: '${(completion * 100).round()}%',
              ),
              const SizedBox(height: 12),
              _MetricRow(
                label: 'Daily streak',
                value: streakDays == 0 ? 'Start today' : '$streakDays day${streakDays == 1 ? '' : 's'}',
              ),
              const SizedBox(height: 12),
              _MetricRow(
                label: 'Strongest topic',
                value: strongestTopic,
              ),
              const SizedBox(height: 12),
              _MetricRow(
                label: 'Weakest topic',
                value: weakestTopic,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SurfaceSection(
          eyebrow: 'Needs review',
          title: 'Weak cocktails',
          child: weakCocktails.isEmpty
              ? Text(
                  'No cocktails are currently flagged for review. Keep the streak going to hold that standard.',
                  style: Theme.of(context).textTheme.bodyLarge,
                )
              : Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final item in weakCocktails)
                      Chip(
                        label: Text(item),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 18),
        SurfaceSection(
          eyebrow: 'Recent rounds',
          title: 'Quiz performance',
          child: recentResults.isEmpty
              ? Text(
                  'No quiz rounds completed yet. Jump into quiz mode to start building performance history.',
                  style: Theme.of(context).textTheme.bodyLarge,
                )
              : Column(
                  children: [
                    for (var i = 0; i < recentResults.length; i++) ...[
                      _ResultRow(result: recentResults[i]),
                      if (i < recentResults.length - 1) const SizedBox(height: 14),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 18),
        SurfaceSection(
          eyebrow: 'Controls',
          title: 'Reset local progress',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Use this if you want to wipe this device’s study and quiz history and start fresh.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onResetProgress,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset progress'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _strongestTopicLabel(TrainingProgress progress) {
    if (progress.totalQuizQuestions == 0) {
      return 'Not enough data yet';
    }

    final missEntries = QuizTopic.values
        .map((topic) => MapEntry(topic, progress.topicMissTotals[topic.key] ?? 0))
        .toList(growable: false);

    final lowestMisses = missEntries.map((entry) => entry.value).reduce((a, b) => a < b ? a : b);
    final strongest = missEntries.firstWhere((entry) => entry.value == lowestMisses).key;
    return strongest.label;
  }

  String _weakestTopicLabel(TrainingProgress progress) {
    if (progress.totalQuizQuestions == 0) {
      return 'Not enough data yet';
    }

    final missEntries = QuizTopic.values
        .map((topic) => MapEntry(topic, progress.topicMissTotals[topic.key] ?? 0))
        .toList(growable: false);
    final highestMisses = missEntries.map((entry) => entry.value).reduce((a, b) => a > b ? a : b);
    if (highestMisses <= 0) {
      return 'No weak topic yet';
    }

    final weakest = missEntries.firstWhere((entry) => entry.value == highestMisses).key;
    return weakest.label;
  }

  List<String> _weakCocktails(List<Cocktail> cocktails, TrainingProgress progress) {
    final cocktailMap = {for (final cocktail in cocktails) cocktail.id: cocktail};
    final weakEntries = progress.cocktails.values.where((item) => item.needsReview).toList()
      ..sort((a, b) {
        final compare = b.totalTopicMisses.compareTo(a.totalTopicMisses);
        if (compare != 0) {
          return compare;
        }
        return b.needPracticeCount.compareTo(a.needPracticeCount);
      });

    return weakEntries
        .take(8)
        .map((entry) => cocktailMap[entry.cocktailId]?.name ?? entry.cocktailId)
        .toList(growable: false);
  }

  int _calculateStreak(List<String> trainingDayKeys) {
    if (trainingDayKeys.isEmpty) {
      return 0;
    }

    final parsed = trainingDayKeys
        .map(DateTime.tryParse)
        .whereType<DateTime>()
        .map((date) => DateTime(date.year, date.month, date.day))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    if (parsed.isEmpty) {
      return 0;
    }

    final today = DateTime.now();
    var cursor = DateTime(today.year, today.month, today.day);
    var streak = 0;

    for (final day in parsed) {
      if (day == cursor) {
        streak += 1;
        cursor = cursor.subtract(const Duration(days: 1));
      } else if (day.isBefore(cursor)) {
        if (streak == 0 && day == cursor.subtract(const Duration(days: 1))) {
          streak += 1;
          cursor = day.subtract(const Duration(days: 1));
        } else {
          break;
        }
      }
    }

    return streak;
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.result});

  final QuizResult result;

  @override
  Widget build(BuildContext context) {
    final completedAt = DateTime.fromMillisecondsSinceEpoch(result.completedAtMillis);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171F27),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetricRow(
            label: 'Round score',
            value: '${result.correctAnswers}/${result.totalQuestions}',
          ),
          const SizedBox(height: 10),
          _MetricRow(
            label: 'Accuracy',
            value: '${(result.accuracy * 100).round()}%',
          ),
          const SizedBox(height: 10),
          _MetricRow(
            label: 'Completed',
            value: _formatDateTime(completedAt),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.year}-$month-$day $hour:$minute';
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
      ],
    );
  }
}

class _ProgressMessage extends StatelessWidget {
  const _ProgressMessage({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return SurfaceSection(
      eyebrow: 'Progress',
      title: title,
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}
