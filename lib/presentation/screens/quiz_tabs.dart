import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/browser_connectivity.dart';
import '../../core/utils/variance_math.dart';
import '../../domain/models/models.dart';
import '../controllers/app_controller.dart';

typedef QuizLinkBuilder = String Function(QuizSession session);
typedef QuizShareDialogOpener =
    Future<void> Function(BuildContext context, String title, String url);
typedef QuizHomeBuilder = Widget Function();
typedef QuizSubmitHandler =
    Future<QuizAttempt> Function(
      Map<String, String> answers,
      Map<String, QuizAnswerConfidence> confidenceByQuestionId,
      DateTime startedAt,
    );

class QuizModeTab extends StatefulWidget {
  const QuizModeTab({
    super.key,
    required this.controller,
    required this.buildQuizLink,
    required this.openShareDialog,
  });

  final AppController controller;
  final QuizLinkBuilder buildQuizLink;
  final QuizShareDialogOpener openShareDialog;

  @override
  State<QuizModeTab> createState() => _QuizModeTabState();
}

class _QuizModeTabState extends State<QuizModeTab> {
  QuizSession? _activeSession;
  QuizAttempt? _completedAttempt;
  QuizFocus _selectedPracticeFocus = QuizFocus.specs;

  void _startPracticeQuiz(String bartenderName, {QuizFocus? focus}) {
    setState(() {
      _completedAttempt = null;
      _selectedPracticeFocus = focus ?? _selectedPracticeFocus;
      _activeSession = widget.controller.generatePracticeQuiz(
        bartenderName: bartenderName,
        focus: _selectedPracticeFocus,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bartenderName =
        widget.controller.currentUser?.displayName ?? 'Bartender';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _QuizHeaderCard(
          title: 'Quiz mode',
          subtitle:
              'A faster, more guided bartender assessment with confidence tracking, clear progress, and saved coaching insight.',
        ),
        const SizedBox(height: 16),
        if (!widget.controller.usingFirebase) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'In this version, quiz results stay on this device.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_completedAttempt != null) ...[
          _AttemptSummaryCard(
            attempt: _completedAttempt!,
            controller: widget.controller,
            onRetry: () => _startPracticeQuiz(
              bartenderName,
              focus: _completedAttempt!.responses.any(
                    (response) =>
                        response.question.kind == QuestionKind.garnish ||
                        response.question.kind == QuestionKind.glassware,
                  )
                  ? QuizFocus.garnishGlassware
                  : QuizFocus.specs,
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_activeSession == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Start a professional practice round',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _selectedPracticeFocus == QuizFocus.specs
                        ? 'Specs rounds mix measures, cocktail identification, ingredient checks, and build style prompts from the approved library.'
                        : 'Service rounds focus on garnish and glassware so bartenders can tighten the final serve details.',
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<QuizFocus>(
                    segments: const [
                      ButtonSegment<QuizFocus>(
                        value: QuizFocus.specs,
                        label: Text('Specs'),
                      ),
                      ButtonSegment<QuizFocus>(
                        value: QuizFocus.garnishGlassware,
                        label: Text('Garnish & glass'),
                      ),
                    ],
                    selected: {_selectedPracticeFocus},
                    onSelectionChanged: (selection) {
                      setState(() {
                        _selectedPracticeFocus = selection.first;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _startPracticeQuiz(bartenderName),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      _selectedPracticeFocus == QuizFocus.specs
                          ? 'Start specs quiz'
                          : 'Start garnish and glass quiz',
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Column(
            children: [
              if (widget.controller.usingFirebase) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Text(
                            'Share this quiz with a live link or QR code while the session is active.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final shareUrl = widget.buildQuizLink(
                              _activeSession!,
                            );
                            await widget.openShareDialog(
                              context,
                              'Share quiz link',
                              shareUrl,
                            );
                          },
                          icon: const Icon(Icons.qr_code_2),
                          label: const Text('Show QR code'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _QuizSessionCard(
                session: _activeSession!,
                bartenderName: bartenderName,
                controller: widget.controller,
                onSubmit: (
                  answers,
                  confidenceByQuestionId,
                  startedAt,
                ) {
                  return widget.controller.submitQuizAttempt(
                    sessionId: _activeSession!.id,
                    bartenderName: bartenderName,
                    answers: answers,
                    confidenceByQuestionId: confidenceByQuestionId,
                    startedAt: startedAt,
                  );
                },
                onCompleted: (attempt) {
                  setState(() {
                    _completedAttempt = attempt;
                    _activeSession = null;
                  });
                },
              ),
            ],
          ),
      ],
    );
  }
}

class BartenderQuizScreen extends StatefulWidget {
  const BartenderQuizScreen({
    super.key,
    required this.controller,
    required this.sessionId,
    required this.homeBuilder,
  });

  final AppController controller;
  final String sessionId;
  final QuizHomeBuilder homeBuilder;

  @override
  State<BartenderQuizScreen> createState() => _BartenderQuizScreenState();
}

class _BartenderQuizScreenState extends State<BartenderQuizScreen> {
  QuizSession? _session;
  bool _loading = true;
  String? _error;
  QuizAttempt? _completedAttempt;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final session =
          widget.controller.findQuizSession(widget.sessionId) ??
          await widget.controller.fetchQuizSession(widget.sessionId);
      if (!mounted) {
        return;
      }
      setState(() {
        _session = session;
        _loading = false;
        if (session == null) {
          _error = 'This quiz is no longer available.';
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _returnHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => widget.homeBuilder()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bartenderName =
        widget.controller.currentUser?.displayName ?? 'Bartender';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _returnHome();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cocktail quiz'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _returnHome,
          ),
        ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : _completedAttempt != null
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _AttemptSummaryCard(
                      attempt: _completedAttempt!,
                      controller: widget.controller,
                      onRetry: _returnHome,
                      retryLabel: 'Back to quiz home',
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _QuizSessionCard(
                      session: _session!,
                      bartenderName: bartenderName,
                      controller: widget.controller,
                      onSubmit: (
                        answers,
                        confidenceByQuestionId,
                        startedAt,
                      ) {
                        return widget.controller.submitQuizAttempt(
                          sessionId: _session!.id,
                          bartenderName: bartenderName,
                          answers: answers,
                          confidenceByQuestionId: confidenceByQuestionId,
                          startedAt: startedAt,
                        );
                      },
                      onCompleted: (attempt) {
                        setState(() {
                          _completedAttempt = attempt;
                        });
                      },
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _QuizSessionCard extends StatefulWidget {
  const _QuizSessionCard({
    required this.session,
    required this.bartenderName,
    required this.controller,
    required this.onSubmit,
    required this.onCompleted,
  });

  final QuizSession session;
  final String bartenderName;
  final AppController controller;
  final QuizSubmitHandler onSubmit;
  final ValueChanged<QuizAttempt> onCompleted;

  @override
  State<_QuizSessionCard> createState() => _QuizSessionCardState();
}

class _QuizSessionCardState extends State<_QuizSessionCard> {
  final Map<String, String> _answers = {};
  final Map<String, QuizAnswerConfidence> _confidenceByQuestionId = {};
  late final DateTime _startedAt;
  int _currentQuestionIndex = 0;
  bool _isSubmitting = false;
  String? _submitStatus;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
  }

  bool get _allAnswered => widget.session.questions.every(
    (question) => (_answers[question.id] ?? '').trim().isNotEmpty,
  );

  bool get _allConfidenceCaptured => widget.session.questions.every(
    (question) => _confidenceByQuestionId.containsKey(question.id),
  );

  Future<void> _submit() async {
    if (_isSubmitting || !_allAnswered || !_allConfidenceCaptured) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _submitStatus = 'Marking quiz...';
    });
    try {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final attempt = await widget.onSubmit(
        _answers,
        _confidenceByQuestionId,
        _startedAt,
      );
      if (!mounted) {
        return;
      }
      final summary = VarianceMath.buildSalesImpactSummary(
        attempt: attempt,
        recipesById: widget.controller.recipesById,
        ingredientsByName: widget.controller.ingredientsByName,
        batches: widget.controller.batches,
      );
      setState(() => _submitStatus = 'Checking results...');
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted) {
        return;
      }
      setState(() => _submitStatus = 'Saving result...');
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted) {
        return;
      }
      await showQuizResultsDialog(context, attempt, summary);
      if (!mounted) {
        return;
      }
      widget.onCompleted(attempt);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
      setState(() {
        _isSubmitting = false;
        _submitStatus = null;
      });
      return;
    }
    if (mounted) {
      setState(() {
        _isSubmitting = false;
        _submitStatus = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final question = session.questions[_currentQuestionIndex];
    final answeredCount = session.questions
        .where((item) => (_answers[item.id] ?? '').trim().isNotEmpty)
        .length;
    final progress = session.questions.isEmpty
        ? 0.0
        : answeredCount / session.questions.length;
    final currentConfidence = _confidenceByQuestionId[question.id];
    final currentAnswer = _answers[question.id];
    final canMoveForward =
        (currentAnswer ?? '').trim().isNotEmpty && currentConfidence != null;
    final canSubmit = _allAnswered && _allConfidenceCaptured && !_isSubmitting;
    final isOnline = BrowserConnectivity.isOnline();
    final syncStatus = widget.controller.trainingSyncStatus;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Question ${_currentQuestionIndex + 1} of ${session.questions.length}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: progress),
              duration: const Duration(milliseconds: 300),
              builder: (context, value, child) {
                return LinearProgressIndicator(value: value, minHeight: 10);
              },
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('$answeredCount answered')),
                Chip(
                  label: Text(
                    '${session.questions.length - answeredCount} left',
                  ),
                ),
                _SummaryTag(label: _quizFocusSupportLabel(session.focus)),
              ],
            ),
            const SizedBox(height: 12),
            _SyncStatusBanner(isOnline: isOnline, syncStatus: syncStatus),
            const SizedBox(height: 20),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _QuizQuestionCard(
                key: ValueKey(question.id),
                questionNumber: _currentQuestionIndex + 1,
                question: question,
                selectedAnswer: currentAnswer,
                confidence: currentConfidence,
                onAnswerChanged: (answer) {
                  setState(() {
                    _answers[question.id] = answer;
                  });
                },
                onConfidenceChanged: (confidence) {
                  setState(() {
                    _confidenceByQuestionId[question.id] = confidence;
                  });
                },
              ),
            ),
            const SizedBox(height: 20),
            if (_isSubmitting || _submitStatus != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(
                    alpha: 0.08,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    if (_isSubmitting)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(Icons.check_circle_outline),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _submitStatus ?? 'Working...',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
              ),
            if (_isSubmitting || _submitStatus != null)
              const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _isSubmitting || _currentQuestionIndex == 0
                      ? null
                      : () {
                          setState(() {
                            _currentQuestionIndex -= 1;
                          });
                        },
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Previous'),
                ),
                if (_currentQuestionIndex < session.questions.length - 1)
                  FilledButton.icon(
                    onPressed: _isSubmitting || !canMoveForward
                        ? null
                        : () {
                            setState(() {
                              _currentQuestionIndex += 1;
                            });
                          },
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Next'),
                  )
                else
                  FilledButton.icon(
                    onPressed: canSubmit ? _submit : null,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.assignment_turned_in),
                    label: Text(_isSubmitting ? 'Submitting...' : 'Submit quiz'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showQuizResultsDialog(
  BuildContext context,
  QuizAttempt attempt,
  QuizSalesImpactSummary summary,
) {
  final improvement = attempt.improvementScorePercent;
  final durationLabel = _formatDuration(attempt.duration);
  final currency = NumberFormat.currency(symbol: '£', decimalDigits: 2);
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Results ready',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  if (attempt.scorePercent >= 90) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.celebration),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Outstanding. Service ready.',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _ResultMetricPill(
                        label: 'Score',
                        value: '${attempt.scorePercent}%',
                      ),
                      _ResultMetricPill(
                        label: 'Correct',
                        value:
                            '${attempt.correctAnswerCount}/${attempt.responses.length}',
                      ),
                      _ResultMetricPill(
                        label: 'Status',
                        value: attempt.passed ? 'Pass' : 'Needs work',
                      ),
                      _ResultMetricPill(
                        label: 'Time',
                        value: durationLabel,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    attempt.previousBestScorePercent == null
                        ? 'Previous best: First recorded quiz'
                        : 'Previous best: ${attempt.previousBestScorePercent}%',
                  ),
                  Text(
                    improvement == null
                        ? 'Improvement: Ready to baseline from this result'
                        : 'Improvement: ${improvement >= 0 ? '+' : ''}$improvement%',
                  ),
                  const SizedBox(height: 12),
                  _ImpactHeadline(summary: summary),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      summary.totalIngredientCostImpactGbp > 0
                          ? 'Quiz attempt saved. Potential overpour stock cost in this round: ${currency.format(summary.totalIngredientCostImpactGbp)}.'
                          : 'Quiz attempt saved successfully.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Continue'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _AttemptSummaryCard extends StatelessWidget {
  const _AttemptSummaryCard({
    required this.attempt,
    required this.controller,
    this.onRetry,
    this.retryLabel = 'Start another quiz',
  });

  final QuizAttempt attempt;
  final AppController controller;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final summary = VarianceMath.buildSalesImpactSummary(
      attempt: attempt,
      recipesById: controller.recipesById,
      ingredientsByName: controller.ingredientsByName,
      batches: controller.batches,
    );
    final feedback = controller.buildStudyFeedbackSummary();
    final improvement = attempt.improvementScorePercent;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Latest result',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ResultMetricPill(
                  label: 'Score',
                  value: '${attempt.scorePercent}%',
                ),
                _ResultMetricPill(
                  label: 'Correct',
                  value: '${attempt.correctAnswerCount}/${attempt.responses.length}',
                ),
                _ResultMetricPill(
                  label: 'Status',
                  value: attempt.passed ? 'Pass' : 'Needs work',
                ),
                _ResultMetricPill(
                  label: 'Time',
                  value: _formatDuration(attempt.duration),
                ),
                _ResultMetricPill(
                  label: 'Previous best',
                  value: attempt.previousBestScorePercent == null
                      ? 'First round'
                      : '${attempt.previousBestScorePercent}%',
                ),
                _ResultMetricPill(
                  label: 'Improvement',
                  value: improvement == null
                      ? 'Baseline set'
                      : '${improvement >= 0 ? '+' : ''}$improvement%',
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SummaryTag(label: _attemptFocusLabel(attempt)),
                if (attempt.highConfidenceMissCount > 0)
                  _SummaryTag(
                    label:
                        '${attempt.highConfidenceMissCount} high-confidence miss${attempt.highConfidenceMissCount == 1 ? '' : 'es'}',
                  ),
                if (attempt.scorePercent >= 90)
                  const _SummaryTag(label: 'Achievement unlocked'),
              ],
            ),
            const SizedBox(height: 12),
            Text(feedback.nextStep),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SummaryTag(
                  label: 'Next deck: ${feedback.recommendedDeckLabel}',
                ),
                for (final cocktail in feedback.focusCocktails.take(2))
                  _SummaryTag(label: cocktail),
              ],
            ),
            const SizedBox(height: 16),
            _ImpactHeadline(summary: summary),
            const SizedBox(height: 16),
            _QuizReviewSummary(responses: attempt.responses),
            const SizedBox(height: 16),
            _QuizImpactSummary(attempt: attempt, summary: summary),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(retryLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultMetricPill extends StatelessWidget {
  const _ResultMetricPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 132, maxWidth: 220),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge,
              softWrap: true,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium,
              softWrap: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryTag extends StatelessWidget {
  const _SummaryTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        softWrap: true,
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

class _ImpactHeadline extends StatelessWidget {
  const _ImpactHeadline({required this.summary});

  final QuizSalesImpactSummary summary;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '£', decimalDigits: 2);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Potential overpour stock cost: ${currency.format(summary.totalIngredientCostImpactGbp)}',
            style: Theme.of(context).textTheme.titleSmall,
            softWrap: true,
          ),
          const SizedBox(height: 4),
          Text(
            'Potential sales value affected: ${currency.format(summary.totalRecoverableRevenueGbp)}',
            softWrap: true,
          ),
          const SizedBox(height: 4),
          Text(
            'Sales basis used: ${summary.totalExposureCocktails} cocktails worth about ${currency.format(summary.totalExposureSalesValueGbp)}.',
            style: Theme.of(context).textTheme.bodySmall,
            softWrap: true,
          ),
        ],
      ),
    );
  }
}

class _QuizReviewSummary extends StatelessWidget {
  const _QuizReviewSummary({required this.responses});

  final List<QuestionResponse> responses;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Detailed review',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ...responses.map(
          (response) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: response.isCorrect
                      ? Colors.green.withValues(alpha: 0.35)
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    response.question.cocktailName,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _questionKindLabel(response.question.kind),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Text('Question: ${response.question.prompt}'),
                  const SizedBox(height: 8),
                  Text(
                    'Your answer: ${response.selectedAnswer.isEmpty ? 'No answer saved' : response.selectedAnswer}',
                  ),
                  Text('Correct answer: ${response.question.correctAnswer}'),
                  Text(
                    'Confidence: ${_confidenceLabel(response.confidence)}',
                  ),
                  const SizedBox(height: 6),
                  Text('Why this matters: ${response.question.explanation}'),
                  if (response.isHighConfidenceMiss) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Coaching opportunity: this was answered with high confidence but was incorrect, so it is worth revisiting before the next shift.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuizQuestionCard extends StatelessWidget {
  const _QuizQuestionCard({
    super.key,
    required this.questionNumber,
    required this.question,
    required this.selectedAnswer,
    required this.confidence,
    required this.onAnswerChanged,
    required this.onConfidenceChanged,
  });

  final int questionNumber;
  final QuizQuestion question;
  final String? selectedAnswer;
  final QuizAnswerConfidence? confidence;
  final ValueChanged<String> onAnswerChanged;
  final ValueChanged<QuizAnswerConfidence> onConfidenceChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.surface,
            Theme.of(context).colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.5,
            ),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((question.imageAssetPath ?? '').trim().isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                question.imageAssetPath!,
                height: 170,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('Q$questionNumber')),
              Chip(label: Text(question.cocktailName)),
              Chip(label: Text(_questionKindLabel(question.kind))),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            question.prompt,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            _questionSupportCopy(question),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          ...question.options.map(
            (option) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onAnswerChanged(option),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selectedAnswer == option
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                    color: selectedAnswer == option
                        ? Theme.of(context).colorScheme.primary.withValues(
                            alpha: 0.08,
                          )
                        : null,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selectedAnswer == option
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(option)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'How confident were you?',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: QuizAnswerConfidence.values.map((option) {
              final selected = confidence == option;
              return ChoiceChip(
                label: Text(_confidenceLabel(option)),
                selected: selected,
                onSelected: (_) => onConfidenceChanged(option),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _QuizImpactSummary extends StatelessWidget {
  const _QuizImpactSummary({
    required this.attempt,
    required this.summary,
  });

  final QuizAttempt attempt;
  final QuizSalesImpactSummary summary;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '£', decimalDigits: 2);
    final overpours = summary.lines
        .where((line) => line.direction == VarianceDirection.overpour)
        .toList();
    final underpours = summary.lines
        .where((line) => line.direction == VarianceDirection.underpour)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(attempt.encouragement),
        if (overpours.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Overpour cost and stock impact',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Checked against ${summary.totalExposureCocktails} recorded cocktail sales worth about ${currency.format(summary.totalExposureSalesValueGbp)}.',
          ),
          ...overpours.map(
            (line) => Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${line.cocktailName} · ${line.ingredientName}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Correct spec variance: +${line.errorMlPerServe.toStringAsFixed(0)}ml across ${line.quantitySold} sales',
                    ),
                    Text(
                      'Total wasted: ${line.totalErrorMl.toStringAsFixed(0)}ml',
                    ),
                    Text(
                      'Cocktails lost: ${line.recoverableCocktails.toStringAsFixed(2)}',
                    ),
                    Text(
                      'Stock cost: ${currency.format(line.ingredientCostImpactGbp)}',
                    ),
                    Text(
                      'Potential sales value affected: ${currency.format(line.recoverableRevenueGbp)}',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Because ${line.totalErrorMl.toStringAsFixed(0)}ml of ${line.ingredientName} was overpoured, enough stock was lost to make ${line.recoverableCocktails.toStringAsFixed(2)} additional ${line.cocktailName}. This represents ${currency.format(line.ingredientCostImpactGbp)} in stock cost and could affect up to ${currency.format(line.recoverableRevenueGbp)} of cocktail sales.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        if (underpours.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Guest experience impact',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ...underpours.map(
            (line) => Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${line.cocktailName} · ${line.ingredientName}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Under by ${line.errorMlPerServe.toStringAsFixed(0)}ml per serve',
                    ),
                    Text(
                      'The cocktail would be weaker than specification and may not meet guest expectations. Flavour balance is affected, consistency drops, and the drink may not leave the bar to brand standard.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _QuizHeaderCard extends StatelessWidget {
  const _QuizHeaderCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

String _quizFocusSupportLabel(QuizFocus focus) {
  return switch (focus) {
    QuizFocus.specs => 'Specs focus',
    QuizFocus.garnishGlassware => 'Garnish & glass',
  };
}

String _questionKindLabel(QuestionKind kind) {
  return switch (kind) {
    QuestionKind.ingredientMeasure => 'Measure',
    QuestionKind.ingredientChoice => 'Ingredient',
    QuestionKind.missingIngredient => 'Missing ingredient',
    QuestionKind.cocktailByIngredient => 'Cocktail match',
    QuestionKind.garnish => 'Garnish',
    QuestionKind.glassware => 'Glassware',
    QuestionKind.method => 'Method',
    QuestionKind.methodOrder => 'Method order',
    QuestionKind.batchAmount => 'Batch amount',
  };
}

String _questionSupportCopy(QuizQuestion question) {
  return switch (question.kind) {
    QuestionKind.ingredientMeasure =>
      'Pick the exact ml spec for ${question.ingredientName ?? 'this ingredient'}.',
    QuestionKind.batchAmount =>
      'Treat batch amounts like any other measured ingredient.',
    QuestionKind.garnish =>
      'Choose the garnish that should leave the bar with this drink.',
    QuestionKind.glassware =>
      'Choose the glass the bartender should serve this cocktail in.',
    QuestionKind.ingredientChoice =>
      'Choose the ingredient that belongs in the approved spec.',
    QuestionKind.missingIngredient =>
      'Spot the ingredient missing from the approved spec.',
    QuestionKind.cocktailByIngredient =>
      'Match the spec clue to the right approved cocktail.',
    QuestionKind.method =>
      'Choose the approved method for this cocktail.',
    QuestionKind.methodOrder =>
      'Choose the next step in the approved service sequence.',
  };
}

String _attemptFocusLabel(QuizAttempt attempt) {
  final hasServiceQuestions = attempt.responses.any(
    (response) =>
        response.question.kind == QuestionKind.garnish ||
        response.question.kind == QuestionKind.glassware,
  );
  return hasServiceQuestions ? 'Garnish & glass round' : 'Specs round';
}

String _confidenceLabel(QuizAnswerConfidence confidence) {
  return switch (confidence) {
    QuizAnswerConfidence.guessing => 'Guessing',
    QuizAnswerConfidence.unsure => 'Unsure',
    QuizAnswerConfidence.fairlySure => 'Fairly Sure',
    QuizAnswerConfidence.certain => 'Certain',
  };
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
}

class _SyncStatusBanner extends StatelessWidget {
  const _SyncStatusBanner({
    required this.isOnline,
    required this.syncStatus,
  });

  final bool isOnline;
  final TrainingSyncStatus syncStatus;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = !isOnline || syncStatus.quizReadsFromCache
        ? colorScheme.tertiaryContainer
        : colorScheme.secondaryContainer;
    final message = !isOnline
        ? 'Offline right now. Saved progress will catch up once you reconnect.'
        : syncStatus.quizReadsFromCache
        ? 'Showing saved quiz data. ${syncStatus.lastQuizSyncMessage}'
        : syncStatus.lastQuizSyncMessage;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(message),
    );
  }
}
