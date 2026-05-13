import 'dart:convert';
import 'dart:io';

import 'package:stock_variance_coach/core/utils/recipe_text_parser.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tooling/parse_ocr_text.dart <ocr-text-file> [output-json-file]',
    );
    exitCode = 64;
    return;
  }

  final inputFile = File(args[0]);
  if (!inputFile.existsSync()) {
    stderr.writeln('Input OCR text file not found: ${inputFile.path}');
    exitCode = 1;
    return;
  }

  final outputFile = args.length > 1
      ? File(args[1])
      : File('${inputFile.path}.drafts.json');

  final parser = RecipeTextParser();
  final text = await inputFile.readAsString();
  final result = parser.parseImportText(
    source: text,
    sourceName: inputFile.uri.pathSegments.isNotEmpty
        ? inputFile.uri.pathSegments.last
        : inputFile.path,
  );

  final payload = {
    'sourceName': result.sourceName,
    'requiresOcr': result.requiresOcr,
    'warnings': result.warnings,
    'draftCount': result.drafts.length,
    'drafts': result.drafts
        .map(
          (draft) => {
            'id': draft.id,
            'pageLabel': draft.pageLabel,
            'name': draft.name,
            'category': draft.category,
            'glassware': draft.glassware,
            'garnish': draft.garnish,
            'method': draft.method,
            'notes': draft.notes,
            'reviewFlags': draft.reviewFlags,
            'ingredients': draft.ingredients
                .map(
                  (ingredient) => {
                    'ingredientName': ingredient.ingredientName,
                    'measureMl': ingredient.measureMl,
                    'preparationNote': ingredient.preparationNote,
                  },
                )
                .toList(),
          },
        )
        .toList(),
  };

  await outputFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(payload),
  );

  stdout.writeln('Recipe draft JSON written to: ${outputFile.path}');
  stdout.writeln('Drafts found: ${result.drafts.length}');
  if (result.warnings.isNotEmpty) {
    stdout.writeln('Warnings:');
    for (final warning in result.warnings) {
      stdout.writeln('- $warning');
    }
  }
}
