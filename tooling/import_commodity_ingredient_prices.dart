import 'dart:convert';
import 'dart:io';

import 'package:stock_variance_coach/core/utils/commodity_csv_ingredient_importer.dart';
import 'package:stock_variance_coach/domain/models/models.dart';

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  final csvFile = File(options.csvPath);
  if (!await csvFile.exists()) {
    stderr.writeln('CSV file not found: ${options.csvPath}');
    exitCode = 2;
    return;
  }

  final accessToken = await _loadFirebaseCliAccessToken();
  final client = HttpClient();
  try {
    final baseUri = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/${options.projectId}/databases/(default)/documents',
    );
    final ingredientDocs = await _fetchVenueIngredientDocs(
      client: client,
      accessToken: accessToken,
      baseUri: baseUri,
      venueId: options.venueId,
    );

    if (ingredientDocs.isEmpty) {
      stdout.writeln(
        'No ingredient documents found for venue ${options.venueId}. Nothing to import.',
      );
      return;
    }

    final csvText = await csvFile.readAsString();
    final importer = CommodityCsvIngredientImporter();
    final syntheticRecipe = CocktailRecipe(
      id: 'commodity-import',
      name: 'Commodity Import',
      category: 'System',
      glassware: '',
      garnish: '',
      method: '',
      notes: '',
      ingredients: [
        for (final doc in ingredientDocs)
          RecipeIngredient(ingredientName: doc.ingredient.name),
      ],
      sourceLabel: 'commodity-csv',
      needsReview: false,
      reviewFlags: const [],
      isApproved: true,
      wasManuallyReviewed: true,
    );

    final result = importer.buildImportPlan(
      csvText: csvText,
      ingredients: [for (final doc in ingredientDocs) doc.ingredient],
      recipes: [syntheticRecipe],
      batches: const [],
    );

    stdout.writeln(
      'Matched ${result.matchedIngredients.length} ingredients; '
      '${result.unmatchedIngredientNames.length} still need manual entry.',
    );

    if (result.matchedIngredients.isNotEmpty) {
      for (final match in result.matchedIngredients) {
        stdout.writeln(
          'MATCH ${match.ingredient.name} -> ${_formatMl(match.bottleSizeMl)} @ ${match.bottlePrice.toStringAsFixed(2)} from ${match.sourceProductName}',
        );
      }
    }

    if (result.unmatchedIngredientNames.isNotEmpty) {
      stdout.writeln('');
      stdout.writeln('Unmatched ingredients:');
      for (final name in result.unmatchedIngredientNames) {
        stdout.writeln('- $name');
      }
    }

    if (options.dryRun) {
      stdout.writeln('');
      stdout.writeln('Dry run only. No Firestore changes were written.');
      return;
    }

    final docsByName = {
      for (final doc in ingredientDocs) _normalize(doc.ingredient.name): doc,
    };
    var updatedCount = 0;
    for (final match in result.matchedIngredients) {
      final doc = docsByName[_normalize(match.ingredient.name)];
      if (doc == null) {
        continue;
      }
      await _patchIngredientPrice(
        client: client,
        accessToken: accessToken,
        documentName: doc.documentName,
        ingredient: match.ingredient,
      );
      updatedCount += 1;
    }

    stdout.writeln('');
    stdout.writeln(
      'Updated $updatedCount ingredient documents in venues/${options.venueId}/ingredients.',
    );
  } finally {
    client.close(force: true);
  }
}

class _Options {
  const _Options({
    required this.projectId,
    required this.venueId,
    required this.csvPath,
    required this.dryRun,
  });

  final String projectId;
  final String venueId;
  final String csvPath;
  final bool dryRun;
}

class _VenueIngredientDocument {
  const _VenueIngredientDocument({
    required this.documentName,
    required this.ingredient,
  });

  final String documentName;
  final Ingredient ingredient;
}

_Options _parseArgs(List<String> args) {
  var projectId = 'cocktail-training-27e96';
  var venueId = 'venue_1';
  var csvPath = r'C:\Users\jaime\Downloads\CommodityReport_20260430_20260531.csv';
  var dryRun = false;

  for (final arg in args) {
    if (arg == '--dry-run') {
      dryRun = true;
      continue;
    }
    if (arg.startsWith('--project=')) {
      projectId = arg.substring('--project='.length).trim();
      continue;
    }
    if (arg.startsWith('--venue=')) {
      venueId = arg.substring('--venue='.length).trim();
      continue;
    }
    if (arg.startsWith('--csv=')) {
      csvPath = arg.substring('--csv='.length).trim();
    }
  }

  return _Options(
    projectId: projectId,
    venueId: venueId,
    csvPath: csvPath,
    dryRun: dryRun,
  );
}

Future<String> _loadFirebaseCliAccessToken() async {
  final homeDir =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '';
  if (homeDir.isEmpty) {
    throw Exception('Could not resolve the current user home directory.');
  }
  final configFile = File(
    '$homeDir\\.config\\configstore\\firebase-tools.json',
  );
  if (!await configFile.exists()) {
    throw Exception(
      'Could not find firebase-tools login data. Run `firebase login` first.',
    );
  }
  final config =
      jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
  final tokens = config['tokens'];
  if (tokens is! Map<String, dynamic>) {
    throw Exception('firebase-tools config does not contain auth tokens.');
  }
  final accessToken = tokens['access_token'];
  if (accessToken is! String || accessToken.isEmpty) {
    throw Exception(
      'firebase-tools config does not contain a usable access token.',
    );
  }
  return accessToken;
}

Future<List<_VenueIngredientDocument>> _fetchVenueIngredientDocs({
  required HttpClient client,
  required String accessToken,
  required Uri baseUri,
  required String venueId,
}) async {
  final uri = baseUri.replace(path: '${baseUri.path}/venues/$venueId/ingredients');
  final response = await _sendJsonRequest(
    client: client,
    accessToken: accessToken,
    uri: uri,
  );
  final documents = (response['documents'] as List<dynamic>? ?? const [])
      .cast<Map<String, dynamic>>();
  return [
    for (final doc in documents)
      _VenueIngredientDocument(
        documentName: doc['name'] as String,
        ingredient: Ingredient(
          id: doc['name'].toString().split('/').last,
          name: _stringField(doc, 'name'),
          bottleSizeMl: _doubleField(doc, 'bottleSizeMl'),
          bottleCost: _doubleField(doc, 'bottleCost'),
        ),
      ),
  ];
}

Future<void> _patchIngredientPrice({
  required HttpClient client,
  required String accessToken,
  required String documentName,
  required Ingredient ingredient,
}) async {
  final updateUri = Uri.parse(
    'https://firestore.googleapis.com/v1/$documentName'
    '?updateMask.fieldPaths=bottleSizeMl'
    '&updateMask.fieldPaths=bottleCost'
    '&updateMask.fieldPaths=costPerMl'
    '&updateMask.fieldPaths=updatedAt',
  );
  final payload = {
    'fields': {
      'bottleSizeMl': {'doubleValue': ingredient.bottleSizeMl},
      'bottleCost': {'doubleValue': ingredient.bottleCost},
      'costPerMl': {'doubleValue': ingredient.costPerMl},
      'updatedAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
    },
  };
  await _sendJsonRequest(
    client: client,
    accessToken: accessToken,
    uri: updateUri,
    method: 'PATCH',
    body: payload,
  );
}

Future<Map<String, dynamic>> _sendJsonRequest({
  required HttpClient client,
  required String accessToken,
  required Uri uri,
  String method = 'GET',
  Map<String, dynamic>? body,
}) async {
  final request = await client.openUrl(method, uri);
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
  request.headers.set(HttpHeaders.acceptHeader, 'application/json');
  if (body != null) {
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
  }
  final response = await request.close();
  final text = await utf8.decodeStream(response);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(
      'Firestore request failed (${response.statusCode}) $method $uri\n$text',
      uri: uri,
    );
  }
  if (text.trim().isEmpty) {
    return const {};
  }
  return jsonDecode(text) as Map<String, dynamic>;
}

String _stringField(Map<String, dynamic> document, String fieldName) {
  final fields = document['fields'] as Map<String, dynamic>? ?? const {};
  final field = fields[fieldName] as Map<String, dynamic>? ?? const {};
  return field['stringValue'] as String? ?? '';
}

double _doubleField(Map<String, dynamic> document, String fieldName) {
  final fields = document['fields'] as Map<String, dynamic>? ?? const {};
  final field = fields[fieldName] as Map<String, dynamic>? ?? const {};
  final raw =
      field['doubleValue'] ??
      field['integerValue'] ??
      field['stringValue'];
  if (raw is num) {
    return raw.toDouble();
  }
  if (raw is String) {
    return double.tryParse(raw) ?? 0;
  }
  return 0;
}

String _normalize(String value) {
  return value
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll('’', "'")
      .replaceAll(RegExp(r"[^a-z0-9']+"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _formatMl(double value) {
  if (value == value.truncateToDouble()) {
    return '${value.toStringAsFixed(0)}ml';
  }
  return '${value.toStringAsFixed(2)}ml';
}
