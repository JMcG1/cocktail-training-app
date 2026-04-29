import 'package:cocktail_training/models/app_user.dart';
import 'package:cocktail_training/models/cocktail.dart';
import 'package:cocktail_training/models/leaderboard_entry.dart';
import 'package:cocktail_training/services/manager_service.dart';
import 'package:cocktail_training/widgets/premium_backdrop.dart';
import 'package:cocktail_training/widgets/surface_section.dart';
import 'package:flutter/material.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({
    super.key,
    required this.currentUser,
    required this.cocktails,
  });

  final AppUser? currentUser;
  final List<Cocktail> cocktails;

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final ManagerService _managerService = ManagerService.instance;
  LeaderboardSort _sortBy = LeaderboardSort.accuracy;
  late Future<List<LeaderboardEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = _loadEntries();
  }

  Future<List<LeaderboardEntry>> _loadEntries() async {
    final currentUser = widget.currentUser;
    if (currentUser == null || !currentUser.isManager) {
      return const [];
    }
    return _managerService.loadLeaderboard(
      manager: currentUser,
      cocktails: widget.cocktails,
      sortBy: _sortBy,
    );
  }

  void _changeSort(LeaderboardSort sort) {
    setState(() {
      _sortBy = sort;
      _entriesFuture = _loadEntries();
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = widget.currentUser;
    if (currentUser == null || !currentUser.isManager) {
      return const _LeaderboardMessage(
        title: 'Manager access only',
        message: 'This leaderboard is available to venue managers only.',
      );
    }

    return PremiumBackdrop(
      child: SafeArea(
        child: FutureBuilder<List<LeaderboardEntry>>(
          future: _entriesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            final entries = snapshot.data ?? const [];

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Team progress',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'See who is getting service-ready, who is staying consistent, and where extra coaching is needed.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 22),
                      SurfaceSection(
                        eyebrow: 'Sort',
                        title: 'How to rank the team',
                        child: Material(
                          color: Colors.transparent,
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final sort in LeaderboardSort.values)
                                FilterChip(
                                  label: Text(sort.label),
                                  selected: _sortBy == sort,
                                  onSelected: (_) => _changeSort(sort),
                                  showCheckmark: false,
                                  selectedColor: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.16),
                                  backgroundColor: const Color(0xFF171F27),
                                  side: BorderSide(
                                    color: _sortBy == sort
                                        ? Theme.of(context).colorScheme.primary
                                              .withValues(alpha: 0.28)
                                        : Theme.of(context).colorScheme.primary
                                              .withValues(alpha: 0.1),
                                  ),
                                  labelStyle: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        color: _sortBy == sort
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : const Color(0xFFE5D9C9),
                                      ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (entries.isEmpty)
                        const _LeaderboardMessage(
                          title: 'No staff progress yet',
                          message:
                              'Once the team completes study and spec checks, progress rankings will appear here.',
                        )
                      else
                        SurfaceSection(
                          eyebrow: 'Team rankings',
                          title: 'Venue training board',
                          child: Column(
                            children: [
                              for (
                                var index = 0;
                                index < entries.length;
                                index++
                              ) ...[
                                _LeaderboardCard(
                                  rank: index + 1,
                                  entry: entries[index],
                                ),
                                if (index < entries.length - 1)
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

class _LeaderboardCard extends StatelessWidget {
  const _LeaderboardCard({required this.rank, required this.entry});

  final int rank;
  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF171E26),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '#$rank',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.displayName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.email,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${entry.accuracyPercent}%',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _MetricRow(
            label: 'Questions answered',
            value: '${entry.totalQuestions}',
          ),
          const SizedBox(height: 10),
          _MetricRow(
            label: 'Specs studied',
            value: '${entry.cocktailsStudied}',
          ),
          const SizedBox(height: 10),
          _MetricRow(
            label: 'Ready for service',
            value: '${(entry.studyCompletion * 100).round()}%',
          ),
          const SizedBox(height: 10),
          _MetricRow(
            label: 'Training streak',
            value: '${entry.streakDays} day${entry.streakDays == 1 ? '' : 's'}',
          ),
          const SizedBox(height: 10),
          _MetricRow(label: 'Weak specs', value: entry.weakAreasSummary),
          const SizedBox(height: 10),
          _MetricRow(
            label: 'Last trained',
            value: _formatDate(entry.recentActivityMillis),
          ),
        ],
      ),
    );
  }

  String _formatDate(int? millis) {
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
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.day} ${months[date.month - 1]} ${date.year} at $hour:$minute';
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

class _LeaderboardMessage extends StatelessWidget {
  const _LeaderboardMessage({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return PremiumBackdrop(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: SurfaceSection(
                eyebrow: 'Leaderboard',
                title: title,
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
