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
- Invite joins resolve through `/join/{venueId}/{inviteId}` and the same URL can be rendered as a QR code inside the app.
- Owner bootstrap should be treated as a controlled recovery/setup flow, not as public registration.

## Trust boundaries in production

- Firebase Auth alone is not enough to grant app access.
- Firestore rules decide whether an authenticated account becomes an owner, manager, or bartender in a specific venue.
- Owner bootstrap now requires a pre-created `bootstrapGrants/{email}` document and consumes it during venue creation.
- Manager and bartender account creation remains invite-driven through `venues/{venueId}/invites/{inviteId}`.

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

Before deploying rules changes, confirm that any required bootstrap grant documents already exist for planned owner setup emails. Otherwise owner bootstrap will fail closed.

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
- injects `APP_BUILD` from the current git commit short hash
- disables the Flutter PWA strategy for Pages builds
- builds production web output with the HTML renderer for stronger Firefox Android compatibility

## Flutter web cache strategy

This app now uses a custom [web/flutter_bootstrap.js](/C:/Users/jaime/Documents/New%20project%202/web/flutter_bootstrap.js) instead of the generated default bootstrap registration flow.

Current behavior:

- do not register a Flutter service worker at startup
- actively unregister legacy Flutter service workers left from older deploys
- clear legacy Flutter cache buckets in the browser before loading the app shell

Why this matters:

- mobile browsers, especially Firefox Android, can stay pinned to stale Flutter shell files after deployment if an older service worker remains active
- desktop may appear healthy while mobile is still running an older `main.dart.js`
- Firefox Android is also more sensitive to CanvasKit/WebGL and browser storage limitations, so production builds use the HTML renderer to reduce browser-specific startup failures

## Cloudflare cache headers for Flutter web

Critical shell files are marked `no-store` through [web/_headers](/C:/Users/jaime/Documents/New%20project%202/web/_headers):

- `/`
- `/index.html`
- `/flutter_bootstrap.js`
- `/flutter.js`
- `/main.dart.js`
- `/version.json`
- `/manifest.json`

This keeps Cloudflare and mobile browsers from holding onto an old app shell after redeploys.

If Cloudflare caching is customized later, keep these shell files effectively uncached unless the deployment flow introduces filename hashing for them.

## Firefox Android notes

The current production build strategy is tuned for mobile-browser stability:

- HTML renderer instead of CanvasKit
- no Flutter service worker registration
- explicit cache clearing for legacy Flutter caches
- Firebase Auth persistence allowed to fall back from local storage to session or in-memory mode
- Firestore web cache forced to in-memory mode with long-polling auto-detection

This means the live app prioritizes reliable startup over offline persistence on Firefox Android and private-browsing style environments.

## Bootstrap grant setup

Use bootstrap grants only when a new owner account truly needs to be provisioned.

Suggested document:

- collection: `bootstrapGrants`
- document id: lowercased owner email
- fields:
  - `email`
  - `role: "owner"`
  - `disabled: false`
  - optional `expiresAt`

After successful bootstrap, the app/rules consume the grant by setting:

- `disabled: true`
- `usedAt`
- `usedByUid`
- `venueId`

This keeps owner bootstrap off the public path even if someone creates a raw Firebase Auth account outside the app.

## Remaining limitation

- Firebase Email/Password sign-up is still enabled at the provider level, so a raw auth account can still be created outside the app.
- The current hardening prevents that account from becoming an app owner, manager, or bartender without a matching bootstrap grant or venue invite.
- For true invite-only account creation, move signup behind a callable Cloud Function, admin-issued custom token flow, or Firebase blocking function.

## Incident recovery guidance

If invite or bootstrap onboarding fails after auth account creation:

1. Check whether a `users/{uid}` document was written.
2. Check whether the invite or bootstrap grant was consumed.
3. If Firestore commit failed and the auth account remained orphaned, remove the auth user in the Firebase console before retrying.
4. If a bootstrap grant or invite was consumed incorrectly, disable it and issue a fresh one rather than trying to reuse stale state.

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
5. On mobile, confirm the login screen shows the expected `Build <hash>` label after refresh.

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
- invite role, expiry, `disabled`, and `currentUses` if the failure happens during invite join

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

### Mobile shows startup failure while desktop works

Check:

- the login or startup screen `Build <hash>` label matches the latest deployment on both devices
- browser site data has been cleared on the mobile device
- Firefox Android or Safari iOS is not still holding an older shell file
- `web/_headers` is present in the deployed output
- custom bootstrap is not registering a service worker

If needed:

1. Clear site data in the mobile browser.
2. Open the site in private/incognito mode.
3. Confirm the build label matches desktop.
4. If it does not, the issue is stale cached shell content rather than Firebase config.

## Manual post-deploy smoke test

1. Open production site.
2. Confirm login screen loads.
3. Confirm owner sign-in works.
4. Confirm manager sign-in works.
5. Confirm managers do not see Admin setup.
6. Confirm owner can access Admin setup.
7. Launch a quiz and open the public link.
8. Close the quiz and confirm the link stops working.
