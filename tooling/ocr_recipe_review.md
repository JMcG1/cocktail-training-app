# OCR Recipe Review

## Summary
- Source folder: `ocr_output/cocktail_specs_2026/`
- OCR page text files read: 65
- Recipe specification pages detected automatically: 49
- Structured recipes exported: 37
- JSON output: `assets/data/cocktails.json`

## Validation
- JSON decoded successfully as a top-level list.
- All recipe ids are unique.
- Each entry includes `id`, `name`, `ingredients`, `method`, `glass`, `garnish`, and `ice`.
- The dataset is stored under `assets/data/` for Flutter asset loading.

## Recipes With Missing Or Conflicting Fields
- `Pornstar Martini` (page 19): missing garnish.

## Low-Confidence OCR Sections
- `Strawberry Shrub Spritz` (page 5): The ingredient table was noisier than the method block, so prosecco and soda volumes were confirmed from the method steps.
- `Hugo Spritz` (page 6): The garnish line merged into the method block, so the mint garnish was recovered from the serving instructions.
- `Watermelon Spritz` (page 7): The ingredient table reads "Cantaloupe Batch" while the method block reads "Watermelon Spritz Batch"; the final dataset follows the method block and recipe title.
- `The Lawnstar Martini` (page 8): The shot-glass prosecco serve and atomizer finish only appeared clearly in the method block, not the ingredient table.
- `Garden Gimlet` (page 13): Sugar syrup only appears clearly in the method block, so it was added from the service steps rather than the ingredient table.
- `The Botanista Cosmo` (page 14): The OCR rendered the lime measure as "145ML"; the recipe image and method layout confirm 15ml.
- `Palmhouse Colada` (page 16): The OCR clipped the soda line, so the 25ml soda serve was confirmed against the source page artwork.
- `Pornstar Martini` (page 19): Several ingredient amounts were noisy in the OCR, and no garnish was listed on the page, so the serve keeps the garnish field blank and flags the recipe for review.
- `Dark and Stormy` (page 21): The lime amount was partially obscured in the ingredient table, so 15ml was confirmed from the method block.
- `Raspberry Martini` (page 23): The OCR page title reads like "Raspberry Martini", and this dataset now follows that page title.
- `Classic Old Fashioned` (page 28): The ingredient table clipped the bourbon line, so the spirit name was recovered from the method instructions.
- `Pimm's & Lemonade` (page 29): The OCR title reads "LEMOMADE"; the final name is corrected to "Lemonade".
- `Irish Coffee` (page 30): The method OCR briefly read the sugar line as "145ML"; the ingredient table confirms a 15ml gomme serve.
- `Hu-No Spritz` (page 35): The OCR text dropped the title, so the recipe name and garnish were confirmed against the source page image.
- `Apernol Spritz` (page 36): The OCR text lost the title and part of the garnish line, so the final name and garnish were image-verified.
- `Botanist Mule` (page 37): The OCR clipped the bottle serve note, so the 200ml ginger beer bottle measure was cross-checked with the page image.
- `Watermelon Cooler` (page 38): The page title and glassware were confirmed from the source image because the OCR text partially dropped them.
- Additional OCR pages with recipe-style layout were detected and ignored for this export: 41, 42, 43, 44, 45, 47, 48, 49, 50, 51, 52, 53.

## Page Coverage
| Page | Cocktail | Category |
| --- | --- | --- |
| 3 | Aperol Spritz | Spritz Off Main Menu |
| 4 | Limoncello Spritz | Spritz Off Main Menu |
| 5 | Strawberry Shrub Spritz | Spritz Off Main Menu |
| 6 | Hugo Spritz | Spritz Off Main Menu |
| 7 | Watermelon Spritz | Spritz Off Main Menu |
| 8 | The Lawnstar Martini | Signature Cocktails |
| 9 | Flower Power 75 | Signature Cocktails |
| 10 | Tomatini Plant Pot | Signature Cocktails |
| 11 | Bramble Plant Pot | Signature Cocktails |
| 12 | Picante Margarita | Signature Cocktails |
| 13 | Garden Gimlet | Signature Cocktails |
| 14 | The Botanista Cosmo | Signature Cocktails |
| 15 | Botany Bay Rum Punch | Signature Cocktails |
| 16 | Palmhouse Colada | Signature Cocktails |
| 17 | The Botanist Ultimate G&T | Signature Cocktails |
| 18 | Espresso Martini | Classic Cocktails |
| 19 | Pornstar Martini | Classic Cocktails |
| 20 | Classic Mojito | Classic Cocktails |
| 21 | Dark and Stormy | Classic Cocktails |
| 22 | Amaretto Sour | Classic Cocktails |
| 23 | Raspberry Martini | Classic Cocktails |
| 24 | Classic Negroni | Classic Cocktails |
| 25 | Paloma | Classic Cocktails |
| 26 | Bloody Botanist | Classic Cocktails |
| 27 | Classic Margarita | Classic Cocktails |
| 28 | Classic Old Fashioned | Classic Cocktails |
| 29 | Pimm's & Lemonade | Spritz Off Main Menu |
| 30 | Irish Coffee | Spritz Off Main Menu |
| 31 | Long Island Iced Tea | Spritz Off Main Menu |
| 32 | Mimosa | Spritz Off Main Menu |
| 33 | Homemade Lemonade | Spritz Off Main Menu |
| 34 | Passionfruit Iced Tea | Non-Alc Cocktails |
| 35 | Hu-No Spritz | Non-Alc Cocktails |
| 36 | Apernol Spritz | Non-Alc Cocktails |
| 37 | Botanist Mule | Non-Alc Cocktails |
| 38 | Watermelon Cooler | Non-Alc Cocktails |
| 39 | Garden Mary | Non-Alc Cocktails |
