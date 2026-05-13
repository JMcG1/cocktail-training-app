# Stock Variance Coach

Supportive Flutter web app for bars that want to reduce cocktail stock variance through targeted recipe learning, short quizzes, and careful coaching language.

## What this build supports

- Manager sign-in with Firebase Auth in production mode
- Demo/local mode for development without Firebase
- PDF and OCR recipe import with manager review and approval
- Approved-recipes-only training, stock concerns, sales entry, and variance workflows
- Weekly stock concern sessions with relevant cocktail filtering
- Bartender quiz sessions through shareable session links
- Supportive potential variance and consistency reporting
- Firestore-backed persistence for production readiness

## Architecture

```text
lib/
  app.dart
  core/
    config/
    theme/
    utils/
  data/
    firestore/
    repositories/
  domain/
    models/
    repositories/
  presentation/
    controllers/
    screens/
```

Key files:

- `lib/data/repositories/demo_repositories.dart`: local/demo repository
- `lib/data/repositories/firebase_repositories.dart`: Firebase Auth + Firestore repositories
- `lib/data/repositories/repository_factory.dart`: demo vs Firebase mode selection
- `lib/data/firestore/firestore_paths.dart`: venue-scoped path builder
- `lib/data/firestore/firestore_serializers.dart`: Firestore model mapping
- `lib/core/utils/recipe_text_parser.dart`: PDF/OCR recipe parsing
- `lib/core/utils/recipe_review_validator.dart`: draft confidence and validation

## Demo mode vs Firebase mode

The app supports two runtime modes:

- `APP_MODE=demo`
  - uses local in-memory repositories
  - uses demo manager credentials
  - no Firebase required
- `APP_MODE=firebase`
  - requires valid Firebase web config
  - uses Firebase Auth and Cloud Firestore
  - persists approved recipes, drafts, sessions, sales, quizzes, and attempts
- `APP_MODE=auto`
  - default
  - uses Firebase when config is present
  - falls back to demo mode otherwise

Required defines:

```text
APP_MODE
DEFAULT_VENUE_ID
FIREBASE_API_KEY
FIREBASE_APP_ID
FIREBASE_MESSAGING_SENDER_ID
FIREBASE_PROJECT_ID
FIREBASE_AUTH_DOMAIN
FIREBASE_STORAGE_BUCKET
DEMO_MANAGER_EMAIL
DEMO_MANAGER_PASSWORD
```

## Firebase project setup

1. Create a Firebase project.
2. Enable Authentication with Email/Password.
3. Create a Firestore database in Native mode.
4. Add a web app and copy the web config values.
5. Configure your Firebase Auth email templates so password reset emails can be sent.
6. A first-run manager can create the first venue from inside the app in Firebase mode.
7. Each signed-in manager should resolve to a `users/{uid}` document with at least:

```json
{
  "displayName": "Venue manager",
  "role": "owner",
  "venueId": "your-venue-id",
  "createdAt": "2026-05-12T12:00:00.000Z",
  "active": true
}
```

8. Each venue should also exist at `venues/{venueId}` with at least:

```json
{
  "name": "Your venue name",
  "ownerUid": "firebase-auth-uid",
  "createdAt": "2026-05-12T12:00:00.000Z",
  "active": true
}
```

## Firestore data model

The app uses venue-scoped collections:

```text
users/{uid}
venues/{venueId}/recipes/{recipeId}
venues/{venueId}/batchRecipes/{batchRecipeId}
venues/{venueId}/recipeDrafts/{draftId}
venues/{venueId}/ingredients/{ingredientId}
venues/{venueId}/stockConcernSessions/{sessionId}
venues/{venueId}/bartenderSales/{salesId}
venues/{venueId}/quizSessions/{quizSessionId}
venues/{venueId}/quizAttempts/{attemptId}
venues/{venueId}/trendSummaries/{summaryId}
```

## Firestore rules deployment

Starter rules live in [firestore.rules](/C:/Users/jaime/Documents/New%20project%202/firestore.rules).

Deploy them with the Firebase CLI:

```powershell
choco install -y firebase-cli
firebase login
firebase use your-project-id
firebase deploy --only firestore:rules
```

The rules are designed so:

- approved recipes and ingredients can be read by the app
- manager-only collections require an owner or manager user doc for the same venue
- venue root documents are protected
- active quiz session documents can be read through a quiz link
- quiz attempts can be created only for active quiz sessions
- no public writes are allowed for admin recipe or venue data

## Running locally

### Demo mode

```powershell
flutter pub get
flutter run -d chrome --dart-define=APP_MODE=demo --dart-define=DEFAULT_VENUE_ID=demo-venue
```

### Firebase mode

```powershell
flutter run -d chrome `
  --dart-define=APP_MODE=firebase `
  --dart-define=DEFAULT_VENUE_ID=your-venue-id `
  --dart-define=FIREBASE_API_KEY=... `
  --dart-define=FIREBASE_APP_ID=... `
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=... `
  --dart-define=FIREBASE_PROJECT_ID=... `
  --dart-define=FIREBASE_AUTH_DOMAIN=... `
  --dart-define=FIREBASE_STORAGE_BUCKET=...
```

Without valid Firebase config, `APP_MODE=auto` falls back to demo mode.

## First-run setup

In Firebase mode, a new manager can:

1. Open the app
2. Choose `Create venue`
3. Enter their name, venue name, email, and password
4. Create the account and become the first owner for that venue
5. Land on the setup checklist inside the manager workspace

The setup checklist guides:

- importing and reviewing cocktail specs
- adding ingredient costs
- creating the first stock concern session
- entering bartender sales
- launching the first quiz

In demo mode, the venue-creation path is intentionally unavailable and the app stays in local walkthrough mode.

## Manager login and password reset

- Managers sign in with Email/Password
- Password reset is available from the sign-in panel
- Demo credentials are shown only in demo mode
- Signing out returns the app to public/demo-safe state

## Venue setup and access assumptions

- every manager belongs to exactly one venue through `users/{uid}.venueId`
- venue-scoped admin data lives under `venues/{venueId}/...`
- owners and managers can access their own venue’s admin data
- bartenders do not get manager dashboard access
- public bartender quiz access is limited to active quiz sessions only

## Quiz link flow

1. Manager creates a stock concern session
2. Manager records relevant bartender sales
3. Manager generates a targeted quiz
4. The app creates an active quiz link such as `/quiz/{sessionId}`
5. The manager can copy the link and share the short session code
6. The manager can close the quiz session when it is no longer needed

When a bartender opens the link:

- they can see only the minimum quiz session data needed
- they can enter their name
- they can complete the quiz
- they receive supportive results

If the session is inactive, expired, or replaced, the link shows a friendly closed message.

## PDF and OCR import workflow

### In-app import flow

1. Sign in as a manager.
2. Open the `Import` tab.
3. Choose `Import curated specs`, a PDF, an OCR text file, or paste OCR text.
4. Review every draft.
5. Approve only the recipes that should become live cocktail specs.

Only approved cocktails and approved batch recipes power training, stock concerns, sales entry, quizzes, and variance calculations.

### Curated OCR dataset

The repository includes curated review-ready datasets at:

- `assets/data/cocktails.json`
- `assets/data/batches.json`

- Use the manager-only `Import curated specs` action in the `Import` tab to load both assets into the review queue.
- The app reads both JSON files from the Flutter asset bundle, not from the filesystem at runtime.
- If your venue already has approved recipes, the import screen lets you choose whether to:
  - skip existing matches
  - update existing matches in place
  - import only new recipes
- Matching is name-based for cocktails, with curated batch ids and aliases used only where the dataset already carries that link information.
- The approval gate still applies. Nothing becomes live until the manager confirms the reviewed drafts.
- Unresolved batch links are intentionally flagged instead of guessed. Managers should fix or confirm them in review before approval.
- `Pornstar Martini` intentionally stays flagged for garnish review because the curated OCR report marks its garnish as missing.

### Curated PDF extraction source files

The curated JSON was produced from the OCR text files under `ocr_output/cocktail_specs_2026/`.

- The current cocktail generator script lives at `tooling/generate_cocktail_dataset.dart`.
- The review report lives at `tooling/ocr_recipe_review.md`.
- Keep the original OCR text files untouched so the source trail stays auditable.
- If you refresh the curated dataset, regenerate or update the cocktail and batch JSON, review the markdown report, then re-import from the in-app curated specs action.
- Batch OCR pages are now parsed separately by the app import pipeline, so OCR refreshes should preserve batch review and approval rather than flattening everything into direct ingredients.

### OCR setup for Windows

Install Tesseract and Poppler from an elevated PowerShell:

```powershell
choco install -y tesseract poppler
```

Verify:

```powershell
tesseract --version
pdftoppm -v
```

Run OCR:

```powershell
C:\Users\jaime\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe tooling\ocr_pdf.py "C:\Users\jaime\Desktop\Cocktail Specs 2026 v1.pdf" --output-dir "ocr_output\cocktail_specs_2026"
```

Parse OCR text into reviewable drafts:

```powershell
dart run tooling/parse_ocr_text.dart "ocr_output\cocktail_specs_2026\Cocktail Specs 2026 v1.ocr.txt"
```

## Production build and deployment

### Production web build

Demo build:

```powershell
flutter build web --release `
  --dart-define=APP_MODE=demo `
  --dart-define=DEFAULT_VENUE_ID=demo-venue
```

Firebase build:

```powershell
flutter build web --release `
  --dart-define=APP_MODE=firebase `
  --dart-define=DEFAULT_VENUE_ID=your-venue-id `
  --dart-define=FIREBASE_API_KEY=... `
  --dart-define=FIREBASE_APP_ID=... `
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=... `
  --dart-define=FIREBASE_PROJECT_ID=... `
  --dart-define=FIREBASE_AUTH_DOMAIN=... `
  --dart-define=FIREBASE_STORAGE_BUCKET=...
```

### Cloudflare Pages

Suggested build command:

```powershell
flutter build web --release --dart-define=APP_MODE=firebase --dart-define=DEFAULT_VENUE_ID=your-venue-id --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=... --dart-define=FIREBASE_MESSAGING_SENDER_ID=... --dart-define=FIREBASE_PROJECT_ID=... --dart-define=FIREBASE_AUTH_DOMAIN=... --dart-define=FIREBASE_STORAGE_BUCKET=...
```

Suggested output directory:

```text
build/web
```

SPA fallback file for deep links is included at [web/_redirects](/C:/Users/jaime/Documents/New%20project%202/web/_redirects) so refreshes on routes like `/quiz/{sessionId}` continue to load the Flutter app.

### Environment variable guidance

For local development and Cloudflare Pages, keep the same `--dart-define` keys aligned with your Firebase web app config:

- `APP_MODE`
- `DEFAULT_VENUE_ID`
- `FIREBASE_API_KEY`
- `FIREBASE_APP_ID`
- `FIREBASE_MESSAGING_SENDER_ID`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_AUTH_DOMAIN`
- `FIREBASE_STORAGE_BUCKET`
- `DEMO_MANAGER_EMAIL`
- `DEMO_MANAGER_PASSWORD`

### Firestore rules deployment

```powershell
firebase deploy --only firestore:rules
```

If you also use indexes later:

```powershell
firebase deploy --only firestore
```

## Manual smoke test

Use this before a real manager trial:

1. Create a new manager account.
2. Create a venue and confirm the setup checklist appears.
3. Import recipes from PDF or OCR text.
4. Review drafts and approve only the recipes that should go live.
5. Confirm approved recipes appear in the cocktail library and training mode.
6. Add at least one ingredient cost.
7. Create a stock concern session using approved ingredients only.
8. Review the affected cocktail pool.
9. Enter bartender sales for relevant cocktails only.
10. Launch a quiz link for one bartender.
11. Open the public quiz link and complete the quiz.
12. Review supportive dashboard insights and historical tracking.
13. Close the quiz session.
14. Refresh the app and confirm recipes, sessions, sales, and quiz history persist.

## Pilot deployment checklist

Use this before opening the app to a live venue pilot:

1. Confirm Firebase Auth Email/Password is enabled.
2. Confirm Firestore rules are deployed to the correct project.
3. Confirm the manager owner account can create a venue and sign back in.
4. Confirm Cloudflare Pages is using the intended Firebase build variables.
5. Confirm at least one OCR import has been reviewed and approved.
6. Confirm ingredient pricing has been added for the main concern spirits and liqueurs.
7. Confirm a stock concern session can be created and refreshed without data loss.
8. Confirm a public quiz link opens only while active and closes cleanly afterwards.
9. Confirm dashboard data persists after a browser refresh.
10. Confirm the venue has at least one backup owner with Firebase access.

## Manager onboarding checklist

Recommended first-week manager workflow:

1. Create the venue and sign in.
2. Import the cocktail spec source.
3. Review OCR drafts carefully and approve only the recipes that should go live.
4. Add bottle pricing for the ingredients you care about most.
5. Run the first weekly stock concern session after stock take.
6. Enter only the relevant bartender sales.
7. Launch the targeted quiz links.
8. Review recipe confidence and training focus areas at the end of the week.

## OCR review guidance

- Keep the no-invention rule strict. Only approve cocktails and batches that are clearly present in the PDF or manually corrected by a manager.
- If a cocktail name looks suspicious, keep it in review rather than guessing.
- If a batch link stays unresolved, keep it in review rather than inventing the match.
- Empty garnish, method, or glassware fields are acceptable if the PDF source is incomplete.
- Delete false positives so they never reach training, stock concern filtering, or quizzes.
- Use the confidence and category filters in the import screen when reviewing large OCR batches.

## Recommended weekly stock-check workflow

1. Complete stock take.
2. Select only the concern ingredients that matter this week.
3. Review the affected cocktail pool.
4. Enter bartender sales for relevant cocktails only.
5. Launch targeted quiz links for the relevant bartenders.
6. Review supportive potential variance, confidence, and consistency opportunity insights.
7. Use the weak-area and trend panels to decide the next training focus.

## Backup and export guidance

- Keep the original PDF and OCR text files alongside the reviewed import source.
- Maintain Firebase project access for at least two trusted managers or owners.
- For pilot backups, export Firestore data periodically from the Firebase console or your normal Firebase backup process.
- If a browser tab is refreshed during service, the weekly stock workflow keeps unsaved progress locally in that browser until it is cleared.

## Cloudflare deployment verification

After deployment:

1. Open the production site.
2. Confirm the landing screen loads without console auth errors.
3. Confirm manager sign-in works with the production Firebase project.
4. Confirm a public quiz link resolves to `/quiz/{sessionId}` correctly.
5. Confirm a hard refresh still loads the Flutter web app and the current route.

## Exact Firebase and Cloudflare deployment steps

1. Install the Firebase CLI if needed:

```powershell
choco install -y firebase-cli
```

2. Authenticate and select the project:

```powershell
firebase login
firebase use your-project-id
```

3. Deploy Firestore rules:

```powershell
firebase deploy --only firestore:rules
```

4. Build Flutter web in Firebase mode:

```powershell
flutter build web --release `
  --dart-define=APP_MODE=firebase `
  --dart-define=DEFAULT_VENUE_ID=your-venue-id `
  --dart-define=FIREBASE_API_KEY=... `
  --dart-define=FIREBASE_APP_ID=... `
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=... `
  --dart-define=FIREBASE_PROJECT_ID=... `
  --dart-define=FIREBASE_AUTH_DOMAIN=... `
  --dart-define=FIREBASE_STORAGE_BUCKET=...
```

5. Deploy the generated `build/web` directory with Cloudflare Pages using the same production environment values.

## Known limitations

- Offline support is pragmatic rather than full offline-first. Unsaved workflow progress is preserved locally, but Firestore writes still require reconnecting.
- OCR quality depends on the source PDF scan quality and Tesseract results.
- Visual trend analysis is currently list- and summary-based rather than chart-heavy.
- POS integration is still intentionally deferred; bartender sales are entered manually.
- Public bartender quiz access is limited to active sessions only and is not a general staff portal.

## Common troubleshooting

- `Manager sign-in is unavailable in local testing`
  - Check whether you are in demo mode. Venue creation and live auth require `APP_MODE=firebase` plus valid Firebase config.
- `PDF import says OCR is required`
  - The PDF is likely image-based. Run the OCR workflow and import the generated `.txt` file into the manager review screen.
- `OCR output contains odd cocktail names`
  - Leave them in review. Do not guess corrections. Fix them manually in the draft editor before approval.
- `No approved recipes yet`
  - Save approved drafts from the import review screen. Pending drafts remain out of training and stock workflows.
- `Bartender quiz link says unavailable`
  - The quiz may be closed or inactive. Launch a fresh active session from the stock workflow.
- `Cloudflare build succeeds but login fails`
  - Recheck the Firebase web config values passed through `--dart-define`, plus your Firebase Auth allowed domains.
- `Firestore writes fail`
  - Confirm rules are deployed, the manager user doc has the right `venueId` and role, and the venue document exists.
- `Firebase connectivity feels inconsistent during service`
  - Check the connection banner in the manager workspace. If the app is offline, continue carefully, keep the local workflow draft intact, and save again once connectivity returns.
- `Auth domain problems`
  - Add your Cloudflare Pages domain to Firebase Authentication allowed domains and verify `FIREBASE_AUTH_DOMAIN` matches the same project.
- `Missing Firebase options`
  - Check every `--dart-define` value in the production build command, especially `FIREBASE_APP_ID`, `FIREBASE_PROJECT_ID`, and `FIREBASE_API_KEY`.
- `Cloudflare blank page after deploy`
  - Confirm the Pages output directory is `build/web`, the site is serving `index.html`, and the `web/_redirects` fallback file is included so deep links reload correctly.
- `Wrong environment mode`
  - `APP_MODE=demo` will keep the app in local/demo mode. Use `APP_MODE=firebase` for production, or `APP_MODE=auto` only when valid Firebase config is present.

If OCR is messy:

- keep uncertain recipes in review
- do not guess missing specs
- correct names and measures manually
- delete false positives before approval

## Persistence behavior

In Firebase mode, the app stores and reloads:

- approved recipes
- recipe review drafts
- ingredients and pricing
- weekly stock concern sessions
- bartender sales
- quiz sessions
- quiz attempts
- trend summaries

In demo mode, the same workflows run locally in memory for fast development and testing.

## Cloudflare Pages deployment

1. Connect the repository to Cloudflare Pages.
2. Use a build command similar to:

```powershell
flutter pub get
flutter build web --release --dart-define=APP_MODE=firebase --dart-define=DEFAULT_VENUE_ID=your-venue-id --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=... --dart-define=FIREBASE_MESSAGING_SENDER_ID=... --dart-define=FIREBASE_PROJECT_ID=... --dart-define=FIREBASE_AUTH_DOMAIN=... --dart-define=FIREBASE_STORAGE_BUCKET=...
```

3. Set publish directory to:

```text
build/web
```

4. Add the same defines as Cloudflare environment variables.

## Validation

```powershell
dart analyze lib test
flutter test
flutter build web --release
```

## Notes

- The app never invents cocktail specs.
- Under-spec answers are shown as quality consistency opportunities, not savings.
- Bartender quiz access stays limited to active session links.
- POS integration is not built yet, but the sales and quiz models are structured so it can be added later.
