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
- create and manage venue invites
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

- A first owner account now requires a pre-created `bootstrapGrants/{email}` document.
- Owner and manager users can create venue-scoped invites for `manager` and `bartender` access.
- Public quiz links remain available only for active quiz sessions.

### Product rule

- Ongoing access is invite-only.
- Role comes from a trusted venue invite, never from a self-selected signup screen.

## Manager-created manager and bartender invites

Current policy:

- Owner can create manager or bartender invites for the same venue.
- Manager can create manager or bartender invites for the same venue.
- Manager must not grant owner-level access.
- Invite links and QR codes both resolve to the same join flow.

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
- manager and bartender account creation occurring in the same transaction as invite redemption
- owner/admin writes using `isOwnerForVenue(venueId)`
- operational manager/owner writes using `isOperationalUserForVenue(venueId)`
- public quiz access being limited to direct active-session access only
- invite reads being limited to direct `get` access on redeemable invite documents

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
- ongoing access is invite-only
- owner creation does not happen through venue invites
- invite redemption ties `users/{uid}` creation to an atomic invite-usage increment in Firestore

### Risk: anonymous users create raw Firebase Auth accounts outside the app

Mitigation today:

- no public signup route is exposed in the app
- raw Firebase Auth signups do not gain venue access without a valid Firestore `users/{uid}` document created through invite redemption

Remaining limitation:

- Firebase Email/Password itself still cannot be made truly invite-only from the client alone. A raw Firebase Auth account can still be created outside the app if Email/Password sign-up remains enabled at the provider level.
- The app now fails closed by requiring either a one-time owner bootstrap grant or a venue invite before any Firestore-backed access can be established.
- Closing the provider-level gap fully requires backend enforcement such as a blocking function, callable broker, or custom auth/token issuance flow.

### Risk: permissions loosened during bug fixing

Mitigation:

- never apply broad `allow read, write: if signedIn()` style fixes
- prefer exact collection-level changes and add tests

## Manual security smoke test checklist

1. Bootstrap the first owner account for a fresh venue.
2. Confirm the owner can access Admin setup.
3. Confirm the owner can import and approve recipes.
4. Confirm the owner can save ingredient pricing.
5. Confirm the owner can create a venue invite.
6. Sign in as the manager.
7. Confirm the manager sees Stock focus and dashboards.
8. Confirm the manager does not see Admin setup or Pricing tabs.
9. Confirm the manager cannot approve recipes or save official pricing.
10. Confirm the manager can create stock concerns, save sales, and launch quizzes.
11. Confirm a signed-in bartender lands in training, not the manager workspace.
12. Confirm a public quiz link opens only while the session is active.
13. Confirm a closed quiz link no longer allows quiz completion.
14. Confirm a join link assigns role and venue from the invite without any role picker.
15. Confirm disabled, expired, and fully used invites are rejected.
16. Confirm no user can choose their own role during normal access flow.

## Trust boundaries

- The Flutter client may guide flows, but it is never trusted to assign roles or venue scope.
- Firebase Auth proves identity only. It does not grant venue access by itself.
- Firestore rules remain the authoritative permission layer for venue isolation, role enforcement, invite usage, and owner bootstrap.
- Invite redemption and owner bootstrap now use Firestore transactions plus one-time metadata (`inviteId` or `bootstrapGrants/{email}`) so partial client failures fail closed.

## Current hardening status

- Manager and bartender account creation is invite-gated.
- Owner bootstrap is grant-gated instead of open to any signed-in auth user.
- Invite redemption uses an isolated secondary Firebase app so the primary app session is created only after Firestore commit succeeds.
- Retry after a partial invite failure is safer because an already-linked auth account can resume instead of spending the invite twice.

## Recommended production-grade architecture

Best next step:

- move account creation behind a callable Cloud Function or auth broker that validates the invite or bootstrap grant server-side, creates the auth user server-side, writes Firestore documents in the same trusted flow, and returns a custom token or success response to the client

Stronger option after that:

- add a Firebase blocking function so raw Email/Password sign-up is rejected unless an approved bootstrap grant or invite token is present in backend-controlled state

## Incident recovery guidance

If invite joins start failing or behaving inconsistently:

1. Check whether the target invite is disabled, expired, or already at `maxUses`.
2. Check whether a `users/{uid}` document already exists for the affected auth account with the expected `venueId`, `role`, and `inviteId`.
3. If Firestore commit failed before auth cleanup, disable the invite if needed, remove the orphan `users/{uid}` doc if it was partially written, and delete the orphan Firebase Auth user from the Firebase console.
4. If owner bootstrap failed, inspect `bootstrapGrants/{email}` for `disabled`, `usedAt`, `usedByUid`, and `venueId` before issuing a fresh grant.
