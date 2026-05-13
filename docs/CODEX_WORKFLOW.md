# Codex Workflow

## Working style

- One prompt should map to one focused task.
- Before coding, summarize the plan and likely affected files.
- Make changes against the real architecture, not assumptions.
- Keep demo data separate from live Firebase data.

## Required validation

Always run:

```powershell
dart analyze lib test tooling
flutter test
flutter build web --release
```

Do not commit if validation is knowingly dirty unless the user explicitly asks for a partial state.

## Tests

- Add or update tests for business-rule changes.
- Add or update tests for permission changes.
- Add or update tests for Firestore-path or collection changes.

## Commits

- Commit after clean validation.
- Use a clear message that describes the real change.
- Push only after the branch is in a stable, explained state.

## Documentation discipline

- Update docs whenever architecture, security, deployment, or business rules change.
- Keep docs aligned with the real codebase.
- Mark planned-but-not-implemented items explicitly.

## Firestore and data-model rules

- Do not rename core collections or models without migration notes.
- Do not change Firestore path constants casually.
- Do not weaken Firestore rules broadly to fix a bug.
- Prefer exact permission fixes over broad access rules.

## Security discipline

- Keep role boundaries enforced in both UI and Firestore rules.
- Never let users choose their own role.
- Treat public quiz access as a narrow exception, not a general read model.

## Business-rule discipline

- Preserve supportive language.
- Do not invent cocktails or missing specs.
- Keep owner-only approval for recipes, batches, and pricing.
- Keep manager workflows focused on operations and coaching.

## Dangerous changes checklist

If touching any of these, explain the impact first:

- `firestore.rules`
- Firestore collection names
- `UserRole`
- variance math
- batch decomposition
- import approval flow
- build-time Firebase define names

## New Codex Session Starter

Copyable prompt:

```text
Before making changes, read these files first and use them as the source of truth:

- docs/PROJECT_CONTEXT.md
- docs/ARCHITECTURE.md
- docs/SECURITY_MODEL.md
- docs/BUSINESS_RULES.md

Then summarize:
- the task you think I want
- the files you expect to touch
- any architecture, security, or business-rule constraints you need to preserve

After that, make the change, run:
- dart analyze lib test tooling
- flutter test
- flutter build web --release

Then report:
- what changed
- validation results
- any doc updates or migration notes required
```
