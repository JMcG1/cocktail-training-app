import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../domain/models/models.dart';
import 'recipe_text_parser.dart';

class PdfRecipeExtractor {
  PdfRecipeExtractor(this._parser);

  final RecipeTextParser _parser;

  RecipeImportResult extract({
    required Uint8List bytes,
    required String fileName,
  }) {
    final document = PdfDocument(inputBytes: bytes);
    try {
      final extractor = PdfTextExtractor(document);
      final pageTexts = <String>[];
      for (var index = 0; index < document.pages.count; index += 1) {
        final text = extractor
            .extractText(
              startPageIndex: index,
              endPageIndex: index,
              layoutText: true,
            )
            .trim();
        pageTexts.add(text);
      }

      final combined = pageTexts.where((text) => text.isNotEmpty).join('\n\n');
      if (combined.trim().isEmpty) {
        return RecipeImportResult(
          sourceName: fileName,
          drafts: const [],
          warnings: const [
            'No selectable text was found in the PDF. This file appears to be image-based or scanned, so OCR is required before recipe text can be extracted reliably.',
          ],
          requiresOcr: true,
          rawText: '',
          pageCount: document.pages.count,
        );
      }

      final result = _parser.parseImportText(
        source: combined,
        sourceName: fileName,
      );
      return RecipeImportResult(
        sourceName: fileName,
        drafts: result.drafts,
        warnings: result.warnings,
        requiresOcr: false,
        rawText: combined,
        pageCount: document.pages.count,
      );
    } finally {
      document.dispose();
    }
  }
}
