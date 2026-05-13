# Stock Variance Coach

Supportive Flutter web app for bars that reduce cocktail stock variance through approved recipe training, targeted quizzes, batch-aware variance analysis, and supportive coaching language.

## Project overview

The app is built around one core product rule: official cocktail specs, batch specs, and pricing are centrally approved by the owner, then reused by managers for weekly stock-focus operations and by bartenders for learning and quiz-taking.

## Documentation index

- [Project context](docs/PROJECT_CONTEXT.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Security model](docs/SECURITY_MODEL.md)
- [Firestore schema](docs/FIRESTORE_SCHEMA.md)
- [Deployment](docs/DEPLOYMENT.md)
- [Business rules](docs/BUSINESS_RULES.md)
- [Codex workflow](docs/CODEX_WORKFLOW.md)

## Quick local run

Demo mode:

```powershell
flutter pub get
flutter run -d chrome --dart-define=APP_MODE=demo --dart-define=DEFAULT_VENUE_ID=demo-venue
```

Firebase mode:

```powershell
flutter run -d chrome `
  --dart-define=APP_MODE=firebase `
  --dart-define=DEFAULT_VENUE_ID=your-venue-id `
  --dart-define=FIREBASE_API_KEY=... `
  --dart-define=FIREBASE_AUTH_DOMAIN=... `
  --dart-define=FIREBASE_PROJECT_ID=... `
  --dart-define=FIREBASE_STORAGE_BUCKET=... `
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=... `
  --dart-define=FIREBASE_APP_ID=...
```

## Quick deployment notes

- Production hosting: Cloudflare Pages
- Production auth/data: Firebase Auth + Firestore
- Build script: [build.sh](build.sh)
- Firestore rules: [firestore.rules](firestore.rules)
- Full setup and troubleshooting: [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)

## Curated OCR dataset

Curated approved-source data lives in:

- [assets/data/cocktails.json](assets/data/cocktails.json)
- [assets/data/batches.json](assets/data/batches.json)

Original OCR source files live in:

- [ocr_output/cocktail_specs_2026](ocr_output/cocktail_specs_2026)

Review output and tooling live in:

- [tooling/ocr_recipe_review.md](tooling/ocr_recipe_review.md)
- [tooling/generate_cocktail_dataset.dart](tooling/generate_cocktail_dataset.dart)

## Validation commands

```powershell
dart analyze lib test tooling
flutter test
flutter build web --release
```

## Key rules to remember

- No invented cocktails or missing specs
- OCR, PDF, and curated imports still require review and approval
- Owners approve recipes, batches, and pricing
- Managers focus on stock concerns, sales, quizzes, and results
- Bartenders focus on learning and quiz-taking
- Supportive, non-blaming wording only
