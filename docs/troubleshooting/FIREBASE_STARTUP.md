# Firebase Startup Troubleshooting

## Symptom

Production site shows:

`Firebase mode could not be started. Check the Firebase web config, allowed auth domain, and deployed Firestore rules, then try again.`

## Required Firebase Auth authorized domains

At minimum, Firebase Authentication must allow:

- your production Cloudflare Pages domain
- any Cloudflare preview domain you expect to use for live Firebase sign-in

Known domains for this project:

- `bar-variance-training.pages.dev`
- `f59d1f00.bar-variance-training.pages.dev`

## Cloudflare Pages domain requirement

If the site hostname is not listed as an authorized domain in Firebase Auth, web auth startup and sign-in flows can fail even when the rest of the config looks correct.

## Where to find Firebase web config

In Firebase console:

1. Open Project settings
2. Open the web app entry
3. Copy the Firebase web config values

Relevant values:

- `apiKey`
- `appId`
- `messagingSenderId`
- `projectId`
- `authDomain`
- `storageBucket`

## Current startup model in this app

- Flutter web initializes Firebase with `DefaultFirebaseOptions.currentPlatform`
- Cloudflare environment variables are still passed through the build for diagnostics and consistency checks
- In production Firebase mode, the app does not silently fall back to demo/local mode

## Common causes of this exact error

### 1. Wrong Firebase web app config

Symptoms:

- startup fails before login screen is usable
- browser console shows initialize-app or auth config errors

Check:

- `lib/firebase_options.dart`
- Cloudflare build diagnostics
- Firebase console web app config

### 2. Missing authorized domain

Symptoms:

- Firebase initializes but auth-related startup or login fails

Check:

- Firebase Auth authorized domains list
- exact hostname shown in the browser address bar

### 3. Stale Cloudflare deployment

Symptoms:

- code looks fixed in GitHub but live site still shows old behavior

Check:

- Cloudflare deployment commit SHA
- build logs
- whether the deployment was rebuilt after env changes

### 4. Incorrect Cloudflare environment variables

Symptoms:

- build logs show missing or unexpectedly short values

Check:

- `APP_MODE`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_AUTH_DOMAIN`
- API key length
- App ID length

### 5. Protected Firestore read too early

Symptoms:

- startup crashes only for returning authenticated users

Check:

- `users/{uid}` exists
- `venueId` is valid
- Firestore rules allow the authenticated user to read their own user doc
- venue read happens only after a valid role/venue lookup

## Browser-console diagnostics now emitted

Startup logging includes:

- Firebase app name
- projectId
- authDomain
- current hostname
- whether `Firebase.initializeApp` succeeded
- exact exception
- stack trace

## Safe manual checklist

1. Open the site and inspect browser console.
2. Confirm logged startup diagnostics match the expected hostname and project id.
3. Confirm Firebase Auth authorized domains include the exact Pages hostname.
4. Confirm Cloudflare deployed the expected commit.
5. Confirm `APP_MODE=firebase` in the build logs.
6. Confirm `lib/firebase_options.dart` matches the intended Firebase web app.
