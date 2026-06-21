import 'package:flutter_test/flutter_test.dart';

import 'package:stock_variance_coach/data/repositories/demo_repositories.dart';
import 'package:stock_variance_coach/domain/models/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalTrainingRepository quiz submission', () {
    late LocalTrainingRepository repository;

    setUp(() async {
      repository = LocalTrainingRepository();
      await repository.initialize();
    });

    test('stores confidence, duration metadata, and previous best improvement', () async {
      final firstSession = repository.generatePracticeQuizSession(
        bartenderName: 'Jamie',
      );
      final firstAnswers = {
        for (final question in firstSession.questions)
          question.id: question.correctAnswer,
      };
      final firstConfidence = {
        for (final question in firstSession.questions)
          question.id: QuizAnswerConfidence.certain,
      };
      final startedAt = DateTime.now().subtract(const Duration(minutes: 2));

      final firstAttempt = await repository.submitQuizAttempt(
        sessionId: firstSession.id,
        bartenderName: 'Jamie',
        answers: firstAnswers,
        confidenceByQuestionId: firstConfidence,
        startedAt: startedAt,
      );

      expect(firstAttempt.scorePercent, 100);
      expect(firstAttempt.previousBestScorePercent, isNull);
      expect(firstAttempt.improvementScorePercent, isNull);
      expect(firstAttempt.duration.inMinutes, greaterThanOrEqualTo(2));
      expect(firstAttempt.responses.every((item) => item.confidence == QuizAnswerConfidence.certain), isTrue);

      final secondSession = repository.generatePracticeQuizSession(
        bartenderName: 'Jamie',
      );
      final secondAnswers = <String, String>{};
      for (final question in secondSession.questions) {
        secondAnswers[question.id] = question.options.firstWhere(
          (option) => option != question.correctAnswer,
          orElse: () => question.correctAnswer,
        );
      }
      final secondConfidence = {
        for (final question in secondSession.questions)
          question.id: QuizAnswerConfidence.certain,
      };

      final secondAttempt = await repository.submitQuizAttempt(
        sessionId: secondSession.id,
        bartenderName: 'Jamie',
        answers: secondAnswers,
        confidenceByQuestionId: secondConfidence,
        startedAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );

      expect(secondAttempt.previousBestScorePercent, 100);
      expect(secondAttempt.improvementScorePercent, lessThanOrEqualTo(0));
      expect(secondAttempt.highConfidenceMissCount, greaterThanOrEqualTo(0));
    });

    test('prevents duplicate submissions for the same session', () async {
      final session = repository.generatePracticeQuizSession(
        bartenderName: 'Morgan',
      );
      final answers = {
        for (final question in session.questions)
          question.id: question.correctAnswer,
      };
      final confidenceByQuestionId = {
        for (final question in session.questions)
          question.id: QuizAnswerConfidence.fairlySure,
      };

      final firstAttempt = await repository.submitQuizAttempt(
        sessionId: session.id,
        bartenderName: 'Morgan',
        answers: answers,
        confidenceByQuestionId: confidenceByQuestionId,
        startedAt: DateTime.now().subtract(const Duration(seconds: 30)),
      );
      final secondAttempt = await repository.submitQuizAttempt(
        sessionId: session.id,
        bartenderName: 'Morgan',
        answers: answers,
        confidenceByQuestionId: confidenceByQuestionId,
        startedAt: DateTime.now().subtract(const Duration(seconds: 30)),
      );

      expect(secondAttempt.id, firstAttempt.id);
      expect(repository.quizAttempts.length, 1);
    });

    test('generated questions include coaching explanations', () {
      final session = repository.generatePracticeQuizSession(
        bartenderName: 'Taylor',
      );

      expect(session.questions, isNotEmpty);
      expect(
        session.questions.every((question) => question.explanation.trim().isNotEmpty),
        isTrue,
      );
    });

    test('generated quizzes now cover extended question types', () {
      final kinds = <QuestionKind>{};
      for (final name in ['Taylor', 'Jamie', 'Morgan']) {
        final specsSession = repository.generatePracticeQuizSession(
          bartenderName: name,
          focus: QuizFocus.specs,
        );
        kinds.addAll(specsSession.questions.map((question) => question.kind));
      }

      expect(kinds.contains(QuestionKind.missingIngredient), isTrue);
      expect(kinds.contains(QuestionKind.methodOrder), isTrue);

      final serviceSession = repository.generatePracticeQuizSession(
        bartenderName: 'Taylor',
        focus: QuizFocus.garnishGlassware,
      );
      expect(
        serviceSession.questions.any(
          (question) => (question.imageAssetPath ?? '').trim().isNotEmpty,
        ),
        isTrue,
      );
    });

    test('adaptive practice prioritizes missed high-volume cocktails', () async {
      final weeklySession = repository.createWeeklySession(
        label: 'Spritz focus',
        weekStart: DateTime(2026, 6, 21),
        concerns: const [StockConcernItem(ingredientName: 'Aperol')],
      );
      repository.saveBartenderSales(
        weekId: weeklySession.id,
        bartenderName: 'Jamie',
        entries: const [
          BartenderSalesEntry(
            cocktailId: 'aperol-spritz',
            cocktailName: 'Aperol Spritz',
            quantitySold: 40,
          ),
        ],
      );

      final focusedSession = repository.generatePracticeQuizSession(
        bartenderName: 'Jamie',
        focusRecipeIds: const ['aperol-spritz'],
        focus: QuizFocus.specs,
      );
      final wrongAnswers = <String, String>{};
      final confidenceByQuestionId = <String, QuizAnswerConfidence>{};
      for (final question in focusedSession.questions) {
        wrongAnswers[question.id] = question.options.firstWhere(
          (option) => option != question.correctAnswer,
          orElse: () => question.correctAnswer,
        );
        confidenceByQuestionId[question.id] = QuizAnswerConfidence.certain;
      }
      await repository.submitQuizAttempt(
        sessionId: focusedSession.id,
        bartenderName: 'Jamie',
        answers: wrongAnswers,
        confidenceByQuestionId: confidenceByQuestionId,
      );

      final adaptiveSession = repository.generatePracticeQuizSession(
        bartenderName: 'Jamie',
        focus: QuizFocus.specs,
      );

      expect(
        adaptiveSession.questions.any(
          (question) => question.cocktailId == 'aperol-spritz',
        ),
        isTrue,
      );
    });

    test('uses fallback sales volume when bartender sales are unavailable', () async {
      final session = repository.generatePracticeQuizSession(
        bartenderName: 'NoSales',
        focus: QuizFocus.specs,
      );
      final answers = {
        for (final question in session.questions)
          question.id: question.correctAnswer,
      };
      final attempt = await repository.submitQuizAttempt(
        sessionId: session.id,
        bartenderName: 'NoSales',
        answers: answers,
      );

      expect(
        attempt.responses.every((response) => response.quantitySold == 30),
        isTrue,
      );
    });
  });
}
