# Cocktail Training Roadmap

Last updated: 2026-06-17

This roadmap reflects the current Flutter web + Firebase + Cloudflare codebase as it exists today. Status values are:

- `Done`: already working in the current app
- `In progress`: partly implemented but still needs tightening
- `Planned`: not implemented yet

## Phase 1: Stabilise

| Item | Current status | Priority | Effort | Risk | Next action |
| --- | --- | --- | --- | --- | --- |
| Login | `Done` in Firebase mode after the recent Cloudflare config fixes | Critical | Small | High if Firebase config drifts | Keep the Firebase env vars and authorized domains documented and run the login smoke test after every production deploy |
| Password reset | `Done` from the login screen | High | Small | Medium if Firebase email templates are not configured clearly | Run live reset-link testing for owner, manager, and bartender accounts |
| Logout | `Done` | High | Small | Low | Add a manual regression check to every release pass |
| Invite system | `Done` for venue-scoped manager and bartender onboarding | Critical | Medium | High because invites control access | Add more automated coverage around expired, disabled, and fully-used invites |
| Role handling | `In progress` | Critical | Medium | High because permissions affect both UX and security | Continue consolidating direct role checks into the hierarchical permission model |
| Cocktail library | `Done` for the fixed approved catalog | High | Small | Medium if curated data drifts from Firestore | Keep the verified catalog as the single approved source of truth |
| Study mode | `Done` | High | Small | Low | Continue tuning copy and mobile readability based on live bartender feedback |
| Quiz mode | `Done` with spec-focus and garnish/glass focus | High | Medium | Medium because quiz quality drives training value | Keep tuning distractors and add more targeted measure-question coverage tests |
| Results saving | `Done` | High | Medium | Medium if venue reads or writes regress | Add a manager-facing regression test for team results visibility |

## Phase 2: Hospitality Ready

| Item | Current status | Priority | Effort | Risk | Next action |
| --- | --- | --- | --- | --- | --- |
| Better bartender study flow | `In progress` | High | Medium | Medium | Split the long all-purpose study flow into clearer bartender-first practice paths if live usage shows confusion |
| Better quiz questions | `In progress` | High | Medium | Medium | Keep spec-measure questions as the default focus and expand targeted weak-area generation |
| Manager dashboard | `Done` but still concentrated in one large screen file | High | Medium | Medium | Break the workspace into smaller widgets without changing behaviour |
| Team progress | `Done` | High | Medium | Medium | Add more manager regression tests around venue teammate loading |
| Weak area tracking | `Done` | Medium | Medium | Medium | Validate that weak-area summaries stay clear on mobile and remain supportive in tone |
| Leaderboard | `Planned` | Low | Medium | Low | Decide whether it is motivating or distracting before implementation |
| Training completion reporting | `Planned` | Medium | Medium | Medium | Define what counts as completion by role and by week before building reports |

## Phase 3: Variance Training

| Item | Current status | Priority | Effort | Risk | Next action |
| --- | --- | --- | --- | --- | --- |
| Stock concerns | `Done` | High | Medium | Medium | Add more manager tests around session creation and duplicate prevention |
| Bartender sales imports/manual sales entry | `Done` for manual entry and the current PDF import flow | High | Medium | Medium because PDF layout assumptions may change | Keep a sample Aztec PDF in test fixtures and add parser regression tests |
| Potential variance calculations | `Done` | High | Medium | Medium | Cross-check live pricing coverage so calculations stay meaningful |
| Ingredient cost impact | `Done` | High | Medium | Medium | Keep chasing missing ingredient prices and add a clearer “missing cost data” manager list |
| Weekly improvement tracking | `In progress` | Medium | Medium | Medium | Decide which summaries should be persisted versus derived on demand |

## Phase 4: Commercial Readiness

| Item | Current status | Priority | Effort | Risk | Next action |
| --- | --- | --- | --- | --- | --- |
| Venue onboarding | `In progress` through owner bootstrap plus invites | High | Medium | High because bootstrap still depends on manual grant setup | Document the bootstrap playbook and consider a backend-assisted onboarding flow |
| Multi-site support | `Planned` | Medium | Large | Medium | Keep venue scoping strict now so cross-venue reporting can be added safely later |
| Trial/subscription readiness | `Planned` | Low | Large | Medium | Leave out until the operational product flow is stable |
| Support page | `Planned` | Low | Small | Low | Add only once live support wording and escalation routes are agreed |
| Privacy policy | `Planned` | Medium | Small | Medium | Draft alongside any broader external rollout |
| Terms | `Planned` | Medium | Small | Medium | Add before public onboarding or commercial trials |
| Data export | `In progress` with lightweight export helpers only | Medium | Medium | Medium | Decide what manager and owner exports are required and formalise the export UX |

## Quick wins

- Finish migrating the remaining duplicated role checks to shared permission helpers.
- Keep the emulator-backed Firestore rules tests growing as new invite, bootstrap, and venue boundaries are added.
- Split the large manager and training workspace widgets into smaller files to reduce regression risk.
- Keep the curated recipe catalog versioned and visible in diagnostics so operators know what is live.

## Not on the roadmap yet

- Broad public signup
- Weakening Firestore rules for convenience
- Separate ingredient pricing products or supplier catalogues
- Replacing the fixed approved cocktail catalog with free-form live editing for bartenders
