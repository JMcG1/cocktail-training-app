import 'dart:math';

import 'package:cocktail_training/models/cocktail.dart';
import 'package:cocktail_training/models/quiz_question.dart';
import 'package:cocktail_training/models/training_progress.dart';
import 'package:cocktail_training/services/quiz_engine.dart';
import 'package:cocktail_training/services/training_progress_service.dart';
import 'package:cocktail_training/widgets/cocktail_image_frame.dart';
import 'package:cocktail_training/widgets/metric_chip.dart';
import 'package:cocktail_training/widgets/premium_backdrop.dart';
import 'package:cocktail_training/widgets/surface_section.dart';
import 'package:flutter/material.dart';

enum _QuizExperience { specCheck, serviceMode, passCheck }

class QuizModeScreen extends StatefulWidget {
  const QuizModeScreen({super.key, required this.cocktails});

  final List<Cocktail> cocktails;

  @override
  State<QuizModeScreen> createState() => _QuizModeScreenState();
}

class _QuizModeScreenState extends State<QuizModeScreen> {
  final TrainingProgressService _progressService =
      TrainingProgressService.instance;
  final QuizEngine _quizEngine = QuizEngine();
  final Random _random = Random();

  _QuizExperience _experience = _QuizExperience.specCheck;
  Set<String> _priorityCocktailIds = const <String>{};
  List<QuizQuestion> _questions = const [];
  List<Cocktail> _serviceCocktails = const [];
  int _index = 0;
  int _correctAnswers = 0;
  int? _selectedIndex;
  bool _answered = false;
  bool _revealed = false;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  QuizSessionSummary? _summary;
  ExamResult? _examResult;
  final Set<String> _missedCocktailIds = <String>{};
  final Set<QuizTopic> _missedTopics = <QuizTopic>{};
  Set<String>? _focusCocktailIds;
  bool _serviceTimerEnabled = true;
  int _passMark = 80;
  DateTime _promptStartedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _startMode(_experience);
  }

  Future<void> _startMode(
    _QuizExperience experience, {
    Set<String>? focusCocktailIds,
  }) async {
    setState(() {
      _loading = true;
      _error = null;
      _experience = experience;
      _summary = null;
      _examResult = null;
      _index = 0;
      _correctAnswers = 0;
      _selectedIndex = null;
      _answered = false;
      _revealed = false;
      _focusCocktailIds = focusCocktailIds;
      _missedCocktailIds.clear();
      _missedTopics.clear();
    });

    if (widget.cocktails.isEmpty) {
      setState(() {
        _loading = false;
      });
      return;
    }

    try {
      await _progressService.startSession(_sessionTypeFor(experience));
      final progress = await _progressService.loadProgress();
      final priorityCocktailIds = await _progressService
          .loadPriorityCocktailIds();

      if (!mounted) {
        return;
      }

      if (experience == _QuizExperience.serviceMode) {
        final serviceCocktails = [...widget.cocktails]
          ..sort(
            (a, b) => _servicePriority(
              progress,
              b,
            ).compareTo(_servicePriority(progress, a)),
          );
        serviceCocktails.shuffle(_random);
        final limited = serviceCocktails
            .take(min(10, serviceCocktails.length))
            .toList(growable: false);
        setState(() {
          _priorityCocktailIds = priorityCocktailIds.toSet();
          _serviceCocktails = limited;
          _questions = const [];
          _loading = false;
          _promptStartedAt = DateTime.now();
        });
        return;
      }

      final questionCount = experience == _QuizExperience.passCheck ? 15 : 12;
      final questions = _quizEngine.buildSession(
        cocktails: widget.cocktails,
        progress: progress,
        questionCount: questionCount,
        focusCocktailIds: focusCocktailIds,
        priorityCocktailIds: priorityCocktailIds.toSet(),
      );

      setState(() {
        _priorityCocktailIds = priorityCocktailIds.toSet();
        _questions = questions;
        _serviceCocktails = const [];
        _loading = false;
        _promptStartedAt = DateTime.now();
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'We couldn’t load this training mode right now.';
        _loading = false;
      });
    }
  }

  TrainingSessionType _sessionTypeFor(_QuizExperience experience) {
    switch (experience) {
      case _QuizExperience.specCheck:
        return TrainingSessionType.quiz;
      case _QuizExperience.serviceMode:
        return TrainingSessionType.service;
      case _QuizExperience.passCheck:
        return TrainingSessionType.exam;
    }
  }

  int _servicePriority(TrainingProgress progress, Cocktail cocktail) {
    final item = progress.cocktails[cocktail.id];
    var score = _priorityCocktailIds.contains(cocktail.id) ? 20 : 0;
    if (item == null) {
      return score + 12;
    }
    score += (100 - item.masteryScore).round();
    score += item.wrongCount * 4;
    return score;
  }

  QuizQuestion get _question => _questions[_index];
  Cocktail get _serviceCocktail => _serviceCocktails[_index];

  Future<void> _answerQuestion(int index) async {
    if (_answered || _submitting) {
      return;
    }

    final question = _question;
    final isCorrect = index == question.correctIndex;

    setState(() {
      _selectedIndex = index;
      _answered = true;
      _submitting = true;
      if (isCorrect) {
        _correctAnswers += 1;
      } else {
        _missedCocktailIds.add(question.cocktailId);
        _missedTopics.add(question.topic);
      }
    });

    try {
      final responseMs = DateTime.now()
          .difference(_promptStartedAt)
          .inMilliseconds;
      await _progressService.recordQuizAnswer(
        cocktailId: question.cocktailId,
        topic: question.topic,
        isCorrect: isCorrect,
        responseMs: responseMs,
        isExam: _experience == _QuizExperience.passCheck,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
      });
    }
  }

  Future<void> _nextQuestion() async {
    if (_index < _questions.length - 1) {
      setState(() {
        _index += 1;
        _selectedIndex = null;
        _answered = false;
        _promptStartedAt = DateTime.now();
      });
      return;
    }

    final summary = QuizSessionSummary(
      totalQuestions: _questions.length,
      correctAnswers: _correctAnswers,
      weakCocktailIds: _missedCocktailIds.toList()..sort(),
      weakTopics: _missedTopics.toList()
        ..sort((a, b) => a.index.compareTo(b.index)),
    );

    await _progressService.recordQuizSessionResult(
      QuizResult(
        completedAtMillis: DateTime.now().millisecondsSinceEpoch,
        totalQuestions: summary.totalQuestions,
        correctAnswers: summary.correctAnswers,
        weakCocktailIds: summary.weakCocktailIds,
        weakTopics: summary.weakTopics.map((topic) => topic.key).toList(),
      ),
    );

    ExamResult? examResult;
    if (_experience == _QuizExperience.passCheck) {
      examResult = await _progressService.recordExamResult(
        score: summary.correctAnswers,
        total: summary.totalQuestions,
        passMark: _passMark,
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _summary = summary;
      _examResult = examResult;
    });
  }

  Future<void> _recordServiceAnswer(bool wasCorrect) async {
    if (_submitting) {
      return;
    }

    final cocktail = _serviceCocktail;
    final responseMs = DateTime.now()
        .difference(_promptStartedAt)
        .inMilliseconds;

    setState(() {
      _submitting = true;
      _revealed = true;
      if (wasCorrect) {
        _correctAnswers += 1;
      } else {
        _missedCocktailIds.add(cocktail.id);
      }
    });

    await _progressService.recordServiceRound(
      cocktailId: cocktail.id,
      wasCorrect: wasCorrect,
      responseMs: responseMs,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _submitting = false;
    });
  }

  Future<void> _nextServicePrompt() async {
    if (_index < _serviceCocktails.length - 1) {
      setState(() {
        _index += 1;
        _revealed = false;
        _promptStartedAt = DateTime.now();
      });
      return;
    }

    final summary = QuizSessionSummary(
      totalQuestions: _serviceCocktails.length,
      correctAnswers: _correctAnswers,
      weakCocktailIds: _missedCocktailIds.toList()..sort(),
      weakTopics: const [],
    );

    await _progressService.recordQuizSessionResult(
      QuizResult(
        completedAtMillis: DateTime.now().millisecondsSinceEpoch,
        totalQuestions: summary.totalQuestions,
        correctAnswers: summary.correctAnswers,
        weakCocktailIds: summary.weakCocktailIds,
        weakTopics: const [],
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _summary = summary;
    });
  }

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
                  Text('Quiz mode', style: theme.textTheme.headlineLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Run spec checks, pressure-test recall in service mode, or complete a formal pass check for service readiness.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 22),
                  SurfaceSection(
                    eyebrow: 'Training modes',
                    title: 'Pick your challenge',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ModePills<_QuizExperience>(
                          currentValue: _experience,
                          items: const {
                            _QuizExperience.specCheck: 'Spec check',
                            _QuizExperience.serviceMode: 'Service mode',
                            _QuizExperience.passCheck: 'Pass check',
                          },
                          onSelected: (value) => _startMode(value),
                        ),
                        if (_experience == _QuizExperience.passCheck) ...[
                          const SizedBox(height: 18),
                          Text(
                            'Pass mark',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final value in const [80, 85, 90])
                                ChoiceChip(
                                  label: Text('$value%'),
                                  selected: _passMark == value,
                                  onSelected: (_) {
                                    setState(() {
                                      _passMark = value;
                                    });
                                  },
                                  showCheckmark: false,
                                ),
                            ],
                          ),
                        ],
                        if (_experience == _QuizExperience.serviceMode) ...[
                          const SizedBox(height: 18),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Show timer'),
                            subtitle: const Text(
                              'Keep the pressure on for quick service recall.',
                            ),
                            value: _serviceTimerEnabled,
                            onChanged: (value) {
                              setState(() {
                                _serviceTimerEnabled = value;
                              });
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_error != null)
                    _QuizMessage(
                      title: 'Quiz mode unavailable',
                      message: _error!,
                    )
                  else if (_experience != _QuizExperience.serviceMode &&
                      _questions.isEmpty)
                    const _QuizMessage(
                      title: 'Spec checks are not ready yet',
                      message:
                          'The current cocktail specs do not have enough detail to build a quiz round yet.',
                    )
                  else if (_experience == _QuizExperience.serviceMode &&
                      _serviceCocktails.isEmpty)
                    const _QuizMessage(
                      title: 'Service mode is not ready yet',
                      message:
                          'We couldn’t build a service drill from the current cocktail specs.',
                    )
                  else if (_summary != null)
                    _ModeSummaryView(
                      experience: _experience,
                      summary: _summary!,
                      cocktails: widget.cocktails,
                      examResult: _examResult,
                      passMark: _passMark,
                      onRetryWeakAreas: _missedCocktailIds.isEmpty
                          ? null
                          : () => _startMode(
                              _experience == _QuizExperience.passCheck
                                  ? _QuizExperience.specCheck
                                  : _experience,
                              focusCocktailIds: _missedCocktailIds,
                            ),
                      onRestart: () => _startMode(_experience),
                    )
                  else if (_experience == _QuizExperience.serviceMode)
                    _ServiceModeCard(
                      cocktail: _serviceCocktail,
                      currentIndex: _index + 1,
                      total: _serviceCocktails.length,
                      score: _correctAnswers,
                      timerEnabled: _serviceTimerEnabled,
                      startedAt: _promptStartedAt,
                      revealed: _revealed,
                      onReveal: () {
                        setState(() {
                          _revealed = true;
                        });
                      },
                      onReview: _recordServiceAnswer,
                      onNext: _nextServicePrompt,
                      submitting: _submitting,
                    )
                  else
                    SurfaceSection(
                      eyebrow: _experience == _QuizExperience.passCheck
                          ? 'Service readiness check'
                          : _focusCocktailIds == null ||
                                _focusCocktailIds!.isEmpty
                          ? 'Spec check'
                          : 'Weak-spec retry',
                      title: 'Question ${_index + 1} of ${_questions.length}',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              MetricChip(
                                label: 'Correct',
                                value: '$_correctAnswers',
                              ),
                              MetricChip(
                                label: 'Accuracy',
                                value: _index == 0 && !_answered
                                    ? '--'
                                    : '${((_correctAnswers / ((_answered ? _index + 1 : _index).clamp(1, _questions.length))) * 100).round()}%',
                              ),
                              MetricChip(
                                label: 'Focus',
                                value: _question.topic.label,
                              ),
                              if (_priorityCocktailIds.contains(
                                _question.cocktailId,
                              ))
                                const MetricChip(
                                  label: 'Priority',
                                  value: 'Manager set',
                                ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          CocktailImageFrame(
                            cocktail: _question.cocktail,
                            width: double.infinity,
                            height: 220,
                            fit: BoxFit.contain,
                            borderRadius: const BorderRadius.all(
                              Radius.circular(24),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            _question.prompt,
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Cocktail: ${_question.cocktailName}',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 18),
                          for (
                            var i = 0;
                            i < _question.options.length;
                            i++
                          ) ...[
                            _AnswerButton(
                              text: _question.options[i],
                              selected: _selectedIndex == i,
                              correct: _question.correctIndex == i,
                              answered: _answered,
                              onTap: () => _answerQuestion(i),
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (_answered) ...[
                            const SizedBox(height: 14),
                            _FeedbackPanel(
                              isCorrect:
                                  _selectedIndex == _question.correctIndex,
                              explanation: _question.explanation,
                              correctAnswer: _question.correctAnswer,
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _submitting ? null : _nextQuestion,
                                icon: const Icon(Icons.chevron_right),
                                label: Text(
                                  _index == _questions.length - 1
                                      ? _experience == _QuizExperience.passCheck
                                            ? 'Finish pass check'
                                            : 'Finish spec check'
                                      : 'Next question',
                                ),
                              ),
                            ),
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

class _ModeSummaryView extends StatelessWidget {
  const _ModeSummaryView({
    required this.experience,
    required this.summary,
    required this.cocktails,
    required this.passMark,
    required this.onRestart,
    this.examResult,
    this.onRetryWeakAreas,
  });

  final _QuizExperience experience;
  final QuizSessionSummary summary;
  final List<Cocktail> cocktails;
  final ExamResult? examResult;
  final int passMark;
  final VoidCallback onRestart;
  final VoidCallback? onRetryWeakAreas;

  @override
  Widget build(BuildContext context) {
    final weakCocktailNames = summary.weakCocktailIds
        .map(
          (id) =>
              cocktails
                  .where((cocktail) => cocktail.id == id)
                  .firstOrNull
                  ?.name ??
              id,
        )
        .toList(growable: false);
    final passResult = examResult;

    return SurfaceSection(
      eyebrow: experience == _QuizExperience.passCheck
          ? 'Pass check complete'
          : experience == _QuizExperience.serviceMode
          ? 'Service drill complete'
          : 'Spec check complete',
      title: passResult != null
          ? '${passResult.percentage.round()}% ${passResult.passed ? 'Passed' : 'Needs another try'}'
          : '${(summary.accuracy * 100).round()}% accuracy',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              MetricChip(
                label: 'Questions',
                value: '${summary.totalQuestions}',
              ),
              MetricChip(label: 'Correct', value: '${summary.correctAnswers}'),
              MetricChip(
                label: 'Weak specs',
                value: '${summary.weakCocktailIds.length}',
              ),
              if (passResult != null)
                MetricChip(label: 'Pass mark', value: '$passMark%'),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            passResult != null
                ? passResult.passed
                      ? 'Pass check passed. This score is now saved to venue training records.'
                      : 'Pass check not passed yet. Review the weak drinks below and try again.'
                : experience == _QuizExperience.serviceMode
                ? 'Use the flagged drinks below to tighten speed and confidence before the next service drill.'
                : 'Use the weak drinks below to focus the next round.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          if (weakCocktailNames.isEmpty)
            Text(
              'No cocktails were flagged for extra review in this round.',
              style: Theme.of(context).textTheme.bodyLarge,
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final name in weakCocktailNames) Chip(label: Text(name)),
              ],
            ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (onRetryWeakAreas != null) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onRetryWeakAreas,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry weak drinks'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton.icon(
                  onPressed: onRestart,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    experience == _QuizExperience.passCheck
                        ? 'Start new pass check'
                        : experience == _QuizExperience.serviceMode
                        ? 'Start new service drill'
                        : 'Start new spec check',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ServiceModeCard extends StatelessWidget {
  const _ServiceModeCard({
    required this.cocktail,
    required this.currentIndex,
    required this.total,
    required this.score,
    required this.timerEnabled,
    required this.startedAt,
    required this.revealed,
    required this.onReveal,
    required this.onReview,
    required this.onNext,
    required this.submitting,
  });

  final Cocktail cocktail;
  final int currentIndex;
  final int total;
  final int score;
  final bool timerEnabled;
  final DateTime startedAt;
  final bool revealed;
  final VoidCallback onReveal;
  final ValueChanged<bool> onReview;
  final Future<void> Function() onNext;
  final bool submitting;

  @override
  Widget build(BuildContext context) {
    final elapsedSeconds = DateTime.now().difference(startedAt).inSeconds;

    return SurfaceSection(
      eyebrow: 'Service mode',
      title: 'Order $currentIndex of $total',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              MetricChip(label: 'Correct', value: '$score'),
              MetricChip(label: 'Prompt', value: cocktail.name),
              if (timerEnabled)
                MetricChip(label: 'Timer', value: '$elapsedSeconds s'),
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
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Order: ${cocktail.name}',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  'Call the build fast, then reveal the answer and mark whether you were right.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (revealed)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AnswerSpec(cocktail: cocktail),
                const SizedBox(height: 18),
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
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: submitting ? null : onNext,
                    icon: const Icon(Icons.chevron_right),
                    label: Text(
                      currentIndex == total ? 'Finish drill' : 'Next order',
                    ),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onReveal,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Reveal answer'),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnswerSpec extends StatelessWidget {
  const _AnswerSpec({required this.cocktail});

  final Cocktail cocktail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            MetricChip(label: 'Build', value: cocktail.buildStyleLabel),
            MetricChip(label: 'Glassware', value: cocktail.glassware),
            MetricChip(label: 'Garnish', value: cocktail.garnish),
          ],
        ),
        const SizedBox(height: 16),
        for (final ingredient in cocktail.ingredients)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              ingredient.displayMeasure.isEmpty
                  ? ingredient.name
                  : '${ingredient.displayMeasure} ${ingredient.name}',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
      ],
    );
  }
}

class _FeedbackPanel extends StatelessWidget {
  const _FeedbackPanel({
    required this.isCorrect,
    required this.explanation,
    required this.correctAnswer,
  });

  final bool isCorrect;
  final String explanation;
  final String correctAnswer;

  @override
  Widget build(BuildContext context) {
    final accent = isCorrect
        ? const Color(0xFF34D399)
        : const Color(0xFFF87171);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isCorrect ? 'Correct spec' : 'Needs another rep',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: accent),
          ),
          const SizedBox(height: 8),
          Text(
            'Correct answer: $correctAnswer',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 6),
          Text(explanation, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    required this.text,
    required this.selected,
    required this.correct,
    required this.answered,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final bool correct;
  final bool answered;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Color borderColor = Theme.of(
      context,
    ).colorScheme.primary.withValues(alpha: 0.14);
    Color backgroundColor = const Color(0xFF171F27);
    IconData? icon;

    if (answered && correct) {
      borderColor = const Color(0xFF34D399);
      backgroundColor = const Color(0x2234D399);
      icon = Icons.check_circle;
    } else if (answered && selected && !correct) {
      borderColor = const Color(0xFFF87171);
      backgroundColor = const Color(0x22F87171);
      icon = Icons.cancel;
    }

    return InkWell(
      onTap: answered ? null : onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text.isEmpty ? 'Not listed' : text,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 12),
              Icon(icon, color: borderColor),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuizMessage extends StatelessWidget {
  const _QuizMessage({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return SurfaceSection(
      eyebrow: 'Quiz mode',
      title: title,
      child: Text(message, style: Theme.of(context).textTheme.bodyLarge),
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

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
