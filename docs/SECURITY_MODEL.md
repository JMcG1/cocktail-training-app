# Security Model

## Role hierarchy

- `owner`
- `manager`
- `bartender`

The owner is the highest application role. Managers operate within a venue but cannot change official recipe or pricing setup. Bartenders are the lowest-privilege role and should only access training or active quiz sessions.

## Role permissions

### Owner

Owner can:

- bootstrap the first venue account
- import OCR, PDF, and curated recipe specs
- review and approve cocktail recipes
- review and approve batch recipes
- edit official recipe data
- edit official batch data
- manage ingredient pricing
- resolve missing costs
- resolve batch links
- publish approved specs
- create and manage venue manager accounts
- access manager workflows too
- update venue-level setup data when needed

Owner cannot:

- bypass approval rules if source data is unresolved
- weaken Firestore rules just to get past a UI issue

### Manager

Manager can:

- sign in to their own venue
- view approved cocktail library and training material
- create weekly stock concern sessions
- enter bartender sales
- launch quiz sessions
- copy quiz links
- close quiz sessions
- view bartender results
- view dashboards and trend summaries

Manager cannot:

- approve recipes
- approve batch recipes
- edit official recipe specs
- edit batch recipes
- manage official pricing
- import OCR/PDF/curated source data
- access owner-only admin setup

### Bartender

Bartender can:

- access training mode
- complete practice quizzes
- complete stock-focus quiz sessions
- receive supportive personal feedback

Bartender cannot:

- access manager dashboards
- create stock concerns
- enter sales
- launch or close quizzes
- approve or edit recipes
- see venue-level team results

## Explicit rules

- Managers cannot approve recipes, batches, or pricing.
- Bartenders cannot access dashboards.
- Users cannot choose their own role.
- No public owner creation after bootstrap.

## Onboarding model

### Current implemented behavior

- A first bootstrap account can create the first `owner` account for a new venue.
- Owner can create venue manager accounts from inside the app.
- Public quiz links remain available only for active quiz sessions.

### Product rule

- Ongoing access should be invite-only.
- Role should come from a trusted invite or trusted owner action, never from a self-selected signup screen.

### Implementation note

The dedicated invite collection and acceptance flow are planned but not fully implemented yet. Future work must add them without weakening existing role protections.

## Manager-created manager and bartender invites

Target policy:

- Owner can create manager invites.
- Manager may create bartender invites later if the dedicated invite flow is implemented.
- Manager must not grant owner-level access.

Current codebase status:

- Owner can directly provision manager accounts.
- Dedicated invite documents are not yet active.
- Bartender account provisioning is still deferred.

## Public quiz-session access rules

Public access is intentionally narrow.

- Public users may read only active quiz session documents needed for quiz taking.
- Public users may create quiz attempts only for active quiz sessions.
- Public users must not gain access to recipes, dashboard data, or venue admin collections.

This is enforced in [firestore.rules](/C:/Users/jaime/Documents/New%20project%202/firestore.rules).

## Venue isolation

Every authenticated operational user belongs to exactly one venue through `users/{uid}.venueId`.

Security assumptions:

- all manager/owner operational writes are scoped to their venue id
- owner-only admin writes are scoped to their venue id
- public quiz access is scoped to a specific active session under a specific venue path

## Firestore rule assumptions

Current rules rely on:

- `users/{uid}` existing and containing `role`, `venueId`, and `active`
- owner/admin writes using `isOwnerForVenue(venueId)`
- operational manager/owner writes using `isOperationalUserForVenue(venueId)`
- public quiz creates validating that the target quiz session is active

UI visibility is not enough. Any permission change must be mirrored in Firestore rules.

## Security risks and mitigations

### Risk: manager gains admin write access

Mitigation:

- keep recipe, batch, draft, pricing, and venue admin writes owner-only in Firestore rules
- keep controller-level owner guards in `AppController`

### Risk: public access to more than active quiz sessions

Mitigation:

- restrict public reads to active quiz sessions only
- restrict public writes to quiz attempts only

### Risk: cross-venue data leakage

Mitigation:

- every privileged read/write checks venue scope in rules
- manager accounts are created with an explicit venue id

### Risk: self-escalated role creation

Mitigation:

- users cannot choose their own role
- ongoing access should be invite-only
- owner creation must stop after initial bootstrap

### Risk: permissions loosened during bug fixing

Mitigation:

- never apply broad `allow read, write: if signedIn()` style fixes
- prefer exact collection-level changes and add tests

## Manual security smoke test checklist

1. Bootstrap the first owner account for a fresh venue.
2. Confirm the owner can access Admin setup.
3. Confirm the owner can import and approve recipes.
4. Confirm the owner can save ingredient pricing.
5. Confirm the owner can create a venue manager account.
6. Sign in as the manager.
7. Confirm the manager sees Stock focus and dashboards.
8. Confirm the manager does not see Admin setup or Pricing tabs.
9. Confirm the manager cannot approve recipes or save official pricing.
10. Confirm the manager can create stock concerns, save sales, and launch quizzes.
11. Confirm a signed-in bartender lands in training, not the manager workspace.
12. Confirm a public quiz link opens only while the session is active.
13. Confirm a closed quiz link no longer allows quiz completion.
14. Confirm no user can choose their own role during normal access flow.
