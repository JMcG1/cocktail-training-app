class Ingredient {
  const Ingredient({required this.name, required this.measure, this.note});

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    return Ingredient(
      name: json['name'] as String,
      measure: json['measure'] as String? ?? '',
      note: json['note'] as String?,
    );
  }

  final String name;
  final String measure;
  final String? note;

  String get displayMeasure => measure;
}
