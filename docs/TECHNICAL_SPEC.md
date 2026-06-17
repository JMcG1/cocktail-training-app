# Cocktail Training Technical Spec

Last updated: 2026-06-17

## App architecture

The app is a Flutter web client with a layered structure:

- `lib/presentation`: screens, widgets, and flow orchestration
- `lib/domain`: core models and repository contracts
- `lib/data`: Firebase and demo repository implementations, Firestore serializers, collection paths
- `lib/core`: config, parsing, matching, pricing, batch graph, PDF import, and utility logic

The main orchestration point is:

- [lib/presentation/controllers/app_controller.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/controllers/app_controller.dart)

The largest UI shell is currently:

- [lib/presentation/screens/app_shell.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/screens/app_shell.dart)

## Main folders

| Folder | Purpose |
| --- | --- |
| `lib/core/config` | Environment config, Firebase bootstrap, app mode wiring |
| `lib/core/utils` | Business utilities such as price matching, batch resolution, variance math, PDF parsing, and CSV import |
| `lib/data/firestore` | Firestore path constants and serializers |
| `lib/data/repositories` | Demo and Firebase repository implementations |
| `lib/domain/models` | App models, enums, and value types |
| `lib/domain/repositories` | Repository interfaces |
| `lib/presentation/controllers` | App state and permission-aware orchestration |
| `lib/presentation/screens` | Role-aware screens and widgets |
| `assets/data` | Bundled approved cocktail and batch catalog |
| `docs` | Product, deployment, security, schema, audit, and roadmap docs |

## Runtime modes

The app supports:

- `demo`
- `firebase`

`AppEnvironment` decides which mode is active, and Cloudflare build variables provide the Firebase web config for production builds.

## Firebase Auth usage

Production auth uses Firebase Email/Password.

Important design points:

- Firebase Auth proves identity only
- Firestore `users/{uid}` documents provide role and venue scope
- Firestore rules enforce actual permissions
- Password reset is initiated from the login screen
- Logout clears local signed-in state

Owner bootstrap is separately gated by `bootstrapGrants/{email}` and can be disabled in the environment.

## Firestore collections in live code

The live collection paths come from [lib/data/firestore/firestore_paths.dart](/C:/Users/jaime/Documents/New%20project%202/lib/data/firestore/firestore_paths.dart).

### Global collections

- `bootstrapGrants`
- `cocktails`
- `batches`
- `cocktailIngredients`
- `users`

### Venue-scoped collections

- `venues/{venueId}/recipes`
- `venues/{venueId}/batchRecipes`
- `venues/{venueId}/invites`
- `venues/{venueId}/recipeDrafts`
- `venues/{venueId}/ingredients`
- `venues/{venueId}/stockConcernSessions`
- `venues/{venueId}/bartenderSales`
- `venues/{venueId}/quizSessions`
- `venues/{venueId}/quizAttempts`
- `venues/{venueId}/trendSummaries`

### Proposed collections mentioned in product planning, not live paths

- `venues/{venueId}/auditLogs`
- `venues/{venueId}/batches`

These are not current live code paths and should not be treated as implemented.

## Role model

Current stored roles:

- `owner`
- `manager`
- `bartender`
- legacy `staff` is still tolerated in compatibility paths

Current app-side hierarchy:

- owner inherits manager workflows
- manager inherits bartender workflows
- hierarchy now lives on `UserRole` itself via shared helpers so controllers and repositories can reuse the same access model

Key controller getters:

- `canAccessBartenderWorkflows`
- `canAccessManagerWorkflows`
- `canAccessAdminSetup`
- `canManageVenueInvites`

## Invite flow

The invite flow is venue-scoped and role-driven.

1. Owner or manager creates an invite in `venues/{venueId}/invites`.
2. Join URL includes the venue and invite identifiers.
3. The join screen reads the invite and displays the fixed role.
4. The user redeems the invite with email, password, and display name.
5. The app creates the Firebase Auth account and the matching `users/{uid}` document.
6. Firestore rules enforce venue scope and allowed roles.

Important current behaviour:

- the user cannot choose their own role from the join flow
- expired, disabled, and overused invites are rejected
- manager-created invites are scoped to the manager's venue

## Recipe flow

The live bartender-facing recipe source is the fixed approved bundled catalog plus Firestore-backed sync behaviour.

Current flow:

1. Bundled approved cocktails and batches load from assets.
2. Firebase mode may overlay Firestore-backed approved data.
3. Approved cocktails appear in the library, study, and quiz flows.
4. Owner-only review and import flows can still prepare or save official data.
5. Price backfills are matched safely by name aliases without overwriting specs.

Current approved catalog counts observed in tests:

- 37 cocktails
- 10 batch recipes

## Quiz flow

The app currently supports:

- practice quizzes
- stock-focus surprise quizzes
- spec-focused quiz behaviour
- garnish and glassware focus as an explicit option

Current flow:

1. Approved recipes load.
2. A quiz session is generated.
3. The bartender answers questions.
4. A `QuizAttempt` is saved.
5. Results and supportive summaries are shown.
6. Managers can review team outcomes; all signed-in users can review personal progress.

## Sales and stock-focus flow

Current manager/owner flow:

1. Create a weekly stock concern session.
2. Choose ingredients of concern.
3. Build the related cocktail target pool.
4. Enter manual sales or import a sales PDF.
5. Launch a live surprise quiz from the selected focus.
6. Review sales-linked variance and coaching summaries.

PDF import notes:

- the app currently parses the present Aztec-style PDF layout
- it extracts employee/product rows and sales value
- it matches approved, priced cocktails only
- it estimates quantity sold by dividing sales value by cocktail price
- if no bartender name matches, it fills each target cocktail with `25` sales for manager testing

## Ingredient cost flow

The existing admin ingredient-cost area is reused.

Ingredient data currently stores:

- `name`
- `bottleSizeMl`
- `bottleCost`
- `isGarnish`

Current behaviour:

- commodity CSV import can prefill bottle size and bottle price data
- unmatched ingredients remain manually editable
- garnish items can be marked and allowed to stay at zero cost
- batch-related price impact is derived from underlying ingredient costs

## Deployment process

Production is hosted on Cloudflare Pages and built from GitHub.

Key files:

- [build.sh](/C:/Users/jaime/Documents/New%20project%202/build.sh)
- [web/_headers](/C:/Users/jaime/Documents/New%20project%202/web/_headers)
- [web/index.html](/C:/Users/jaime/Documents/New%20project%202/web/index.html)
- [web/flutter_bootstrap.js](/C:/Users/jaime/Documents/New%20project%202/web/flutter_bootstrap.js)
- [web/flutter_service_worker.js](/C:/Users/jaime/Documents/New%20project%202/web/flutter_service_worker.js)

Current build expectations:

- Cloudflare builds `build/web`
- `APP_MODE=firebase` must be set for production
- `FIREBASE_*` values are injected at build time
- Flutter web is built with `--pwa-strategy=none`

## Cache and service worker strategy

The current deployment strategy is intentionally conservative to avoid stale Flutter builds in normal browser tabs.

Current protections:

- `index.html` references `flutter_bootstrap.js` with a build stamp
- build output writes version metadata
- `_headers` disables aggressive caching for critical bootstrap files
- `flutter_bootstrap.js` clears legacy caches and service workers
- `flutter_service_worker.js` is cleanup-only

This is meant to keep Cloudflare deployments safe in normal tabs, not only in incognito mode.

## Firestore rules and security model

The app depends on Firestore rules for real enforcement.

Rules are expected to protect:

- venue scoping
- invite redemption
- owner-only admin writes
- manager operational reads and writes
- active-session-only public quiz access

The client should never be treated as the permission boundary on its own.

Current regression harness:

- `npm run test:firestore-rules`
- [test/firestore_rules_test.cjs](/C:/Users/jaime/Documents/New%20project%202/test/firestore_rules_test.cjs)

The current emulator-backed rules coverage checks:

- owner ingredient-cost writes
- manager denial on owner-only ingredient-cost writes
- manager access to non-owner venue teammates
- manager denial on owner profile reads
- manager invite creation
- bartender denial on invite creation
- public redeemable invite access without invite listing
- manager stock concern writes
- bartender denial on stock concern writes
- bartender quiz attempt creation for their own active session only

## Current technical risks

- `app_shell.dart` still concentrates a large amount of UI logic
- some role checks are still duplicated in UI and controller logic
- true provider-level invite-only auth is not fully enforced because Email/Password signup still exists at the Firebase provider level
- the sales PDF parser is format-sensitive and should stay covered by regression tests
- the new Firestore rules harness is targeted rather than exhaustive, so invite redemption transactions and bootstrap-grant flows still need deeper coverage

## Recommended near-term refactors

1. Break the largest workspace widgets into smaller presentation files.
2. Centralize remaining permission checks behind a shared role/permission helper.
3. Extend the Firestore rules harness to cover bootstrap-grant flows, invite redemption updates, and cross-venue quiz data boundaries.
4. Add parser regression fixtures for commodity CSV and sales PDF imports.
