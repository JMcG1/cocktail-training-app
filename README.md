# CocktailTraining

CocktailTraining is a Flutter web app built for bartender training, with a premium mobile-first interface, searchable cocktail, spritz, and shooter references, extracted drink photos, and study, quiz, progress, and invite flows.

## Included

- Firebase web auth and Firestore are used on web; non-web/test environments fall back to local mock session storage
- Searchable cocktail library backed by local JSON assets
- Cocktail detail pages powered by clean domain models
- Study, quiz, and progress experiences
- Bottom navigation optimized for mobile layouts
- Cloudflare Pages-friendly web routing fallback for static hosting

## Local development

```bash
flutter pub get
flutter run -d chrome
```

## Extracting Specs From Source PDFs

Drop the source training PDF into `source_pdfs/`, then run:

```bash
python tooling/extract_cocktail_specs.py
```

The extractor is tuned for the Belhaven-style serve guide currently in this repo and updates both `assets/data/cocktails.json` and the drink image assets in `assets/images/cocktails/`.

## Build for Cloudflare Pages

```bash
flutter build web --release
```

Use these Cloudflare Pages settings:

- Build command: `flutter build web --release`
- Build output directory: `build/web`

The app includes `web/_redirects` so direct requests continue resolving to `index.html` during static hosting.

## Current Backend Status

- Cloudflare Pages currently serves the static Flutter web build.
- No Cloudflare Worker or Pages Function backend is wired in this repo.
- Firebase Auth + Firestore power login, roles, and invites on web.
- `LocalAppStore` remains as a fallback for non-web/test environments and local onboarding flow testing.
