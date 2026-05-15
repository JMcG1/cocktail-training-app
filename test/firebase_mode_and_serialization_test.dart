import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_variance_coach/core/config/app_environment.dart';
import 'package:stock_variance_coach/data/firestore/firestore_paths.dart';
import 'package:stock_variance_coach/data/firestore/firestore_serializers.dart';
import 'package:stock_variance_coach/data/repositories/demo_repositories.dart';
import 'package:stock_variance_coach/data/repositories/repository_mode_resolver.dart';
import 'package:stock_variance_coach/domain/models/models.dart';
import 'package:stock_variance_coach/domain/repositories/repositories.dart';
import 'package:stock_variance_coach/presentation/controllers/app_controller.dart';
import 'package:stock_variance_coach/presentation/screens/app_shell.dart';

void main() {
  group('Repository mode resolver', () {
    test('uses demo mode when explicitly requested', () {
      expect(
        RepositoryModeResolver.shouldUseFirebase(
          environment: _environment(appMode: AppMode.demo),
          firebaseAvailable: true,
        ),
        isFalse,
      );
    });

    test('uses firebase mode when available', () {
      expect(
        RepositoryModeResolver.shouldUseFirebase(
          environment: _environment(appMode: AppMode.firebase),
          firebaseAvailable: true,
        ),
        isTrue,
      );
    });

    test('falls back locally when auto mode has no firebase config', () {
      expect(
        RepositoryModeResolver.shouldUseFirebase(
          environment: _environment(appMode: AppMode.auto),
          firebaseAvailable: false,
        ),
        isFalse,
      );
    });
  });

  group('Firestore paths', () {
    test('build venue scoped collection paths', () {
      expect(FirestorePaths.recipes('venue-123'), 'venues/venue-123/recipes');
      expect(
        FirestorePaths.batchRecipes('venue-123'),
        'venues/venue-123/batchRecipes',
      );
      expect(
        FirestorePaths.recipeDrafts('venue-123'),
        'venues/venue-123/recipeDrafts',
      );
      expect(
        FirestorePaths.stockConcernSessions('venue-123'),
        'venues/venue-123/stockConcernSessions',
      );
      expect(FirestorePaths.users(), 'users');
    });
  });

  group('Firestore serializers', () {
    test('round trips persisted models', () {
      final recipe = CocktailRecipe(
        id: 'recipe-1',
        name: 'Reviewed Sour',
        category: 'Classic Cocktails',
        glassware: 'Coupe',
        garnish: 'Orange twist',
        method: 'Shake and fine strain.',
        notes: 'Worth revisiting citrus balance.',
        ingredients: const [
          RecipeIngredient(ingredientName: 'Vodka', measureMl: 40),
        ],
        sourceLabel: 'pdf-review',
        needsReview: false,
        reviewFlags: const [],
        isApproved: true,
        wasManuallyReviewed: true,
      );
      final draft = RecipeImportDraft(
        id: 'draft-1',
        sourceLabel: 'ocr.txt',
        pageLabel: 'Page 12',
        name: 'APERNOL SPRITZ',
        category: 'Non-Alc Cocktails',
        glassware: 'Spritz glass',
        garnish: 'Orange slice',
        method: 'Build over ice.',
        notes: '',
        ingredients: const [
          RecipeIngredient(
            ingredientName: 'Lyre\'s Italian Spritz',
            measureMl: 35,
          ),
        ],
        reviewFlags: const ['Possible OCR issue in the cocktail name.'],
        status: RecipeDraftStatus.pending,
        wasManuallyReviewed: false,
      );
      const sales = BartenderWeeklySales(
        bartenderName: 'Jamie',
        entries: [
          BartenderSalesEntry(
            cocktailId: 'recipe-1',
            cocktailName: 'Reviewed Sour',
            quantitySold: 12,
          ),
        ],
      );
      final session = WeeklyConcernSession(
        id: 'week-1',
        label: 'Monday focus',
        weekStart: DateTime(2026, 5, 12),
        concerns: const [
          StockConcernItem(
            ingredientName: 'Vodka',
            amountShortMl: 300,
            estimatedImpact: 12,
            notes: 'Worth checking martini builds.',
          ),
        ],
        targetCocktailIds: const ['recipe-1'],
        bartenderSales: const [sales],
        quizSessionIds: const ['quiz-1'],
      );
      final quizSession = QuizSession(
        id: 'quiz-1',
        title: 'Targeted quiz',
        bartenderName: 'Jamie',
        kind: QuizKind.stockVariance,
        isActive: true,
        createdAt: DateTime(2026, 5, 12),
        questions: const [
          QuizQuestion(
            id: 'question-1',
            cocktailId: 'recipe-1',
            cocktailName: 'Reviewed Sour',
            kind: QuestionKind.ingredientMeasure,
            prompt: 'How much vodka is in Reviewed Sour?',
            options: ['35ml', '40ml', '45ml', '50ml'],
            correctAnswer: '40ml',
            ingredientName: 'Vodka',
            correctMeasureMl: 40,
          ),
        ],
        weekId: 'week-1',
      );
      final attempt = QuizAttempt(
        id: 'attempt-1',
        sessionId: 'quiz-1',
        bartenderName: 'Jamie',
        submittedAt: DateTime(2026, 5, 12),
        scorePercent: 80,
        responses: const [
          QuestionResponse(
            question: QuizQuestion(
              id: 'question-1',
              cocktailId: 'recipe-1',
              cocktailName: 'Reviewed Sour',
              kind: QuestionKind.ingredientMeasure,
              prompt: 'How much vodka is in Reviewed Sour?',
              options: ['35ml', '40ml', '45ml', '50ml'],
              correctAnswer: '40ml',
              ingredientName: 'Vodka',
              correctMeasureMl: 40,
            ),
            selectedAnswer: '45ml',
            isCorrect: false,
            quantitySold: 12,
            deltaMl: 5,
          ),
        ],
        overpourLines: const [
          VarianceLine(
            ingredientName: 'Vodka',
            totalMl: 60,
            approximateValue: 2.4,
            direction: VarianceDirection.overpour,
          ),
        ],
        underpourLines: const [],
        coachingAreas: const ['Reviewed Sour'],
        encouragement: 'Solid progress.',
        weekId: 'week-1',
      );

      final recipeRoundTrip = FirestoreSerializers.recipeFromMap(
        'recipe-1',
        FirestoreSerializers.recipeToMap(recipe),
      );
      final draftRoundTrip = FirestoreSerializers.draftFromMap(
        'draft-1',
        FirestoreSerializers.draftToMap(draft),
      );
      final sessionRoundTrip = FirestoreSerializers.weeklySessionFromMap(
        'week-1',
        FirestoreSerializers.weeklySessionToMap(session),
        bartenderSales: [sales],
      );
      final quizRoundTrip = FirestoreSerializers.quizSessionFromMap(
        'quiz-1',
        FirestoreSerializers.quizSessionToMap(quizSession),
      );
      final attemptRoundTrip = FirestoreSerializers.quizAttemptFromMap(
        'attempt-1',
        FirestoreSerializers.quizAttemptToMap(attempt),
      );

      expect(recipeRoundTrip.name, recipe.name);
      expect(draftRoundTrip.status, RecipeDraftStatus.pending);
      expect(sessionRoundTrip.concerns.single.notes, contains('martini'));
      expect(quizRoundTrip.questions.single.correctAnswer, '40ml');
      expect(attemptRoundTrip.overpourLines.single.totalMl, 60);
    });
  });

  group('Auth-gated shell', () {
    testWidgets('manager route requires auth', (tester) async {
      final controller = AppController(
        authRepository: _ShellAuthRepository(currentUserValue: null),
        trainingRepository: LocalTrainingRepository(),
        environment: _environment(appMode: AppMode.demo),
      );
      await controller.initialize();

      await tester.pumpWidget(
        MaterialApp(home: AppShell(controller: controller)),
      );
      await tester.pump();

      expect(find.text('Welcome back to service support'), findsOneWidget);
    });

    testWidgets('shows manager workspace when a manager is authenticated', (
      tester,
    ) async {
      final auth = _ShellAuthRepository(
        currentUserValue: AppUser(
          id: 'manager-1',
          email: 'manager@example.com',
          displayName: 'Manager',
          role: UserRole.manager,
          venueId: 'venue-1',
          venueName: 'Venue One',
          createdAt: _createdAt,
          active: true,
        ),
      );
      final controller = AppController(
        authRepository: auth,
        trainingRepository: LocalTrainingRepository(),
        environment: _environment(appMode: AppMode.demo),
      );
      await controller.initialize();

      await tester.pumpWidget(
        MaterialApp(home: AppShell(controller: controller)),
      );
      await tester.pump();

      expect(find.textContaining('manager space'), findsOneWidget);
      expect(find.text('Admin setup'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('shows owner admin setup when an owner is authenticated', (
      tester,
    ) async {
      final auth = _ShellAuthRepository(
        currentUserValue: AppUser(
          id: 'owner-1',
          email: 'owner@example.com',
          displayName: 'Owner',
          role: UserRole.owner,
          venueId: 'venue-1',
          venueName: 'Venue One',
          createdAt: _createdAt,
          active: true,
        ),
      );
      final controller = AppController(
        authRepository: auth,
        trainingRepository: LocalTrainingRepository(),
        environment: _environment(appMode: AppMode.demo),
      );
      await controller.initialize();

      await tester.pumpWidget(
        MaterialApp(home: AppShell(controller: controller)),
      );
      await tester.pump();

      expect(find.textContaining('owner/admin space'), findsOneWidget);
      expect(find.text('Admin setup'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets(
      'signed-in bartender lands in training instead of manager workspace',
      (tester) async {
        final auth = _ShellAuthRepository(
          currentUserValue: AppUser(
            id: 'bartender-1',
            email: 'bartender@example.com',
            displayName: 'Bartender',
            role: UserRole.bartender,
            venueId: 'venue-1',
            venueName: 'Venue One',
            createdAt: _createdAt,
            active: true,
          ),
        );
        final controller = AppController(
          authRepository: auth,
          trainingRepository: LocalTrainingRepository(),
          environment: _environment(appMode: AppMode.demo),
        );
        await controller.initialize();

        await tester.pumpWidget(
          MaterialApp(home: AppShell(controller: controller)),
        );
        await tester.pump();

        expect(find.text('Practice space'), findsOneWidget);
        expect(find.textContaining('manager space'), findsNothing);
      },
    );

    testWidgets('inactive quiz session shows friendly closed message', (
      tester,
    ) async {
      final controller = AppController(
        authRepository: _ShellAuthRepository(currentUserValue: null),
        trainingRepository: LocalTrainingRepository(),
        environment: _environment(appMode: AppMode.demo),
      );
      await controller.initialize();

      await tester.pumpWidget(
        MaterialApp(
          home: BartenderQuizScreen(
            controller: controller,
            sessionId: 'missing-session',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('unavailable right now'), findsOneWidget);
    });

    test('quiz link opens only while the session is active', () {
      final repository = LocalTrainingRepository();
      repository.saveImportedDrafts([
        const RecipeImportDraft(
          id: 'quiz-recipe',
          sourceLabel: 'manual',
          pageLabel: 'manual',
          name: 'Approved Sour',
          category: 'Classics',
          glassware: 'Coupe',
          garnish: 'Orange twist',
          method: 'Shake and fine strain.',
          notes: '',
          ingredients: [
            RecipeIngredient(ingredientName: 'Vodka', measureMl: 40),
          ],
          reviewFlags: [],
          status: RecipeDraftStatus.approved,
          wasManuallyReviewed: true,
        ),
      ]);
      final week = repository.createWeeklySession(
        label: 'Monday focus',
        weekStart: DateTime(2026, 5, 12),
        concerns: const [StockConcernItem(ingredientName: 'Vodka')],
      );
      repository.saveBartenderSales(
        weekId: week.id,
        bartenderName: 'Jamie',
        entries: const [
          BartenderSalesEntry(
            cocktailId: 'quiz-recipe',
            cocktailName: 'Approved Sour',
            quantitySold: 4,
          ),
        ],
      );
      final quiz = repository.generateStockQuizSession(
        weekId: week.id,
        bartenderName: 'Jamie',
      );

      expect(repository.findQuizSession(quiz.id), isNotNull);

      repository.deactivateQuizSession(quiz.id);

      expect(repository.findQuizSession(quiz.id), isNull);
    });
  });

  group('Onboarding and controller wiring', () {
    test('first manager creates venue and profile', () async {
      final auth = _ConfigurableAuthRepository();
      final training = _TrackingTrainingRepository();
      final controller = AppController(
        authRepository: auth,
        trainingRepository: training,
        environment: _environment(appMode: AppMode.firebase),
      );

      final created = await controller.createManagerAccount(
        email: 'owner@venue.com',
        password: 'password123',
        displayName: 'Owner',
        venueName: 'Botanical Bar',
      );

      expect(created, isTrue);
      expect(auth.createdUser, isNotNull);
      expect(auth.createdUser!.venueName, 'Botanical Bar');
      expect(training.configuredVenueId, 'venue-created');
    });

    test('password reset flow is wired', () async {
      final auth = _ConfigurableAuthRepository();
      final controller = AppController(
        authRepository: auth,
        trainingRepository: _TrackingTrainingRepository(),
        environment: _environment(appMode: AppMode.firebase),
      );

      await controller.sendPasswordReset(email: 'manager@venue.com');

      expect(auth.lastResetEmail, 'manager@venue.com');
      expect(controller.successMessage, contains('reset link'));
    });

    test(
      'user can only access their own venue data through configured venue scope',
      () async {
        final auth = _ConfigurableAuthRepository(
          signedInUser: AppUser(
            id: 'manager-2',
            email: 'manager@venue.com',
            displayName: 'Manager',
            role: UserRole.manager,
            venueId: 'venue-b',
            venueName: 'Venue B',
            createdAt: _createdAt,
            active: true,
          ),
        );
        final training = _TrackingTrainingRepository();
        final controller = AppController(
          authRepository: auth,
          trainingRepository: training,
          environment: _environment(appMode: AppMode.firebase),
        );

        await controller.signInManager(
          email: 'manager@venue.com',
          password: 'password',
        );

        expect(training.configuredVenueId, 'venue-b');
        expect(training.loadManagerDataCalls, 1);
      },
    );

    test('owner can create and pause venue invites', () async {
      final auth = _ConfigurableAuthRepository(
        initialUser: AppUser(
          id: 'owner-1',
          email: 'owner@example.com',
          displayName: 'Owner',
          role: UserRole.owner,
          venueId: 'venue-a',
          venueName: 'Venue A',
          createdAt: _createdAt,
          active: true,
        ),
      );
      final controller = AppController(
        authRepository: auth,
        trainingRepository: _TrackingTrainingRepository(),
        environment: _environment(appMode: AppMode.firebase),
      );
      await controller.initialize(usingFirebase: true);

      final invite = await controller.createVenueInvite(
        role: UserRole.manager,
        expiresAt: DateTime(2026, 6, 1),
        maxUses: 2,
      );

      expect(invite.role, UserRole.manager);
      expect(controller.venueInvites.single.id, invite.id);

      await controller.setVenueInviteDisabled(
        inviteId: invite.id,
        disabled: true,
      );

      expect(
        controller.venueInvites
            .firstWhere((item) => item.id == invite.id)
            .disabled,
        isTrue,
      );
    });

    test('invite redemption locks role and venue from the invite', () async {
      final auth = _ConfigurableAuthRepository();
      final ownerController = AppController(
        authRepository: auth,
        trainingRepository: _TrackingTrainingRepository(),
        environment: _environment(appMode: AppMode.firebase),
      );
      auth._currentUser = AppUser(
        id: 'owner-1',
        email: 'owner@example.com',
        displayName: 'Owner',
        role: UserRole.owner,
        venueId: 'venue-a',
        venueName: 'Venue A',
        createdAt: _createdAt,
        active: true,
      );
      await ownerController.initialize(usingFirebase: true);
      final invite = await ownerController.createVenueInvite(
        role: UserRole.bartender,
        expiresAt: DateTime(2026, 6, 1),
        maxUses: 1,
      );

      final joinController = AppController(
        authRepository: auth,
        trainingRepository: _TrackingTrainingRepository(),
        environment: _environment(appMode: AppMode.firebase),
      );
      await joinController.redeemVenueInvite(
        venueId: invite.venueId,
        inviteId: invite.id,
        email: 'bartender@venue.com',
        password: 'password123',
        displayName: 'Jamie',
      );

      expect(auth.redeemedInviteUser, isNotNull);
      expect(auth.redeemedInviteUser!.role, UserRole.bartender);
      expect(auth.redeemedInviteUser!.venueId, 'venue-a');
      expect(
        auth._venueInvites
            .firstWhere((item) => item.id == invite.id)
            .currentUses,
        1,
      );
    });

    test('sign-out clears manager data and resets venue scope', () async {
      final auth = _ConfigurableAuthRepository(
        initialUser: AppUser(
          id: 'manager-1',
          email: 'manager@example.com',
          displayName: 'Manager',
          role: UserRole.manager,
          venueId: 'venue-x',
          venueName: 'Venue X',
          createdAt: _createdAt,
          active: true,
        ),
      );
      final training = _TrackingTrainingRepository();
      final controller = AppController(
        authRepository: auth,
        trainingRepository: training,
        environment: _environment(appMode: AppMode.demo),
      );
      await controller.initialize();

      await controller.signOut();

      expect(controller.currentUser, isNull);
      expect(training.configuredVenueId, 'venue-1');
      expect(training.initializeCalls, greaterThanOrEqualTo(2));
    });

    test('setup checklist state changes as data is added', () async {
      final training = LocalTrainingRepository();
      final controller = AppController(
        authRepository: _ShellAuthRepository(
          currentUserValue: AppUser(
            id: 'owner-1',
            email: 'owner@example.com',
            displayName: 'Owner',
            role: UserRole.owner,
            venueId: 'venue-1',
            venueName: 'Venue One',
            createdAt: _createdAt,
            active: true,
          ),
        ),
        trainingRepository: training,
        environment: _environment(appMode: AppMode.demo),
      );
      await controller.initialize();

      expect(controller.buildSetupChecklist().completedCount, 0);

      training.saveImportedDrafts([
        const RecipeImportDraft(
          id: 'draft-approved',
          sourceLabel: 'manual',
          pageLabel: 'manual',
          name: 'Approved Sour',
          category: 'Classics',
          glassware: 'Coupe',
          garnish: 'Orange twist',
          method: 'Shake and fine strain.',
          notes: '',
          ingredients: [
            RecipeIngredient(ingredientName: 'Vodka', measureMl: 40),
          ],
          reviewFlags: [],
          status: RecipeDraftStatus.approved,
          wasManuallyReviewed: true,
        ),
      ]);
      controller.saveIngredient(
        name: 'Vodka',
        bottleSizeMl: 700,
        bottleCost: 28,
      );
      final session = controller.createWeeklySession(
        label: 'Monday focus',
        weekStart: DateTime(2026, 5, 12),
        concerns: const [StockConcernItem(ingredientName: 'Vodka')],
      );
      controller.saveBartenderSales(
        weekId: session.id,
        bartenderName: 'Jamie',
        entries: const [
          BartenderSalesEntry(
            cocktailId: 'draft-approved',
            cocktailName: 'Approved Sour',
            quantitySold: 10,
          ),
        ],
      );
      controller.generateStockQuiz(weekId: session.id, bartenderName: 'Jamie');

      expect(controller.buildSetupChecklist().completedCount, 5);
    });

    test(
      'owner can approve recipes and pricing, while manager cannot edit official spec data',
      () async {
        final ownerController = AppController(
          authRepository: _ShellAuthRepository(
            currentUserValue: AppUser(
              id: 'owner-1',
              email: 'owner@example.com',
              displayName: 'Owner',
              role: UserRole.owner,
              venueId: 'venue-1',
              venueName: 'Venue One',
              createdAt: _createdAt,
              active: true,
            ),
          ),
          trainingRepository: LocalTrainingRepository(),
          environment: _environment(appMode: AppMode.demo),
        );
        await ownerController.initialize();

        final approved = ownerController.approveImportDraft(
          const RecipeImportDraft(
            id: 'draft-1',
            sourceLabel: 'manual',
            pageLabel: 'Page 1',
            name: 'Owner Approved Sour',
            category: 'Classics',
            glassware: 'Coupe',
            garnish: 'Orange twist',
            method: 'Shake and fine strain.',
            notes: '',
            ingredients: [
              RecipeIngredient(ingredientName: 'Vodka', measureMl: 40),
            ],
            reviewFlags: [],
            status: RecipeDraftStatus.pending,
            wasManuallyReviewed: false,
          ),
        );
        ownerController.saveIngredient(
          name: 'Vodka',
          bottleSizeMl: 700,
          bottleCost: 28,
        );

        expect(approved.status, RecipeDraftStatus.approved);
        expect(ownerController.ingredients.single.name, 'Vodka');

        final managerController = AppController(
          authRepository: _ShellAuthRepository(
            currentUserValue: AppUser(
              id: 'manager-1',
              email: 'manager@example.com',
              displayName: 'Manager',
              role: UserRole.manager,
              venueId: 'venue-1',
              venueName: 'Venue One',
              createdAt: _createdAt,
              active: true,
            ),
          ),
          trainingRepository: LocalTrainingRepository(),
          environment: _environment(appMode: AppMode.demo),
        );
        await managerController.initialize();

        expect(
          () => managerController.approveImportDraft(
            const RecipeImportDraft(
              id: 'draft-2',
              sourceLabel: 'manual',
              pageLabel: 'Page 1',
              name: 'Manager Draft',
              category: 'Classics',
              glassware: 'Coupe',
              garnish: 'Orange twist',
              method: 'Shake',
              notes: '',
              ingredients: [
                RecipeIngredient(ingredientName: 'Vodka', measureMl: 40),
              ],
              reviewFlags: [],
              status: RecipeDraftStatus.pending,
              wasManuallyReviewed: false,
            ),
          ),
          throwsException,
        );
        expect(
          () => managerController.saveIngredient(
            name: 'Vodka',
            bottleSizeMl: 700,
            bottleCost: 28,
          ),
          throwsException,
        );
      },
    );

    test('manager can create stock concerns and view results', () async {
      final training = LocalTrainingRepository();
      training.saveImportedDrafts([
        const RecipeImportDraft(
          id: 'approved-sour',
          sourceLabel: 'manual',
          pageLabel: 'manual',
          name: 'Approved Sour',
          category: 'Classics',
          glassware: 'Coupe',
          garnish: 'Orange twist',
          method: 'Shake and fine strain.',
          notes: '',
          ingredients: [
            RecipeIngredient(ingredientName: 'Vodka', measureMl: 40),
          ],
          reviewFlags: [],
          status: RecipeDraftStatus.approved,
          wasManuallyReviewed: true,
        ),
      ]);
      final controller = AppController(
        authRepository: _ShellAuthRepository(
          currentUserValue: AppUser(
            id: 'manager-1',
            email: 'manager@example.com',
            displayName: 'Manager',
            role: UserRole.manager,
            venueId: 'venue-1',
            venueName: 'Venue One',
            createdAt: _createdAt,
            active: true,
          ),
        ),
        trainingRepository: training,
        environment: _environment(appMode: AppMode.demo),
      );
      await controller.initialize();

      final session = controller.createWeeklySession(
        label: 'Monday focus',
        weekStart: DateTime(2026, 5, 12),
        concerns: const [StockConcernItem(ingredientName: 'Vodka')],
      );
      controller.saveBartenderSales(
        weekId: session.id,
        bartenderName: 'Jamie',
        entries: const [
          BartenderSalesEntry(
            cocktailId: 'approved-sour',
            cocktailName: 'Approved Sour',
            quantitySold: 4,
          ),
        ],
      );
      final quiz = controller.generateStockQuiz(
        weekId: session.id,
        bartenderName: 'Jamie',
      );

      expect(session.targetCocktailIds, contains('approved-sour'));
      expect(quiz.questions, isNotEmpty);
    });

    test(
      'manager can create venue-scoped invites but not owner invites',
      () async {
        final auth = _ConfigurableAuthRepository(
          initialUser: AppUser(
            id: 'manager-1',
            email: 'manager@example.com',
            displayName: 'Manager',
            role: UserRole.manager,
            venueId: 'venue-1',
            venueName: 'Venue One',
            createdAt: _createdAt,
            active: true,
          ),
        );
        final controller = AppController(
          authRepository: auth,
          trainingRepository: _TrackingTrainingRepository(),
          environment: _environment(appMode: AppMode.firebase),
        );
        await controller.initialize(usingFirebase: true);

        final invite = await controller.createVenueInvite(
          role: UserRole.manager,
          expiresAt: DateTime(2026, 6, 1),
          maxUses: 1,
        );

        expect(invite.venueId, 'venue-1');
        expect(invite.role, UserRole.manager);
        expect(
          () => controller.createVenueInvite(
            role: UserRole.owner,
            expiresAt: DateTime(2026, 6, 1),
            maxUses: 1,
          ),
          throwsException,
        );
      },
    );

    test('invite redemption rejects disabled and overused invites', () async {
      final auth = _ConfigurableAuthRepository(
        initialUser: AppUser(
          id: 'owner-1',
          email: 'owner@example.com',
          displayName: 'Owner',
          role: UserRole.owner,
          venueId: 'venue-1',
          venueName: 'Venue One',
          createdAt: _createdAt,
          active: true,
        ),
      );
      final ownerController = AppController(
        authRepository: auth,
        trainingRepository: _TrackingTrainingRepository(),
        environment: _environment(appMode: AppMode.firebase),
      );
      await ownerController.initialize(usingFirebase: true);

      final disabledInvite = await ownerController.createVenueInvite(
        role: UserRole.bartender,
        expiresAt: DateTime(2026, 6, 1),
        maxUses: 1,
      );
      await ownerController.setVenueInviteDisabled(
        inviteId: disabledInvite.id,
        disabled: true,
      );

      final joinController = AppController(
        authRepository: auth,
        trainingRepository: _TrackingTrainingRepository(),
        environment: _environment(appMode: AppMode.firebase),
      );

      expect(
        () => joinController.redeemVenueInvite(
          venueId: disabledInvite.venueId,
          inviteId: disabledInvite.id,
          email: 'bartender@venue.com',
          password: 'password123',
          displayName: 'Jamie',
        ),
        throwsException,
      );

      final singleUseInvite = await ownerController.createVenueInvite(
        role: UserRole.manager,
        expiresAt: DateTime(2026, 6, 1),
        maxUses: 1,
      );
      await joinController.redeemVenueInvite(
        venueId: singleUseInvite.venueId,
        inviteId: singleUseInvite.id,
        email: 'manager@venue.com',
        password: 'password123',
        displayName: 'Floor Manager',
      );
      await auth.signOut();

      expect(
        () => joinController.redeemVenueInvite(
          venueId: singleUseInvite.venueId,
          inviteId: singleUseInvite.id,
          email: 'manager2@venue.com',
          password: 'password123',
          displayName: 'Second Manager',
        ),
        throwsException,
      );
    });
  });

  group('Firestore rule assumptions', () {
    test(
      'rules keep owner-only admin writes and operational manager writes separate',
      () {
        final rules = File('firestore.rules').readAsStringSync();

        expect(rules, contains("function isOwnerForVenue(venueId)"));
        expect(rules, contains("function isOperationalUserForVenue(venueId)"));
        expect(rules, contains("match /venues/{venueId}/invites/{inviteId}"));
        expect(rules, contains("validInviteRole"));
        expect(
          rules,
          contains("match /venues/{venueId}/batchRecipes/{batchRecipeId}"),
        );
        expect(
          rules,
          contains("match /venues/{venueId}/recipeDrafts/{draftId}"),
        );
        expect(rules, contains("allow write: if isOwnerForVenue(venueId);"));
        expect(
          rules,
          contains("match /venues/{venueId}/stockConcernSessions/{sessionId}"),
        );
        expect(
          rules,
          contains("allow read, write: if isOperationalUserForVenue(venueId);"),
        );
        expect(
          rules,
          contains(
            "allow get: if isOperationalUserForVenue(venueId) || isPublicQuizSession();",
          ),
        );
        expect(
          rules,
          contains("allow list: if isOperationalUserForVenue(venueId);"),
        );
        expect(
          rules,
          isNot(
            contains(
              "match /venues/{venueId}/recipes/{recipeId} {\n      allow read: if true;",
            ),
          ),
        );
        expect(
          rules,
          isNot(
            contains(
              "match /venues/{venueId}/ingredients/{ingredientId} {\n      allow read: if true;",
            ),
          ),
        );
        expect(rules, contains("match /bootstrapGrants/{grantId}"));
        expect(rules, contains("bootstrapGrantIsRedeemable"));
        expect(rules, contains("bootstrapGrantAfter().data.usedByUid == uid"));
        expect(
          rules,
          contains("bootstrapGrantAfter().data.venueId == request.resource.data.venueId"),
        );
        expect(
          rules,
          contains("bootstrapGrantAfter().data.venueId == venueId"),
        );
        expect(rules, contains("allow get: if false;"));
      },
    );
  });
}

final _createdAt = DateTime(2026, 1, 1);

AppEnvironment _environment({required AppMode appMode}) {
  return AppEnvironment(
    firebaseApiKey: '',
    firebaseAppId: '',
    firebaseMessagingSenderId: '',
    firebaseProjectId: '',
    firebaseAuthDomain: '',
    firebaseStorageBucket: '',
    demoManagerEmail: 'manager@example.com',
    demoManagerPassword: 'password',
    defaultVenueId: 'venue-1',
    appMode: appMode,
  );
}

class _ShellAuthRepository implements AuthRepository {
  _ShellAuthRepository({required this.currentUserValue});

  final AppUser? currentUserValue;

  @override
  AppUser? get currentUser => currentUserValue;

  @override
  Future<void> initialize() async {}

  @override
  Future<AppUser> createManagerAccount({
    required String email,
    required String password,
    required String displayName,
    required String venueName,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<AppUser> signInManager({
    required String email,
    required String password,
  }) async {
    return currentUserValue!;
  }

  @override
  Future<AppUser> createVenueManagerAccount({
    required String venueId,
    required String venueName,
    required String email,
    required String password,
    required String displayName,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<VenueInvite> createVenueInvite({
    required String venueId,
    required UserRole role,
    required String createdBy,
    required DateTime expiresAt,
    required int maxUses,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<VenueInvite>> listVenueInvites({required String venueId}) async {
    return const [];
  }

  @override
  Future<VenueInvite?> fetchVenueInvite({
    required String venueId,
    required String inviteId,
  }) async {
    return null;
  }

  @override
  Future<void> setVenueInviteDisabled({
    required String venueId,
    required String inviteId,
    required bool disabled,
  }) async {}

  @override
  Future<AppUser> redeemVenueInvite({
    required String venueId,
    required String inviteId,
    required String email,
    required String password,
    required String displayName,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<AppUser>> listVenueUsers({required String venueId}) async {
    return currentUserValue == null ? const [] : [currentUserValue!];
  }

  @override
  Future<void> setVenueUserActive({
    required String venueId,
    required String userId,
    required bool active,
  }) async {}

  @override
  Future<void> sendPasswordReset({required String email}) async {}

  @override
  Future<void> signOut() async {}
}

class _ConfigurableAuthRepository implements AuthRepository {
  _ConfigurableAuthRepository({
    this.initialUser,
    this.signedInUser,
    List<AppUser>? venueUsers,
  }) : _currentUser = initialUser,
       _venueUsers = venueUsers ?? (initialUser == null ? [] : [initialUser]);

  final AppUser? initialUser;
  final AppUser? signedInUser;
  AppUser? _currentUser;
  final List<AppUser> _venueUsers;
  final List<VenueInvite> _venueInvites = [];
  AppUser? createdUser;
  AppUser? createdVenueManager;
  AppUser? redeemedInviteUser;
  String? lastResetEmail;

  @override
  AppUser? get currentUser => _currentUser;

  @override
  Future<void> initialize() async {}

  @override
  Future<AppUser> createManagerAccount({
    required String email,
    required String password,
    required String displayName,
    required String venueName,
  }) async {
    createdUser = AppUser(
      id: 'owner-1',
      email: email,
      displayName: displayName,
      role: UserRole.owner,
      venueId: 'venue-created',
      venueName: venueName,
      createdAt: _createdAt,
      active: true,
    );
    _currentUser = createdUser;
    _venueUsers
      ..clear()
      ..add(createdUser!);
    return createdUser!;
  }

  @override
  Future<AppUser> signInManager({
    required String email,
    required String password,
  }) async {
    _currentUser =
        signedInUser ??
        AppUser(
          id: 'manager-signin',
          email: email,
          displayName: 'Manager',
          role: UserRole.manager,
          venueId: 'venue-signin',
          venueName: 'Venue Sign-in',
          createdAt: _createdAt,
          active: true,
        );
    if (_currentUser != null &&
        !_venueUsers.any((user) => user.id == _currentUser!.id)) {
      _venueUsers.add(_currentUser!);
    }
    return _currentUser!;
  }

  @override
  Future<AppUser> createVenueManagerAccount({
    required String venueId,
    required String venueName,
    required String email,
    required String password,
    required String displayName,
  }) async {
    createdVenueManager = AppUser(
      id: 'manager-created',
      email: email,
      displayName: displayName,
      role: UserRole.manager,
      venueId: venueId,
      venueName: venueName,
      createdAt: _createdAt,
      active: true,
    );
    _venueUsers.add(createdVenueManager!);
    return createdVenueManager!;
  }

  @override
  Future<VenueInvite> createVenueInvite({
    required String venueId,
    required UserRole role,
    required String createdBy,
    required DateTime expiresAt,
    required int maxUses,
  }) async {
    final invite = VenueInvite(
      id: 'invite-${_venueInvites.length + 1}',
      venueId: venueId,
      role: role,
      createdBy: createdBy,
      createdAt: _createdAt,
      expiresAt: expiresAt,
      maxUses: maxUses,
      currentUses: 0,
      disabled: false,
    );
    _venueInvites.add(invite);
    return invite;
  }

  @override
  Future<List<VenueInvite>> listVenueInvites({required String venueId}) async {
    return _venueInvites.where((invite) => invite.venueId == venueId).toList();
  }

  @override
  Future<VenueInvite?> fetchVenueInvite({
    required String venueId,
    required String inviteId,
  }) async {
    return _venueInvites.cast<VenueInvite?>().firstWhere(
      (invite) => invite?.id == inviteId && invite?.venueId == venueId,
      orElse: () => null,
    );
  }

  @override
  Future<void> setVenueInviteDisabled({
    required String venueId,
    required String inviteId,
    required bool disabled,
  }) async {
    final index = _venueInvites.indexWhere(
      (invite) => invite.id == inviteId && invite.venueId == venueId,
    );
    if (index == -1) {
      return;
    }
    _venueInvites[index] = _venueInvites[index].copyWith(disabled: disabled);
  }

  @override
  Future<AppUser> redeemVenueInvite({
    required String venueId,
    required String inviteId,
    required String email,
    required String password,
    required String displayName,
  }) async {
    final index = _venueInvites.indexWhere(
      (invite) => invite.id == inviteId && invite.venueId == venueId,
    );
    if (index == -1) {
      throw Exception('Invite not found.');
    }
    final invite = _venueInvites[index];
    if (!invite.isRedeemable) {
      throw Exception('Invite is no longer available.');
    }
    _venueInvites[index] = invite.copyWith(currentUses: invite.currentUses + 1);
    redeemedInviteUser = AppUser(
      id: 'redeemed-${invite.id}',
      email: email,
      displayName: displayName,
      role: invite.role,
      venueId: venueId,
      venueName: 'Venue Sign-in',
      createdAt: _createdAt,
      active: true,
    );
    _currentUser = redeemedInviteUser;
    _venueUsers.add(redeemedInviteUser!);
    return redeemedInviteUser!;
  }

  @override
  Future<List<AppUser>> listVenueUsers({required String venueId}) async {
    return _venueUsers.where((user) => user.venueId == venueId).toList();
  }

  @override
  Future<void> setVenueUserActive({
    required String venueId,
    required String userId,
    required bool active,
  }) async {
    final index = _venueUsers.indexWhere(
      (user) => user.id == userId && user.venueId == venueId,
    );
    if (index == -1) {
      return;
    }
    _venueUsers[index] = _venueUsers[index].copyWith(active: active);
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {
    lastResetEmail = email;
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
  }
}

class _TrackingTrainingRepository extends LocalTrainingRepository {
  String? configuredVenueId;
  int loadManagerDataCalls = 0;
  int initializeCalls = 0;

  @override
  void configureVenue(String venueId) {
    configuredVenueId = venueId;
  }

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
    await super.initialize();
  }

  @override
  Future<void> loadManagerData() async {
    loadManagerDataCalls += 1;
    await super.loadManagerData();
  }
}
