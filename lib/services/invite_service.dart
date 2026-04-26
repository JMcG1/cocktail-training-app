import 'dart:math';

import 'package:cocktail_training/models/app_user.dart';
import 'package:cocktail_training/models/invite_token.dart';
import 'package:cocktail_training/models/user_role.dart';
import 'package:cocktail_training/services/local_app_store.dart';

class InviteService {
  InviteService._();

  static final InviteService instance = InviteService._();

  static const _inviteRoute = '/#/join';

  final LocalAppStore _store = LocalAppStore.instance;

  Future<InviteValidationResult> validateToken(String? token) async {
    final normalized = token?.trim().toUpperCase() ?? '';
    if (normalized.isEmpty) {
      return const InviteValidationResult(error: 'Invalid invite link.');
    }

    final invites = await _store.loadInvites();
    final invite = invites.where((item) => item.token == normalized).firstOrNull;

    if (invite == null) {
      return const InviteValidationResult(error: 'This invite link does not exist.');
    }
    if (!invite.active) {
      return const InviteValidationResult(error: 'This invite has been deactivated.');
    }
    if (invite.isExpired) {
      return const InviteValidationResult(error: 'This invite has expired.');
    }
    if (invite.isUsedUp) {
      return const InviteValidationResult(error: 'This invite has already been fully used.');
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
    final invites = await _store.loadInvites();
    final now = DateTime.now();
    final created = <InviteToken>[];

    for (var i = 0; i < count; i++) {
      final token = _generateUniqueToken(invites.followedBy(created).map((item) => item.token).toSet());
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
          expiresAtMillis: now.add(Duration(days: expiryDays)).millisecondsSinceEpoch,
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
    final invites = await _store.loadInvites();
    final filtered = invites.where((invite) => invite.venueId == venueId).toList()
      ..sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
    return filtered;
  }

  Future<void> markInviteUsed(String token) async {
    final invites = await _store.loadInvites();
    final updated = [
      for (final invite in invites)
        if (invite.token == token)
          invite.copyWith(
            usedCount: invite.usedCount + 1,
            active: invite.usedCount + 1 < invite.maxUses ? invite.active : false,
          )
        else
          invite,
    ];
    await _store.saveInvites(updated);
  }

  Future<void> deactivateInvite(String token) async {
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

  Future<Map<UserRole, InviteToken>> createDefaultInviteLinks(AppUser manager) async {
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
    return {
      UserRole.staff: staffInvite,
      UserRole.manager: managerInvite,
    };
  }

  String _generateUniqueToken(Set<String> existingTokens) {
    const characters = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();

    for (var attempt = 0; attempt < 20; attempt++) {
      final token = List.generate(8, (_) => characters[random.nextInt(characters.length)]).join();
      if (!existingTokens.contains(token)) {
        return token;
      }
    }

    throw StateError('Could not generate a unique invite token.');
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
