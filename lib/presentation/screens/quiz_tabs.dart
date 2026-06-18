import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/variance_math.dart';
import '../../domain/models/models.dart';
import '../controllers/app_controller.dart';

typedef QuizLinkBuilder = String Function(QuizSession session);
typedef QuizShareDialogOpener =
    Future<void> Function(BuildContext context, String title, String url);
typedef QuizHomeBuilder = Widget Function();

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
  Map<String, String> _answers = {};
  QuizAttempt? _completedAttempt;
  QuizFocus _selectedPracticeFocus = QuizFocus.specs;

  void _startPracticeQuiz(String bartenderName, {QuizFocus? focus}) {
    setState(() {
      _completedAttempt = null;
      _answers = {};
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
              'Questions are generated from the approved cocktail and batch specs only. Batch amounts are treated like ingredients.',
        ),
        const SizedBox(height: 16),
        if (!widget.controller.usingFirebase) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Demo mode keeps quizzes on this device only. Shareable quiz links and QR codes appear when the app is running in Firebase mode.',
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
                    (response) => response.question.kind == QuestionKind.garnish ||
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
                    'Start a quick quiz',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _selectedPracticeFocus == QuizFocus.specs
                        ? 'Specs quiz focuses on measures and batch amounts from approved recipes.'
                        : 'Garnish and glass quiz checks service details without mixing in spec-measure questions.',
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
                  ElevatedButton(
                    onPressed: () => _startPracticeQuiz(bartenderName),
                    child: Text(
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
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'This quiz can be shared with a live link or QR code while the session stays active.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: 12),
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
                answers: _answers,
                onAnswerChanged: (questionId, answer) {
                  setState(() => _answers[questionId] = answer);
                },
                onSubmit: () {
                  final attempt = widget.controller.submitQuizAttempt(
                    sessionId: _activeSession!.id,
                    bartenderName: bartenderName,
                    answers: _answers,
                  );
                  setState(() {
                    _completedAttempt = attempt;
                    _activeSession = null;
                    _answers = {};
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
  final Map<String, String> _answers = {};
  QuizAttempt? _completedAttempt;
  QuizSalesImpactSummary? _completedSummary;

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
        _error = error.toString();
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
              : _completedAttempt != null && _completedSummary != null
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
              : _QuizSessionCard(
                  session: _session!,
                  answers: _answers,
                  onAnswerChanged: (questionId, answer) {
                    setState(() => _answers[questionId] = answer);
                  },
                  onSubmit: () {
                    final attempt = widget.controller.submitQuizAttempt(
                      sessionId: _session!.id,
                      bartenderName: bartenderName,
                      answers: _answers,
                    );
                    final summary = VarianceMath.buildSalesImpactSummary(
                      attempt: attempt,
                      recipesById: widget.controller.recipesById,
                      ingredientsByName: widget.controller.ingredientsByName,
                      batches: widget.controller.batches,
                    );
                    setState(() {
                      _completedAttempt = attempt;
                      _completedSummary = summary;
                    });
                  },
                ),
        ),
      ),
    );
  }
}

class _QuizSessionCard extends StatelessWidget {
  const _QuizSessionCard({
    required this.session,
    required this.answers,
    required this.onAnswerChanged,
    required this.onSubmit,
  });

  final QuizSession session;
  final Map<String, String> answers;
  final void Function(String questionId, String answer) onAnswerChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final answeredCount = session.questions
        .where((question) => (answers[question.id] ?? '').isNotEmpty)
        .length;
    final allAnswered = session.questions.every(
      (question) => (answers[question.id] ?? '').isNotEmpty,
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '${session.questions.length} approved questions · ${_quizFocusLabel(session.focus)}',
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: session.questions.isEmpty
                    ? 0
                    : answeredCount / session.questions.length,
              ),
              const SizedBox(height: 8),
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
                  Chip(label: Text(_quizFocusSupportLabel(session.focus))),
                ],
              ),
              const SizedBox(height: 20),
              for (var index = 0; index < session.questions.length; index += 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: _QuizQuestionCard(
                    questionNumber: index + 1,
                    question: session.questions[index],
                    selectedAnswer: answers[session.questions[index].id],
                    onAnswerChanged: onAnswerChanged,
                  ),
                ),
              ElevatedButton(
                onPressed: allAnswered ? onSubmit : null,
                child: const Text('Submit quiz'),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
    final correctCount = attempt.responses.where((response) => response.isCorrect).length;
    final incorrectCount = attempt.responses.length - correctCount;
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
            Text(
              '${attempt.scorePercent}%',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('$correctCount correct')),
                Chip(label: Text('$incorrectCount to revisit')),
                Chip(label: Text(_attemptFocusLabel(attempt))),
              ],
            ),
            const SizedBox(height: 10),
            Text(feedback.nextStep),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Next deck: ${feedback.recommendedDeckLabel}')),
                for (final cocktail in feedback.focusCocktails.take(2))
                  Chip(label: Text(cocktail)),
              ],
            ),
            const SizedBox(height: 12),
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

class _QuizQuestionCard extends StatelessWidget {
  const _QuizQuestionCard({
    required this.questionNumber,
    required this.question,
    required this.selectedAnswer,
    required this.onAnswerChanged,
  });

  final int questionNumber;
  final QuizQuestion question;
  final String? selectedAnswer;
  final void Function(String questionId, String answer) onAnswerChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('Q$questionNumber')),
              Chip(label: Text(question.cocktailName)),
              Chip(label: Text(_questionKindLabel(question.kind))),
            ],
          ),
          const SizedBox(height: 10),
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
                onTap: () => onAnswerChanged(question.id, option),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selectedAnswer == option
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                    color: selectedAnswer == option
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(attempt.encouragement),
        if (summary.lines.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Sales impact from this quiz',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Checked against ${summary.totalExposureCocktails} recorded cocktail sales worth about ${currency.format(summary.totalExposureSalesValueGbp)}.',
          ),
          Text(
            'Ingredient cost impact: ${currency.format(summary.totalIngredientCostImpactGbp)}',
          ),
          Text(
            'Extra cocktails hidden in the error volume: ${summary.totalRecoverableCocktails.toStringAsFixed(2)}',
          ),
          Text(
            'Estimated sales value of those cocktails: ${currency.format(summary.totalRecoverableRevenueGbp)}',
          ),
          const SizedBox(height: 12),
          ...summary.lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
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
                      '${line.direction == VarianceDirection.overpour ? 'Over' : 'Under'} by ${line.errorMlPerServe.toStringAsFixed(0)}ml per serve across ${line.quantitySold} sold',
                    ),
                    Text(
                      'Recorded exposure value: ${currency.format(line.exposureSalesValueGbp)}',
                    ),
                    Text(
                      'Total volume impact: ${line.totalErrorMl.toStringAsFixed(0)}ml',
                    ),
                    Text(
                      'Direct ingredient cost impact: ${currency.format(line.ingredientCostImpactGbp)}',
                    ),
                    Text(
                      'That error volume could have made ${line.recoverableCocktails.toStringAsFixed(2)} more ${line.cocktailName}',
                    ),
                    Text(
                      'Estimated sales value of those cocktails: ${currency.format(line.recoverableRevenueGbp)}',
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

String _quizFocusLabel(QuizFocus focus) {
  return switch (focus) {
    QuizFocus.specs => 'Specs focus',
    QuizFocus.garnishGlassware => 'Garnish and glass focus',
  };
}

String _quizFocusSupportLabel(QuizFocus focus) {
  return switch (focus) {
    QuizFocus.specs => 'Measures, pours, and batches only',
    QuizFocus.garnishGlassware => 'Service details only',
  };
}

String _questionKindLabel(QuestionKind kind) {
  return switch (kind) {
    QuestionKind.ingredientMeasure => 'Measure',
    QuestionKind.ingredientChoice => 'Ingredient',
    QuestionKind.cocktailByIngredient => 'Cocktail match',
    QuestionKind.garnish => 'Garnish',
    QuestionKind.glassware => 'Glassware',
    QuestionKind.method => 'Method',
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
    QuestionKind.cocktailByIngredient =>
      'Match the ingredient clue to the right approved cocktail.',
    QuestionKind.method =>
      'Choose the approved method for this cocktail.',
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
