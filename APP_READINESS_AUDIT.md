# App Readiness Audit

Date: 2026-06-15
Project: Flutter web cocktail training app
Scope: Codebase audit only. No major changes made during this pass.

## Summary

The app has a solid amount of product logic already in place: approved cocktails exist, prices are mostly wired in, invite flows and role-aware screens exist, Firebase mode and demo mode are both supported, and the web build includes good anti-cache protection for Flutter web.

The main readiness problem is not "missing everything"; it is that a few structural issues can make the live app unreliable or confusing:

- recipe, batch, and ingredient data are split across global and venue-scoped Firestore collections
- Firestore rules for owner bootstrap look malformed and may block first-time setup
- the quiz/share flow is not aligned with Firebase Auth requirements
- the analyzer/test suite is not clean, so regressions can slip through

If those are fixed first, the rest becomes much easier to trust and extend.

---

## 1. Critical Blockers

### Issue 1
- Area: Firestore data model
- Severity: Critical
- What is wrong: Approved cocktails, batches, and ingredients are not consistently stored and loaded from the same place. The app loads global collections (`cocktails`, `batches`, `cocktailIngredients`) but some import/review flows save venue-scoped collections (`venues/{venueId}/recipes`, `batchRecipes`, `ingredients`).
- Why it matters: Imported or reviewed data can fail to appear in the live app, and ingredient pricing can leak across venues. This is the biggest risk to correctness and multi-venue safety.
- File(s) likely involved: `lib/data/firestore/firestore_paths.dart`, `lib/data/repositories/firebase_repositories.dart`
- Suggested fix: Choose one canonical model for production data. Most likely: keep approved cocktail content as a single global catalog and keep venue-specific mutable data in venue-scoped collections, or fully move all live reads/writes to venue-scoped collections. Then update all loaders, save methods, and seed/import logic to match.
- Whether Codex can fix it automatically or needs my input: Needs your input on the intended tenancy model, then Codex can implement it.

### Issue 2
- Area: Firestore security rules
- Severity: Critical
- What is wrong: Owner/bootstrap rules appear malformed. Venue creation relies on bootstrap grant helpers that use `request.resource.data.email`, but venue docs do not naturally contain that field. The `bootstrapGrants` delete rule also references `venueId` outside its scope.
- Why it matters: First-time owner/admin setup may fail in production even if the UI looks correct. Broken rules also reduce confidence in all role-gated behavior.
- File(s) likely involved: `firestore.rules`
- Suggested fix: Rewrite the bootstrap grant flow so venue creation checks a valid grant using explicit fields available on the venue create request, and remove invalid variable references from `bootstrapGrants` rules.
- Whether Codex can fix it automatically or needs my input: Codex can likely fix it automatically after confirming the intended owner bootstrap flow.

### Issue 3
- Area: Quiz access flow
- Severity: Critical
- What is wrong: The app routes directly to `/quiz/...` screens, but Firestore rules for saving quiz attempts require a signed-in venue user. The UI currently suggests quizzes can be opened from links/QR codes.
- Why it matters: Staff can reach a quiz screen and then fail when results try to save, which breaks a core bartender workflow.
- File(s) likely involved: `lib/presentation/screens/app_shell.dart`, `firestore.rules`, `lib/data/repositories/firebase_repositories.dart`
- Suggested fix: Pick one model and align everything to it: either require login before quiz launch, or support invite-token/public quiz entry with a different persistence model and rules.
- Whether Codex can fix it automatically or needs my input: Needs your decision on the intended quiz access model.

### Issue 4
- Area: Test and analyzer health
- Severity: Critical
- What is wrong: `dart analyze` is not clean, and there are failing/stale tests. Two widget tests reference a missing `RecipeImportTab`. One study-mode test fails because the key reveal button is not visible in the default test viewport. One Firebase/serialization test now assumes only one ingredient and crashes with `Too many elements`.
- Why it matters: The app does not have a trustworthy regression safety net right now.
- File(s) likely involved: `test/recipe_import_widget_test.dart`, `test/recipe_import_publish_error_widget_test.dart`, `test/widget_test.dart`, `test/firebase_mode_and_serialization_test.dart`
- Suggested fix: Remove or update obsolete tests, adjust the study screen layout/test harness for small viewports, and rewrite the stale Firebase test assumptions to match the current bundled catalog.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically.

---

## 2. Authentication And Invites

### Issue 5
- Area: Owner/admin bootstrap
- Severity: High
- What is wrong: The public landing page still exposes an owner/admin setup toggle and bootstrap flow.
- Why it matters: It is useful during setup, but it also exposes an internal onboarding path in the live login experience and increases the chance of production confusion.
- File(s) likely involved: `lib/presentation/screens/app_shell.dart`, `lib/presentation/controllers/app_controller.dart`
- Suggested fix: Hide this behind an environment flag, admin-only deployment mode, or a dedicated bootstrap URL that can later be disabled.
- Whether Codex can fix it automatically or needs my input: Needs your preference for how visible bootstrap should remain.

### Issue 6
- Area: Invite-only signup policy
- Severity: High
- What is wrong: The UI suggests managers can only invite bartenders, but backend logic and rules appear more permissive and still accept manager invites in some paths.
- Why it matters: Policy mismatches create hard-to-debug permission surprises and can lead to accidental privilege escalation.
- File(s) likely involved: `lib/presentation/controllers/app_controller.dart`, `lib/data/repositories/firebase_repositories.dart`, `firestore.rules`
- Suggested fix: Enforce the same invite role rules in UI, controller, repository, and security rules.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically after a quick confirmation of the exact allowed roles.

### Issue 7
- Area: Staff removal / account lifecycle
- Severity: High
- What is wrong: Removing a venue user appears to delete the Firestore user document only, not the Firebase Auth account.
- Why it matters: Removed staff can still have valid sign-in credentials, which creates orphaned auth users and confusing login failures.
- File(s) likely involved: `lib/presentation/controllers/app_controller.dart`, `lib/data/repositories/firebase_repositories.dart`
- Suggested fix: Decide whether removal means full account deletion, venue access removal, or deactivation. Then make the UI and backend follow that model consistently.
- Whether Codex can fix it automatically or needs my input: Needs your policy decision, then Codex can implement it.

### Issue 8
- Area: Password reset
- Severity: Medium
- What is wrong: Reset exists and the UX copy is decent, but it depends on the login form email field being filled first and does not appear to have stronger empty/error handling around venue context confusion.
- Why it matters: This is not broken, but it is easy for staff to miss.
- File(s) likely involved: `lib/presentation/screens/app_shell.dart`, `lib/presentation/controllers/app_controller.dart`
- Suggested fix: Keep the current behavior, but tighten empty-state and success/error messaging and make the action more prominent on mobile.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically.

### Issue 9
- Area: Firebase Auth / profile creation
- Severity: Medium
- What is wrong: Profile creation logic exists, but it has not yet been backed by a clean end-to-end smoke test covering invite redeem, profile creation, role assignment, and venue scoping together.
- Why it matters: This is one of the highest-value real-world flows.
- File(s) likely involved: `lib/data/repositories/firebase_repositories.dart`, `test/firebase_mode_and_serialization_test.dart`
- Suggested fix: Add one realistic integration-style test path for invite redemption and user profile creation.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically.

---

## 3. Cocktail Data

### Issue 10
- Area: Approved cocktail catalog
- Severity: High
- What is wrong: The app has a fixed approved cocktail list, but because of the Firestore collection split, it is not fully guaranteed that the same approved list is what every live screen reads after sync/import activity.
- Why it matters: Bartenders and managers need one stable source of truth.
- File(s) likely involved: `assets/data/cocktails.json`, `lib/core/utils/bundled_cocktail_catalog_loader.dart`, `lib/data/repositories/firebase_repositories.dart`
- Suggested fix: After resolving the collection model, enforce one canonical approved catalog load path and add a smoke check for the expected count.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically after the tenancy decision.

### Issue 11
- Area: Cocktail prices
- Severity: Medium
- What is wrong: On-menu approved cocktails now have prices, but four off-menu cocktails still have `null` prices: `Pimm's & Lemonade`, `Irish Coffee`, `Long Island Iced Tea`, `Mimosa`.
- Why it matters: Your later Aztec sales estimation depends on prices. Even if these are intentionally off-menu, the app needs a clear rule for how they are treated.
- File(s) likely involved: `assets/data/cocktails.json`, `lib/core/utils/approved_cocktail_prices.dart`, `test/cocktails_asset_test.dart`
- Suggested fix: Keep them nullable if they are intentionally excluded, but label them clearly as off-menu/non-priced in admin logic and exclude them from future sales estimation checks until prices are supplied.
- Whether Codex can fix it automatically or needs my input: Needs your confirmation on the long-term off-menu rule.

### Issue 12
- Area: Cocktail naming consistency
- Severity: Medium
- What is wrong: The recipe rename to `Raspberry Martini` is in place, but the image path still points to `assets/cocktails/clover-club.png`.
- Why it matters: The app will still display the image, so it is not functionally broken, but the asset naming is now misleading and easy to trip over later.
- File(s) likely involved: `assets/data/cocktails.json`, `assets/cocktails/`
- Suggested fix: Rename the asset file and update the reference, or document the legacy asset name until a proper replacement image is added.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically.

### Issue 13
- Area: Batch ingredient linkage
- Severity: Low
- What is wrong: Batch references appear present, but there is no explicit readiness check ensuring all cocktails that expect linked batches still resolve after imports/backfills in Firebase mode.
- Why it matters: Batch-heavy drinks are harder to learn if linkage breaks silently.
- File(s) likely involved: `assets/data/batches.json`, `lib/data/repositories/firebase_repositories.dart`
- Suggested fix: Add one batch linkage validation in seed/import verification.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically.

### Issue 14
- Area: Approval workflow
- Severity: Low
- What is wrong: The app still contains recipe import/review scaffolding and tests even though your current product direction is a fixed approved cocktail list with no approval step required for daily use.
- Why it matters: Dead or semi-dead approval code increases noise and keeps stale tests around.
- File(s) likely involved: `test/recipe_import_widget_test.dart`, `test/recipe_import_publish_error_widget_test.dart`, related import/review UI and controller code
- Suggested fix: Either fully retire the old review flow or clearly separate it as an admin-only maintenance tool and refresh the tests.
- Whether Codex can fix it automatically or needs my input: Needs your preference on whether this feature should stay.

---

## 4. Library And Study Screens

### Issue 15
- Area: Study mode content
- Severity: High
- What is wrong: A staff-management card is rendered inside the study screen, including the message "Owners can remove staff accounts from the venue here."
- Why it matters: This is confusing for bartenders and puts admin behavior in the wrong place.
- File(s) likely involved: `lib/presentation/screens/app_shell.dart`
- Suggested fix: Move staff management back into the team/admin area and keep study mode focused on cocktail learning only.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically.

### Issue 16
- Area: Mobile layout
- Severity: High
- What is wrong: The study-mode reveal flow does not hold up cleanly in a small/default viewport; the existing widget test fails because the reveal button is off-screen.
- Why it matters: Mobile-first reliability is one of your stated goals.
- File(s) likely involved: `lib/presentation/screens/app_shell.dart`, `test/widget_test.dart`
- Suggested fix: Make the study card more compact or scroll-safe on short screens and then update the widget test to lock this in.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically.

### Issue 17
- Area: Cocktail display clarity
- Severity: Medium
- What is wrong: Core recipe details are present, but there is still room to improve scan-ability for bartenders, especially ingredient/spec emphasis versus secondary metadata.
- Why it matters: Learning speed matters more than data density on the bartender side.
- File(s) likely involved: `lib/presentation/screens/app_shell.dart`
- Suggested fix: Keep bartender screens focused on spec, garnish, glassware, method, and batch note visibility, with less admin-style framing.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically.

### Issue 18
- Area: Title wrapping / card layout
- Severity: Low
- What is wrong: The app already uses truncation and max lines in several list cards, but there is no explicit visual test for long cocktail names on common mobile widths.
- Why it matters: Long names like spritz variants can degrade quickly on smaller devices.
- File(s) likely involved: `lib/presentation/screens/app_shell.dart`, `test/widget_test.dart`
- Suggested fix: Add one small-screen widget test for long-title cards and detail headers.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically.

---

## 5. Quiz System

### Issue 19
- Area: Quiz question quality
- Severity: Medium
- What is wrong: The quiz system already covers recipe, ingredient, garnish, method, and batch-related prompts, but some wrong-answer generation is simplistic and can fall back to generic filler such as `Needs review`.
- Why it matters: Weak distractors make quizzes less useful as a training tool.
- File(s) likely involved: `lib/data/repositories/demo_repositories.dart`, Firebase-backed quiz generation code
- Suggested fix: Improve distractor generation using same-category ingredients, nearby measures, same glassware families, and cocktail-family confusion options.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically.

### Issue 20
- Area: Quiz result persistence
- Severity: High
- What is wrong: Save logic exists, but the public/shareable quiz route is not aligned with the authenticated save rules.
- Why it matters: A quiz that can be started but not reliably saved is not production-ready.
- File(s) likely involved: `lib/presentation/screens/app_shell.dart`, `firestore.rules`, `lib/data/repositories/firebase_repositories.dart`
- Suggested fix: Resolve the auth model mismatch before relying on manager-facing progress reporting.
- Whether Codex can fix it automatically or needs my input: Needs your decision on intended access flow.

### Issue 21
- Area: Manager reporting on results
- Severity: Medium
- What is wrong: Manager team/progress views exist, but they depend on the quiz persistence path being reliable first.
- Why it matters: Reporting quality is only as good as the captured data.
- File(s) likely involved: `lib/presentation/screens/app_shell.dart`, `lib/presentation/controllers/app_controller.dart`
- Suggested fix: Treat this as blocked by the quiz persistence/auth fix, then add one manager-visible results smoke test.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically after the blocker is fixed.

### Issue 22
- Area: Units and measures
- Severity: Low
- What is wrong: Measure answers generally show `ml` correctly, but there is no broader automated check that future quiz question types always display units consistently.
- Why it matters: Consistent units are important for bartender training accuracy.
- File(s) likely involved: quiz generation and rendering code, widget tests
- Suggested fix: Add a unit-format assertion for measure-based quiz questions.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically.

---

## 6. Admin / Manager Tools

### Issue 23
- Area: Ingredient cost admin
- Severity: Medium
- What is wrong: The existing ingredient cost section exists and now supports the intended direction, but because ingredient storage is tied into the broader collection inconsistency, updates may not be safely venue-scoped in Firebase mode.
- Why it matters: Ingredient bottle cost is one of your next operational data layers and must not cross-pollinate venues.
- File(s) likely involved: `lib/presentation/screens/app_shell.dart`, `lib/presentation/controllers/app_controller.dart`, `lib/data/repositories/firebase_repositories.dart`
- Suggested fix: Resolve the canonical ingredient collection model first, then keep the current admin UI and import helper on top of that.
- Whether Codex can fix it automatically or needs my input: Needs the tenancy decision first.

### Issue 24
- Area: Cocktail price editing
- Severity: Medium
- What is wrong: Prices are stored and shown, but there does not appear to be a manager/owner UI to edit cocktail prices directly.
- Why it matters: If menu prices change, the app currently depends on seed/import changes rather than a clean admin update path.
- File(s) likely involved: `lib/presentation/controllers/app_controller.dart`, `lib/presentation/screens/app_shell.dart`
- Suggested fix: Add a simple owner/manager price edit surface only if you want prices maintained in-app rather than through seed/import.
- Whether Codex can fix it automatically or needs my input: Needs your decision on whether in-app price editing is required.

### Issue 25
- Area: Role management
- Severity: Medium
- What is wrong: Role-aware logic exists, but role management feels incomplete from the UI side. There is no clear, polished place to pause, restore, or fully manage venue staff lifecycle.
- Why it matters: Managers need a simple, trustworthy team admin flow.
- File(s) likely involved: `lib/presentation/controllers/app_controller.dart`, `lib/presentation/screens/app_shell.dart`
- Suggested fix: Consolidate invites, active/inactive state, and removal into one team management area.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically.

### Issue 26
- Area: Broken or unnecessary admin surfaces
- Severity: Medium
- What is wrong: Settings/admin content includes technical deployment details and there are backend/controller methods for weekly sessions and stock quiz generation that do not seem wired into the UI.
- Why it matters: Unused or overly technical admin surfaces make the app feel unfinished.
- File(s) likely involved: `lib/presentation/screens/app_shell.dart`, `lib/presentation/controllers/app_controller.dart`
- Suggested fix: Remove technical copy from user-facing admin screens and either wire up or hide unfinished operational tools.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically, but may need your preference on hiding versus completing unfinished tools.

---

## 7. Aztec Report Import Readiness

### Issue 27
- Area: PDF import capability
- Severity: High
- What is wrong: Aztec `Product Sales by Employee` import is not built yet. There is no parser for employee, product name, or sales value extraction from those PDFs.
- Why it matters: This is the foundation of the later sales-exposure feature.
- File(s) likely involved: new parser/import code will be needed; existing `lib/core/utils/pdf_recipe_extractor.dart` is for recipe PDFs, not Aztec sales reports
- Suggested fix: Add this as a separate future feature after the current readiness blockers are fixed.
- Whether Codex can fix it automatically or needs my input: Codex can build it later, but it needs sample PDFs and acceptance rules.

### Issue 28
- Area: Cocktail sales estimation model
- Severity: High
- What is wrong: Current bartender sales data stores `quantitySold`, not `salesValue` plus estimated quantity. There is no workflow for `sales value / cocktail price`.
- Why it matters: The future exposure metric depends on price-aware estimation.
- File(s) likely involved: domain models, Firestore serializers, repositories, future import workflow
- Suggested fix: Introduce a future sales-import model that stores source row data, matched cocktail, sales value, estimated quantity, and review status.
- Whether Codex can fix it automatically or needs my input: Needs your future data design approval.

### Issue 29
- Area: Name matching and review flow
- Severity: Medium
- What is wrong: There is not yet a dedicated normalization/review layer for matching POS/Aztec product names against approved cocktails only.
- Why it matters: Real reports will contain short forms, spelling drift, and unmatched products.
- File(s) likely involved: future importer/matcher code
- Suggested fix: Reuse the cocktail name normalization approach already used for price backfill as the basis for Aztec matching, and include an unmatched rows review queue.
- Whether Codex can fix it automatically or needs my input: Codex can build automatically later once sample reports are available.

### Issue 30
- Area: Weekly bartender exposure storage
- Severity: Medium
- What is wrong: There is no complete storage/reporting model yet for weekly bartender cocktail exposure data derived from imported sales.
- Why it matters: This is the final product output you want from the Aztec workflow.
- File(s) likely involved: future Firestore models, dashboard/reporting screens
- Suggested fix: Design this after importer parsing and matching are proven on real reports.
- Whether Codex can fix it automatically or needs my input: Needs your reporting requirements later.

---

## 8. Firebase / Firestore

### Issue 31
- Area: Production versus demo mode
- Severity: High
- What is wrong: Demo mode is intentionally browser-local and does not persist across refresh. That is acceptable for demo use, but it can confuse testing if people assume it mirrors production persistence.
- Why it matters: Readiness testing must happen against Firebase mode, not only demo mode.
- File(s) likely involved: `lib/core/config/app_environment.dart`, demo repositories, UI messaging
- Suggested fix: Keep demo mode, but label it more clearly and ensure production acceptance testing uses Firebase mode.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically.

### Issue 32
- Area: Firebase config safety
- Severity: High
- What is wrong: The web app has a bundled fallback Firebase config for the `bar-variance-training` project. If deployment or local defines are missing, the app can still boot against the fallback project instead of failing closed.
- Why it matters: This creates real risk of pointing the wrong environment at the wrong Firebase project.
- File(s) likely involved: `lib/firebase_options.dart`, `lib/core/config/firebase_bootstrap.dart`
- Suggested fix: Decide whether production should fail closed when required Firebase env vars are missing. For production, that is usually the safer choice.
- Whether Codex can fix it automatically or needs my input: Needs your preference on fallback behavior.

### Issue 33
- Area: Firestore indexes
- Severity: Low
- What is wrong: `firestore.indexes.json` is empty.
- Why it matters: This is not a blocker today, but it means index requirements are not documented or pre-provisioned as the app grows.
- File(s) likely involved: `firestore.indexes.json`
- Suggested fix: Add indexes only when query patterns require them, but document expected future ones for invites, quiz attempts, and progress reporting.
- Whether Codex can fix it automatically or needs my input: Codex can help later once query patterns are finalized.

### Issue 34
- Area: Seed/import scripts
- Severity: Medium
- What is wrong: Seed and import utilities exist, but because of the collection split, they do not yet guarantee that a production sync lands in the exact collections the app reads live.
- Why it matters: Data seeding only helps if the runtime reads the same documents.
- File(s) likely involved: `lib/core/utils/*`, `lib/data/repositories/firebase_repositories.dart`, related tooling/tests
- Suggested fix: Reconcile data paths first, then re-run and tighten all seed/import verification checks.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically after the tenancy decision.

---

## 9. Cloudflare / Web Deployment

### Issue 35
- Area: Cache and service worker handling
- Severity: Medium
- What is wrong: The codebase does a lot of the right things already: PWA strategy is disabled, bootstrap checks `version.json`, `_headers` disables caching for critical files, and the service worker is a cleanup worker. However, this has not been live-verified from the deployed site in a normal browser session during this audit.
- Why it matters: Flutter web cache problems are one of the easiest ways for users to think "the app is broken" when deployment is actually stale.
- File(s) likely involved: `build.sh`, `web/flutter_bootstrap.js`, `web/_headers`, `web/flutter_service_worker.js`, `web/_redirects`
- Suggested fix: Keep the current setup and add one live deployment checklist step after each production push: normal tab, mobile browser, hard refresh, and old-tab reload.
- Whether Codex can fix it automatically or needs my input: Codex can document the checklist automatically; live verification needs you.

### Issue 36
- Area: Build/deploy confidence
- Severity: Low
- What is wrong: Release build succeeds locally, which is good, but there is no explicit deployment smoke test captured in the repo for Cloudflare Pages.
- Why it matters: Successful build is not the same as successful environment wiring.
- File(s) likely involved: `build.sh`, deployment docs
- Suggested fix: Add a short deployment verification checklist to the repo.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically.

---

## 10. UX And Wording

### Issue 37
- Area: User-facing wording
- Severity: High
- What is wrong: Several screens still expose technical or deployment-oriented wording such as Cloudflare/Firebase stack details, Spark limits, and environment/version language.
- Why it matters: Bartenders and managers should not need to parse infrastructure language.
- File(s) likely involved: `lib/presentation/screens/app_shell.dart`, `lib/presentation/controllers/app_controller.dart`
- Suggested fix: Remove technical/debug copy from normal product screens and keep diagnostics behind an admin-only or debug-only panel.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically.

### Issue 38
- Area: Empty states and loading states
- Severity: Medium
- What is wrong: Core flows have some messaging, but the app would benefit from more polished empty states and clearer feedback when data is missing, still syncing, or unavailable because of permissions.
- Why it matters: This is especially important on mobile and for venue onboarding.
- File(s) likely involved: `lib/presentation/screens/app_shell.dart`
- Suggested fix: Add a pass focused on empty/loading/error states after structural blockers are fixed.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically.

### Issue 39
- Area: Mobile-first polish
- Severity: Medium
- What is wrong: The app is generally responsive, but the failed study-mode viewport test suggests that mobile ergonomics still need a dedicated pass.
- Why it matters: Your real audience is likely phone-first.
- File(s) likely involved: `lib/presentation/screens/app_shell.dart`, widget tests
- Suggested fix: Run a mobile-focused layout sweep on library, study, quiz, and team/admin tabs.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically.

---

## 11. Tests / Debug Tools

### Issue 40
- Area: Smoke tests
- Severity: High
- What is wrong: There are some valuable tests already, but the suite is not currently serving as a dependable smoke net because analyzer and widget tests are not clean.
- Why it matters: Readiness work should end with a simple "green means safe" signal.
- File(s) likely involved: `test/`
- Suggested fix: Establish a minimum required CI/local smoke set: app boots, login screen renders, approved cocktail count is correct, study reveal works on mobile size, quiz save path works, and manager results view loads.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically.

### Issue 41
- Area: Approved cocktail count and price checks
- Severity: Medium
- What is wrong: There are already tests around asset validity and price fields, but there is no single readiness check that enforces the expected approved cocktail count together with your intended priced/off-menu rules.
- Why it matters: This is the kind of simple check that prevents accidental catalog drift.
- File(s) likely involved: `test/cocktails_asset_test.dart`, `test/verified_recipe_sync_test.dart`
- Suggested fix: Add one explicit catalog readiness test that checks approved count, duplicate IDs/names, and expected off-menu exceptions for missing prices.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically.

### Issue 42
- Area: Ingredient cost data checks
- Severity: Medium
- What is wrong: There is importer coverage, but there is not yet a broad readiness check that every ingredient used by approved cocktails either has bottle pricing or is clearly flagged as needing manual completion.
- Why it matters: This will matter once ingredient-cost reporting becomes operational.
- File(s) likely involved: ingredient import tests, admin ingredient cost logic
- Suggested fix: Add a validation/reporting helper for ingredient coverage by approved recipes.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically.

### Issue 43
- Area: Firebase connection and role access diagnostics
- Severity: Medium
- What is wrong: Some runtime diagnostics exist, but there is no concise readiness/debug view that confirms current Firebase mode, current venue scope, current role, and whether core collections are reachable.
- Why it matters: This would make production troubleshooting much faster without exposing too much technical detail to normal users.
- File(s) likely involved: app controller, debug/admin surfaces
- Suggested fix: Add a small owner-only diagnostics panel or hidden debug route.
- Whether Codex can fix it automatically or needs my input: Codex can fix automatically.

---

## Quick Wins

- Fix the stale tests and get `dart analyze` green again.
- Remove the staff-management block from study mode.
- Clean up technical wording from user-facing settings/admin screens.
- Add a mobile viewport widget test for library/study/quiz basics.
- Rename the legacy `clover-club.png` reference used by `Raspberry Martini`.
- Add one explicit catalog readiness test for approved cocktail count and expected price coverage rules.

## Do This Next

1. Decide the real Firestore tenancy model for cocktails, batches, and ingredients.
2. Fix the Firestore rules bootstrap flow and validate first-time owner setup.
3. Decide whether quizzes require login or support link-based access without prior login.
4. Clean the analyzer/test suite so future work can move safely.
5. Run one full Firebase-mode smoke pass on mobile and desktop.

## Do Later

- Build Aztec PDF import once the current app foundations are stable.
- Add richer cocktail price editing only if you want price maintenance inside the app.
- Add a fuller ingredient coverage report for cost tracking.
- Improve quiz distractor quality and learning UX polish.
- Add a lightweight owner-only diagnostics panel.

## Questions For Jaime

1. Should approved cocktails, batches, and ingredients be global across all venues, or fully venue-scoped?
2. Should quiz links work only for signed-in staff, or should a QR/link allow a lightweight join-and-play flow?
3. When a staff member is removed, should their Firebase Auth account be deleted, disabled, or just detached from the venue?
4. Do you want cocktail prices to stay seed-managed, or should managers/owners be able to edit them in-app?
5. Should off-menu cocktails remain in the catalog with `null` prices, or should they be hidden/excluded from future sales estimation logic until priced?
6. Do you want the old recipe import/review flow kept as an internal maintenance tool, or removed entirely now that the list is fixed?

## Overall Readiness Verdict

The app is not far off, but it is not ready to rely on as a stable production workflow yet. The core product shape is there. The main work now is tightening the data model, rules, auth/quiz alignment, and regression safety so the existing features behave predictably before new features are added.
