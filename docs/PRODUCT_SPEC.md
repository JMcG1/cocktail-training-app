# Cocktail Training Product Spec

Last updated: 2026-06-17

## What the app does

Cocktail Training is a mobile-first hospitality training app for venue teams.

It helps bartenders:

- study approved cocktail specs
- practise measures, ingredients, garnish, and batch knowledge
- complete quizzes
- review their own progress

It helps managers and owners:

- invite staff into the venue workspace
- review team progress
- launch targeted surprise quizzes
- import or enter cocktail sales for training review
- maintain approved cocktail, batch, and ingredient-cost data

The product is designed to feel operational and supportive rather than technical or punitive.

## Who it is for

- Bartenders who need to learn and retain the current approved cocktail list
- Managers who coach bartenders and review team training
- Owners/admins who control approved specs, prices, ingredient cost data, and venue setup

## Product principles

- Invite-only access
- Mobile-first layout
- Approved cocktails only in bartender-facing learning flows
- Supportive wording around mistakes, variance, and coaching
- Venue-scoped data separation
- Real Firebase auth and persistence in production

## Roles

### Owner/Admin

In the current codebase the top role is stored as `owner`. In product language, this is the owner/admin role.

Owner/admin can:

- do everything a manager can do
- access the admin setup screens
- manage approved cocktail and batch data
- manage ingredient bottle sizes and bottle prices
- manage venue-level setup
- review import and draft flows

Owner/admin cannot:

- bypass Firestore security rules
- make unresolved draft data live without the existing review/save flow

### Manager

Manager inherits bartender access and also gets venue management tools.

Manager can:

- study cocktails
- use practice quizzes
- review personal progress
- invite bartenders
- invite managers under the current venue policy
- view team results
- view team progress
- create stock concern sessions
- enter or import bartender sales for training analysis
- launch surprise quiz QR codes

Manager cannot:

- access owner-only admin setup
- approve official recipes or batch recipes
- edit owner-only approved catalog setup
- manage owner bootstrap

### Bartender

Bartender can:

- open the approved cocktail library
- use study mode
- take practice quizzes
- take live surprise quizzes
- view personal results and progress

Bartender cannot:

- access manager team tools
- access owner/admin setup
- invite staff
- manage ingredient pricing
- import sales reports

## Role matrix

| Capability | Bartender | Manager | Owner/Admin |
| --- | --- | --- | --- |
| Log in | Yes | Yes | Yes |
| Reset password | Yes | Yes | Yes |
| View approved cocktail library | Yes | Yes | Yes |
| Use study mode | Yes | Yes | Yes |
| Take practice quiz | Yes | Yes | Yes |
| View own progress | Yes | Yes | Yes |
| View team progress | No | Yes | Yes |
| Create bartender invites | No | Yes | Yes |
| Create manager invites | No | Yes | Yes |
| Import sales PDF | No | Yes | Yes |
| Launch surprise quiz QR | No | Yes | Yes |
| Manage ingredient costs | No | No | Yes |
| Manage approved cocktail data | No | No | Yes |
| Access admin setup | No | No | Yes |

## Main user journeys

### Bartender journey

1. Receive an invite link or QR code from a manager.
2. Join the venue with the role decided by the invite.
3. Log in with email and password.
4. Open the approved cocktail library.
5. Study specs and linked batch details.
6. Take practice quizzes or live surprise quizzes.
7. Review personal results and progress.

### Manager journey

1. Log in to the venue workspace.
2. Review team progress and recent quiz results.
3. Create bartender or manager invites.
4. Choose stock concerns for the week.
5. Enter or import sales data by bartender.
6. Launch a surprise quiz focused on the relevant ingredients or specs.
7. Review coaching opportunities and sales-linked impact.

### Owner/admin journey

1. Log in to the venue workspace.
2. Open admin setup.
3. Review the approved cocktail and batch catalog.
4. Update ingredient bottle size and bottle price data.
5. Manage venue-level setup and quality-control tasks.
6. Use manager tools when testing or reviewing training flows.

## Key screens

### Landing and login

- Email/password login
- Password reset
- Invite-only explanation
- Optional owner bootstrap entry point when enabled

### Join via invite

- Reads the invite from the link
- Shows the fixed role from the invite
- Does not allow self-selected role changes

### Approved cocktail library

- Approved cocktail cards
- Image where available
- Ingredients
- Method
- Garnish
- Glassware
- Linked batch details

### Study mode

- Mobile-friendly reveal flow
- Focused on quick repetition and memory refresh

### Quiz

- Practice quiz
- Spec-focused quiz
- Garnish and glassware quiz
- Live surprise quiz via link or QR when launched by a manager

### Progress

- Bartender: own results only
- Manager and owner: own progress plus team views in the separate team workspace

### Team workspace

- Staff invites
- Team results
- Team progress
- Sales import and stock concern workflows
- Surprise quiz launch

### Admin setup

- Ingredient cost management
- Commodity CSV import into ingredient costs
- Approved catalog support tasks
- Pricing and setup controls reserved for owner/admin access

## Current product boundaries

- The app uses a fixed approved cocktail catalog as the live learning source.
- Bartenders are not expected to work through draft approval tools.
- The owner/admin role is implemented as `owner` in code.
- Manager-created manager invites are currently allowed by the live venue policy.
- The PDF sales import is built around the current Aztec-style report layout and should be treated as format-sensitive.

## Proposed later behaviour, not yet fully productised

- Venue-level manager-invite policy flags
- Cross-venue reporting
- Completion certificates or formal training completion states
- Commercial subscription and support flows
