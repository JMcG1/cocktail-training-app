# Cocktail Training Audit Report

Last updated: 2026-06-17

This report reflects the current codebase after the recent login, role hierarchy, ingredient cost, and manager PDF import fixes. It is intended as a practical “what still needs attention” view, not a historical bug list.

## Overall audit summary

- No new critical blocker was found in this static audit.
- The app now has a workable production foundation for login, invite-only onboarding, approved cocktails, quizzes, ingredient-cost import, and manager sales import.
- The most important remaining work is hardening and maintainability, not a full rebuild.

## Findings

### 1. True invite-only auth is not fully enforced at the Firebase provider level

- Area: Authentication
- Severity: High
- Affected files: [lib/data/repositories/firebase_repositories.dart](/C:/Users/jaime/Documents/New%20project%202/lib/data/repositories/firebase_repositories.dart), [firestore.rules](/C:/Users/jaime/Documents/New%20project%202/firestore.rules), [docs/SECURITY_MODEL.md](/C:/Users/jaime/Documents/New%20project%202/docs/SECURITY_MODEL.md)
- What is wrong: The app fails closed without a matching Firestore user path, invite, or bootstrap grant, but Firebase Email/Password signup can still exist at the provider level outside the app.
- Why it matters: It is secure enough for venue access today, but not a perfect invite-only auth story at the provider layer.
- Recommended fix: Move signup behind a backend-controlled flow such as a callable function, blocking function, or auth broker.
- Status: Left as a task

### 2. Role inheritance is better, but permission checks are still partly duplicated

- Area: Role and permission model
- Severity: Medium
- Affected files: [lib/presentation/controllers/app_controller.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/controllers/app_controller.dart), [lib/presentation/screens/app_shell.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/screens/app_shell.dart), [firestore.rules](/C:/Users/jaime/Documents/New%20project%202/firestore.rules)
- What is wrong: Higher-role inheritance now exists, but some role checks still use direct comparisons in UI or controller code instead of one shared permission model.
- Why it matters: Duplicated permission logic increases the chance that owners lose manager features or managers lose bartender features in future edits.
- Recommended fix: Keep consolidating the remaining screen-level conditionals onto the shared `UserRole` hierarchy helpers as files are touched.
- Status: Improved now

### 3. Firestore rules coverage is now present, but still focused on the highest-risk boundaries

- Area: Firebase and security
- Severity: Medium
- Affected files: [firestore.rules](/C:/Users/jaime/Documents/New%20project%202/firestore.rules), [package.json](/C:/Users/jaime/Documents/New%20project%202/package.json), [test/firestore_rules_test.cjs](/C:/Users/jaime/Documents/New%20project%202/test/firestore_rules_test.cjs)
- What is wrong: The repo now has emulator-backed rules tests for ingredient-cost writes, venue-scoped reads, invite creation, invite redemption, quiz-attempt boundaries, and bootstrap owner creation, but the coverage is still targeted rather than exhaustive.
- Why it matters: This is now protecting the highest-risk transactional flows, but future collections and policy changes can still regress quietly if they are not added to the harness.
- Recommended fix: Keep extending the harness as new secured collections or onboarding paths are added.
- Status: Improved now

### 4. The main screen file is still too large

- Area: UI architecture
- Severity: Medium
- Affected files: [lib/presentation/screens/app_shell.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/screens/app_shell.dart)
- What is wrong: A very large share of app UI and workflow logic still lives in one screen file.
- Why it matters: This slows down safe changes, increases merge friction, and makes role-specific regressions easier to miss.
- Recommended fix: Split manager workspace, training workspace, progress, ingredient-cost admin, and import panels into smaller widgets/files without changing behaviour.
- Status: Left as a task

### 5. The sales PDF importer is format-sensitive

- Area: Sales import readiness
- Severity: Medium
- Affected files: [lib/core/utils/sales_pdf_importer.dart](/C:/Users/jaime/Documents/New%20project%202/lib/core/utils/sales_pdf_importer.dart)
- What is wrong: The parser relies on the current Aztec-style text layout and known portion labels.
- Why it matters: A supplier export format change could silently reduce matches or increase fallback imports.
- Recommended fix: Add regression fixtures and tests using representative PDFs, and surface clearer warnings if row matching drops unexpectedly.
- Status: Left as a task

### 6. Manager-created manager invites are allowed but not venue-policy configurable

- Area: Invite system
- Severity: Medium
- Affected files: [lib/presentation/controllers/app_controller.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/controllers/app_controller.dart), [lib/presentation/screens/app_shell.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/screens/app_shell.dart), [firestore.rules](/C:/Users/jaime/Documents/New%20project%202/firestore.rules)
- What is wrong: The current implementation allows managers to create manager invites, but there is no venue-level policy switch controlling that.
- Why it matters: This may be correct for the current venue, but it is a policy assumption embedded in the code.
- Recommended fix: Either keep it as the documented current policy or add a venue-level setting later.
- Status: Left as a task

### 7. The ingredient pricing data model still uses the internal field name `bottleCost`

- Area: Ingredient costs
- Severity: Low
- Affected files: [lib/domain/models/models.dart](/C:/Users/jaime/Documents/New%20project%202/lib/domain/models/models.dart), [lib/data/firestore/firestore_serializers.dart](/C:/Users/jaime/Documents/New%20project%202/lib/data/firestore/firestore_serializers.dart)
- What is wrong: The UI and product language talk about bottle price, but the stored model field is `bottleCost`.
- Why it matters: It is not broken, but it is easy to confuse when comparing code, Firestore data, and user-facing wording.
- Recommended fix: Keep the current field for compatibility, or document it clearly and migrate only if there is a strong reason.
- Status: Left as a task

### 8. The approved catalog and live Firestore data need stronger version visibility

- Area: Cocktail data
- Severity: Medium
- Affected files: [lib/core/utils/curated_recipe_importer.dart](/C:/Users/jaime/Documents/New%20project%202/lib/core/utils/curated_recipe_importer.dart), [lib/data/repositories/firebase_repositories.dart](/C:/Users/jaime/Documents/New%20project%202/lib/data/repositories/firebase_repositories.dart)
- What is wrong: The fixed approved cocktail list is now the live source of truth, but there is no stronger operator-facing catalog version marker in the product surface.
- Why it matters: It becomes harder to confirm exactly which approved recipe set is live after future updates.
- Recommended fix: Add visible catalog metadata such as version and published timestamp.
- Status: Left as a task

### 9. Some production-critical behaviours still rely on manual smoke testing

- Area: Tests and deployment
- Severity: Medium
- Affected files: [build.sh](/C:/Users/jaime/Documents/New%20project%202/build.sh), [web/_headers](/C:/Users/jaime/Documents/New%20project%202/web/_headers), `test/`
- What is wrong: Login, Cloudflare cache safety, invite flows, and live-role behaviour are still mostly verified manually.
- Why it matters: The app can work well in production and still regress quietly between deployments.
- Recommended fix: Keep the manual test plan, but also add targeted integration tests around the highest-risk flows.
- Status: Left as a task

### 10. Analyzer failures in several tests were blocking a clean baseline

- Area: Test reliability
- Severity: Medium
- Affected files: [test/widget_test.dart](/C:/Users/jaime/Documents/New%20project%202/test/widget_test.dart), [test/curated_import_test.dart](/C:/Users/jaime/Documents/New%20project%202/test/curated_import_test.dart), [test/pilot_reliability_test.dart](/C:/Users/jaime/Documents/New%20project%202/test/pilot_reliability_test.dart), [test/recipe_import_widget_test.dart](/C:/Users/jaime/Documents/New%20project%202/test/recipe_import_widget_test.dart), [test/recipe_import_publish_error_widget_test.dart](/C:/Users/jaime/Documents/New%20project%202/test/recipe_import_publish_error_widget_test.dart), [test/verified_recipe_sync_test.dart](/C:/Users/jaime/Documents/New%20project%202/test/verified_recipe_sync_test.dart)
- What is wrong: The `AppEnvironment` constructor had changed, and these tests were missing the required `allowOwnerBootstrap` parameter.
- Why it matters: A broken analyzer baseline hides new problems and makes the repo less trustworthy.
- Recommended fix: Add the missing parameter and keep the baseline clean.
- Status: Fixed now

## Areas checked with no new blocker found in this pass

- Authentication login flow is wired for Firebase mode
- Password reset is present from the login screen
- Invite-only join flow fixes the role from the invite
- Approved cocktails, prices, and batch data are bundled and tested
- Ingredient cost CSV import exists in the existing admin area
- Bartenders no longer need to use settings/admin tools
- Cloudflare cache-busting and cleanup strategy is intentionally defensive

## Quick wins

1. Add PDF parser regression fixtures.
2. Split `app_shell.dart` into smaller role-focused screen files.
3. Add a visible approved-catalog version marker.
4. Continue moving remaining screen-level permission checks onto the shared role helpers.

## Do this next

1. Reduce maintainability risk by breaking up the largest screen file.
2. Keep testing the live PDF and commodity import workflows with saved fixtures.
3. Add a few more targeted app-level tests around owner/manager/bartender workspace routing.

## Do later

1. Decide whether managers should always be allowed to create manager invites.
2. Add stronger catalog versioning and diagnostics.
3. Consider a backend-managed invite-only auth flow.

## Questions for Jaime

1. Do you want manager-created manager invites to remain permanently allowed, or should that become a venue-level setting later?
2. Should manager accounts ever be included as surprise-quiz participants, or should those flows stay bartender-only by design?
3. Do you want the internal Firestore ingredient field name `bottleCost` left as-is for stability, or eventually renamed to match “bottle price” wording?
