# Firestore Schema

This document describes the intended and current Firestore shape for the project.

Important:

- The canonical current batch collection path is `venues/{venueId}/batchRecipes/{batchRecipeId}`.
- The invite and audit-log collections are documented here because they are part of the product/security plan, but they are not fully implemented yet.
- Do not rename core collections casually. Add migration notes first.

## Global collections

### `bootstrapGrants/{email}`

Purpose:

- one-time owner bootstrap authorization for controlled venue setup

Key fields:

- `email`
- `role` expected to remain `owner`
- `disabled`
- optional `expiresAt`
- optional `usedAt`
- optional `usedByUid`
- optional `venueId`

Read/write permissions:

- clients cannot read or create bootstrap grants directly
- the bootstrap client may update only its own matching grant during successful owner setup
- long-term management of grants should be done by trusted admins through backend tooling or the Firebase console

Related models/files:

- bootstrap logic in [firebase_repositories.dart](/C:/Users/jaime/Documents/New%20project%202/lib/data/repositories/firebase_repositories.dart)
- rules in [firestore.rules](/C:/Users/jaime/Documents/New%20project%202/firestore.rules)

Migration notes:

- keep document id equal to the normalized bootstrap email expected by the client flow
- if bootstrap moves to a callable backend later, this collection can become fully backend-managed or be replaced entirely

### `users/{uid}`

Purpose:

- stores application role and venue scope for authenticated users

Key fields:

- `displayName`
- `email`
- `role`
- `venueId`
- `inviteId` for invite-created manager/bartender accounts
- `createdAt`
- `active`

Read/write permissions:

- self-read allowed
- owner can read users in the same venue
- owner can create manager users in the same venue
- users cannot freely change their own role

Related models/files:

- `AppUser` in [models.dart](/C:/Users/jaime/Documents/New%20project%202/lib/domain/models/models.dart)
- auth repositories in [firebase_repositories.dart](/C:/Users/jaime/Documents/New%20project%202/lib/data/repositories/firebase_repositories.dart)
- rules in [firestore.rules](/C:/Users/jaime/Documents/New%20project%202/firestore.rules)

Migration notes:

- if invite-based onboarding becomes active, add invite source metadata rather than changing `role` semantics

## Venue root

### `venues/{venueId}`

Purpose:

- stores venue-level identity and ownership metadata

Key fields:

- `name`
- `ownerUid`
- `createdAt`
- `active`

Read/write permissions:

- owner and manager can read
- owner can update
- bootstrap owner can create

Related models/files:

- `VenueProfile` in [models.dart](/C:/Users/jaime/Documents/New%20project%202/lib/domain/models/models.dart)

Migration notes:

- keep venue root minimal; operational history belongs in subcollections

## Planned access-management collections

### `venues/{venueId}/invites/{inviteId}`

Purpose:

- planned collection for invite-only onboarding

Current status:

- active
- used for invite-only manager and bartender onboarding

Suggested key fields:

- `venueId`
- `role`
- `createdBy`
- `createdAt`
- `expiresAt`
- `maxUses`
- `currentUses`
- `disabled`

Read/write permissions:

- owner and manager can create manager/bartender invites for their own venue
- public clients can `get` only a single redeemable invite doc needed for a join link
- invite acceptance must never allow role escalation
- invite usage increments must happen atomically with user creation

Related models/files:

- `VenueInvite`
- auth flow in [firebase_repositories.dart](/C:/Users/jaime/Documents/New%20project%202/lib/data/repositories/firebase_repositories.dart)
- rules in [firestore.rules](/C:/Users/jaime/Documents/New%20project%202/firestore.rules)

Migration notes:

- public list access must remain disabled
- if invite metadata expands later, keep role and venue locked to the invite

## Official spec collections

### `venues/{venueId}/recipes/{recipeId}`

Purpose:

- stores approved cocktail recipes used by training, stock focus, quizzes, and variance math

Key fields:

- `name`
- `category`
- `glassware`
- `garnish`
- `method`
- `notes`
- `ingredients`
- `sourceLabel`
- `needsReview`
- `reviewFlags`
- `isApproved`
- `wasManuallyReviewed`

Read/write permissions:

- signed-in venue users read
- owner-only write

Related models/files:

- `CocktailRecipe`
- `FirestoreSerializers.recipeToMap/fromMap`
- `RecipeImportDraft.toRecipe`

Migration notes:

- do not add guessed fallback fields from general cocktail knowledge

### `venues/{venueId}/batches/{batchId}`

Purpose:

- requested conceptual collection for batch recipes

Current status:

- not the live collection path
- live code currently uses `venues/{venueId}/batchRecipes/{batchRecipeId}`

Migration notes:

- if this path is ever introduced, it requires explicit migration from `batchRecipes`
- do not rename the collection without migration code, serializer updates, and rule updates

### `venues/{venueId}/batchRecipes/{batchRecipeId}`

Purpose:

- current live collection for approved batch recipes

Key fields:

- `name`
- `category`
- `notes`
- `ingredients`
- `totalBatchVolumeMl`
- `sourceLabel`
- `needsReview`
- `reviewFlags`
- `isApproved`
- `wasManuallyReviewed`

Read/write permissions:

- signed-in venue users read
- owner-only write

Related models/files:

- `BatchRecipe`
- `FirestorePaths.batchRecipes`
- `FirestoreSerializers.batchRecipeToMap/fromMap`

Migration notes:

- circular reference protection must remain intact if nested batch support expands

### `venues/{venueId}/ingredients/{ingredientId}`

Purpose:

- stores ingredient bottle size and cost data used for variance value calculations

Key fields:

- `name`
- `bottleSizeMl`
- `bottleCost`

Read/write permissions:

- signed-in venue users read
- owner-only write

Related models/files:

- `Ingredient`
- `VarianceMath`
- `BatchGraphResolver`

Migration notes:

- missing costs should remain explicit, not inferred

### `venues/{venueId}/recipeDrafts/{draftId}`

Purpose:

- stores imported OCR/PDF/curated drafts still in review

Key fields:

- `sourceLabel`
- `pageLabel`
- `name`
- `category`
- `glassware`
- `garnish`
- `method`
- `notes`
- `ingredients`
- `reviewFlags`
- `status`
- `wasManuallyReviewed`
- `entityType`
- `totalBatchVolumeMl`

Read/write permissions:

- owner-only read/write

Related models/files:

- `RecipeImportDraft`
- import tabs in [app_shell.dart](/C:/Users/jaime/Documents/New%20project%202/lib/presentation/screens/app_shell.dart)

Migration notes:

- preserve OCR traceability fields if import pipeline changes later

## Operational collections

### `venues/{venueId}/stockConcernSessions/{sessionId}`

Purpose:

- stores weekly stock concern definitions and targeted cocktail pool ids

Key fields:

- `label`
- `weekStart`
- `concerns`
- `targetCocktailIds`
- `quizSessionIds`

Read/write permissions:

- owner and manager read/write

Related models/files:

- `WeeklyConcernSession`
- `ManagerTrialHelpers`
- `WeeklyFocusTab`

Migration notes:

- keep this operational and venue-scoped; do not move approved spec data here

### `venues/{venueId}/bartenderSales/{salesId}`

Purpose:

- stores bartender-specific relevant cocktail sales for a weekly stock focus session

Key fields:

- `weekId`
- `bartenderName`
- `entries`

Read/write permissions:

- owner and manager read/write

Related models/files:

- `BartenderWeeklySales`
- `BartenderSalesEntry`

Migration notes:

- if POS integration lands later, preserve compatibility with manually entered workflow

### `venues/{venueId}/quizSessions/{quizSessionId}`

Purpose:

- stores generated quiz sessions for practice and stock-focus flows

Key fields:

- `title`
- `bartenderName`
- `kind`
- `isActive`
- `createdAt`
- `questions`
- `weekId`

Read/write permissions:

- owner and manager write
- owner and manager read
- public direct `get` only while `isActive == true`
- no public list access

Related models/files:

- `QuizSession`
- quiz generation in repositories

Migration notes:

- public access must stay session-limited and active-only

### `venues/{venueId}/quizAttempts/{attemptId}`

Purpose:

- stores submitted quiz results and variance output

Key fields:

- `sessionId`
- `weekId`
- `bartenderName`
- `submittedAt`
- `scorePercent`
- `responses`
- `overpourLines`
- `underpourLines`
- `batchOverpourLines`
- `batchUnderpourLines`
- `coachingAreas`
- `encouragement`

Read/write permissions:

- public create only for active quiz sessions
- owner and manager read
- no public read/update/delete

Related models/files:

- `QuizAttempt`
- `VarianceMath`

Migration notes:

- wording fields must stay supportive

### `venues/{venueId}/trendSummaries/{summaryId}`

Purpose:

- stores lightweight operational rollups for dashboard/trend views

Key fields:

- implementation-specific summary fields such as bartender name, latest score, and potential variance value

Read/write permissions:

- owner and manager read/write

Related models/files:

- `FirestoreSerializers.trendSummaryToMap`
- dashboard assembly in `AppController`

Migration notes:

- treat as derived/cacheable operational summary, not the canonical source of truth

## Planned audit collection

### `venues/{venueId}/auditLogs/{logId}`

Purpose:

- planned owner/admin trace log for sensitive actions

Current status:

- documented/reserved
- not fully implemented in the current app

Suggested key fields:

- `actorUid`
- `actorRole`
- `action`
- `targetCollection`
- `targetId`
- `summary`
- `createdAt`

Read/write permissions:

- owner read
- system/owner-controlled writes only

Related models/files:

- future implementation should log approvals, pricing changes, manager account changes, and rule-sensitive setup changes

Migration notes:

- add only with a clear retention and privacy policy
