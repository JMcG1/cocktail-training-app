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

  static const _inviteRoute = '/#/join';
  static const _invitesCollection = 'invites';

  final LocalAppStore _store = LocalAppStore.instance;

  bool get _useFirebaseAuth => BackendRuntimeService.instance.useFirebaseAuth;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  Future<InviteValidationResult> validateToken(String? token) async {
    final normalized = token?.trim().toUpperCase() ?? '';
    if (normalized.isEmpty) {
      return const InviteValidationResult(error: 'Invalid invite link.');
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

        final data = snapshot.data();
        if (data == null) {
          return const InviteValidationResult(
            error: 'This invite could not be loaded.',
          );
        }

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
            error: 'This invite has already been fully used.',
          );
        }

        return InviteValidationResult(invite: invite);
      } on FirebaseException catch (error, stackTrace) {
        debugPrint(
          '[InviteService] Firebase validateToken error: ${error.code}',
        );
        debugPrint('$stackTrace');
        return const InviteValidationResult(
          error: 'We couldn’t check that invite right now.',
        );
      }
    }

    final invites = await _store.loadInvites();
    final invite = invites
        .where((item) => item.token == normalized)
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
      return const InviteValidationResult(error: 'This invite has expired.');
    }
    if (invite.isUsedUp) {
      return const InviteValidationResult(
        error: 'This invite has already been fully used.',
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
          expiresAtMillis: now
              .add(Duration(days: expiryDays))
              .millisecondsSinceEpoch,
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
          expiresAtMillis: now
              .add(Duration(days: expiryDays))
              .millisecondsSinceEpoch,
        ),
      );
    }

    await _store.saveInvites([...invites, ...created]);
    return created;
  }

  Future<InviteToken> createInvite({
    required AppUser manager,
    required UserRole role,
    int maxUses = 1,
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

      final invites =
          querySnapshot.docs
              .map((doc) => InviteToken.fromFirestore(doc.id, doc.data()))
              .toList()
            ..sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
      return invites;
    }

    final invites = await _store.loadInvites();
    final filtered =
        invites.where((invite) => invite.venueId == venueId).toList()
          ..sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
    return filtered;
  }

  Future<void> markInviteUsed(String token) async {
    if (_useFirebaseAuth) {
      final inviteRef = _firestore.collection(_invitesCollection).doc(token);
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(inviteRef);
        if (!snapshot.exists) {
          return;
        }
        final data = snapshot.data();
        if (data == null) {
          return;
        }
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
        if (invite.token == token)
          invite.copyWith(
            usedCount: invite.usedCount + 1,
            active: invite.usedCount + 1 < invite.maxUses
                ? invite.active
                : false,
          )
        else
          invite,
    ];
    await _store.saveInvites(updated);
  }

  Future<void> deactivateInvite(String token) async {
    if (_useFirebaseAuth) {
      await _firestore.collection(_invitesCollection).doc(token).update({
        'active': false,
      });
      return;
    }

    final invites = await _store.loadInvites();
    final updated = [
      for (final invite in invites)
        if (invite.token == token) invite.copyWith(active: false) else invite,
    ];
    await _store.saveInvites(updated);
  }

  String buildInviteLink(String token) {
    final origin = Uri.base.origin;
    return '$origin$_inviteRoute?token=$token';
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
      maxUses: 3,
      expiryDays: 7,
    );
    return {UserRole.staff: staffInvite, UserRole.manager: managerInvite};
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
    for (var attempt = 0; attempt < 20; attempt++) {
      final token = _randomToken();
      if (!existingTokens.contains(token)) {
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
}

class InviteValidationResult {
  const InviteValidationResult({this.invite, this.error});

  final InviteToken? invite;
  final String? error;

  bool get isValid => invite != null && error == null;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
