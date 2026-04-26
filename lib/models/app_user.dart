import 'package:cocktail_training/models/user_role.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.password = '',
    required this.role,
    required this.venueId,
    required this.active,
    required this.createdAtMillis,
    this.lastSignInAtMillis,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: _stringFromValue(json['id']),
      name: _stringFromValue(json['name']),
      email: _stringFromValue(json['email']),
      password: _stringFromValue(json['password']),
      role: UserRoleX.fromKey(_stringOrNullFromValue(json['role'])),
      venueId: _stringFromValue(json['venueId']),
      active: _boolFromValue(json['active'], fallback: true),
      createdAtMillis: _millisFromValue(json['createdAtMillis']),
      lastSignInAtMillis: _nullableMillisFromValue(json['lastSignInAtMillis']),
    );
  }

  factory AppUser.fromFirestore(String id, Object? source) {
    final data = _firestoreMap(source);
    final createdAtSource = data['createdAt'] ?? data['createdAtMillis'];
    final lastSignInSource =
        data['lastSignInAt'] ?? data['lastSignInAtMillis'];

    return AppUser(
      id: id,
      name: _stringFromValue(data['name']),
      email: _stringFromValue(data['email']),
      password: _stringFromValue(data['password']),
      role: UserRoleX.fromKey(_stringOrNullFromValue(data['role'])),
      venueId: _stringFromValue(data['venueId']),
      active: _boolFromValue(data['active'], fallback: true),
      createdAtMillis: _millisFromValue(createdAtSource),
      lastSignInAtMillis: _nullableMillisFromValue(lastSignInSource),
    );
  }

  final String id;
  final String name;
  final String email;
  final String password;
  final UserRole role;
  final String venueId;
  final bool active;
  final int createdAtMillis;
  final int? lastSignInAtMillis;

  bool get isManager => role == UserRole.manager;

  AppUser copyWith({
    String? name,
    String? email,
    String? password,
    UserRole? role,
    String? venueId,
    bool? active,
    int? createdAtMillis,
    int? lastSignInAtMillis,
  }) {
    return AppUser(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      password: password ?? this.password,
      role: role ?? this.role,
      venueId: venueId ?? this.venueId,
      active: active ?? this.active,
      createdAtMillis: createdAtMillis ?? this.createdAtMillis,
      lastSignInAtMillis: lastSignInAtMillis ?? this.lastSignInAtMillis,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'password': password,
      'role': role.key,
      'venueId': venueId,
      'active': active,
      'createdAtMillis': createdAtMillis,
      'lastSignInAtMillis': lastSignInAtMillis,
    };
  }

  Map<String, dynamic> toFirestore() {
    return {
      'active': active,
      'createdAt': Timestamp.fromMillisecondsSinceEpoch(createdAtMillis),
      'email': email,
      'name': name,
      'role': role.key,
      'venueId': venueId,
      if (lastSignInAtMillis != null)
        'lastSignInAt': Timestamp.fromMillisecondsSinceEpoch(
          lastSignInAtMillis!,
        ),
    };
  }

  static Map<Object?, Object?> _firestoreMap(Object? source) {
    if (source is Map) {
      return source;
    }
    return const {};
  }

  static String _stringFromValue(Object? value) {
    return _stringOrNullFromValue(value) ?? '';
  }

  static String? _stringOrNullFromValue(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value.trim();
    }
    return value.toString().trim();
  }

  static bool _boolFromValue(Object? value, {required bool fallback}) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
    }
    return fallback;
  }

  static int _millisFromValue(Object? value) {
    final parsed = _nullableMillisFromValue(value);
    return parsed ?? 0;
  }

  static int? _numStringToInt(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return int.tryParse(trimmed) ?? double.tryParse(trimmed)?.round();
  }

  static int? _timestampFromMap(Map map) {
    final seconds = map['seconds'];
    final nanoseconds = map['nanoseconds'];

    if (seconds is num) {
      final secondsMillis = seconds.toInt() * 1000;
      final nanosMillis = nanoseconds is num
          ? (nanoseconds.toDouble() / 1000000).round()
          : 0;
      return secondsMillis + nanosMillis;
    }

    return null;
  }

  static int? _nullableMillisFromValue(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is Timestamp) {
      return value.millisecondsSinceEpoch;
    }
    if (value is DateTime) {
      return value.millisecondsSinceEpoch;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return _numStringToInt(value);
    }
    if (value is Map) {
      return _timestampFromMap(value);
    }
    return null;
  }
}
