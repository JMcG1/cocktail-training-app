# Business Rules

## Tone and wording

- Supportive language only.
- Never say “you lost money”.
- Never say “you caused loss”.
- Prefer:
  - “potential variance”
  - “recipe confidence”
  - “training focus”
  - “consistency opportunity”

The app should coach, not blame.

## Variance meaning

- Overpour and underpour are different.
- Overpour contributes to potential stock variance and cost impact.
- Underpour is a quality and consistency issue.
- Underpour is not framed as a saving.

## Approved-source rule

Recipes must come from an approved source:

- reviewed PDF extraction
- reviewed OCR extraction
- curated reviewed dataset

The app must not:

- invent cocktails
- invent missing measures
- fill missing garnish, glassware, or method from general cocktail knowledge

## Import and approval rule

- OCR data must go through review and approval.
- Curated imports still go through review and approval.
- Drafts with unresolved issues should stay in review.
- False positives should be deleted, not guessed into valid recipes.

## Owner/admin rule

- Owner approves recipes.
- Owner approves batch recipes.
- Owner approves pricing.
- Managers do not change official spec data.

## Manager workflow rule

Managers focus on:

- stock concerns
- bartender sales
- targeted quiz launch
- supportive result review

Managers should not become recipe approvers or OCR correction operators.

## Stock concern rule

Stock concern quizzes must use only relevant approved recipes.

That means:

- only cocktails linked to the concern ingredient should be included
- batch-linked cocktails must be included when the underlying ingredient is in concern

## Batch rule

- Batch recipes must be resolved before reliable variance calculations.
- Batch links must not be invented silently.
- Batch variance must break down into underlying ingredients.
- Circular or unresolved batch references must be flagged.

## Cost rule

- Ingredient costs drive approximate pound-value calculations.
- Batch cost derives from underlying ingredient contributions.
- Missing costs should stay visible as missing, not estimated from guesswork.

## Reporting rule

Dashboards and quiz results should describe:

- potential variance
- confidence
- focus areas
- consistency opportunities

They should not present punitive or shaming language.
