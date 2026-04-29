import 'dart:math';

import 'package:cocktail_training/models/cocktail.dart';
import 'package:cocktail_training/models/training_progress.dart';
import 'package:cocktail_training/services/training_progress_service.dart';
import 'package:cocktail_training/widgets/cocktail_image_frame.dart';
import 'package:cocktail_training/widgets/metric_chip.dart';
import 'package:cocktail_training/widgets/premium_backdrop.dart';
import 'package:cocktail_training/widgets/surface_section.dart';
import 'package:flutter/material.dart';

class StudyModeScreen extends StatefulWidget {
  const StudyModeScreen({super.key, required this.cocktails});

  final List<Cocktail> cocktails;

  @override
  State<StudyModeScreen> createState() => _StudyModeScreenState();
}

class _StudyModeScreenState extends State<StudyModeScreen> {
  final TrainingProgressService _progressService =
      TrainingProgressService.instance;
  final Random _random = Random();

  TrainingProgress? _progress;
  String _selectedCategory = _allFilter;
  String _selectedBuildStyle = _allFilter;
  int _cardIndex = 0;
  bool _revealed = false;
  bool _loading = true;
  bool _startingSession = true;
  String? _error;

  static const String _allFilter = 'All';

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    try {
      await _progressService.startSession(TrainingSessionType.study);
      final progress = await _progressService.loadProgress();
      if (!mounted) {
        return;
      }
      setState(() {
        _progress = progress;
        _loading = false;
        _startingSession = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'We couldn’t load your study session right now.';
        _loading = false;
        _startingSession = false;
      });
    }
  }

  List<Cocktail> get _orderedCocktails {
    final cocktails = widget.cocktails.where((cocktail) {
      final categoryMatches =
          _selectedCategory == _allFilter ||
          cocktail.category == _selectedCategory;
      final buildMatches =
          _selectedBuildStyle == _allFilter ||
          cocktail.buildStyleLabel == _selectedBuildStyle;
      return categoryMatches && buildMatches;
    }).toList();

    cocktails.sort((a, b) {
      final priorityCompare = _priorityForCocktail(
        b,
      ).compareTo(_priorityForCocktail(a));
      if (priorityCompare != 0) {
        return priorityCompare;
      }
      return a.name.compareTo(b.name);
    });

    return cocktails;
  }

  Cocktail? get _currentCocktail {
    final cocktails = _orderedCocktails;
    if (cocktails.isEmpty) {
      return null;
    }

    final index = _cardIndex.clamp(0, cocktails.length - 1);
    return cocktails[index];
  }

  List<String> get _categories => [
    _allFilter,
    ...widget.cocktails.map((cocktail) => cocktail.category).toSet().toList()
      ..sort(),
  ];

  List<String> get _buildStyles => [
    _allFilter,
    ...widget.cocktails
        .map((cocktail) => cocktail.buildStyleLabel)
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort(),
  ];

  int _priorityForCocktail(Cocktail cocktail) {
    final progress = _progress?.cocktails[cocktail.id];
    if (progress == null) {
      return 10;
    }

    var score = 0;
    score += progress.needPracticeCount * 5;
    score += progress.quizIncorrect * 4;
    score += progress.totalTopicMisses * 2;
    score -= progress.knewCount * 2;
    score -= progress.quizCorrect;
    score -= min(progress.studyAttempts, 4);

    if (progress.lastStudiedAtMillis == null) {
      score += 2;
    }

    return score;
  }

  Future<void> _recordReview(bool knewIt) async {
    final cocktail = _currentCocktail;
    if (cocktail == null) {
      return;
    }

    final updated = await _progressService.recordStudyReview(
      cocktailId: cocktail.id,
      knewIt: knewIt,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _progress = updated;
      _revealed = false;
      if (_cardIndex < _orderedCocktails.length - 1) {
        _cardIndex += 1;
      } else {
        _cardIndex = 0;
      }
    });
  }

  void _move(int delta) {
    final cocktails = _orderedCocktails;
    if (cocktails.isEmpty) {
      return;
    }

    setState(() {
      _cardIndex = (_cardIndex + delta) % cocktails.length;
      if (_cardIndex < 0) {
        _cardIndex += cocktails.length;
      }
      _revealed = false;
    });
  }

  void _shuffleDeck() {
    final cocktails = _orderedCocktails;
    if (cocktails.isEmpty) {
      return;
    }

    setState(() {
      _cardIndex = _random.nextInt(cocktails.length);
      _revealed = false;
    });
  }

  void _setCategory(String value) {
    setState(() {
      _selectedCategory = value;
      _cardIndex = 0;
      _revealed = false;
    });
  }

  void _setBuildStyle(String value) {
    setState(() {
      _selectedBuildStyle = value;
      _cardIndex = 0;
      _revealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cocktails = _orderedCocktails;
    final cocktail = _currentCocktail;
    final studiedCount = _progress?.studiedCocktailIds.length ?? 0;
    final completion = widget.cocktails.isEmpty
        ? 0
        : studiedCount / widget.cocktails.length;

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
                  Text('Study mode', style: theme.textTheme.headlineLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Practise one cocktail spec at a time, reveal the answer, and mark whether you are service-ready or need another rep.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 22),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_error != null)
                    _StudyMessage(
                      title: 'Study mode unavailable',
                      message: _error!,
                    )
                  else ...[
                    SurfaceSection(
                      eyebrow: 'Session focus',
                      title: 'Build your practice set',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              MetricChip(
                                label: 'Specs trained',
                                value:
                                    '$studiedCount / ${widget.cocktails.length}',
                              ),
                              MetricChip(
                                label: 'Practice reps',
                                value: '${_progress?.totalStudyReviews ?? 0}',
                              ),
                              MetricChip(
                                label: 'Coverage',
                                value: '${(completion * 100).round()}%',
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Category',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _FilterWrap(
                            values: _categories,
                            selectedValue: _selectedCategory,
                            onSelected: _setCategory,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Build style',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _FilterWrap(
                            values: _buildStyles,
                            selectedValue: _selectedBuildStyle,
                            onSelected: _setBuildStyle,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (cocktails.isEmpty)
                      const _StudyMessage(
                        title: 'No cocktails match these filters',
                        message:
                            'Try widening the category or build style filters to keep training moving.',
                      )
                    else if (cocktail == null)
                      const _StudyMessage(
                        title: 'No practice card available',
                        message:
                            'We couldn’t prepare a practice card from the current cocktail specs.',
                      )
                    else
                      SurfaceSection(
                        eyebrow: 'Spec practice',
                        title: 'Spec ${_cardIndex + 1} of ${cocktails.length}',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CocktailImageFrame(
                              cocktail: cocktail,
                              width: double.infinity,
                              height: 260,
                              fit: BoxFit.contain,
                              borderRadius: const BorderRadius.all(
                                Radius.circular(24),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                MetricChip(
                                  label: 'Category',
                                  value: cocktail.category,
                                ),
                                MetricChip(
                                  label: 'Build',
                                  value: cocktail.buildStyleLabel.isEmpty
                                      ? 'Not listed'
                                      : cocktail.buildStyleLabel,
                                ),
                                MetricChip(
                                  label: 'Focus',
                                  value: _priorityLabel(cocktail),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Text(
                              cocktail.name,
                              style: theme.textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _revealed
                                  ? 'Check your recall against the live spec below.'
                                  : 'Call the full spec from memory, then reveal it when you are ready.',
                              style: theme.textTheme.bodyLarge,
                            ),
                            const SizedBox(height: 18),
                            if (_revealed)
                              _RevealedStudySpec(cocktail: cocktail)
                            else
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _revealed = true;
                                    });
                                  },
                                  icon: const Icon(Icons.visibility_outlined),
                                  label: const Text('Reveal recipe spec'),
                                ),
                              ),
                            const SizedBox(height: 18),
                            if (_revealed) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _recordReview(false),
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('Need practice'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: () => _recordReview(true),
                                      icon: const Icon(
                                        Icons.check_circle_outline,
                                      ),
                                      label: const Text('Service-ready'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                            ],
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: cocktails.length > 1
                                        ? () => _move(-1)
                                        : null,
                                    icon: const Icon(Icons.chevron_left),
                                    label: const Text('Previous'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: cocktails.length > 1
                                        ? _shuffleDeck
                                        : null,
                                    icon: const Icon(Icons.shuffle),
                                    label: const Text('Shuffle'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: cocktails.length > 1
                                        ? () => _move(1)
                                        : null,
                                    icon: const Icon(Icons.chevron_right),
                                    label: const Text('Next'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    if (_startingSession) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Starting your practice session...',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _priorityLabel(Cocktail cocktail) {
    final progress = _progress?.cocktails[cocktail.id];
    if (progress == null) {
      return 'Fresh card';
    }
    if (progress.needPracticeCount > progress.knewCount ||
        progress.totalTopicMisses > 0) {
      return 'Needs practice';
    }
    if (progress.knewCount >= 2 && progress.totalQuizAttempts >= 2) {
      return 'Strong recall';
    }
    return 'In rotation';
  }
}

class _RevealedStudySpec extends StatelessWidget {
  const _RevealedStudySpec({required this.cocktail});

  final Cocktail cocktail;

  @override
  Widget build(BuildContext context) {
    final ingredients = cocktail.ingredients
        .where((item) => item.name.trim().isNotEmpty)
        .toList();
    final methodSteps = cocktail.methodSteps
        .where((item) => item.trim().isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StudySectionTitle('Ingredients'),
        if (ingredients.isEmpty)
          const Text('No ingredients are listed for this spec.')
        else
          for (final ingredient in ingredients)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(
                      ingredient.displayMeasure.isEmpty
                          ? 'Serve'
                          : ingredient.displayMeasure,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      ingredient.note == null || ingredient.note!.trim().isEmpty
                          ? ingredient.name
                          : '${ingredient.name} (${ingredient.note!.trim()})',
                    ),
                  ),
                ],
              ),
            ),
        const SizedBox(height: 12),
        _StudySectionTitle('Method'),
        if (methodSteps.isEmpty)
          const Text('No method steps are listed for this spec.')
        else
          for (var i = 0; i < methodSteps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('${i + 1}. ${methodSteps[i]}'),
            ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            MetricChip(
              label: 'Garnish',
              value: cocktail.garnish.trim().isEmpty
                  ? 'No garnish listed'
                  : cocktail.garnish,
            ),
            MetricChip(
              label: 'Glassware',
              value: cocktail.glassware.trim().isEmpty
                  ? 'Not listed'
                  : cocktail.glassware,
            ),
            MetricChip(
              label: 'Build style',
              value: cocktail.buildStyleLabel.trim().isEmpty
                  ? 'Not listed'
                  : cocktail.buildStyleLabel,
            ),
          ],
        ),
      ],
    );
  }
}

class _StudySectionTitle extends StatelessWidget {
  const _StudySectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _FilterWrap extends StatelessWidget {
  const _FilterWrap({
    required this.values,
    required this.selectedValue,
    required this.onSelected,
  });

  final List<String> values;
  final String selectedValue;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final value in values)
            FilterChip(
              label: Text(value),
              selected: selectedValue == value,
              onSelected: (_) => onSelected(value),
              showCheckmark: false,
              selectedColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.16),
              backgroundColor: const Color(0xFF171F27),
              side: BorderSide(
                color: selectedValue == value
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.26)
                    : Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.1),
              ),
              labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selectedValue == value
                    ? Theme.of(context).colorScheme.primary
                    : const Color(0xFFE5D9C9),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
        ],
      ),
    );
  }
}

class _StudyMessage extends StatelessWidget {
  const _StudyMessage({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return SurfaceSection(
      eyebrow: 'Study mode',
      title: title,
      child: Text(message, style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}
