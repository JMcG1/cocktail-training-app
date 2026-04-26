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

class QuizModeScreen extends StatefulWidget {
  const QuizModeScreen({super.key, required this.cocktails});

  final List<Cocktail> cocktails;

  @override
  State<QuizModeScreen> createState() => _QuizModeScreenState();
}

class _QuizModeScreenState extends State<QuizModeScreen> {
  final TrainingProgressService _progressService = TrainingProgressService.instance;
  final QuizEngine _quizEngine = QuizEngine();

  List<QuizQuestion> _questions = const [];
  int _index = 0;
  int _correctAnswers = 0;
  int? _selectedIndex;
  bool _answered = false;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  QuizSessionSummary? _summary;
  final Set<String> _missedCocktailIds = <String>{};
  final Set<QuizTopic> _missedTopics = <QuizTopic>{};
  Set<String>? _focusCocktailIds;

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  Future<void> _startSession({Set<String>? focusCocktailIds}) async {
    if (widget.cocktails.isEmpty) {
      setState(() {
        _questions = const [];
        _loading = false;
      });
      return;
    }

    try {
      await _progressService.startSession(TrainingSessionType.quiz);
      final progress = await _progressService.loadProgress();
      final questions = _quizEngine.buildSession(
        cocktails: widget.cocktails,
        progress: progress,
        focusCocktailIds: focusCocktailIds,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _questions = questions;
        _focusCocktailIds = focusCocktailIds;
        _index = 0;
        _correctAnswers = 0;
        _selectedIndex = null;
        _answered = false;
        _loading = false;
        _submitting = false;
        _summary = null;
        _error = null;
        _missedCocktailIds.clear();
        _missedTopics.clear();
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Quiz mode could not load a training session right now.';
        _loading = false;
      });
    }
  }

  QuizQuestion get _question => _questions[_index];

  Future<void> _answer(int index) async {
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
      await _progressService.recordQuizAnswer(
        cocktailId: question.cocktailId,
        topic: question.topic,
        isCorrect: isCorrect,
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
      });
      return;
    }

    final summary = QuizSessionSummary(
      totalQuestions: _questions.length,
      correctAnswers: _correctAnswers,
      weakCocktailIds: _missedCocktailIds.toList()..sort(),
      weakTopics: _missedTopics.toList()..sort((a, b) => a.index.compareTo(b.index)),
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
                    'Answer service-style questions across glassware, garnish, ingredients, method, and build style.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 22),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_error != null)
                    _QuizMessage(
                      title: 'Quiz mode unavailable',
                      message: _error!,
                    )
                  else if (_questions.isEmpty)
                    const _QuizMessage(
                      title: 'Not enough quiz data',
                      message: 'The current cocktail dataset does not have enough spec detail to build a multiple-choice round yet.',
                    )
                  else if (_summary != null)
                    _QuizSummaryView(
                      summary: _summary!,
                      cocktails: widget.cocktails,
                      onRetryWeakAreas: _missedCocktailIds.isEmpty
                          ? null
                          : () => _startSession(focusCocktailIds: _missedCocktailIds),
                      onStartFreshRound: () => _startSession(),
                    )
                  else
                    SurfaceSection(
                      eyebrow: _focusCocktailIds == null || _focusCocktailIds!.isEmpty
                          ? 'Live quiz'
                          : 'Weak-area retry',
                      title: 'Question ${_index + 1} of ${_questions.length}',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              MetricChip(label: 'Score', value: '$_correctAnswers'),
                              MetricChip(
                                label: 'Accuracy',
                                value: _index == 0 && !_answered
                                    ? '--'
                                    : '${((_correctAnswers / ((_answered ? _index + 1 : _index).clamp(1, _questions.length))) * 100).round()}%',
                              ),
                              MetricChip(label: 'Focus', value: _question.topic.label),
                            ],
                          ),
                          const SizedBox(height: 18),
                          CocktailImageFrame(
                            cocktail: _question.cocktail,
                            width: double.infinity,
                            height: 220,
                            fit: BoxFit.contain,
                            borderRadius: const BorderRadius.all(Radius.circular(24)),
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
                          for (var i = 0; i < _question.options.length; i++) ...[
                            _AnswerButton(
                              text: _question.options[i],
                              selected: _selectedIndex == i,
                              correct: _question.correctIndex == i,
                              answered: _answered,
                              onTap: () => _answer(i),
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (_answered) ...[
                            const SizedBox(height: 14),
                            _FeedbackPanel(
                              isCorrect: _selectedIndex == _question.correctIndex,
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
                                  _index == _questions.length - 1 ? 'Finish round' : 'Next question',
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

class _QuizSummaryView extends StatelessWidget {
  const _QuizSummaryView({
    required this.summary,
    required this.cocktails,
    required this.onStartFreshRound,
    this.onRetryWeakAreas,
  });

  final QuizSessionSummary summary;
  final List<Cocktail> cocktails;
  final VoidCallback onStartFreshRound;
  final VoidCallback? onRetryWeakAreas;

  @override
  Widget build(BuildContext context) {
    final weakCocktailNames = summary.weakCocktailIds
        .map((id) => cocktails.where((cocktail) => cocktail.id == id).firstOrNull?.name ?? id)
        .toList(growable: false);

    return SurfaceSection(
      eyebrow: 'Round complete',
      title: '${(summary.accuracy * 100).round()}% accuracy',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              MetricChip(label: 'Questions', value: '${summary.totalQuestions}'),
              MetricChip(label: 'Correct', value: '${summary.correctAnswers}'),
              MetricChip(label: 'Needs review', value: '${summary.weakCocktailIds.length}'),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            summary.weakTopics.isEmpty
                ? 'Strong round. No weak topics were flagged in this session.'
                : 'Topics to revisit: ${summary.weakTopics.map((topic) => topic.label).join(', ')}.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          if (weakCocktailNames.isEmpty)
            Text(
              'No cocktails were flagged for extra review this round.',
              style: Theme.of(context).textTheme.bodyLarge,
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final name in weakCocktailNames)
                  Chip(
                    label: Text(name),
                  ),
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
                    label: const Text('Retry weak areas'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton.icon(
                  onPressed: onStartFreshRound,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start fresh round'),
                ),
              ),
            ],
          ),
        ],
      ),
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
    final accent = isCorrect ? const Color(0xFF34D399) : const Color(0xFFF87171);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accent.withValues(alpha: 0.38),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isCorrect ? 'Correct' : 'Not quite',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: accent,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Answer: $correctAnswer',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 6),
          Text(
            explanation,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
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
    Color borderColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.14);
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
  const _QuizMessage({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return SurfaceSection(
      eyebrow: 'Quiz mode',
      title: title,
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
