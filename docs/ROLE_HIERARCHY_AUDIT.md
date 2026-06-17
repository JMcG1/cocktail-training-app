# Role Hierarchy Audit

Date: 2026-06-17

## Intended hierarchy

Owner/Admin
  -> Manager
  -> Bartender

Manager
  -> Bartender

Bartender
  -> Base training access

The practical rule is:
- higher roles should inherit lower-role features automatically
- owner/admin-only actions should stay restricted
- manager-only actions should stay available to owner/admin too

## Summary

The codebase already had a partial hierarchy model in the controller:
- `canAccessManagerWorkflows`
- `canManageVenueInvites`
- `canAccessAdminSetup`

That part was broadly correct.

The main problems were:
- some bartender-style access was still checked as bartender-only instead of signed-in-user access
- managers could open the team dashboard but could not reliably load venue teammates because the controller and Firestore rules still treated user-list reads as owner-only
- manager/admin progress used team attempt data instead of their own personal attempts, which broke true bartender-permission inheritance

## Fixed now

### 1. Higher roles now inherit bartender workflow access more cleanly

Status: Fixed

Changes:
- added `canAccessBartenderWorkflows` in [lib/presentation/controllers/app_controller.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/controllers/app_controller.dart)
- app home routing now uses inherited bartender access instead of direct bartender-only routing in [lib/presentation/screens/app_shell.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/screens/app_shell.dart)

Why it mattered:
- direct bartender-only checks make the hierarchy brittle
- manager/admin should still be able to use bartender features without special-case routing

### 2. Managers can now load venue teammates as part of manager access

Status: Fixed

Changes:
- `_refreshVenueUsersIfNeeded` now uses manager-level access, not admin-only access, in [lib/presentation/controllers/app_controller.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/controllers/app_controller.dart)
- Firestore rules now allow operational users to read non-owner user docs in their venue in [firestore.rules](/C:/Users/jaime/Documents/New%20project%202/firestore.rules)

Why it mattered:
- managers are expected to review team progress and manage training within their venue
- before this fix, the manager dashboard could be missing teammate data even though the manager UI was visible

### 3. Manager/admin progress is now personal again

Status: Fixed

Changes:
- added `personalQuizAttempts` in [lib/presentation/controllers/app_controller.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/controllers/app_controller.dart)
- `ProgressTab` now uses personal attempts for manager/admin view and keeps team-wide coaching in the Team tab in [lib/presentation/screens/app_shell.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/screens/app_shell.dart)
- role-scoped startup loading now loads personal progress for any signed-in user, not bartenders only, in [lib/presentation/controllers/app_controller.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/controllers/app_controller.dart)

Why it mattered:
- managers and owners should inherit bartender-style "my own progress" access
- the old behavior mixed personal and team progress in a confusing way

## Findings still present

### Finding A: Permission model is still partly duplicated

Severity: Medium

Area:
- controller getters
- UI role filters
- Firestore rules helper functions

Files:
- [lib/presentation/controllers/app_controller.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/controllers/app_controller.dart)
- [lib/presentation/screens/app_shell.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/screens/app_shell.dart)
- [firestore.rules](/C:/Users/jaime/Documents/New%20project%202/firestore.rules)

What is wrong:
- some access uses inherited helpers
- some access still relies on direct role comparisons

Examples:
- owner-only staff removal and pause checks are direct
- bartender-only user filtering in some manager UI sections is direct
- Firestore still models hierarchy as separate helper functions rather than one shared role-rank concept

Recommendation:
- centralize app-side role inheritance into a small permission model or role-rank helper
- keep explicit direct checks only where the business rule is intentionally owner-only

### Finding B: Managers can create manager invites without an explicit venue policy layer

Severity: Medium

Files:
- [lib/presentation/screens/app_shell.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/screens/app_shell.dart)
- [lib/presentation/controllers/app_controller.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/controllers/app_controller.dart)
- [firestore.rules](/C:/Users/jaime/Documents/New%20project%202/firestore.rules)

What is wrong:
- current behavior allows managers to create `manager` invites
- the product note says "if permitted by venue rules", but that policy layer does not exist yet

Recommendation:
- either document that current venue policy permits manager-created manager invites
- or add a venue-level flag later if that distinction matters operationally

### Finding C: Team dashboard still assumes bartenders are the primary operational targets

Severity: Low

Files:
- [lib/presentation/screens/app_shell.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/screens/app_shell.dart)

What is wrong:
- surprise quiz and sales import dropdowns intentionally target bartender accounts only
- that is mostly correct for day-to-day use, but it means managers are not treated as test participants inside those specific flows

Recommendation:
- keep as-is if the business intent is "manager tools target bartender coaching"
- otherwise add an optional "include managers in training targets" switch later

## Security-model note

The updated Firestore rule intentionally allows managers to read non-owner user docs in their own venue, but still blocks:
- reading owner user docs through manager access
- owner-only admin writes
- cross-venue access

That matches the current hierarchy better without weakening venue isolation.

## Regression checks added

Added coverage in [test/firebase_mode_and_serialization_test.dart](/C:/Users/jaime/Documents/New%20project%202/test/firebase_mode_and_serialization_test.dart):
- manager inherits venue teammate loading through manager access
- manager personal progress stays separate from team attempts
- Firestore rules still include the intended manager read restriction boundary

## Recommended next steps

1. Introduce a shared app-side permission object or role-rank helper and migrate remaining duplicated checks to it.
2. Decide whether manager-created manager invites are always allowed or need a venue policy flag.
3. Decide whether managers should appear in training-target dropdowns for surprise quiz and sales-import testing.
4. Add widget-level tests that verify owner, manager, and bartender see the correct navigation and tabs.
