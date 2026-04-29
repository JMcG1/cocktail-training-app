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
import 'package:cocktail_training/services/training_progress_service.dart';
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
  final TrainingProgressService _trainingProgressService =
      TrainingProgressService.instance;

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
    final invites = await _inviteService.loadInvitesForVenue(
      currentUser.venueId,
    );
    final venueName = await _sessionService.venueNameFor(currentUser.venueId);

    return _ManagerSnapshot(
      overview: overview,
      leaderboard: leaderboard.take(5).toList(growable: false),
      invites: invites.take(3).toList(growable: false),
      staffInvite: invites
          .where((invite) => invite.role == UserRole.staff && invite.isUsable)
          .firstOrNull,
      managerInvite: invites
          .where((invite) => invite.role == UserRole.manager && invite.isUsable)
          .firstOrNull,
      venueName: venueName,
    );
  }

  Future<void> _signOut() async {
    await _sessionService.signOut();
  }

  Future<void> _editPriorityCocktails(List<String> selectedIds) async {
    final chosen = <String>{...selectedIds};
    final saved = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Priority cocktails',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Choose the drinks managers want the team to train first.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 18),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final cocktail in widget.cocktails)
                              CheckboxListTile(
                                value: chosen.contains(cocktail.id),
                                contentPadding: EdgeInsets.zero,
                                title: Text(cocktail.name),
                                subtitle: Text(cocktail.buildStyleLabel),
                                onChanged: (value) {
                                  setSheetState(() {
                                    if (value ?? false) {
                                      chosen.add(cocktail.id);
                                    } else {
                                      chosen.remove(cocktail.id);
                                    }
                                  });
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () =>
                                Navigator.of(context).pop(chosen.toList()),
                            child: const Text('Save priorities'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    if (saved == null) {
      return;
    }

    await _trainingProgressService.savePriorityCocktailIds(saved);
    if (!mounted) {
      return;
    }

    setState(() {
      _snapshotFuture = _loadSnapshot();
    });
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

            if (snapshot.hasError) {
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 120),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 760),
                    child: const SurfaceSection(
                      eyebrow: 'Manager tools',
                      title: 'Manager tools are unavailable',
                      child: Text(
                        'We couldn’t load your venue overview right now.',
                      ),
                    ),
                  ),
                ),
              );
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
                        'Manager dashboard',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Keep training simple for the floor: invite staff, check progress, and spot weak specs before service gets busy.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 18),
                      SurfaceSection(
                        eyebrow: 'Venue',
                        title: data.venueName ?? manager.venueId,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _MetricRow(
                              label: 'Signed in as',
                              value: manager.name,
                            ),
                            const SizedBox(height: 10),
                            _MetricRow(
                              label: 'Manager account',
                              value: manager.email,
                            ),
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
                                MetricChip(
                                  label: 'Bartenders',
                                  value: '${overview.totalStaff}',
                                ),
                                MetricChip(
                                  label: 'Training active',
                                  value: '${overview.activeStaff}',
                                ),
                                MetricChip(
                                  label: 'Spec checks',
                                  value: '${overview.totalQuizAttempts}',
                                ),
                                MetricChip(
                                  label: 'Average score',
                                  value:
                                      '${(overview.averageScore * 100).round()}%',
                                ),
                                MetricChip(
                                  label: 'Pass checks passed',
                                  value: '${overview.latestExamPasses}',
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Text(
                              overview.weakCocktailAreas.isEmpty
                                  ? 'No weak spec clusters yet. Once the team starts training, recurring misses will show up here.'
                                  : 'Weak specs to watch: ${overview.weakCocktailAreas.join(', ')}',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      SurfaceSection(
                        eyebrow: 'Invite tools',
                        title: 'Invite staff and managers',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Keep fresh staff invite links and manager invite links ready, then open the full invite tools when you need batches or revokes.',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                SizedBox(
                                  width: 360,
                                  child: _QuickInviteCard(
                                    title: 'Staff invite link',
                                    subtitle: data.staffInvite == null
                                        ? 'Generate a fresh link for bartenders joining the venue.'
                                        : 'Ready to share with bartenders.',
                                    invite: data.staffInvite,
                                  ),
                                ),
                                SizedBox(
                                  width: 360,
                                  child: _QuickInviteCard(
                                    title: 'Manager invite link',
                                    subtitle: data.managerInvite == null
                                        ? 'Generate carefully for trusted managers only.'
                                        : 'Ready for additional managers.',
                                    invite: data.managerInvite,
                                    warning: true,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () => Navigator.of(
                                  context,
                                ).pushNamed('/manager/invites'),
                                icon: const Icon(Icons.group_add_outlined),
                                label: const Text('Open invite tools'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      SurfaceSection(
                        eyebrow: 'Venue priorities',
                        title: 'Manager-set training focus',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              overview.priorityCocktailIds.isEmpty
                                  ? 'No priority cocktails set yet. Add the serves you want the team to keep front of mind.'
                                  : 'These cocktails are pushed to the front of adaptive training for the whole venue.',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: overview.priorityCocktailIds.isEmpty
                                  ? const [
                                      Chip(
                                        label: Text(
                                          'No priority cocktails yet',
                                        ),
                                      ),
                                    ]
                                  : [
                                      for (final id
                                          in overview.priorityCocktailIds)
                                        Chip(
                                          label: Text(
                                            widget.cocktails
                                                    .where(
                                                      (cocktail) =>
                                                          cocktail.id == id,
                                                    )
                                                    .firstOrNull
                                                    ?.name ??
                                                id,
                                          ),
                                        ),
                                    ],
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _editPriorityCocktails(
                                  overview.priorityCocktailIds,
                                ),
                                icon: const Icon(
                                  Icons.playlist_add_check_circle_outlined,
                                ),
                                label: const Text('Set priority cocktails'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: 360,
                            child: FilledButton.icon(
                              onPressed: () => Navigator.of(
                                context,
                              ).pushNamed('/manager/invites'),
                              icon: const Icon(Icons.group_add_outlined),
                              label: const Text('Manage invite links'),
                            ),
                          ),
                          SizedBox(
                            width: 360,
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(
                                context,
                              ).pushNamed('/manager/leaderboard'),
                              icon: const Icon(Icons.leaderboard_outlined),
                              label: const Text('Review team progress'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SurfaceSection(
                        eyebrow: 'Recent invite links',
                        title: 'Recent sharing activity',
                        child: data.invites.isEmpty
                            ? Text(
                                'No invite links created yet. Generate a staff invite link or manager invite link to start onboarding the team.',
                                style: Theme.of(context).textTheme.bodyLarge,
                              )
                            : Column(
                                children: [
                                  for (
                                    var index = 0;
                                    index < data.invites.length;
                                    index++
                                  ) ...[
                                    _InvitePreviewRow(
                                      invite: data.invites[index],
                                    ),
                                    if (index < data.invites.length - 1)
                                      const SizedBox(height: 14),
                                  ],
                                ],
                              ),
                      ),
                      const SizedBox(height: 18),
                      SurfaceSection(
                        eyebrow: 'Top performers',
                        title: 'Team progress snapshot',
                        child: data.leaderboard.isEmpty
                            ? Text(
                                'No team progress has been recorded yet.',
                                style: Theme.of(context).textTheme.bodyLarge,
                              )
                            : Column(
                                children: [
                                  for (
                                    var index = 0;
                                    index < data.leaderboard.length;
                                    index++
                                  ) ...[
                                    _LeaderboardPreviewCard(
                                      rank: index + 1,
                                      entry: data.leaderboard[index],
                                    ),
                                    if (index < data.leaderboard.length - 1)
                                      const SizedBox(height: 14),
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
        latestExamPasses: 0,
        priorityCocktailIds: [],
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
    this.invite,
    this.warning = false,
  });

  final String title;
  final String subtitle;
  final InviteToken? invite;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final accent = warning
        ? const Color(0xFFF28B82)
        : Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171F27),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: accent),
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          Text(
            invite == null
                ? 'No active link ready yet'
                : '${invite!.remainingUses} place${invite!.remainingUses == 1 ? '' : 's'} left',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (invite != null) ...[
            const SizedBox(height: 8),
            Text(
              'Expires ${_formatDate(invite!.expiresAtMillis)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(int? millis) {
    if (millis == null) {
      return 'without an expiry';
    }

    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
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
                child: Text('Only venue managers can open this dashboard.'),
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
            '${invite.usedCount}/${invite.maxUses} used · ${invite.active ? 'Active' : 'Inactive'} · Expires ${_formatDate(invite.expiresAtMillis)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  String _formatDate(int? millis) {
    if (millis == null) {
      return 'never';
    }

    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }
}

class _LeaderboardPreviewCard extends StatelessWidget {
  const _LeaderboardPreviewCard({required this.rank, required this.entry});

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
          _MetricRow(label: 'Spec checks', value: '${entry.totalQuestions}'),
          const SizedBox(height: 8),
          _MetricRow(
            label: 'Latest pass check',
            value: entry.latestExamScore == null
                ? 'Not taken yet'
                : '${entry.latestExamScore}% ${entry.latestExamPassed == true ? 'Passed' : 'Retry needed'}',
          ),
          const SizedBox(height: 8),
          _MetricRow(
            label: 'Last trained',
            value: _formatRecent(entry.recentActivityMillis),
          ),
          const SizedBox(height: 8),
          _MetricRow(
            label: 'Weak drinks',
            value: entry.weakCocktails.isEmpty
                ? 'Nothing flagged'
                : entry.weakCocktails.join(', '),
          ),
        ],
      ),
    );
  }

  String _formatRecent(int? millis) {
    if (millis == null) {
      return 'No activity yet';
    }

    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
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
