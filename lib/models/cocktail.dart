import 'package:cocktail_training/models/ingredient.dart';

class Cocktail {
  const Cocktail({
    required this.id,
    required this.name,
    required this.category,
    required this.buildStyle,
    required this.glassware,
    required this.garnish,
    required this.description,
    required this.source,
    required this.sourcePage,
    this.imageAssetPath,
    required this.tags,
    required this.ingredients,
    required this.methodSteps,
    required this.notes,
  });

  factory Cocktail.fromJson(Map<String, dynamic> json) {
    return Cocktail(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      buildStyle: json['buildStyle'] as String,
      glassware: json['glassware'] as String,
      garnish: json['garnish'] as String,
      description: json['description'] as String,
      source: json['source'] as String,
      sourcePage: (json['sourcePage'] as num).toInt(),
      imageAssetPath: json['imageAssetPath'] as String?,
      tags: List<String>.from(json['tags'] as List<dynamic>),
      ingredients: (json['ingredients'] as List<dynamic>)
          .map((item) => Ingredient.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      methodSteps: List<String>.from(json['methodSteps'] as List<dynamic>),
      notes: List<String>.from(json['notes'] as List<dynamic>),
    );
  }

  final String id;
  final String name;
  final String category;
  final String buildStyle;
  final String glassware;
  final String garnish;
  final String description;
  final String source;
  final int sourcePage;
  final String? imageAssetPath;
  final List<String> tags;
  final List<Ingredient> ingredients;
  final List<String> methodSteps;
  final List<String> notes;

  String get buildStyleLabel => buildStyle.replaceAll('-', ' ');

  bool get isAlcoholFree {
    return category.toLowerCase().contains('alcohol-free') ||
        name.contains('0%');
  }

  String get sourceLabel => 'Page $sourcePage';

  bool get hasImage => imageAssetPath != null && imageAssetPath!.isNotEmpty;

  String get imageHeroTag => 'cocktail-image-$id';

  bool matchesQuery(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }

    final haystack = <String>[
      name,
      category,
      buildStyleLabel,
      glassware,
      garnish,
      description,
      source,
      ...tags,
      ...notes,
      ...ingredients.map((ingredient) => ingredient.name),
      ...ingredients.map((ingredient) => ingredient.measure),
    ].join(' ').toLowerCase();

    return haystack.contains(normalized);
  }
}
