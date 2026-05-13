import 'dart:convert';

class WeeklyWorkflowDraft {
  const WeeklyWorkflowDraft({
    required this.selectedWeekId,
    required this.selectedConcerns,
    required this.shortValues,
    required this.impactValues,
    required this.noteValues,
    required this.bartenderName,
    required this.salesValues,
  });

  final String? selectedWeekId;
  final Map<String, bool> selectedConcerns;
  final Map<String, String> shortValues;
  final Map<String, String> impactValues;
  final Map<String, String> noteValues;
  final String bartenderName;
  final Map<String, String> salesValues;

  bool get hasUnsavedProgress {
    return (selectedWeekId?.trim().isNotEmpty ?? false) ||
        selectedConcerns.values.any((value) => value) ||
        shortValues.values.any((value) => value.trim().isNotEmpty) ||
        impactValues.values.any((value) => value.trim().isNotEmpty) ||
        noteValues.values.any((value) => value.trim().isNotEmpty) ||
        bartenderName.trim().isNotEmpty ||
        salesValues.values.any((value) => value.trim().isNotEmpty);
  }

  Map<String, dynamic> toMap() {
    return {
      'selectedWeekId': selectedWeekId,
      'selectedConcerns': selectedConcerns,
      'shortValues': shortValues,
      'impactValues': impactValues,
      'noteValues': noteValues,
      'bartenderName': bartenderName,
      'salesValues': salesValues,
    };
  }

  String toJson() => jsonEncode(toMap());

  static WeeklyWorkflowDraft fromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      return empty();
    }
    return fromMap(decoded);
  }

  static WeeklyWorkflowDraft fromMap(Map<String, dynamic> map) {
    return WeeklyWorkflowDraft(
      selectedWeekId: map['selectedWeekId'] as String?,
      selectedConcerns: _boolMap(map['selectedConcerns']),
      shortValues: _stringMap(map['shortValues']),
      impactValues: _stringMap(map['impactValues']),
      noteValues: _stringMap(map['noteValues']),
      bartenderName: map['bartenderName'] as String? ?? '',
      salesValues: _stringMap(map['salesValues']),
    );
  }

  static WeeklyWorkflowDraft empty() {
    return const WeeklyWorkflowDraft(
      selectedWeekId: null,
      selectedConcerns: {},
      shortValues: {},
      impactValues: {},
      noteValues: {},
      bartenderName: '',
      salesValues: {},
    );
  }

  static Map<String, String> _stringMap(dynamic value) {
    if (value is! Map) {
      return const {};
    }
    return {
      for (final entry in value.entries)
        '${entry.key}': entry.value?.toString() ?? '',
    };
  }

  static Map<String, bool> _boolMap(dynamic value) {
    if (value is! Map) {
      return const {};
    }
    return {
      for (final entry in value.entries)
        '${entry.key}': entry.value == true,
    };
  }
}
