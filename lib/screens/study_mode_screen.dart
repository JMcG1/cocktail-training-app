import 'dart:math';

import 'package:cocktail_training/models/cocktail.dart';
import 'package:cocktail_training/models/training_progress.dart';
import 'package:cocktail_training/services/training_progress_service.dart';
import 'package:cocktail_training/widgets/cocktail_image_frame.dart';
import 'package:cocktail_training/widgets/metric_chip.dart';
import 'package:cocktail_training/widgets/premium_backdrop.dart';
import 'package:cocktail_training/widgets/surface_section.dart';
import 'package:flutter/material.dart';

enum _StudyExperience { flashcards, blindRecall }

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
  Set<String> _priorityCocktailIds = const <String>{};
  String _selectedCategory = _allFilter;
  String _selectedBuildStyle = _allFilter;
  int _cardIndex = 0;
  bool _revealed = false;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  _StudyExperience _experience = _StudyExperience.flashcards;
  DateTime _promptStartedAt = DateTime.now();

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
      final priorityCocktailIds = await _progressService
          .loadPriorityCocktailIds();
      if (!mounted) {
        return;
      }
      setState(() {
        _progress = progress;
        _priorityCocktailIds = priorityCocktailIds.toSet();
        _loading = false;
        _promptStartedAt = DateTime.now();
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'We couldn’t load your study session right now.';
        _loading = false;
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
    var score = 0;
    if (_priorityCocktailIds.contains(cocktail.id)) {
      score += 16;
    }
    if (progress == null) {
      return score + 10;
    }
    score += (100 - progress.masteryScore).round();
    score += progress.wrongCount * 4;
    score += progress.totalTopicMisses * 3;
    if (progress.lastAttemptedAtMillis == null) {
      score += 8;
    }
    if (progress.lastWrongAtMillis != null) {
      final hoursSinceWrong =
          (DateTime.now().millisecondsSinceEpoch -
              progress.lastWrongAtMillis!) ~/
          3600000;
      if (hoursSinceWrong <= 24) {
        score += 8;
      }
    }
    return score;
  }

  void _setCategory(String value) {
    setState(() {
      _selectedCategory = value;
      _cardIndex = 0;
      _revealed = false;
      _promptStartedAt = DateTime.now();
    });
  }

  void _setBuildStyle(String value) {
    setState(() {
      _selectedBuildStyle = value;
      _cardIndex = 0;
      _revealed = false;
      _promptStartedAt = DateTime.now();
    });
  }

  void _setExperience(_StudyExperience experience) {
    if (_experience == experience) {
      return;
    }

    setState(() {
      _experience = experience;
      _revealed = false;
      _promptStartedAt = DateTime.now();
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
      _promptStartedAt = DateTime.now();
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
      _promptStartedAt = DateTime.now();
    });
  }

  Future<void> _recordFlashcardReview(bool knewIt) async {
    if (_submitting) {
      return;
    }

    final cocktail = _currentCocktail;
    if (cocktail == null) {
      return;
    }

    setState(() {
      _submitting = true;
    });

    final updated = await _progressService.recordStudyReview(
      cocktailId: cocktail.id,
      knewIt: knewIt,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _progress = updated;
      _submitting = false;
      _advanceCard();
    });
  }

  Future<void> _recordBlindRecall(bool wasCorrect) async {
    if (_submitting) {
      return;
    }

    final cocktail = _currentCocktail;
    if (cocktail == null) {
      return;
    }

    setState(() {
      _submitting = true;
    });

    final responseMs = DateTime.now()
        .difference(_promptStartedAt)
        .inMilliseconds;
    final updated = await _progressService.recordBlindRecallReview(
      cocktailId: cocktail.id,
      wasCorrect: wasCorrect,
      responseMs: responseMs,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _progress = updated;
      _submitting = false;
      _advanceCard();
    });
  }

  void _advanceCard() {
    final cocktails = _orderedCocktails;
    _revealed = false;
    if (cocktails.isEmpty) {
      _cardIndex = 0;
    } else if (_cardIndex < cocktails.length - 1) {
      _cardIndex += 1;
    } else {
      _cardIndex = 0;
    }
    _promptStartedAt = DateTime.now();
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
                    'Train specs in two ways: review the full build on flashcards or run blind recall and mark whether you could call it on shift.',
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
                      eyebrow: 'Session setup',
                      title: 'Choose how you want to train',
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
                          _ModePills<_StudyExperience>(
                            currentValue: _experience,
                            items: const {
                              _StudyExperience.flashcards: 'Flashcards',
                              _StudyExperience.blindRecall: 'Blind recall',
                            },
                            onSelected: _setExperience,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Categories',
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
                        eyebrow: _experience == _StudyExperience.flashcards
                            ? 'Flashcard review'
                            : 'Blind recall',
                        title:
                            '${cocktail.name} • ${_cardIndex + 1} of ${cocktails.length}',
                        child: _experience == _StudyExperience.flashcards
                            ? _FlashcardExperience(
                                cocktail: cocktail,
                                revealed: _revealed,
                                priority: _priorityLabel(cocktail),
                                onReveal: () {
                                  setState(() {
                                    _revealed = true;
                                  });
                                },
                                onReview: _recordFlashcardReview,
                                submitting: _submitting,
                              )
                            : _BlindRecallExperience(
                                cocktail: cocktail,
                                revealed: _revealed,
                                priority: _priorityLabel(cocktail),
                                onReveal: () {
                                  setState(() {
                                    _revealed = true;
                                  });
                                },
                                onReview: _recordBlindRecall,
                                submitting: _submitting,
                              ),
                      ),
                    if (cocktails.isNotEmpty) ...[
                      const SizedBox(height: 16),
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
    if (_priorityCocktailIds.contains(cocktail.id)) {
      return 'Manager priority';
    }
    final progress = _progress?.cocktails[cocktail.id];
    if (progress == null) {
      return 'Fresh spec';
    }
    if (progress.needsReview) {
      return 'Needs practice';
    }
    if (progress.isMastered) {
      return 'Mastered';
    }
    return 'In rotation';
  }
}

class _FlashcardExperience extends StatelessWidget {
  const _FlashcardExperience({
    required this.cocktail,
    required this.revealed,
    required this.priority,
    required this.onReveal,
    required this.onReview,
    required this.submitting,
  });

  final Cocktail cocktail;
  final bool revealed;
  final String priority;
  final VoidCallback onReveal;
  final ValueChanged<bool> onReview;
  final bool submitting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CocktailImageFrame(
          cocktail: cocktail,
          width: double.infinity,
          height: 240,
          fit: BoxFit.contain,
          borderRadius: const BorderRadius.all(Radius.circular(24)),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            MetricChip(label: 'Category', value: cocktail.category),
            MetricChip(label: 'Build', value: cocktail.buildStyleLabel),
            MetricChip(label: 'Focus', value: priority),
          ],
        ),
        const SizedBox(height: 18),
        Text(cocktail.name, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          revealed
              ? 'Compare your recall with the live recipe spec below.'
              : 'Call the full spec from memory, then reveal it when you are ready.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 18),
        if (revealed)
          _RevealedStudySpec(cocktail: cocktail)
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onReveal,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Reveal recipe spec'),
            ),
          ),
        if (revealed) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: submitting ? null : () => onReview(false),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Need practice'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: submitting ? null : () => onReview(true),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Service-ready'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _BlindRecallExperience extends StatelessWidget {
  const _BlindRecallExperience({
    required this.cocktail,
    required this.revealed,
    required this.priority,
    required this.onReveal,
    required this.onReview,
    required this.submitting,
  });

  final Cocktail cocktail;
  final bool revealed;
  final String priority;
  final VoidCallback onReveal;
  final ValueChanged<bool> onReview;
  final bool submitting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            MetricChip(label: 'Focus', value: priority),
            MetricChip(label: 'Glassware', value: cocktail.glassware),
            MetricChip(label: 'Garnish', value: cocktail.garnish),
          ],
        ),
        const SizedBox(height: 22),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF171F27),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Call this spec from memory',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              Text(cocktail.name, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 10),
              Text(
                'Say the ingredients, method, garnish, and glassware before you reveal the answer.',
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (revealed)
          _RevealedStudySpec(cocktail: cocktail)
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onReveal,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Reveal answer'),
            ),
          ),
        if (revealed) ...[
          const SizedBox(height: 18),
          Text('How did that feel?', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: submitting ? null : () => onReview(false),
                  icon: const Icon(Icons.close),
                  label: const Text('Missed it'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: submitting ? null : () => onReview(true),
                  icon: const Icon(Icons.check),
                  label: const Text('Got it'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
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

class _ModePills<T> extends StatelessWidget {
  const _ModePills({
    required this.currentValue,
    required this.items,
    required this.onSelected,
  });

  final T currentValue;
  final Map<T, String> items;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final entry in items.entries)
          ChoiceChip(
            label: Text(entry.value),
            selected: entry.key == currentValue,
            onSelected: (_) => onSelected(entry.key),
            showCheckmark: false,
          ),
      ],
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
