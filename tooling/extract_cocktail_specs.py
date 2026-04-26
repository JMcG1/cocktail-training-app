import json
import re
from io import BytesIO
from pathlib import Path

from PIL import Image
from pypdf import PdfReader


BUILD_STYLES = {'Built-Drink', 'Shaken-Drink'}
SECTION_MAP = {
    range(20, 38): 'Cocktails',
    range(51, 55): 'Spritz',
    range(56, 61): 'Shooters',
    range(62, 69): 'Alcohol-Free Cocktails',
}
EXTRACTION_PAGES = tuple(range(20, 38)) + tuple(range(51, 55)) + tuple(range(56, 61)) + tuple(range(62, 69))
IMAGE_OUTPUT_DIR = Path('assets/images/cocktails')
MAX_IMAGE_SIZE = (900, 1400)


def section_for_page(page_num: int) -> str:
    for page_range, name in SECTION_MAP.items():
        if page_num in page_range:
            return name
    return 'Cocktails'


def normalize_text(value: str) -> str:
    value = value.replace('\u017e', '¾')
    value = value.replace('T ea', 'Tea')
    value = value.replace('T op', 'Top')
    value = value.replace('Fever-tree', 'Fever-Tree')
    value = value.replace('CleanCo', 'Clean Co')
    value = value.replace('Warners', "Warner's")
    value = re.sub(r'\s+', ' ', value)
    return value.strip()


def clean_name(value: str) -> str:
    return normalize_text(value).rstrip('*').strip()


def slugify(value: str) -> str:
    value = value.lower().replace('0%', 'zero-percent')
    value = re.sub(r'[^a-z0-9]+', '-', value)
    return value.strip('-')


def humanize_build_style(value: str) -> str:
    return value.replace('-', ' ')


def parse_glassware(step: str) -> str:
    cleaned = re.sub(r'^\d+\.\s+', '', step)
    cleaned = cleaned.replace('Prepare a clean & cool ', '')
    cleaned = cleaned.replace('Use a clean & cool ', '')
    cleaned = cleaned.rstrip('.')
    return normalize_text(cleaned)


def parse_ingredient(line: str) -> dict[str, str | None] | None:
    original = normalize_text(line)
    if not original:
        return None

    if original.endswith('*'):
        original = original[:-1].strip()

    lower = original.lower()
    if lower.startswith('top with '):
        return {'measure': 'Top with', 'name': original[9:].strip(), 'note': None}

    match = re.match(r'^(\d+(?:-\d+)?(?:\.\d+)?(?:ml|x))\s+(.+)$', original, re.I)
    if match:
        return {'measure': match.group(1), 'name': match.group(2).strip(), 'note': None}

    match = re.match(r'^(\d+(?:-\d+)?)\s+Cubes? of\s+(.+)$', original, re.I)
    if match:
        return {'measure': f'{match.group(1)} cubes', 'name': match.group(2).strip(), 'note': None}

    match = re.match(r'^(\d+)\s+Lime Wedges\s+(.+)$', original, re.I)
    if match:
        return {'measure': f'{match.group(1)} wedges', 'name': 'Lime', 'note': match.group(2).strip()}

    if original.lower() == 'ice':
        return {'measure': '', 'name': 'Ice', 'note': None}

    return {'measure': '', 'name': original, 'note': None}


def ingredient_phrase(ingredients: list[dict[str, str | None]]) -> str:
    named = [item['name'] for item in ingredients if item['name'] and item['name'].lower() != 'ice']
    if not named:
        return 'core bar ingredients'
    if len(named) == 1:
        return named[0]
    if len(named) == 2:
        return f'{named[0]} and {named[1]}'
    return f'{named[0]}, {named[1]}, and {named[2]}'


def build_description(build_style: str, glassware: str, ingredients: list[dict[str, str | None]]) -> str:
    return f'{humanize_build_style(build_style)} in {glassware} with {ingredient_phrase(ingredients)}.'


def build_tags(section: str, build_style: str, glassware: str, name: str) -> list[str]:
    tags = [section, humanize_build_style(build_style), glassware]
    if 'spritz' in name.lower() and 'Spritz' not in tags:
        tags.append('Spritz')
    if section == 'Shooters':
        tags.append('Shot')
    if '0%' in name or 'Alcohol-Free' in section:
        tags.append('Alcohol-Free')
    return tags


def reset_image_output_dir() -> None:
    IMAGE_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for image_file in IMAGE_OUTPUT_DIR.glob('*.jpg'):
        image_file.unlink()


def extract_drink_image(page, slug: str) -> str | None:
    images = list(page.images)
    if not images:
        return None

    output_path = IMAGE_OUTPUT_DIR / f'{slug}.jpg'

    with Image.open(BytesIO(images[0].data)) as image:
        if image.mode not in {'RGB', 'L'}:
            image = image.convert('RGB')
        elif image.mode == 'L':
            image = image.convert('RGB')

        image.thumbnail(MAX_IMAGE_SIZE, Image.Resampling.LANCZOS)
        image.save(
            output_path,
            format='JPEG',
            quality=86,
            optimize=True,
            progressive=True,
        )

    return output_path.as_posix()


def extract_steps_and_ingredients(lines: list[str]) -> tuple[list[str], list[dict[str, str | None]], list[str]]:
    method_steps: list[str] = []
    ingredients: list[dict[str, str | None]] = []
    notes: list[str] = []
    current_step: str | None = None
    add_mode = False
    note_buffer: str | None = None

    def flush_step() -> None:
        nonlocal current_step
        if current_step is not None:
            method_steps.append(current_step.strip())
            current_step = None

    def flush_note() -> None:
        nonlocal note_buffer
        if note_buffer:
            notes.append(note_buffer.strip())
            note_buffer = None

    for raw_line in lines:
        line = normalize_text(raw_line)
        if not line or line in BUILD_STYLES:
            continue

        if line.startswith('*'):
            flush_step()
            flush_note()
            note_buffer = line.lstrip('*').strip()
            continue

        step_match = re.match(r'^(\d+)\.\s+(.+)$', line)
        if step_match:
            flush_note()
            flush_step()
            current_step = step_match.group(2).strip()
            add_mode = 'add:' in current_step.lower() or 'add (in order):' in current_step.lower()
            continue

        if note_buffer is not None:
            note_buffer = f'{note_buffer} {line}'.strip()
            continue

        if add_mode and current_step is not None:
            ingredient = parse_ingredient(line)
            if ingredient:
                ingredients.append(ingredient)
            current_step = f'{current_step} {line}'.strip()
            continue

        if current_step is not None:
            current_step = f'{current_step} {line}'.strip()
        else:
            notes.append(line)

    flush_note()
    flush_step()
    return method_steps, ingredients, notes


def extract_cocktails(pdf_path: Path) -> list[dict[str, object]]:
    reader = PdfReader(str(pdf_path))
    pending_premix: dict[str, dict[str, object]] = {}
    results: list[dict[str, object]] = []
    reset_image_output_dir()

    for page_num in EXTRACTION_PAGES:
        page = reader.pages[page_num - 1]
        lines = (page.extract_text() or '').replace('\x00', ' ').splitlines()
        lines = [line for line in lines if line.strip()]
        if not lines or lines[0].strip() != 'Perfect Drink Build':
            continue

        name = clean_name(lines[1])
        if '(Premix)' in name:
            premix_steps, premix_ingredients, premix_notes = extract_steps_and_ingredients(lines[2:])
            pending_premix[clean_name(name.replace('(Premix)', '').strip())] = {
                'ingredients': premix_ingredients,
                'steps': premix_steps,
                'notes': premix_notes,
            }
            continue

        build_style = 'Built-Drink'
        remaining_lines = lines[2:]
        if remaining_lines and remaining_lines[0] in BUILD_STYLES:
            build_style = remaining_lines[0]
            remaining_lines = remaining_lines[1:]
        elif remaining_lines and remaining_lines[-1] in BUILD_STYLES:
            build_style = remaining_lines[-1]
            remaining_lines = remaining_lines[:-1]

        method_steps, ingredients, notes = extract_steps_and_ingredients(remaining_lines)
        glassware = parse_glassware(method_steps[0]) if method_steps else ''
        garnish = ''
        for step in method_steps:
            garnish_match = re.search(r'Garnish with\s+(.+)$', step, re.I)
            if garnish_match:
                garnish = garnish_match.group(1).strip().rstrip('.').replace('*', '')
                break

        premix = pending_premix.get(name)
        if premix:
            premix_summary = ', '.join(
                ' '.join(part for part in [item['measure'], item['name']] if part).strip()
                for item in premix['ingredients']
            )
            if premix_summary:
                notes.append(f'Premix build: {premix_summary}.')
            for step in premix['steps']:
                if step not in notes:
                    notes.append(f'Premix step: {step}.')
            notes.extend(premix['notes'])

        slug = slugify(name)
        results.append(
            {
                'id': slug,
                'name': name,
                'category': section_for_page(page_num),
                'buildStyle': build_style,
                'glassware': glassware,
                'garnish': garnish,
                'description': build_description(build_style, glassware, ingredients),
                'source': 'Belhaven Mainstream Perfect Serve',
                'sourcePage': page_num,
                'imageAssetPath': extract_drink_image(page, slug),
                'tags': build_tags(section_for_page(page_num), build_style, glassware, name),
                'ingredients': ingredients,
                'methodSteps': method_steps,
                'notes': notes,
            }
        )

    return results


def main() -> None:
    source_dir = Path('source_pdfs')
    pdf_files = sorted(source_dir.glob('*.pdf'))
    if not pdf_files:
        raise SystemExit('No PDF found in source_pdfs/.')

    cocktails = extract_cocktails(pdf_files[0])
    print(json.dumps(cocktails, indent=2))


if __name__ == '__main__':
    main()
