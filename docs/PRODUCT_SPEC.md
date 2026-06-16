# Cocktail Training Product Spec

## Purpose

Cocktail Training is a mobile-first Flutter web app for bartenders and managers.
It helps venue teams learn approved cocktail specs, practise knowledge before shifts,
track improvement over time, and use ingredient pricing plus sales data to highlight
training opportunities without sounding punitive.

## Core roles

- Owner/Admin: manage venue settings, approved specs, images, ingredient costs, and venue-wide data
- Manager: invite managers and bartenders, upload weekly sales reports, review team performance, and identify training opportunities
- Bartender: study cocktails, take quizzes, and review personal progress only

## Product rules

- The app is invite-only. Public sign-up is not part of the product.
- Invite links decide the role automatically.
- Managers and bartenders must remain venue-scoped.
- The library and study screens should show only approved cocktails and approved batch information.
- The app should feel like a professional hospitality training platform, not a developer tool.
- Mobile usability comes first across login, study, quiz, and manager workflows.

## Library and study expectations

- Show cocktail image, name, ingredients, measures, method, garnish, glassware, batch usage, and helpful notes
- Keep titles readable on mobile without awkward single-word wrapping
- Support hide/reveal learning mode and weak-area practice focus
- Use simple bartender-friendly wording

## Quiz expectations

- Include missing ingredient, measure, garnish, method, glassware, batch, and full-spec questions
- Always display units on measures such as `50ml`
- Use believable distractors rather than silly trick answers
- Save results per bartender and expose team visibility only to managers

## Ingredient pricing expectations

- Reuse the existing ingredient cost admin area
- Store ingredient name, bottle size, and bottle price
- Calculate cost per ml from bottle price and bottle size

## Sales and variance expectations

- Managers upload Aztec Product Sales by Employee PDFs
- Extract venue, date range, employee names, and cocktail products sold
- Ignore non-cocktail items unless explicitly mapped later
- Support bartender review, name cleanup, duplicate merging, and ignored staff rows
- Link sales to existing users where possible and avoid duplicate accounts
- Use quiz answers plus cocktail sales volume and ingredient cost per ml to describe potential variance and estimated cost impact
- Keep the language supportive: training opportunity, potential variance, estimated cost impact

## History expectations

- New weekly imports replace the current live sales reference set
- Historical quiz, progress, and cost-impact summaries must remain intact
- Historical charts should continue to reflect the calculation context that existed when each result was saved

## Technical expectations

- Reliable Firebase Authentication and Firestore access in normal browser tabs
- Correct role permissions and venue scoping
- Cloudflare Pages deployment that works on mobile, tablet, and desktop
- No requirement for Incognito Mode
