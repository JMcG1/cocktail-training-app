class AppVenue {
  const AppVenue({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.createdAtMillis,
  });

  factory AppVenue.fromJson(Map<String, dynamic> json) {
    return AppVenue(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      createdBy: json['createdBy'] as String? ?? '',
      createdAtMillis: json['createdAtMillis'] as int? ?? 0,
    );
  }

  final String id;
  final String name;
  final String createdBy;
  final int createdAtMillis;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdBy': createdBy,
      'createdAtMillis': createdAtMillis,
    };
  }
}
