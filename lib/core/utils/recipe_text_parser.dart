import '../../domain/models/models.dart';

class RecipeTextParser {
  RecipeImportResult parseImportText({
    required String source,
    required String sourceName,
  }) {
    final raw = source.trim();
    if (raw.isEmpty) {
      return RecipeImportResult(
        sourceName: sourceName,
        drafts: const [],
        warnings: const [
          'No extractable text was provided. If the PDF is scanned, run OCR first and then paste the OCR text here for review.',
        ],
        requiresOcr: true,
        rawText: raw,
        pageCount: 0,
      );
    }

    final hasPageMarkers = raw.contains('===== PAGE');
    final blocks = hasPageMarkers
        ? _extractOcrPages(raw)
        : raw
            .split(RegExp(r'\n\s*\n'))
            .map((block) => _RecipeBlock(text: block.trim(), label: 'Block', pageNumber: null))
            .where((block) => block.text.isNotEmpty)
            .toList();

    final drafts = <RecipeImportDraft>[];
    final warnings = <String>[];
    final tocEntriesByPdfPage =
        hasPageMarkers ? _extractContentsMap(blocks) : <int, _TocEntry>{};

    for (var index = 0; index < blocks.length; index += 1) {
      final block = blocks[index];
      final draft = hasPageMarkers
          ? _parseOcrPage(
              pageText: block.text,
              id: 'import-${DateTime.now().microsecondsSinceEpoch}-$index',
              sourceName: sourceName,
              pageLabel: block.label,
              tocEntry: tocEntriesByPdfPage[block.pageNumber],
            )
          : _parseBlock(
              block: block.text,
              id: 'import-${DateTime.now().microsecondsSinceEpoch}-$index',
              sourceName: sourceName,
              pageLabel: '${block.label} ${index + 1}',
            );
      if (draft == null) {
        continue;
      }
      drafts.add(draft);
    }

    if (drafts.isEmpty) {
      warnings.add(
        'No complete recipe drafts were detected automatically. Review the OCR text and split it into clearer recipe blocks if needed.',
      );
    }

    return RecipeImportResult(
      sourceName: sourceName,
      drafts: drafts,
      warnings: warnings,
      requiresOcr: false,
      rawText: raw,
      pageCount: 0,
    );
  }

  RecipeImportDraft? parseSingleRecipe({
    required String source,
    required String fallbackId,
    required String sourceName,
  }) {
    return _parseBlock(
      block: source,
      id: fallbackId,
      sourceName: sourceName,
      pageLabel: 'Manual entry',
    );
  }

  RecipeImportDraft? _parseBlock({
    required String block,
    required String id,
    required String sourceName,
    required String pageLabel,
  }) {
    final lines = block
        .split(RegExp(r'[\r\n]+'))
        .map(_cleanLine)
        .where((line) => line.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return null;
    }

    var name = '';
    var category = '';
    var glassware = '';
    var garnish = '';
    var method = '';
    final noteLines = <String>[];
    final ingredients = <RecipeIngredient>[];
    final reviewFlags = <String>[];

    name = _detectName(lines) ?? '';
    if (name.isEmpty) {
      reviewFlags.add('Cocktail name needs review.');
      name = 'Needs review';
    }

    for (final line in lines) {
      final lower = line.toLowerCase();
      if (lower == name.toLowerCase()) {
        continue;
      }
      if (lower.startsWith('cocktail:') || lower.startsWith('name:')) {
        name = _valueAfterColon(line);
        continue;
      }
      if (lower.startsWith('category:')) {
        category = _valueAfterColon(line);
        continue;
      }
      if (lower.startsWith('glassware:') || lower.startsWith('glass:')) {
        glassware = _valueAfterColon(line);
        continue;
      }
      if (lower.startsWith('garnish:')) {
        garnish = _valueAfterColon(line);
        continue;
      }
      if (lower.startsWith('method:') || lower.startsWith('build:')) {
        method = _valueAfterColon(line);
        continue;
      }
      if (lower.startsWith('notes:')) {
        noteLines.add(_valueAfterColon(line));
        continue;
      }

      final ingredient = _parseIngredientLine(line);
      if (ingredient != null) {
        ingredients.add(ingredient);
        if (ingredient.measureMl == null) {
          reviewFlags.add('An ingredient measure needs review for "$line".');
        }
        continue;
      }

      if (_looksLikeInstruction(line)) {
        method = method.isEmpty ? line : '$method $line'.trim();
      } else {
        noteLines.add(line);
      }
    }

    if (ingredients.isEmpty) {
      reviewFlags.add('No ingredient measures were confidently detected.');
    }
    if (glassware.isEmpty) {
      reviewFlags.add('Glassware was missing or unclear.');
    }
    if (garnish.isEmpty) {
      reviewFlags.add('Garnish was missing or unclear.');
    }
    if (method.isEmpty) {
      reviewFlags.add('Method was missing or unclear.');
    }

    return RecipeImportDraft(
      id: id,
      sourceLabel: sourceName,
      pageLabel: pageLabel,
      name: name,
      category: category,
      glassware: glassware,
      garnish: garnish,
      method: method,
      notes: noteLines.join('\n').trim(),
      ingredients: ingredients,
      reviewFlags: reviewFlags.toSet().toList(),
      status: RecipeDraftStatus.pending,
      wasManuallyReviewed: false,
    );
  }

  RecipeImportDraft? _parseOcrPage({
    required String pageText,
    required String id,
    required String sourceName,
    required String pageLabel,
    required _TocEntry? tocEntry,
  }) {
    if (tocEntry == null) {
      return null;
    }
    if (!pageText.toLowerCase().contains('ingredients & volumes')) {
      return null;
    }

    final lines = pageText
        .split(RegExp(r'[\r\n]+'))
        .map(_cleanLine)
        .where((line) => line.isNotEmpty && !line.startsWith('===== PAGE'))
        .toList();
    if (lines.isEmpty) {
      return null;
    }

    final ingredientsHeaderIndex = lines.indexWhere(
      (line) => line.toLowerCase().contains('ingredients & volumes'),
    );
    if (ingredientsHeaderIndex == -1) {
      return null;
    }

    final methodHeaderIndex = lines.indexWhere(
      (line) => line.toLowerCase().contains('method & spec notes'),
    );
    final garnishHeaderIndex = lines.indexWhere(
      (line) => line.toLowerCase() == 'garnish',
    );

    final title = _cleanExpectedTitle(tocEntry.title);
    if (_isExcludedRecipeTitle(title)) {
      return null;
    }
    final reviewFlags = <String>[];
    if (title.isEmpty) {
      reviewFlags.add('Cocktail name needs review.');
    }

    final ingredientLines = lines
        .skip(ingredientsHeaderIndex + 1)
        .take(
          (methodHeaderIndex != -1 ? methodHeaderIndex : (garnishHeaderIndex != -1 ? garnishHeaderIndex : lines.length)) -
              (ingredientsHeaderIndex + 1),
        )
        .toList();
    final methodLines = methodHeaderIndex == -1
        ? <String>[]
        : lines
            .skip(methodHeaderIndex + 1)
            .take(
              (garnishHeaderIndex != -1 ? garnishHeaderIndex : lines.length) -
                  (methodHeaderIndex + 1),
            )
            .where((line) => !_looksLikeNoise(line))
            .toList();
    final ingredients = _extractOcrIngredients(
      ingredientLines: ingredientLines,
      methodLines: methodLines,
    );
    if (ingredients.isEmpty) {
      reviewFlags.add('No ingredient measures were confidently detected.');
    }
    final garnishLines = garnishHeaderIndex == -1
        ? <String>[]
        : lines
            .skip(garnishHeaderIndex + 1)
            .where((line) => !_looksLikeNoise(line))
            .take(4)
            .toList();

    final method = methodLines.join(' ').trim();
    final garnish = garnishLines.join(', ').trim().isNotEmpty
        ? garnishLines.join(', ').trim()
        : _extractGarnishFromMethod(methodLines);
    if (method.isEmpty) {
      reviewFlags.add('Method was missing or unclear.');
    }
    if (garnish.isEmpty) {
      reviewFlags.add('Garnish was missing or unclear.');
    }

    final glassware = _detectGlassware(lines);
    if (glassware.isEmpty) {
      reviewFlags.add('Glassware was missing or unclear.');
    }

    return RecipeImportDraft(
      id: id,
      sourceLabel: sourceName,
      pageLabel: pageLabel,
      name: title.isEmpty ? 'Needs review' : title,
      category: tocEntry.section,
      glassware: glassware,
      garnish: garnish,
      method: method,
      notes: '',
      ingredients: ingredients,
      reviewFlags: reviewFlags,
      status: RecipeDraftStatus.pending,
      wasManuallyReviewed: false,
    );
  }

  RecipeIngredient? _parseIngredientLine(String line) {
    final normalized = line.replaceAll('*', '').trim();
    final methodMatch = RegExp(
      r"^(?:ADD|USE|TOP|PRE-POUR|SERVE)\s+(?<measure>\d+(?:\.\d+)?)\s*ML\s+(?<name>[A-Z0-9& '\-]+)$",
      caseSensitive: false,
    ).firstMatch(normalized);
    if (methodMatch != null) {
      return RecipeIngredient(
        ingredientName: _sanitizeIngredientName(methodMatch.namedGroup('name')!),
        measureMl: double.tryParse(methodMatch.namedGroup('measure')!),
      );
    }

    final withMeasure = RegExp(
      r'^(?<name>.+?)\s*[:\-]?\s*(?<measure>\d+(?:\.\d+)?)\s*ml(?:\s*[,/-]\s*(?<prep>.+))?$',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (withMeasure != null) {
      return RecipeIngredient(
        ingredientName: _sanitizeIngredientName(withMeasure.namedGroup('name')!),
        measureMl: double.tryParse(withMeasure.namedGroup('measure')!),
        preparationNote: withMeasure.namedGroup('prep')?.trim(),
      );
    }

    final reversed = RegExp(
      r'^(?<measure>\d+(?:\.\d+)?)\s*ml\s+(?<name>.+?)(?:\s*[,/-]\s*(?<prep>.+))?$',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (reversed != null) {
      return RecipeIngredient(
        ingredientName: _sanitizeIngredientName(reversed.namedGroup('name')!),
        measureMl: double.tryParse(reversed.namedGroup('measure')!),
        preparationNote: reversed.namedGroup('prep')?.trim(),
      );
    }

    if (_looksLikeLikelyIngredient(normalized)) {
      return RecipeIngredient(
        ingredientName: normalized,
        measureMl: null,
      );
    }
    return null;
  }

  String? _detectName(List<String> lines) {
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (lower.startsWith('cocktail:') || lower.startsWith('name:')) {
        return _valueAfterColon(line);
      }
      if (_looksLikeTitle(line)) {
        return line;
      }
    }
    return null;
  }

  String _valueAfterColon(String line) {
    return line.split(':').skip(1).join(':').trim();
  }

  bool _looksLikeTitle(String line) {
    final lower = line.toLowerCase();
    if (lower.contains('ml') ||
        lower.startsWith('ingredient') ||
        lower.startsWith('garnish') ||
        lower.startsWith('glass') ||
        lower.startsWith('method') ||
        lower.startsWith('build') ||
        lower.startsWith('notes')) {
      return false;
    }
    return line.length <= 60 && !RegExp(r'\d').hasMatch(line);
  }

  bool _looksLikeLikelyIngredient(String line) {
    final lower = line.toLowerCase();
    return !lower.startsWith('garnish') &&
        !lower.startsWith('glass') &&
        !lower.startsWith('method') &&
        !lower.startsWith('build') &&
        !lower.startsWith('notes') &&
        line.length <= 50;
  }

  List<RecipeIngredient> _extractOcrIngredients({
    required List<String> ingredientLines,
    required List<String> methodLines,
  }) {
    final parsed = <RecipeIngredient>[];
    for (final line in [...methodLines, ...ingredientLines]) {
      final normalized = line
          .toUpperCase()
          .replaceAll('OML', '0ML')
          .replaceAll('S5ML', '55ML')
          .replaceAll('SO0A', 'SODA');

      for (final match in RegExp(r"(\d{1,3})\s*ML\s+([A-Z][A-Z0-9 &'\-]+)").allMatches(normalized)) {
        final measure = double.tryParse(match.group(1)!);
        final name = _sanitizeIngredientName(match.group(2)!);
        if (measure == null || name.isEmpty) {
          continue;
        }
        final existingIndex = parsed.indexWhere(
          (item) => item.ingredientName.toLowerCase() == name.toLowerCase(),
        );
        final ingredient = RecipeIngredient(
          ingredientName: _titleCase(name.toLowerCase()),
          measureMl: measure,
        );
        if (existingIndex == -1) {
          parsed.add(ingredient);
        } else {
          parsed[existingIndex] = ingredient;
        }
      }

      for (final match in RegExp(r"([A-Z][A-Z0-9 &'\-]+)\s+(\d{1,3})\s*ML").allMatches(normalized)) {
        final measure = double.tryParse(match.group(2)!);
        final name = _sanitizeIngredientName(match.group(1)!);
        if (measure == null || name.isEmpty) {
          continue;
        }
        final existingIndex = parsed.indexWhere(
          (item) => item.ingredientName.toLowerCase() == name.toLowerCase(),
        );
        final ingredient = RecipeIngredient(
          ingredientName: _titleCase(name.toLowerCase()),
          measureMl: measure,
        );
        if (existingIndex == -1) {
          parsed.add(ingredient);
        } else {
          parsed[existingIndex] = ingredient;
        }
      }
    }
    return parsed;
  }

  String _extractGarnishFromMethod(List<String> methodLines) {
    for (final line in methodLines) {
      final match = RegExp(r'GARNISH WITH (.+)', caseSensitive: false).firstMatch(line);
      if (match != null) {
        return match.group(1)!.trim();
      }
    }
    return '';
  }

  bool _looksLikeInstruction(String line) {
    final lower = line.toLowerCase();
    return lower.startsWith('shake') ||
        lower.startsWith('stir') ||
        lower.startsWith('build') ||
        lower.startsWith('roll') ||
        lower.startsWith('fine strain') ||
        lower.startsWith('double strain') ||
        lower.startsWith('top') ||
        lower.startsWith('serve');
  }

  String _detectGlassware(List<String> lines) {
    const options = [
      'spritz glass',
      'wine glass',
      'coupe glass',
      'coupe',
      'highball',
      'rocks glass',
      'martini glass',
      'shot glass',
      'plant pot',
      'goblet',
      'balloon glass',
      'tankard',
    ];
    for (final line in lines) {
      final lower = line.toLowerCase();
      for (final option in options) {
        if (lower.contains(option)) {
          return _titleCase(option);
        }
      }
    }
    return '';
  }

  bool _looksLikeNoise(String line) {
    final lower = line.toLowerCase();
    return lower == 'add:' ||
        lower == 'garnish' ||
        lower.contains('when ordered spray') ||
        lower.contains('atomizer at the table') ||
        lower == 'description';
  }

  String _titleCase(String value) {
    return value
        .split(' ')
        .map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _sanitizeIngredientName(String value) {
    return value
        .replaceAll(RegExp(r'^[^A-Za-z]+'), '')
        .replaceAll(RegExp(r'[_@()\\[\\]{}]'), '')
        .replaceAll(RegExp(r'^(AND|WITH|OF)\s+'), '')
        .replaceAll(RegExp(r'\s+(AND|WITH|OF)$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _cleanLine(String line) {
    return line.replaceAll('\u2022', '').replaceAll('\t', ' ').trim();
  }

  List<_RecipeBlock> _extractOcrPages(String raw) {
    final matches = RegExp(r'===== PAGE (\d+) =====').allMatches(raw).toList();
    final blocks = <_RecipeBlock>[];
    for (var index = 0; index < matches.length; index += 1) {
      final start = matches[index].end;
      final end = index + 1 < matches.length ? matches[index + 1].start : raw.length;
      final pageNumber = matches[index].group(1) ?? '${index + 1}';
      blocks.add(
        _RecipeBlock(
          text: raw.substring(start, end).trim(),
          label: 'Page $pageNumber',
          pageNumber: int.tryParse(pageNumber),
        ),
      );
    }
    return blocks;
  }

  Map<int, _TocEntry> _extractContentsMap(List<_RecipeBlock> blocks) {
    final pageTwo = blocks.where((block) => block.pageNumber == 2).firstOrNull;
    if (pageTwo == null) {
      return {};
    }

    final map = <int, _TocEntry>{};
    final lines = pageTwo.text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => _cleanLine(line).toUpperCase())
        .where((line) => line.isNotEmpty)
        .toList();
    var currentSection = '';

    for (final line in lines) {
      final section = _extractSectionName(line);
      if (section.isNotEmpty) {
        currentSection = section;
      }

      final matches = RegExp(r"([A-Z&'\-\s0-9]+?)\s*-\s*(\d{1,2})").allMatches(line);
      for (final match in matches) {
        final rawName = match.group(1)?.trim() ?? '';
        final internalPage = int.tryParse(match.group(2) ?? '');
        if (internalPage == null || internalPage > 37) {
          continue;
        }
        final cleanedName = rawName
            .replaceAll(RegExp(r'\s+'), ' ')
            .replaceAll('765', '75')
            .trim();
        if (cleanedName.isEmpty || _isExcludedRecipeTitle(cleanedName)) {
          continue;
        }
        map[internalPage + 2] = _TocEntry(
          title: cleanedName,
          section: currentSection,
        );
      }
    }
    return map;
  }

  String _extractSectionName(String line) {
    if (line.contains('SPRITZ OFF MAIN MENU')) {
      return 'Spritz Off Main Menu';
    }
    if (line.contains('SIGNATURE COCKTAILS')) {
      return 'Signature Cocktails';
    }
    if (line.contains('CLASSIC COCKTAILS')) {
      return 'Classic Cocktails';
    }
    if (line.contains('NON-ALC COCKTAILS')) {
      return 'Non-Alc Cocktails';
    }
    if (line.contains('BATCHES') || line.contains('GUIDES & EXTRAS')) {
      return 'Guides & Extras';
    }
    if (line.contains('HOMEMADE INGREDIENTS')) {
      return 'Homemade Ingredients';
    }
    return '';
  }

  bool _isExcludedRecipeTitle(String value) {
    final normalized = value.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return true;
    }
    const blockedExact = {
      'HOMEMADE LEMONADE',
      'BATCHES',
      'CLASSIC COCKTAILS',
      'COLOUR CODES',
      'BATCH PREPPING',
      'JERRY CAN CLEANING',
      'BAR STATION SET UP',
      'BAR STATION: INSIDE & SPEED RAIL',
      'SLICE & DICE GUIDE',
      'NON ALC VS ALC COCKTAILS',
      'GLASS RIMS',
    };
    if (blockedExact.contains(normalized)) {
      return true;
    }
    return normalized.startsWith('BATCH ') ||
        normalized.startsWith('GUIDE ') ||
        normalized.startsWith('HOMEMADE ');
  }

  String _cleanExpectedTitle(String value) {
    return value
        .replaceFirst('SPRITZ OFF MAIN MENU ', '')
        .replaceFirst('SIGNATURE COCKTAILS NON-ALC COCKTAILS ', '')
        .replaceFirst('GUIDES & EXTRAS ', '')
        .replaceFirst('CLASSIC COCKTAILS ', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class _RecipeBlock {
  const _RecipeBlock({
    required this.text,
    required this.label,
    required this.pageNumber,
  });

  final String text;
  final String label;
  final int? pageNumber;
}

class _TocEntry {
  const _TocEntry({
    required this.title,
    required this.section,
  });

  final String title;
  final String section;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
