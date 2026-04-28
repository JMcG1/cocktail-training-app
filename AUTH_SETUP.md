# Auth Setup

This app uses Firebase Authentication (email/password) plus Firestore for invite-only account creation on web.

## Firebase Authentication

1. Open Firebase Console for `cocktail-training-27e96`.
2. Go to `Authentication > Sign-in method`.
3. Enable `Email/Password`.
4. In `Authentication > Templates`, review the password reset email template so it matches your venue/team tone.

## Authorized Domains

Add these domains in `Authentication > Settings > Authorized domains`:

- `cocktail-training-app.pages.dev`
- your Cloudflare deployment/custom domain if you add one later
- `localhost` for local Chrome development

## Firestore

The app expects these collections:

- `users/{uid}`
- `invites/{CODE}`
- `venues/{venueId}`

Invite-only signup works like this:

1. A manager creates an invite document in `invites`.
2. The join screen reads `/join?code=CODE` or `#/join?code=CODE`.
3. Firebase Auth creates the email/password account.
4. Firestore writes `users/{uid}` using the invite’s `role` and `venueId`.
5. Firestore increments `invites/{CODE}.usedCount`.

## Firestore Rules

A suggested `firestore.rules` file is included in the repo root.

Deploy it with your Firebase project before relying on manager/staff access control:

```bash
firebase deploy --only firestore:rules
```

The current rules assume:

- staff can read/update their own `users/{uid}` profile
- managers can read users and invites for their venue
- invite documents can be read by code holder so `/join?code=...` works pre-login

## Web App Initialization

Firebase web config lives in:

- `lib/firebase_options.dart`

Firebase initialization runs before the app starts in:

- `lib/main.dart`
- `lib/services/backend_runtime_service.dart`

The web entrypoint also preloads Firebase web modules in:

- `web/index.html`

## Current Backend Notes

- Login uses `FirebaseAuth.instance.signInWithEmailAndPassword(...)`
- Invite signup uses `FirebaseAuth.instance.createUserWithEmailAndPassword(...)`
- Password reset uses `FirebaseAuth.instance.sendPasswordResetEmail(...)`
- Training progress is still stored locally, not in Firestore yet

