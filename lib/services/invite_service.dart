import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cocktail_training/models/app_user.dart';
import 'package:cocktail_training/models/invite_token.dart';
import 'package:cocktail_training/models/user_role.dart';
import 'package:cocktail_training/services/backend_runtime_service.dart';
import 'package:cocktail_training/services/local_app_store.dart';
import 'package:flutter/foundation.dart';

class InviteService {
  InviteService._();

  static final InviteService instance = InviteService._();

  static const _defaultAppBaseUrl = 'https://cocktail-training-app.pages.dev';
  static const _configuredAppBaseUrl = String.fromEnvironment(
    'APP_BASE_URL',
    defaultValue: _defaultAppBaseUrl,
  );
  static const _inviteRoute = '/join';
  static const _invitesCollection = 'invites';

  final LocalAppStore _store = LocalAppStore.instance;

  bool get _useFirebaseAuth => BackendRuntimeService.instance.useFirebaseAuth;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  // ============================
  // VALIDATE INVITE
  // ============================

  Future<InviteValidationResult> validateToken(String? token) async {
    final normalized = token?.trim().toUpperCase() ?? '';

    debugPrint('[InviteService] validateToken raw=$token normalized=$normalized');
    debugPrint('[InviteService] useFirebaseAuth=$_useFirebaseAuth');

    if (normalized.isEmpty) {
      return const InviteValidationResult(
        error: 'This invite link is missing its invite code.',
      );
    }

    if (_useFirebaseAuth) {
      try {
        final snapshot = await _firestore
            .collection(_invitesCollection)
            .doc(normalized)
            .get();

        if (!snapshot.exists) {
          return const InviteValidationResult(
            error: 'This invite link does not exist.',
          );
        }

        final data = snapshot.data()!; // ✅ NO Map.from

        final invite = InviteToken.fromFirestore(snapshot.id, data);

        if (!invite.active) {
          return const InviteValidationResult(
            error: 'This invite has been deactivated.',
          );
        }

        if (invite.isExpired) {
          return const InviteValidationResult(
            error: 'This invite has expired.',
          );
        }

        if (invite.isUsedUp) {
          return const InviteValidationResult(
            error: 'This invite has already been used too many times.',
          );
        }

        return InviteValidationResult(invite: invite);
      } catch (error, stackTrace) {
        debugPrint('[InviteService] validateToken error: $error');
        debugPrint('$stackTrace');

        return const InviteValidationResult(
          error: 'We couldn’t check that invite right now.',
        );
      }
    }

    // LOCAL MODE
    final invites = await _store.loadInvites();

    final invite = invites
        .where((item) => item.token.trim().toUpperCase() == normalized)
        .firstOrNull;

    if (invite == null) {
      return const InviteValidationResult(
        error: 'This invite link does not exist.',
      );
    }

    if (!invite.active) {
      return const InviteValidationResult(
        error: 'This invite has been deactivated.',
      );
    }

    if (invite.isExpired) {
      return const InviteValidationResult(
        error: 'This invite has expired.',
      );
    }

    if (invite.isUsedUp) {
      return const InviteValidationResult(
        error: 'This invite has already been used too many times.',
      );
    }

    return InviteValidationResult(invite: invite);
  }

  // ============================
  // CREATE INVITES
  // ============================

  Future<List<InviteToken>> createInvites({
    required AppUser manager,
    required UserRole role,
    required int count,
    required int maxUses,
    required int expiryDays,
  }) async {
    final now = DateTime.now();
    final created = <InviteToken>[];

    if (_useFirebaseAuth) {
      for (var i = 0; i < count; i++) {
        final token = await _generateFirebaseUniqueToken();

        final invite = InviteToken(
          token: token,
          venueId: manager.venueId,
          role: role,
          active: true,
          maxUses: maxUses,
          usedCount: 0,
          createdBy: manager.id,
          createdAtMillis: now.millisecondsSinceEpoch,
          expiresAtMillis:
          now.add(Duration(days: expiryDays)).millisecondsSinceEpoch,
        );

        await _firestore
            .collection(_invitesCollection)
            .doc(token)
            .set(invite.toFirestore());

        created.add(invite);
      }

      return created;
    }

    final existing = await _store.loadInvites();

    for (var i = 0; i < count; i++) {
      final token = _generateLocalUniqueToken(
        existing.followedBy(created).map((e) => e.token).toSet(),
      );

      created.add(
        InviteToken(
          token: token,
          venueId: manager.venueId,
          role: role,
          active: true,
          maxUses: maxUses,
          usedCount: 0,
          createdBy: manager.id,
          createdAtMillis: now.millisecondsSinceEpoch,
          expiresAtMillis:
          now.add(Duration(days: expiryDays)).millisecondsSinceEpoch,
        ),
      );
    }

    await _store.saveInvites([...existing, ...created]);

    return created;
  }

  Future<InviteToken> createInvite({
    required AppUser manager,
    required UserRole role,
    int maxUses = 30,
    int expiryDays = 30,
  }) async {
    final invites = await createInvites(
      manager: manager,
      role: role,
      count: 1,
      maxUses: maxUses,
      expiryDays: expiryDays,
    );

    return invites.first;
  }

  // ============================
  // LOAD INVITES
  // ============================

  Future<List<InviteToken>> loadInvitesForVenue(String venueId) async {
    if (_useFirebaseAuth) {
      final querySnapshot = await _firestore
          .collection(_invitesCollection)
          .where('venueId', isEqualTo: venueId)
          .get();

      final invites = querySnapshot.docs
          .map((doc) => InviteToken.fromFirestore(doc.id, doc.data()))
          .toList()
        ..sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));

      return invites;
    }

    final invites = await _store.loadInvites();

    return invites
      ..where((i) => i.venueId == venueId)
      ..toList()
      ..sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
  }

  // ============================
  // UPDATE INVITES
  // ============================

  Future<void> markInviteUsed(String token) async {
    final normalized = token.trim().toUpperCase();

    if (_useFirebaseAuth) {
      final ref = _firestore.collection(_invitesCollection).doc(normalized);

      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref);

        if (!snap.exists) return;

        final data = snap.data()!;
        final invite = InviteToken.fromFirestore(snap.id, data);

        final newCount = invite.usedCount + 1;

        tx.update(ref, {
          'usedCount': newCount,
          'active': newCount < invite.maxUses,
        });
      });

      return;
    }

    final invites = await _store.loadInvites();

    final updated = [
      for (final invite in invites)
        if (invite.token.trim().toUpperCase() == normalized)
          invite.copyWith(
            usedCount: invite.usedCount + 1,
            active: invite.usedCount + 1 < invite.maxUses,
          )
        else
          invite,
    ];

    await _store.saveInvites(updated);
  }

  Future<void> deactivateInvite(String token) async {
    final normalized = token.trim().toUpperCase();

    if (_useFirebaseAuth) {
      await _firestore
          .collection(_invitesCollection)
          .doc(normalized)
          .update({'active': false});
      return;
    }

    final invites = await _store.loadInvites();

    final updated = [
      for (final invite in invites)
        if (invite.token.trim().toUpperCase() == normalized)
          invite.copyWith(active: false)
        else
          invite,
    ];

    await _store.saveInvites(updated);
  }

  // ============================
  // LINK BUILDER
  // ============================

  String buildInviteLink(String token) {
    final base = _normalizedAppBaseUrl();
    final normalized = token.trim().toUpperCase();

    return '$base/#$_inviteRoute?code=$normalized';
  }

  // ============================
  // TOKEN GENERATION
  // ============================

  Future<String> _generateFirebaseUniqueToken() async {
    for (var i = 0; i < 20; i++) {
      final token = _randomToken();

      final snap = await _firestore
          .collection(_invitesCollection)
          .doc(token)
          .get();

      if (!snap.exists) return token;
    }

    throw StateError('Could not generate a unique invite token.');
  }

  String _generateLocalUniqueToken(Set<String> existing) {
    final normalized = existing.map((e) => e.toUpperCase()).toSet();

    for (var i = 0; i < 20; i++) {
      final token = _randomToken();
      if (!normalized.contains(token)) return token;
    }

    throw StateError('Could not generate a unique invite token.');
  }

  String _randomToken() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();

    return List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
  }

  String _normalizedAppBaseUrl() {
    final trimmed = _configuredAppBaseUrl.trim();

    if (trimmed.isEmpty) return _defaultAppBaseUrl;

    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}

// ============================
// RESULT
// ============================

class InviteValidationResult {
  const InviteValidationResult({this.invite, this.error});

  final InviteToken? invite;
  final String? error;

  bool get isValid => invite != null && error == null;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}