import 'package:cocktail_training/models/app_user.dart';
import 'package:cocktail_training/models/cocktail.dart';
import 'package:cocktail_training/models/invite_token.dart';
import 'package:cocktail_training/models/leaderboard_entry.dart';
import 'package:cocktail_training/models/manager_overview.dart';
import 'package:cocktail_training/models/user_role.dart';
import 'package:cocktail_training/services/invite_service.dart';
import 'package:cocktail_training/services/role_guard.dart';
import 'package:cocktail_training/services/manager_service.dart';
import 'package:cocktail_training/services/session_service.dart';
import 'package:cocktail_training/widgets/metric_chip.dart';
import 'package:cocktail_training/widgets/premium_backdrop.dart';
import 'package:cocktail_training/widgets/surface_section.dart';
import 'package:flutter/material.dart';

class ManagerDashboardScreen extends StatefulWidget {
  const ManagerDashboardScreen({
    super.key,
    required this.currentUser,
    required this.cocktails,
  });

  final AppUser? currentUser;
  final List<Cocktail> cocktails;

  @override
  State<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends State<ManagerDashboardScreen> {
  final ManagerService _managerService = ManagerService.instance;
  final InviteService _inviteService = InviteService.instance;
  final SessionService _sessionService = SessionService.instance;

  late Future<_ManagerSnapshot> _snapshotFuture;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = _loadSnapshot();
  }

  Future<_ManagerSnapshot> _loadSnapshot() async {
    final currentUser = widget.currentUser;
    if (currentUser == null || !currentUser.isManager) {
      return const _ManagerSnapshot.empty();
    }

    final overview = await _managerService.loadOverview(
      manager: currentUser,
      cocktails: widget.cocktails,
    );
    final leaderboard = await _managerService.loadLeaderboard(
      manager: currentUser,
      cocktails: widget.cocktails,
      sortBy: LeaderboardSort.accuracy,
    );
    final invites = await _inviteService.loadInvitesForVenue(currentUser.venueId);
    final venueName = await _sessionService.venueNameFor(currentUser.venueId);

    return _ManagerSnapshot(
      overview: overview,
      leaderboard: leaderboard.take(5).toList(growable: false),
      invites: invites.take(3).toList(growable: false),
      staffInvite: invites.where((invite) => invite.role == UserRole.staff && invite.isUsable).firstOrNull,
      managerInvite: invites.where((invite) => invite.role == UserRole.manager && invite.isUsable).firstOrNull,
      venueName: venueName,
    );
  }

  Future<void> _signOut() async {
    await _sessionService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = widget.currentUser;
    if (!RoleGuard.canAccessManagerTools(currentUser)) {
      return const _UnauthorizedManagerView();
    }
    final manager = currentUser!;

    return PremiumBackdrop(
      child: SafeArea(
        child: FutureBuilder<_ManagerSnapshot>(
          future: _snapshotFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data ?? const _ManagerSnapshot.empty();
            final overview = data.overview;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Manager Dashboard',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Oversee venue training, create role-based invite links, and track team performance from one place.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 18),
                      SurfaceSection(
                        eyebrow: 'Venue',
                        title: data.venueName ?? manager.venueId,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _MetricRow(label: 'Signed in as', value: manager.email),
                            const SizedBox(height: 10),
                            _MetricRow(label: 'Role', value: manager.role.label),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _signOut,
                                icon: const Icon(Icons.logout),
                                label: const Text('Log out'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      SurfaceSection(
                        eyebrow: 'Overview',
                        title: 'Team health',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                MetricChip(label: 'Total staff', value: '${overview.totalStaff}'),
                                MetricChip(label: 'Active staff', value: '${overview.activeStaff}'),
                                MetricChip(label: 'Quiz attempts', value: '${overview.totalQuizAttempts}'),
                                MetricChip(
                                  label: 'Average score',
                                  value: '${(overview.averageScore * 100).round()}%',
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Text(
                              overview.weakCocktailAreas.isEmpty
                                  ? 'No weak cocktail clusters yet. Once staff begin training, recurring weak areas will appear here.'
                                  : 'Weak cocktail areas: ${overview.weakCocktailAreas.join(', ')}',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      SurfaceSection(
                        eyebrow: 'Invite tools',
                        title: 'Onboard staff and managers',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Use fresh role-based links or jump into the full invite manager for batching and revoking links.',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: _QuickInviteCard(
                                    title: 'Staff invite',
                                    subtitle: data.staffInvite == null
                                        ? 'Generate a new staff onboarding link.'
                                        : 'Ready to share with venue staff.',
                                    token: data.staffInvite?.token,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _QuickInviteCard(
                                    title: 'Manager invite',
                                    subtitle: data.managerInvite == null
                                        ? 'Generate carefully for trusted managers.'
                                        : 'Reserved for additional managers.',
                                    token: data.managerInvite?.token,
                                    warning: true,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () => Navigator.of(context).pushNamed('/manager/invites'),
                                icon: const Icon(Icons.group_add_outlined),
                                label: const Text('Open invite tools'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => Navigator.of(context).pushNamed('/manager/invites'),
                              icon: const Icon(Icons.group_add_outlined),
                              label: const Text('Manage invites'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).pushNamed('/manager/leaderboard'),
                              icon: const Icon(Icons.leaderboard_outlined),
                              label: const Text('Open leaderboard'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SurfaceSection(
                        eyebrow: 'Recent invite links',
                        title: 'Shareable access',
                        child: data.invites.isEmpty
                            ? Text(
                                'No invite links created yet. Generate staff or manager links to start onboarding the team.',
                                style: Theme.of(context).textTheme.bodyLarge,
                              )
                            : Column(
                                children: [
                                  for (var index = 0; index < data.invites.length; index++) ...[
                                    _InvitePreviewRow(invite: data.invites[index]),
                                    if (index < data.invites.length - 1) const SizedBox(height: 14),
                                  ],
                                ],
                              ),
                      ),
                      const SizedBox(height: 18),
                      SurfaceSection(
                        eyebrow: 'Leaderboard preview',
                        title: 'Top team members',
                        child: data.leaderboard.isEmpty
                            ? Text(
                                'No staff progress has been recorded yet.',
                                style: Theme.of(context).textTheme.bodyLarge,
                              )
                            : Column(
                                children: [
                                  for (var index = 0; index < data.leaderboard.length; index++) ...[
                                    _LeaderboardPreviewCard(
                                      rank: index + 1,
                                      entry: data.leaderboard[index],
                                    ),
                                    if (index < data.leaderboard.length - 1) const SizedBox(height: 14),
                                  ],
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ManagerSnapshot {
  const _ManagerSnapshot({
    required this.overview,
    required this.leaderboard,
    required this.invites,
    required this.staffInvite,
    required this.managerInvite,
    this.venueName,
  });

  const _ManagerSnapshot.empty()
      : overview = const ManagerOverview(
          totalStaff: 0,
          activeStaff: 0,
          totalQuizAttempts: 0,
          averageScore: 0,
          weakCocktailAreas: [],
        ),
        leaderboard = const [],
        invites = const [],
        staffInvite = null,
        managerInvite = null,
        venueName = null;

  final ManagerOverview overview;
  final List<LeaderboardEntry> leaderboard;
  final List<InviteToken> invites;
  final InviteToken? staffInvite;
  final InviteToken? managerInvite;
  final String? venueName;
}

class _QuickInviteCard extends StatelessWidget {
  const _QuickInviteCard({
    required this.title,
    required this.subtitle,
    this.token,
    this.warning = false,
  });

  final String title;
  final String subtitle;
  final String? token;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final accent = warning ? const Color(0xFFF28B82) : Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171F27),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accent.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: accent),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Text(
            token ?? 'No active link yet',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      ),
    );
  }
}

class _UnauthorizedManagerView extends StatelessWidget {
  const _UnauthorizedManagerView();

  @override
  Widget build(BuildContext context) {
    return PremiumBackdrop(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: SurfaceSection(
                eyebrow: 'Manager dashboard',
                title: 'Manager access only',
                child: Text('This dashboard is reserved for venue managers.'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InvitePreviewRow extends StatelessWidget {
  const _InvitePreviewRow({required this.invite});

  final InviteToken invite;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171F27),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            invite.role.inviteLabel,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            invite.token,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '${invite.usedCount}/${invite.maxUses} uses · ${invite.active ? 'Active' : 'Inactive'}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _LeaderboardPreviewCard extends StatelessWidget {
  const _LeaderboardPreviewCard({
    required this.rank,
    required this.entry,
  });

  final int rank;
  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171F27),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '#$rank',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  entry.displayName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${entry.accuracyPercent}%',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _MetricRow(label: 'Questions', value: '${entry.totalQuestions}'),
          const SizedBox(height: 8),
          _MetricRow(label: 'Weak areas', value: entry.weakAreasSummary),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
      ],
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
