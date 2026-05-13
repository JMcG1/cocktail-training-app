# Project Context

## App purpose

Stock Variance Coach is a Flutter web app for hospitality teams. It helps venues reduce cocktail stock variance through approved recipe training, targeted stock-focus quizzes, supportive coaching language, and ingredient-level variance reporting.

## Product summary

The product has two connected goals:

- Keep official cocktail and batch specs centrally controlled.
- Help venue managers coach bartenders with supportive, non-blaming workflow and reporting.

The app is not a public recipe app and not a generic POS system. It is a controlled internal tool for venue setup, training, quiz delivery, and variance analysis.

## Core workflow

1. An owner bootstraps the venue and maintains official setup data.
2. The owner imports OCR, PDF, or curated recipe sources into review.
3. The owner reviews and approves cocktail specs, batch specs, and ingredient pricing.
4. Approved specs become the shared source for training, quizzes, stock concern targeting, and variance calculations.
5. Managers create weekly stock concerns, enter bartender sales, launch targeted quizzes, and review results.
6. Bartenders study approved recipes and complete practice or stock-focus quiz sessions.

## Tech stack

- Flutter web
- Dart
- Firebase Authentication with Email/Password in live mode
- Cloud Firestore in live mode
- Cloudflare Pages for deployment
- GitHub-backed deployment workflow
- Demo/local repository mode for development without Firebase

## Current deployment setup

- Production deploy target: Cloudflare Pages
- Production data/auth backend: Firebase
- Build entrypoint: [build.sh](/C:/Users/jaime/Documents/New%20project%202/build.sh)
- Firestore rules file: [firestore.rules](/C:/Users/jaime/Documents/New%20project%202/firestore.rules)
- App runtime mode is controlled by `APP_MODE`
- Current supported modes:
  - `demo`
  - `firebase`
  - `auto`

## Important project constraints

- No public signup.
- Invite-only access is the product rule for ongoing access management.
- Role comes from trusted setup or future invite flow, never user choice.
- The first bootstrap account may create the first owner account for a new venue.
- No public owner creation after bootstrap.
- Owner approves recipes, batches, and pricing.
- Managers handle stock concerns, sales, quizzes, and results.
- Bartenders only learn and take quizzes.
- No invented cocktails or invented missing specs.
- OCR data must go through review and approval before it becomes live.
- Supportive, non-blaming wording only.
- Firestore rules must enforce permissions, not just the UI.

## Current status

Implemented now:

- Three-role permission model: `owner`, `manager`, `bartender`
- Owner-only admin setup for imports, approvals, pricing, and official spec editing
- Manager-only operational stock-focus workflow
- Bartender training and quiz-taking flow
- Batch recipe support in training, variance, stock concern propagation, and dashboard reporting
- Curated OCR-derived dataset import from Flutter assets
- Firebase-mode auth and venue-scoped Firestore persistence

Partially implemented or planned:

- Invite-only access is a product rule, but the dedicated invite collection and invite acceptance workflow are not fully implemented yet
- `auditLogs` are reserved in the schema plan but not yet active in the app
- Bartender lightweight account flow is planned later; public active quiz links remain the main bartender entry path today

## Key directories and files

- [lib/app.dart](/C:/Users/jaime/Documents/New%20project%202/lib/app.dart): app bootstrap and root widget
- [lib/core/config](/C:/Users/jaime/Documents/New%20project%202/lib/core/config): environment and Firebase bootstrap
- [lib/core/utils](/C:/Users/jaime/Documents/New%20project%202/lib/core/utils): parsing, validation, batch graph, variance math, curated import
- [lib/data/firestore](/C:/Users/jaime/Documents/New%20project%202/lib/data/firestore): collection paths and serializers
- [lib/data/repositories](/C:/Users/jaime/Documents/New%20project%202/lib/data/repositories): demo and Firebase repositories
- [lib/domain/models](/C:/Users/jaime/Documents/New%20project%202/lib/domain/models): shared domain models
- [lib/domain/repositories](/C:/Users/jaime/Documents/New%20project%202/lib/domain/repositories): repository interfaces
- [lib/presentation/controllers/app_controller.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/controllers/app_controller.dart): main app state and permission gating
- [lib/presentation/screens/app_shell.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/screens/app_shell.dart): major UI flows
- [assets/data](/C:/Users/jaime/Documents/New%20project%202/assets/data): curated cocktail and batch datasets
- [ocr_output/cocktail_specs_2026](/C:/Users/jaime/Documents/New%20project%202/ocr_output/cocktail_specs_2026): original OCR text source files
- [tooling](/C:/Users/jaime/Documents/New%20project%202/tooling): OCR/dataset tooling and review outputs
- [test](/C:/Users/jaime/Documents/New%20project%202/test): behavior and workflow tests

## Things Codex must not change without explanation

- Firestore collection names and paths
- `UserRole` meanings or role boundaries
- Approval gate behavior for OCR/PDF/curated imports
- Supportive wording model for variance and coaching output
- Batch decomposition and cost calculation behavior
- Public quiz session safety model
- Demo/live repository separation
- Core environment define names passed through `build.sh`
- Curated asset format in `assets/data` without migration notes

If any of those need to change, document the reason, migration impact, and test coverage in the same task.
