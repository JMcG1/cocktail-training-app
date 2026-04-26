# CocktailTraining

CocktailTraining is a Flutter web app built for bartender training, with a premium mobile-first interface, searchable cocktail, spritz, and shooter references, extracted drink photos, and placeholder study, quiz, and progress experiences.

## Included

- Firebase Auth-ready login placeholder
- Searchable cocktail library backed by local JSON assets
- Cocktail detail pages powered by clean domain models
- Placeholder study, quiz, and progress screens
- Bottom navigation optimized for mobile layouts
- Cloudflare Pages-friendly web routing fallback

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
