# Product Roadmap

This roadmap keeps the next rounds of work focused on the highest-impact improvements for the live hospitality product.

## Current focus

### 1. Make production support easier
- Add an owner/admin diagnostics view with build, runtime mode, venue scope, and verified recipe-set health.
- Keep the login-screen build label and browser recovery actions easy to find during rollout checks.
- Use these diagnostics as the first stop before changing Firebase or deployment settings.

### 2. Keep the verified recipe set as the live source of truth
- Continue treating the checked-in curated catalog as the approved live spec set for this venue.
- Keep OCR and PDF draft review available only as a back-office review tool.
- Reduce any remaining copy that makes draft approval sound like the main bartender-facing path.

### 3. Keep role separation clear in the UI
- Make owner/admin setup, manager operations, and bartender learning feel like clearly different workspaces.
- Keep supportive wording consistent across dashboards, study flows, and settings.
- Avoid exposing admin-only concepts where they do not help the current role.

## Next phase

### 4. Move verified spec publishing out of the live app
- Replace in-app recipe publishing with a safer seed or sync workflow run by tooling or a tightly scoped owner action.
- Keep the live app read-focused for official specs whenever practical.
- Preserve batch decomposition, unresolved flags, and image mapping in the published catalog.

### 5. Add stronger security regression coverage
- Add emulator-backed Firestore rules tests for venue isolation and role boundaries.
- Cover owner-only recipe and pricing actions, manager venue-only actions, and bartender access limits.
- Keep invite redemption and malformed-user failure modes under automated coverage.

### 6. Version the curated catalog explicitly
- Add catalog metadata such as `catalogVersion`, `publishedAt`, and source reference notes.
- Make it easier to compare what recipe set is live in a venue against the checked-in source material.
- Support safer future venue rollouts without guessing which spec revision is active.

## Later improvements

### 7. Improve manager visibility for batch-driven variance
- Show how a cocktail depends on a batch and how that batch decomposes into underlying ingredients.
- Make stock-focus insights easier to trust when batch composition drives the variance story.

### 8. Add a more guided first-run workflow
- Give owners a simple setup path for verified specs, ingredient pricing, and venue invites.
- Give managers a first-run path for stock-focus sessions, sales entry, and coaching follow-up.
- Give bartenders a quicker start into study and practice without extra setup friction.

### 9. Add lightweight owner audit visibility
- Track important owner/admin actions such as verified spec refresh, pricing updates, and invite changes.
- Keep the tone operational and supportive rather than punitive.

## Guardrails

- Do not weaken Firestore rules to make setup easier.
- Do not reintroduce public signup.
- Do not invent cocktail specs or fill gaps from general knowledge.
- Keep supportive, hospitality-friendly language across all new work.
