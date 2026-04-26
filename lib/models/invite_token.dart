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
      token: json['token'] as String? ?? '',
      venueId: json['venueId'] as String? ?? '',
      role: UserRoleX.fromKey(json['role'] as String?),
      active: json['active'] as bool? ?? true,
      maxUses: json['maxUses'] as int? ?? 1,
      usedCount: json['usedCount'] as int? ?? 0,
      createdBy: json['createdBy'] as String? ?? '',
      createdAtMillis: json['createdAtMillis'] as int? ?? 0,
      expiresAtMillis: json['expiresAtMillis'] as int?,
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
    if (expiresAtMillis == null) {
      return false;
    }
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
}
