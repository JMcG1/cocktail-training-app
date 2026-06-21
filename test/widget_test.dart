import 'package:flutter_test/flutter_test.dart';
import 'package:stock_variance_coach/core/utils/workspace_tab_history.dart';
import 'package:stock_variance_coach/domain/models/models.dart';
import 'package:stock_variance_coach/presentation/screens/app_shell.dart';

import 'test_app_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('practice quiz can be generated and submitted from approved data', () async {
    final controller = buildTestController(
      user: buildTestUser(role: UserRole.bartender, name: 'Bartender'),
    );
    await controller.initialize(usingFirebase: false);

    final session = controller.generatePracticeQuiz(
      bartenderName: 'Bartender',
    );
    expect(session.questions, isNotEmpty);

    final answers = {
      for (final question in session.questions)
        question.id: question.correctAnswer,
    };
    final attempt = await controller.submitQuizAttempt(
      sessionId: session.id,
      bartenderName: 'Bartender',
      answers: answers,
    );

    expect(attempt.scorePercent, greaterThanOrEqualTo(0));
    expect(controller.latestAttempt, isNotNull);
  });

  test('invite route parser supports path and query formats', () {
    final pathInvite = inviteRouteFromUri(
      Uri.parse('https://example.com/join/venue-1/invite-1'),
    );
    final queryInvite = inviteRouteFromUri(
      Uri.parse('https://example.com/?venue=venue-2&invite=invite-2'),
    );

    expect(pathInvite, isNotNull);
    expect(pathInvite!.venueId, 'venue-1');
    expect(pathInvite.inviteId, 'invite-1');
    expect(queryInvite, isNotNull);
    expect(queryInvite!.venueId, 'venue-2');
    expect(queryInvite.inviteId, 'invite-2');
  });

  test('invite link builder preserves the current app path', () {
    final invite = VenueInvite(
      id: 'invite-9',
      venueId: 'venue-3',
      role: UserRole.bartender,
      createdBy: 'owner-1',
      createdAt: DateTime(2026),
      expiresAt: DateTime(2026, 1, 8),
      maxUses: 1,
      currentUses: 0,
      disabled: false,
    );

    final uri = inviteLinkUriFromBase(
      Uri.parse('https://example.com/training-app/'),
      invite,
    );

    expect(
      uri.toString(),
      'https://example.com/training-app/?venue=venue-3&invite=invite-9',
    );
  });

  test('quiz link builder preserves the current app path', () {
    final session = QuizSession(
      id: 'quiz-9',
      title: 'Practice quiz',
      bartenderName: 'Bartender',
      kind: QuizKind.practice,
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
      questions: const [],
    );

    final uri = quizLinkUriFromBase(
      Uri.parse('https://example.com/training-app/'),
      session,
    );

    expect(uri.toString(), 'https://example.com/training-app/quiz/quiz-9');
  });

  test('workspace tab history walks back through in-app tabs', () {
    final history = WorkspaceTabHistory(initialIndex: 0);

    history.visit(1);
    history.visit(2);
    expect(history.debugStack, [0, 1, 2]);

    history.syncFromBrowser(1);
    expect(history.currentIndex, 1);
    expect(history.debugStack, [0, 1]);

    final previous = history.popPrevious();
    expect(previous, 0);
    expect(history.currentIndex, 0);
    expect(history.debugStack, [0]);
  });
}
