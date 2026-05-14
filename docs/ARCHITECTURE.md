# Architecture

## Overview

The app is a Flutter web client organized around a simple layered structure:

- `presentation`: widgets and high-level app flow
- `domain`: models and repository interfaces
- `data`: repository implementations, Firestore paths, serializers
- `core`: environment config, parsing, validation, batch graph logic, variance math, utility helpers

The design goal is to keep product rules in the controller and shared utility layer, while repositories provide either local demo data or Firebase-backed persistence.

## Flutter app structure

- [lib/main.dart](/C:/Users/jaime/Documents/New%20project%202/lib/main.dart): Flutter entrypoint
- [lib/app.dart](/C:/Users/jaime/Documents/New%20project%202/lib/app.dart): root app bootstrapping and `MaterialApp`
- [lib/presentation/screens/app_shell.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/screens/app_shell.dart): landing screen, role-based shell routing, manager workspace, training workspace, quiz screen, and most screen widgets
- [lib/presentation/controllers/app_controller.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/controllers/app_controller.dart): central UI state and permission-aware orchestration

## Repository pattern

Repository interfaces live in:

- [lib/domain/repositories/repositories.dart](/C:/Users/jaime/Documents/New%20project%202/lib/domain/repositories/repositories.dart)

Implementations live in:

- [lib/data/repositories/demo_repositories.dart](/C:/Users/jaime/Documents/New%20project%202/lib/data/repositories/demo_repositories.dart)
- [lib/data/repositories/firebase_repositories.dart](/C:/Users/jaime/Documents/New%20project%202/lib/data/repositories/firebase_repositories.dart)

Repository selection happens in:

- [lib/data/repositories/repository_factory.dart](/C:/Users/jaime/Documents/New%20project%202/lib/data/repositories/repository_factory.dart)
- [lib/data/repositories/repository_mode_resolver.dart](/C:/Users/jaime/Documents/New%20project%202/lib/data/repositories/repository_mode_resolver.dart)

This pattern is important because:

- demo mode must stay isolated from live data
- business logic should work in tests without Firebase
- Firebase-specific behavior should stay mostly in the data layer

## Demo vs Firebase mode

### Demo mode

- Uses in-memory/local repositories
- Good for UI work, parsing logic, tests, and flow prototyping
- No live auth or Firestore persistence

### Firebase mode

- Uses Firebase Auth and Firestore repositories
- Requires valid Firebase web config
- Enforces venue-scoped persistence and real auth state

Config lives in:

- [lib/core/config/app_environment.dart](/C:/Users/jaime/Documents/New%20project%202/lib/core/config/app_environment.dart)
- [lib/core/config/firebase_bootstrap.dart](/C:/Users/jaime/Documents/New%20project%202/lib/core/config/firebase_bootstrap.dart)

## Controller responsibilities

[app_controller.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/controllers/app_controller.dart) owns:

- startup wiring
- current user and role-aware permission checks
- invite creation, invite redemption, and venue invite refresh
- success/error state
- owner-only import/review/publish actions
- manager/owner operational actions
- derived data for dashboard and workflow screens
- helper methods used by the UI for filtering and validation

It should not become a dumping ground for raw parsing or Firestore serialization.

## Model structure

Primary domain models live in:

- [lib/domain/models/models.dart](/C:/Users/jaime/Documents/New%20project%202/lib/domain/models/models.dart)

Key groups:

- auth/identity: `AppUser`, `UserRole`, `VenueProfile`
- recipe data: `CocktailRecipe`, `BatchRecipe`, `RecipeIngredient`
- import/review: `RecipeImportDraft`, `RecipeImportResult`, review confidence/status enums
- operations: `WeeklyConcernSession`, `StockConcernItem`, `BartenderWeeklySales`
- quiz data: `QuizSession`, `QuizQuestion`, `QuizAttempt`, `QuestionResponse`
- variance: `VarianceLine`, source/direction enums

## Import, review, and approval flow

Owner-only flow:

1. Source enters from curated assets, OCR text, or PDF import.
2. Parsing happens in utility code.
3. Results are turned into `RecipeImportDraft` objects.
4. Review state is derived by [recipe_review_validator.dart](/C:/Users/jaime/Documents/New%20project%202/lib/core/utils/recipe_review_validator.dart).
5. Owner edits drafts, approves drafts, keeps drafts in review, or deletes false positives.
6. Approved drafts are saved into official recipe and batch collections.

Main files:

- [lib/core/utils/recipe_text_parser.dart](/C:/Users/jaime/Documents/New%20project%202/lib/core/utils/recipe_text_parser.dart)
- [lib/core/utils/curated_recipe_importer.dart](/C:/Users/jaime/Documents/New%20project%202/lib/core/utils/curated_recipe_importer.dart)
- [lib/core/utils/recipe_review_validator.dart](/C:/Users/jaime/Documents/New%20project%202/lib/core/utils/recipe_review_validator.dart)
- [lib/presentation/screens/app_shell.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/screens/app_shell.dart)

## Training flow

Training mode is visible to bartenders and owner/manager users after sign-in.

Public access is intentionally limited to active quiz links in Firebase mode.

Flow:

1. Load approved recipes from repository
2. Show approved library
3. Show study flashcards
4. Generate practice quiz sessions from approved data
5. Surface supportive weak-area suggestions

Main files:

- `TrainingWorkspace` in [app_shell.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/screens/app_shell.dart)
- quiz generation in repositories
- weak-area and dashboard summaries in `AppController`

## Stock concern flow

Manager/owner operational flow:

1. Choose stock concern ingredients
2. Build a relevant recipe pool from approved cocktails and batch decomposition
3. Enter bartender sales for relevant cocktails only
4. Generate targeted quiz links
5. Review results and trends

Main files:

- `WeeklyFocusTab` in [app_shell.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/screens/app_shell.dart)
- [lib/core/utils/manager_trial_helpers.dart](/C:/Users/jaime/Documents/New%20project%202/lib/core/utils/manager_trial_helpers.dart)
- [lib/core/utils/batch_recipe_graph.dart](/C:/Users/jaime/Documents/New%20project%202/lib/core/utils/batch_recipe_graph.dart)

## Quiz flow

Two quiz families exist:

- practice quiz
- stock variance quiz

Flow:

1. Repository generates `QuizSession`
2. Bartender answers questions
3. Responses are converted into `QuizAttempt`
4. Attempt closes the active session
5. Supportive result screen and dashboard/trend metrics are updated

Main files:

- repository quiz generation methods
- `QuizPlayerPanel`, `BartenderQuizScreen`, and `QuizResultsPanel` in [app_shell.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/screens/app_shell.dart)

## Variance calculation flow

Variance math is centralized so business rules stay consistent.

Flow:

1. Quiz attempt captures selected answers and delta from approved spec
2. Variance engine classifies overpour vs underpour
3. Batch variance is decomposed into underlying ingredients
4. Ingredient pricing gives approximate value impact
5. Results are surfaced as supportive insight, not blame

Main files:

- [lib/core/utils/variance_math.dart](/C:/Users/jaime/Documents/New%20project%202/lib/core/utils/variance_math.dart)
- [lib/core/utils/batch_recipe_graph.dart](/C:/Users/jaime/Documents/New%20project%202/lib/core/utils/batch_recipe_graph.dart)

## Batch recipe flow

Batch recipes are first-class approved entities.

Flow:

1. OCR/curated import can create batch drafts
2. Owner approves batch drafts
3. Cocktails reference batches by linked batch id/name
4. Batch graph resolver links cocktails to approved batches
5. Variance and shortage analysis expand batch usage into underlying ingredients

Main files:

- [lib/core/utils/batch_recipe_graph.dart](/C:/Users/jaime/Documents/New%20project%202/lib/core/utils/batch_recipe_graph.dart)
- [lib/core/utils/curated_recipe_importer.dart](/C:/Users/jaime/Documents/New%20project%202/lib/core/utils/curated_recipe_importer.dart)
- [lib/core/utils/recipe_text_parser.dart](/C:/Users/jaime/Documents/New%20project%202/lib/core/utils/recipe_text_parser.dart)

## Trend analytics flow

Dashboard and insight summaries are assembled in the controller from stored sessions and attempts.

Outputs include:

- potential variance by ingredient
- potential variance by batch
- variance by bartender
- weekly confidence
- ingredient misses
- completion status
- supportive training focus areas

Main files:

- `buildDashboard()` in [app_controller.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/controllers/app_controller.dart)
- `InsightsTab` and dashboard UI in [app_shell.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/screens/app_shell.dart)

## Responsibility map

- environment config: `lib/core/config`
- parsing and algorithmic rules: `lib/core/utils`
- collection naming and persistence mapping: `lib/data/firestore`
- auth/data implementations: `lib/data/repositories`
- app state and permission enforcement: `lib/presentation/controllers/app_controller.dart`
- user flow and UI: `lib/presentation/screens/app_shell.dart`

## Invite flow

Invite onboarding now lives across:

- route parsing and join UI in [app_shell.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/screens/app_shell.dart)
- invite orchestration in [app_controller.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/controllers/app_controller.dart)
- invite persistence and atomic redemption in [firebase_repositories.dart](/C:/Users/jaime/Documents/New%20project%202/lib/data/repositories/firebase_repositories.dart)
- enforcement in [firestore.rules](/C:/Users/jaime/Documents/New%20project%202/firestore.rules)

## Common extension points

- Add new derived dashboard metrics in `AppController`
- Add new import validations in `recipe_review_validator.dart`
- Add new parsing support in `recipe_text_parser.dart`
- Add new quiz question behavior in repositories and `VarianceMath`
- Add new persistence fields in `models.dart` plus `firestore_serializers.dart`

## Dangerous files that require extra care

- [firestore.rules](/C:/Users/jaime/Documents/New%20project%202/firestore.rules)
- [lib/data/firestore/firestore_paths.dart](/C:/Users/jaime/Documents/New%20project%202/lib/data/firestore/firestore_paths.dart)
- [lib/domain/models/models.dart](/C:/Users/jaime/Documents/New%20project%202/lib/domain/models/models.dart)
- [lib/presentation/controllers/app_controller.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/controllers/app_controller.dart)
- [lib/core/utils/variance_math.dart](/C:/Users/jaime/Documents/New%20project%202/lib/core/utils/variance_math.dart)
- [lib/core/utils/batch_recipe_graph.dart](/C:/Users/jaime/Documents/New%20project%202/lib/core/utils/batch_recipe_graph.dart)

Changes there can break data compatibility, permission enforcement, or business-rule correctness very quickly.
