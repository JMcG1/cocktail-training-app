# Cocktail Training

Mobile-first Flutter web training app for hospitality teams. It helps bartenders and managers learn approved cocktail specs, practise them through quizzes, track improvement over time, and use ingredient pricing plus venue sales data to highlight training opportunities.

## Project overview

The app is built around one core product rule: official cocktail specs, batch specs, images, and pricing are centrally approved by the owner/admin, then reused by managers for team coaching and by bartenders for study and quiz practice.

## Documentation index

- [Project context](docs/PROJECT_CONTEXT.md)
- [Product spec](docs/PRODUCT_SPEC.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Security model](docs/SECURITY_MODEL.md)
- [Firestore schema](docs/FIRESTORE_SCHEMA.md)
- [Deployment](docs/DEPLOYMENT.md)
- [Business rules](docs/BUSINESS_RULES.md)
- [Product roadmap](docs/ROADMAP.md)
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
- Intended Firebase plan: Spark/no-cost unless usage outgrows the free tier
- Supported production backend shape: Auth + Firestore only
- Firebase Cloud Functions and Firebase Storage are not part of the supported production path for invite, join, or quiz sharing
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
