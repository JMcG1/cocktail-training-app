import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cocktail_training/models/user_role.dart';

class InviteToken {
  const InviteToken({
    required this.token,
    required this.venueId,
    required this.role,
    required this.active,
    required this.maxUses,
    required this.usedCount,
    required this.createdBy,
    required this.createdAtMillis,
    this.expiresAtMillis,
  });

  factory InviteToken.fromJson(Map<String, dynamic> json) {
    return InviteToken(
      token: _stringValue(json['token']),
      venueId: _stringValue(json['venueId']),
      role: UserRoleX.fromKey(_stringValue(json['role'])),
      active: _boolValue(json['active'], fallback: true),
      maxUses: _intValue(json['maxUses'], fallback: 1),
      usedCount: _intValue(json['usedCount']),
      createdBy: _stringValue(json['createdBy']),
      createdAtMillis: _millisFromValue(json['createdAtMillis']),
      expiresAtMillis: _nullableMillisFromValue(json['expiresAtMillis']),
    );
  }

  factory InviteToken.fromFirestore(String token, Map<String, dynamic> json) {
    return InviteToken(
      token: token,
      venueId: _stringValue(json['venueId']),
      role: UserRoleX.fromKey(_stringValue(json['role'])),
      active: _boolValue(json['active'], fallback: true),
      maxUses: _intValue(json['maxUses'], fallback: 1),
      usedCount: _intValue(json['usedCount']),
      createdBy: _stringValue(json['createdBy']),
      createdAtMillis: _millisFromValue(json['createdAt']),
      expiresAtMillis: _nullableMillisFromValue(json['expiresAt']),
    );
  }

  final String token;
  final String venueId;
  final UserRole role;
  final bool active;
  final int maxUses;
  final int usedCount;
  final String createdBy;
  final int createdAtMillis;
  final int? expiresAtMillis;

  bool get isExpired {
    if (expiresAtMillis == null) return false;
    return DateTime.now().millisecondsSinceEpoch > expiresAtMillis!;
  }

  bool get isUsedUp => usedCount >= maxUses;
  int get remainingUses => (maxUses - usedCount).clamp(0, maxUses);
  bool get isUsable => active && !isExpired && !isUsedUp;

  InviteToken copyWith({
    bool? active,
    int? maxUses,
    int? usedCount,
    int? createdAtMillis,
    int? expiresAtMillis,
  }) {
    return InviteToken(
      token: token,
      venueId: venueId,
      role: role,
      active: active ?? this.active,
      maxUses: maxUses ?? this.maxUses,
      usedCount: usedCount ?? this.usedCount,
      createdBy: createdBy,
      createdAtMillis: createdAtMillis ?? this.createdAtMillis,
      expiresAtMillis: expiresAtMillis ?? this.expiresAtMillis,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'venueId': venueId,
      'role': role.key,
      'active': active,
      'maxUses': maxUses,
      'usedCount': usedCount,
      'createdBy': createdBy,
      'createdAtMillis': createdAtMillis,
      'expiresAtMillis': expiresAtMillis,
    };
  }

  Map<String, dynamic> toFirestore() {
    return {
      'active': active,
      'createdAt': Timestamp.fromMillisecondsSinceEpoch(createdAtMillis),
      'createdBy': createdBy,
      'expiresAt': expiresAtMillis == null
          ? null
          : Timestamp.fromMillisecondsSinceEpoch(expiresAtMillis!),
      'maxUses': maxUses,
      'role': role.key,
      'usedCount': usedCount,
      'venueId': venueId,
    };
  }

  static String _stringValue(Object? value) {
    if (value == null) return '';
    return value.toString();
  }

  static bool _boolValue(Object? value, {bool fallback = false}) {
    if (value is bool) return value;
    return fallback;
  }

  static int _intValue(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static int _millisFromValue(Object? value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static int? _nullableMillisFromValue(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
