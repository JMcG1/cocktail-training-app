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
                    onPressed: () {
                      setState(() {
                        _completedAttempt = null;
                        _answers = {};
                        _activeSession = widget.controller.generatePracticeQuiz(
                          bartenderName: bartenderName,
                          focus: _selectedPracticeFocus,
                        );
                      });
                    },
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
                      ingredientsByName: {
                        for (final ingredient in widget.controller.ingredients)
                          _normalizeIngredientName(ingredient.name): ingredient,
                      },
                      batches: widget.controller.batches,
                    );
                    showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Quiz complete'),
                        content: SingleChildScrollView(
                          child: _QuizImpactSummary(
                            attempt: attempt,
                            summary: summary,
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
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
              const SizedBox(height: 20),
              ...session.questions.map(
                (question) => Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        question.prompt,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
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
                                  color: answers[question.id] == option
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                            .colorScheme
                                            .outlineVariant,
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    answers[question.id] == option
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
  });

  final QuizAttempt attempt;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final summary = VarianceMath.buildSalesImpactSummary(
      attempt: attempt,
      recipesById: controller.recipesById,
      ingredientsByName: {
        for (final ingredient in controller.ingredients)
          _normalizeIngredientName(ingredient.name): ingredient,
      },
      batches: controller.batches,
    );
    final feedback = controller.buildStudyFeedbackSummary();
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
          ],
        ),
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
            'Ingredient cost impact: ${currency.format(summary.totalIngredientCostImpactGbp)}',
          ),
          Text(
            'Cocktails recoverable from the error volume: ${summary.totalRecoverableCocktails.toStringAsFixed(2)}',
          ),
          Text(
            'Estimated cocktail sales value: ${currency.format(summary.totalRecoverableRevenueGbp)}',
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
                      'Total volume impact: ${line.totalErrorMl.toStringAsFixed(0)}ml',
                    ),
                    Text(
                      'Ingredient cost impact: ${currency.format(line.ingredientCostImpactGbp)}',
                    ),
                    Text(
                      'Could have made ${line.recoverableCocktails.toStringAsFixed(2)} more cocktails',
                    ),
                    Text(
                      'Estimated cocktail sales value: ${currency.format(line.recoverableRevenueGbp)}',
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

String _normalizeIngredientName(String value) {
  return value
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r"[^a-z0-9']+"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
