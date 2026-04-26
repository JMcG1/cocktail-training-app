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
      final invitePath = '$_invitesCollection/$normalized';
      debugPrint('[InviteService] checking Firestore path: $invitePath');

      try {
        final snapshot = await _firestore
            .collection(_invitesCollection)
            .doc(normalized)
            .get();

        debugPrint('[InviteService] Firestore doc exists: ${snapshot.exists}');
        debugPrint('[InviteService] Firestore doc id: ${snapshot.id}');
        debugPrint('[InviteService] Firestore data: ${snapshot.data()}');

        if (!snapshot.exists) {
          return const InviteValidationResult(
            error: 'This invite link does not exist.',
          );
        }

        final data = Map<String, dynamic>.from(snapshot.data()!);
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
      } on FirebaseException catch (error, stackTrace) {
        debugPrint(
          '[InviteService] Firebase validateToken error: ${error.code} ${error.message}',
        );
        debugPrint('$stackTrace');

        return const InviteValidationResult(
          error: 'We couldn’t check that invite right now.',
        );
      } catch (error, stackTrace) {
        debugPrint('[InviteService] validateToken unexpected error: $error');
        debugPrint('$stackTrace');

        return const InviteValidationResult(
          error: 'We couldn’t check that invite right now.',
        );
      }
    }

    debugPrint('[InviteService] Firebase auth disabled, checking local invites.');

    final invites = await _store.loadInvites();
    final invite = invites
        .where((item) => item.token.trim().toUpperCase() == normalized)
        .firstOrNull;

    debugPrint('[InviteService] local invite found: ${invite != null}');

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

  Future<List<InviteToken>> createInvites({
    required AppUser manager,
    required UserRole role,
    required int count,
    required int maxUses,
    required int expiryDays,
  }) async {
    if (_useFirebaseAuth) {
      final now = DateTime.now();
      final created = <InviteToken>[];

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

    final invites = await _store.loadInvites();
    final now = DateTime.now();
    final created = <InviteToken>[];

    for (var i = 0; i < count; i++) {
      final token = _generateLocalUniqueToken(
        invites.followedBy(created).map((item) => item.token).toSet(),
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

    await _store.saveInvites([...invites, ...created]);
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

  Future<List<InviteToken>> loadInvitesForVenue(String venueId) async {
    if (_useFirebaseAuth) {
      final querySnapshot = await _firestore
          .collection(_invitesCollection)
          .where('venueId', isEqualTo: venueId)
          .get();

      final invites = querySnapshot.docs
          .map(
            (doc) => InviteToken.fromFirestore(
          doc.id,
          Map<String, dynamic>.from(doc.data()),
        ),
      )
          .toList()
        ..sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));

      return invites;
    }

    final invites = await _store.loadInvites();

    final filtered = invites.where((invite) => invite.venueId == venueId).toList()
      ..sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));

    return filtered;
  }

  Future<void> markInviteUsed(String token) async {
    final normalized = token.trim().toUpperCase();

    if (_useFirebaseAuth) {
      final inviteRef = _firestore.collection(_invitesCollection).doc(normalized);

      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(inviteRef);

        if (!snapshot.exists) {
          return;
        }

        final data = Map<String, dynamic>.from(snapshot.data()!);
        final invite = InviteToken.fromFirestore(snapshot.id, data);
        final newUsedCount = invite.usedCount + 1;

        transaction.update(inviteRef, {
          'active': newUsedCount < invite.maxUses ? invite.active : false,
          'usedCount': newUsedCount,
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
            active:
            invite.usedCount + 1 < invite.maxUses ? invite.active : false,
          )
        else
          invite,
    ];

    await _store.saveInvites(updated);
  }

  Future<void> deactivateInvite(String token) async {
    final normalized = token.trim().toUpperCase();

    if (_useFirebaseAuth) {
      await _firestore.collection(_invitesCollection).doc(normalized).update({
        'active': false,
      });

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

  String buildInviteLink(String token) {
    final baseUrl = _normalizedAppBaseUrl();
    final normalized = token.trim().toUpperCase();

    return '$baseUrl/#$_inviteRoute?code=$normalized';
  }

  Future<Map<UserRole, InviteToken>> createDefaultInviteLinks(
      AppUser manager,
      ) async {
    final staffInvite = await createInvite(
      manager: manager,
      role: UserRole.staff,
      maxUses: 30,
      expiryDays: 30,
    );

    final managerInvite = await createInvite(
      manager: manager,
      role: UserRole.manager,
      maxUses: 30,
      expiryDays: 30,
    );

    return {
      UserRole.staff: staffInvite,
      UserRole.manager: managerInvite,
    };
  }

  Future<String> _generateFirebaseUniqueToken() async {
    for (var attempt = 0; attempt < 20; attempt++) {
      final token = _randomToken();

      final snapshot = await _firestore
          .collection(_invitesCollection)
          .doc(token)
          .get();

      if (!snapshot.exists) {
        return token;
      }
    }

    throw StateError('Could not generate a unique invite token.');
  }

  String _generateLocalUniqueToken(Set<String> existingTokens) {
    final normalizedExisting =
    existingTokens.map((token) => token.trim().toUpperCase()).toSet();

    for (var attempt = 0; attempt < 20; attempt++) {
      final token = _randomToken();

      if (!normalizedExisting.contains(token)) {
        return token;
      }
    }

    throw StateError('Could not generate a unique invite token.');
  }

  String _randomToken() {
    const characters = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();

    return List.generate(
      8,
          (_) => characters[random.nextInt(characters.length)],
    ).join();
  }

  String _normalizedAppBaseUrl() {
    final trimmed = _configuredAppBaseUrl.trim();

    if (trimmed.isEmpty) {
      return _defaultAppBaseUrl;
    }

    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}

class InviteValidationResult {
  const InviteValidationResult({
    this.invite,
    this.error,
  });

  final InviteToken? invite;
  final String? error;

  bool get isValid => invite != null && error == null;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}