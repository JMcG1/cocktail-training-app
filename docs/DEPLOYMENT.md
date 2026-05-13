# Deployment

## Overview

The live app is deployed as a Flutter web build on Cloudflare Pages and uses Firebase for authentication and Firestore persistence when `APP_MODE=firebase`.

## Firebase project setup

1. Create or open the Firebase project.
2. Add a web app to the project.
3. Enable Firestore.
4. Enable Firebase Authentication with Email/Password.
5. Keep the Firebase web config values available for Cloudflare build variables.

## Email/password auth

- Production auth uses Firebase Email/Password.
- The app expects authenticated users to resolve to `users/{uid}` documents with the correct `role` and `venueId`.
- Password reset is supported from the login screen.

## Authorized domains

Firebase Authentication should allow the live Cloudflare Pages domains.

Known production domains used in this project:

- `bar-variance-training.pages.dev`
- `f59d1f00.bar-variance-training.pages.dev`

If the preview or production deployment domain changes, add the new domain in Firebase Auth before expecting live sign-in to work.

## Firestore rules deployment

Rules source:

- [firestore.rules](/C:/Users/jaime/Documents/New%20project%202/firestore.rules)

Deploy with Firebase CLI:

```powershell
firebase login
firebase use your-project-id
firebase deploy --only firestore:rules
```

If indexes are needed later:

```powershell
firebase deploy --only firestore
```

## Cloudflare Pages setup

Current deployment pattern:

- GitHub repository connected to Cloudflare Pages
- automatic deploys from pushed commits
- build output directory: `build/web`
- build command uses [build.sh](/C:/Users/jaime/Documents/New%20project%202/build.sh)

## GitHub auto-deploy

Recommended setup:

- connect `main` branch to production
- allow preview builds for pull requests or non-production branches if desired
- keep Cloudflare environment variables in sync across production and preview where appropriate

## `build.sh` behavior

[build.sh](/C:/Users/jaime/Documents/New%20project%202/build.sh):

- reads Cloudflare environment variables
- prints safe diagnostics
- clones Flutter stable
- enables web support
- runs `flutter pub get`
- builds web release with quoted `--dart-define` arguments

Safe diagnostics currently printed:

- `APP_MODE`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_AUTH_DOMAIN`
- Firebase API key length only
- Firebase App ID length only

## Required Cloudflare environment variables

Document the names, not the private values.

- `APP_MODE`
- `FIREBASE_API_KEY`
- `FIREBASE_AUTH_DOMAIN`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_STORAGE_BUCKET`
- `FIREBASE_MESSAGING_SENDER_ID`
- `FIREBASE_APP_ID`

Optional local/demo variables:

- `DEFAULT_VENUE_ID`
- `DEMO_MANAGER_EMAIL`
- `DEMO_MANAGER_PASSWORD`

## Public Firebase web config

Firebase web config values are not treated as secret server credentials, but they still should not be copied around unnecessarily in docs or logs.

This repo documents:

- required variable names
- safe diagnostics
- setup flow

It should avoid:

- pasting unnecessary live values into markdown

## How to rotate the Firebase API key

1. Create or rotate the web API key in Google Cloud / Firebase console.
2. Confirm application restrictions are still correct for the web app.
3. Update `FIREBASE_API_KEY` in Cloudflare Pages environment variables.
4. Rebuild/redeploy the site.
5. Confirm the app boots and sign-in works.

Do not rotate only one part of the config set and assume the deploy is valid.

## How to retry deployments

If a Cloudflare deploy fails:

1. Recheck environment variable values.
2. Re-run the deploy from Cloudflare Pages.
3. If the repository changed, push a no-op or follow-up commit.
4. Verify the build logs include the expected safe diagnostics.

## How to run a local build

Demo mode:

```powershell
flutter run -d chrome --dart-define=APP_MODE=demo --dart-define=DEFAULT_VENUE_ID=demo-venue
```

Local release build:

```powershell
flutter build web --release --dart-define=APP_MODE=demo --dart-define=DEFAULT_VENUE_ID=demo-venue
```

## How to run a Firebase build locally

```powershell
flutter build web --release `
  --dart-define=APP_MODE=firebase `
  --dart-define=DEFAULT_VENUE_ID=your-venue-id `
  --dart-define=FIREBASE_API_KEY=... `
  --dart-define=FIREBASE_AUTH_DOMAIN=... `
  --dart-define=FIREBASE_PROJECT_ID=... `
  --dart-define=FIREBASE_STORAGE_BUCKET=... `
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=... `
  --dart-define=FIREBASE_APP_ID=...
```

## Common errors and fixes

### `firebase_auth/api-key-not-valid`

Check:

- Cloudflare env var value is present
- `build.sh` is passing the key through correctly
- Firebase project id and app id match the same web app
- the deployed bundle reflects the current environment variables

### Firebase sign-in popup or domain errors

Check:

- Firebase Auth authorized domains
- `FIREBASE_AUTH_DOMAIN`
- Cloudflare Pages domain and preview domain entries

### Firestore permission denied

Check:

- deployed `firestore.rules`
- `users/{uid}` role and `venueId`
- owner vs manager action boundaries

### App falls back to demo unexpectedly

Check:

- `APP_MODE`
- whether required Firebase config values are present
- Firebase bootstrap errors at startup

### Cloudflare build succeeds but runtime auth fails

Check:

- live Firebase config variable names
- safe build diagnostics in Cloudflare logs
- authorized domains
- Firestore rules

### Deep links like `/quiz/{sessionId}` fail on refresh

Check:

- Cloudflare serves the SPA fallback
- `build/web` includes the expected routing fallback files

## Manual post-deploy smoke test

1. Open production site.
2. Confirm login screen loads.
3. Confirm owner sign-in works.
4. Confirm manager sign-in works.
5. Confirm managers do not see Admin setup.
6. Confirm owner can access Admin setup.
7. Launch a quiz and open the public link.
8. Close the quiz and confirm the link stops working.
