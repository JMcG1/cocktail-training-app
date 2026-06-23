import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/utils/browser_connectivity.dart';
import '../../domain/models/models.dart';
import '../controllers/app_controller.dart';
import 'shell_route_helpers.dart';
import 'shell_support_widgets.dart';

class ManagerTeamTab extends StatefulWidget {
  const ManagerTeamTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<ManagerTeamTab> createState() => _ManagerTeamTabState();
}

class _ManagerTeamTabState extends State<ManagerTeamTab> {
  UserRole _inviteRole = UserRole.bartender;
  final TextEditingController _maxUsesController = TextEditingController(
    text: '1',
  );
  int _expiryDays = 7;
  String? _surpriseBartenderName;
  List<String> _surpriseConcernNames = const [];
  String? _salesImportWeekId;
  String? _salesImportBartenderName;
  bool _isImportingSalesPdf = false;

  String _roleLabel(UserRole role) {
    return switch (role) {
      UserRole.owner => 'Owner/Admin',
      UserRole.manager => 'Manager',
      UserRole.bartender => 'Bartender',
    };
  }

  @override
  void initState() {
    super.initState();
    if (!widget.controller.canAccessManagerWorkflows) {
      _inviteRole = UserRole.bartender;
    }
  }

  @override
  void dispose() {
    _maxUsesController.dispose();
    super.dispose();
  }

  Future<void> _pickSurpriseConcernIngredients() async {
    final options = widget.controller.concernIngredientNames;
    final selected = {..._surpriseConcernNames};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Choose concern ingredients'),
              content: SizedBox(
                width: 420,
                child: options.isEmpty
                    ? const Text('No approved ingredients are available yet.')
                    : SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final option in options)
                              CheckboxListTile(
                                value: selected.contains(option),
                                title: Text(option),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                onChanged: (value) {
                                  setDialogState(() {
                                    if (value == true) {
                                      selected.add(option);
                                    } else {
                                      selected.remove(option);
                                    }
                                  });
                                },
                              ),
                          ],
                        ),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Use selected ingredients'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed == true && mounted) {
      setState(() {
        _surpriseConcernNames = selected.toList()..sort();
      });
    }
  }

  Future<void> _importSalesPdf({
    required WeeklyConcernSession session,
    required String bartenderName,
  }) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (!mounted || picked == null || picked.files.isEmpty) {
      return;
    }
    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The selected PDF could not be read.')),
      );
      return;
    }

    setState(() => _isImportingSalesPdf = true);
    try {
      final preview = widget.controller.importBartenderSalesPdf(
        bytes: bytes,
        fileName: file.name,
        weekId: session.id,
        bartenderName: bartenderName,
      );
      if (!mounted) {
        return;
      }
      final review = await showDialog<_SalesPdfReviewResult>(
        context: context,
        builder: (context) => _SalesPdfImportReviewDialog(
          controller: widget.controller,
          bytes: bytes,
          sourceFileName: file.name,
          session: session,
          bartenderName: bartenderName,
          preview: preview,
        ),
      );
      if (review != null) {
        final editedEntries = review.entries;
        widget.controller.saveBartenderSales(
          weekId: session.id,
          bartenderName: bartenderName,
          entries: editedEntries,
        );
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved ${editedEntries.length} cocktail sales lines for $bartenderName.',
            ),
          ),
        );
        setState(() {});
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isImportingSalesPdf = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = widget.controller.buildDashboard();
    final currency = NumberFormat.currency(symbol: '£', decimalDigits: 2);
    final bartenderCompletion =
        dashboard.bartenderAverageScores.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final weakCocktails = dashboard.misunderstoodCocktails.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final weakIngredients = dashboard.ingredientMisses.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final weakBatches = dashboard.potentialVarianceByBatch.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final weakGarnishes = dashboard.garnishMisses.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final weakGlassware = dashboard.glasswareMisses.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final weakBuildStyles = dashboard.buildStyleMisses.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final varianceByBartender =
        dashboard.potentialVarianceByBartender.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final confidenceVsAccuracy = dashboard.confidenceAccuracy.entries.toList()
      ..sort((a, b) => a.key.index.compareTo(b.key.index));
    final teamMembers = widget.controller.venueUsers
        .where((user) => user.role != UserRole.owner)
        .toList();
    final bartenderCount = teamMembers
        .where((user) => user.role == UserRole.bartender)
        .length;
    final bartenderUsers =
        teamMembers
            .where((user) => user.role == UserRole.bartender && user.active)
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final weeklySessions = [...widget.controller.weeklySessions]
      ..sort((a, b) => b.weekStart.compareTo(a.weekStart));
    final exposureSummaries = widget.controller.buildBartenderExposureSummaries();
    final selectedBartenderName =
        _surpriseBartenderName ??
        (bartenderUsers.isNotEmpty ? bartenderUsers.first.displayName : null);
    _surpriseBartenderName = selectedBartenderName;
    final selectedSalesBartenderName =
        _salesImportBartenderName ??
        (bartenderUsers.isNotEmpty ? bartenderUsers.first.displayName : null);
    _salesImportBartenderName = selectedSalesBartenderName;
    final selectedSalesSession = weeklySessions
        .cast<WeeklyConcernSession?>()
        .firstWhere(
          (session) => session != null && session.id == _salesImportWeekId,
          orElse: () => weeklySessions.isNotEmpty ? weeklySessions.first : null,
        );
    _salesImportWeekId = selectedSalesSession?.id;
    final totalEstimatedCostImpact = dashboard
        .potentialVarianceByBartender
        .values
        .fold<double>(0, (sum, value) => sum + value);
    final isOnline = BrowserConnectivity.isOnline();
    final syncStatus = widget.controller.trainingSyncStatus;

    final inviteOptions = const [UserRole.manager, UserRole.bartender];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const HeaderCard(
          title: 'Team dashboard',
          subtitle:
              'Review team progress, invite staff, and use quiz performance plus estimated cost impact to spot helpful training opportunities.',
        ),
        const SizedBox(height: 16),
        _ManagerSyncBanner(isOnline: isOnline, syncStatus: syncStatus),
        const SizedBox(height: 16),
        if (!widget.controller.usingFirebase) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Live staff invites are not available in this build yet, but you can still review the training and sales data already loaded here.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            MetricCard(
              title: 'Team members',
              value: '${teamMembers.length}',
              caption: '$bartenderCount bartenders in this venue',
            ),
            MetricCard(
              title: 'Average score',
              value: '${dashboard.venueAverageScore}%',
              caption: 'Across loaded team attempts',
            ),
            MetricCard(
              title: 'Completion rate',
              value: '${dashboard.quizCompletionRate}%',
              caption: 'Weekly quiz completion',
            ),
            MetricCard(
              title: 'Estimated impact',
              value: currency.format(totalEstimatedCostImpact),
              caption: 'Training opportunity snapshot',
            ),
            MetricCard(
              title: 'High-confidence misses',
              value: '${dashboard.highConfidenceWrongAnswers}',
              caption: 'Coaching opportunities',
            ),
            MetricCard(
              title: 'Lost cocktail capacity',
              value: dashboard.totalRecoverableCocktails.toStringAsFixed(1),
              caption: 'From overpour volume',
            ),
            MetricCard(
              title: 'Potential lost sales',
              value: currency.format(dashboard.totalRecoverableRevenueGbp),
              caption: 'Operational value at risk',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bartender exposure history',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Saved PDF imports build a weekly exposure history for each bartender so you can see who is handling the most volume and which cocktails deserve the closest coaching.',
                ),
                const SizedBox(height: 16),
                if (exposureSummaries.isEmpty)
                  const Text(
                    'No bartender exposure has been saved yet. Import a Product Sales by Employee PDF to start building this history.',
                  )
                else
                  ...exposureSummaries.map(
                    (summary) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _BartenderExposureCard(summary: summary),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create invite',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (!widget.controller.usingFirebase)
                  const Text(
                    'Live invite links are not available in this build yet.',
                  )
                else ...[
                  const Text(
                    'Each invite already sets the right role for the person joining.',
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<UserRole>(
                          initialValue: _inviteRole,
                          items: inviteOptions
                              .map(
                                (role) => DropdownMenuItem(
                                  value: role,
                                  child: Text(_roleLabel(role)),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _inviteRole = value);
                            }
                          },
                          decoration: const InputDecoration(labelText: 'Role'),
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: TextField(
                          controller: _maxUsesController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Max uses',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<int>(
                          initialValue: _expiryDays,
                          items: const [1, 3, 7, 14]
                              .map(
                                (days) => DropdownMenuItem(
                                  value: days,
                                  child: Text('$days days'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _expiryDays = value);
                            }
                          },
                          decoration: const InputDecoration(
                            labelText: 'Expires in',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: widget.controller.isBusy
                        ? null
                        : () async {
                            try {
                              await widget.controller.createVenueInvite(
                                role: _inviteRole,
                                expiresAt: DateTime.now().add(
                                  Duration(days: _expiryDays),
                                ),
                                maxUses:
                                    int.tryParse(
                                      _maxUsesController.text.trim(),
                                    ) ??
                                    1,
                              );
                              if (mounted) {
                                setState(() {});
                              }
                            } catch (_) {}
                          },
                    child: const Text('Create invite'),
                  ),
                  if (widget.controller.successMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(widget.controller.successMessage!),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    'Live invites',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (widget.controller.venueInvites.isEmpty)
                    const Text('No invites have been created yet.')
                  else
                    ...widget.controller.venueInvites.map(
                      (invite) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _InviteCard(
                          invite: invite,
                          roleLabel: _roleLabel(invite.role),
                          onShowQr: () async {
                            final joinUrl = inviteLinkUriFromBase(
                              Uri.base,
                              invite,
                            ).toString();
                            await showShareLinkDialog(
                              context: context,
                              title: 'Invite QR code',
                              url: joinUrl,
                            );
                          },
                          onCopyLink: () async {
                            final joinUrl = inviteLinkUriFromBase(
                              Uri.base,
                              invite,
                            ).toString();
                            await Clipboard.setData(
                              ClipboardData(text: joinUrl),
                            );
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Invite link copied.'),
                              ),
                            );
                          },
                          onDelete: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Delete invite link?'),
                                content: const Text(
                                  'This invite link will stop working immediately.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true) {
                              return;
                            }
                            try {
                              await widget.controller.deleteVenueInvite(
                                inviteId: invite.id,
                              );
                              if (mounted) {
                                setState(() {});
                              }
                            } catch (_) {}
                          },
                          onToggleLive: (value) async {
                            await widget.controller.setVenueInviteDisabled(
                              inviteId: invite.id,
                              disabled: !value,
                            );
                            if (mounted) {
                              setState(() {});
                            }
                          },
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Import sales PDF',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Upload the weekly Product Sales by Employee PDF and save only the approved target cocktails for one bartender at a time. If the selected bartender name is not found in the PDF, each target cocktail is filled with 25 so managers can test the flow.',
                ),
                const SizedBox(height: 16),
                if (weeklySessions.isEmpty)
                  const Text(
                    'Create a stock-focus session first so the importer knows which cocktails matter for this week.',
                  )
                else if (bartenderUsers.isEmpty)
                  const Text(
                    'Add at least one active bartender account before importing sales from a PDF.',
                  )
                else ...[
                  DropdownButtonFormField<String>(
                    initialValue: selectedSalesSession?.id,
                    items: weeklySessions
                        .map(
                          (session) => DropdownMenuItem(
                            value: session.id,
                            child: Text(
                              '${DateFormat('dd MMM').format(session.weekStart)} · ${session.label}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() => _salesImportWeekId = value);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Stock-focus session',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedSalesBartenderName,
                    items: bartenderUsers
                        .map(
                          (user) => DropdownMenuItem(
                            value: user.displayName,
                            child: Text(user.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() => _salesImportBartenderName = value);
                    },
                    decoration: const InputDecoration(labelText: 'Bartender'),
                  ),
                  const SizedBox(height: 12),
                  if ((selectedSalesSession?.targetCocktailIds.length ?? 0) > 0)
                    Text(
                      'This session will import ${selectedSalesSession!.targetCocktailIds.length} target cocktails only.',
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed:
                        _isImportingSalesPdf ||
                            selectedSalesSession == null ||
                            (selectedSalesBartenderName ?? '').isEmpty
                        ? null
                        : () => _importSalesPdf(
                            session: selectedSalesSession,
                            bartenderName: selectedSalesBartenderName!,
                          ),
                    icon: _isImportingSalesPdf
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file),
                    label: Text(
                      _isImportingSalesPdf
                          ? 'Reading PDF...'
                          : 'Import sales from PDF',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Surprise quiz',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Launch a focused quiz on ingredients that are costing the team the most when specs are missed.',
                ),
                const SizedBox(height: 16),
                if (!widget.controller.usingFirebase)
                  const Text(
                    'Live surprise quiz links are not available in this build yet.',
                  )
                else if (bartenderUsers.isEmpty)
                  const Text(
                    'Add at least one active bartender account before launching a surprise quiz.',
                  )
                else ...[
                  DropdownButtonFormField<String>(
                    initialValue: selectedBartenderName,
                    items: bartenderUsers
                        .map(
                          (user) => DropdownMenuItem(
                            value: user.displayName,
                            child: Text(user.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() => _surpriseBartenderName = value);
                    },
                    decoration: const InputDecoration(labelText: 'Bartender'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pickSurpriseConcernIngredients,
                    icon: const Icon(Icons.playlist_add_check),
                    label: Text(
                      _surpriseConcernNames.isEmpty
                          ? 'Choose concern ingredients'
                          : 'Change concern ingredients',
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_surpriseConcernNames.isEmpty)
                    const Text(
                      'Choose at least one ingredient before launching the quiz.',
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _surpriseConcernNames
                          .map((name) => Chip(label: Text(name)))
                          .toList(),
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed:
                        _surpriseConcernNames.isEmpty ||
                            (_surpriseBartenderName ?? '').isEmpty
                        ? null
                        : () async {
                            final labelIngredients = _surpriseConcernNames
                                .take(2)
                                .join(' + ');
                            final session = widget.controller.createWeeklySession(
                              label:
                                  'Surprise quiz · ${_surpriseBartenderName!} · $labelIngredients',
                              weekStart: DateTime.now(),
                              concerns: _surpriseConcernNames
                                  .map(
                                    (name) =>
                                        StockConcernItem(ingredientName: name),
                                  )
                                  .toList(),
                            );
                            final quiz = widget.controller.generateStockQuiz(
                              weekId: session.id,
                              bartenderName: _surpriseBartenderName!,
                              focus: QuizFocus.specs,
                            );
                            final shareUrl = quizLinkUriFromBase(
                              Uri.base,
                              quiz,
                            ).toString();
                            if (!mounted) {
                              return;
                            }
                            await showShareLinkDialog(
                              context: context,
                              title: 'Surprise quiz QR code',
                              url: shareUrl,
                            );
                          },
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text('Launch surprise quiz QR'),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Staff access',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (teamMembers.isEmpty)
                  const Text('No staff accounts are loaded yet.')
                else
                  ...teamMembers.map(
                    (user) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(user.displayName),
                      subtitle: Text(
                        '${_roleLabel(user.role)} · ${user.email}${user.active ? '' : ' · paused'}',
                      ),
                      trailing: Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Switch(
                            value: user.active,
                            onChanged: widget.controller.isOwnerAuthenticated
                                ? (value) async {
                                    await widget.controller.setVenueUserActive(
                                      userId: user.id,
                                      active: value,
                                    );
                                    if (mounted) {
                                      setState(() {});
                                    }
                                  }
                                : null,
                          ),
                          if (widget.controller.isOwnerAuthenticated)
                            IconButton(
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Remove staff access?'),
                                    content: Text(
                                      'Remove ${user.displayName} from this venue team list? Their historical quiz results stay available.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(true),
                                        child: const Text('Remove'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true) {
                                  return;
                                }
                                try {
                                  await widget.controller.deleteVenueUser(
                                    userId: user.id,
                                  );
                                  if (mounted) {
                                    setState(() {});
                                  }
                                } catch (_) {}
                              },
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Remove staff access',
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _ManagerTrendCard(
          title: 'Bartender score trend',
          items: bartenderCompletion
              .take(6)
              .map((entry) => (label: entry.key, value: entry.value))
              .toList(),
          suffix: '%',
        ),
        const SizedBox(height: 16),
        InsightListCard(
          title: 'Bartender average scores',
          emptyLabel:
              'Team quiz history will appear here after the first submissions.',
          items: bartenderCompletion
              .map((entry) => '${entry.key} · ${entry.value}% average')
              .toList(),
        ),
        const SizedBox(height: 16),
        InsightListCard(
          title: 'Estimated cost impact opportunities',
          emptyLabel:
              'Estimated impact highlights will appear after quiz submissions are saved.',
          items: varianceByBartender
              .take(8)
              .map((entry) => '${entry.key} · ${currency.format(entry.value)}')
              .toList(),
        ),
        const SizedBox(height: 16),
        _ManagerTrendCard(
          title: 'Top errors this week',
          items: weakCocktails
              .take(5)
              .map((entry) => (label: entry.key, value: entry.value))
              .toList(),
        ),
        const SizedBox(height: 16),
        InsightListCard(
          title: 'Weak cocktails',
          emptyLabel: 'No repeated cocktail misses are visible yet.',
          items: weakCocktails
              .take(8)
              .map((entry) => '${entry.key} · ${entry.value} misses')
              .toList(),
        ),
        const SizedBox(height: 16),
        InsightListCard(
          title: 'Weak ingredient areas',
          emptyLabel: 'Ingredient trends will appear after a few quizzes.',
          items: weakIngredients
              .take(8)
              .map((entry) => '${entry.key} · ${entry.value} misses')
              .toList(),
        ),
        const SizedBox(height: 16),
        InsightListCard(
          title: 'Weak batch areas',
          emptyLabel:
              'Batch-specific patterns will appear once batch questions are answered.',
          items: weakBatches
              .take(8)
              .map(
                (entry) =>
                    '${entry.key} · ${entry.value.toStringAsFixed(0)}ml attention area',
              )
              .toList(),
        ),
        const SizedBox(height: 16),
        InsightListCard(
          title: 'Most missed garnishes',
          emptyLabel: 'Garnish misses will appear after service-focused quizzes.',
          items: weakGarnishes
              .take(8)
              .map((entry) => '${entry.key} · ${entry.value} misses')
              .toList(),
        ),
        const SizedBox(height: 16),
        InsightListCard(
          title: 'Most missed glassware',
          emptyLabel:
              'Glassware misses will appear after service-focused quizzes.',
          items: weakGlassware
              .take(8)
              .map((entry) => '${entry.key} · ${entry.value} misses')
              .toList(),
        ),
        const SizedBox(height: 16),
        InsightListCard(
          title: 'Most missed build styles',
          emptyLabel: 'Build-style misses will appear after method questions.',
          items: weakBuildStyles
              .take(8)
              .map((entry) => '${entry.key} · ${entry.value} misses')
              .toList(),
        ),
        const SizedBox(height: 16),
        InsightListCard(
          title: 'Confidence vs accuracy',
          emptyLabel:
              'Confidence tracking appears after the first saved quiz attempts.',
          items: confidenceVsAccuracy
              .map(
                (entry) =>
                    '${_confidenceLabel(entry.key)} · ${entry.value.correct} correct / ${entry.value.wrong} wrong',
              )
              .toList(),
        ),
      ],
    );
  }
}

class _ManagerSyncBanner extends StatelessWidget {
  const _ManagerSyncBanner({
    required this.isOnline,
    required this.syncStatus,
  });

  final bool isOnline;
  final TrainingSyncStatus syncStatus;

  @override
  Widget build(BuildContext context) {
    final background = !isOnline || syncStatus.quizReadsFromCache
        ? Theme.of(context).colorScheme.tertiaryContainer
        : Theme.of(context).colorScheme.secondaryContainer;
    final text = !isOnline
        ? 'Offline right now. Team reporting will catch up once you reconnect.'
        : syncStatus.quizReadsFromCache
        ? 'Showing saved team reporting. ${syncStatus.lastQuizSyncMessage}'
        : syncStatus.lastQuizSyncMessage;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text),
    );
  }
}

class _ManagerTrendCard extends StatelessWidget {
  const _ManagerTrendCard({
    required this.title,
    required this.items,
    this.suffix = '',
  });

  final String title;
  final List<({String label, int value})> items;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const Text('Trend data appears after saved team quiz results.')
            else
              ...items.map((item) {
                final maxValue = items
                    .map((entry) => entry.value)
                    .fold<int>(1, (max, value) => value > max ? value : max);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(item.label)),
                          Text('${item.value}$suffix'),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: maxValue == 0 ? 0 : item.value / maxValue,
                        minHeight: 8,
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

String _confidenceLabel(QuizAnswerConfidence confidence) {
  return switch (confidence) {
    QuizAnswerConfidence.guessing => 'Guessing',
    QuizAnswerConfidence.unsure => 'Unsure',
    QuizAnswerConfidence.fairlySure => 'Fairly sure',
    QuizAnswerConfidence.certain => 'Certain',
  };
}

class InsightListCard extends StatelessWidget {
  const InsightListCard({
    super.key,
    required this.title,
    required this.items,
    required this.emptyLabel,
  });

  final String title;
  final List<String> items;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Text(emptyLabel)
            else
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 7),
                        child: Icon(Icons.circle, size: 8),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(item)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SalesPdfImportPreviewCard extends StatelessWidget {
  const _SalesPdfImportPreviewCard({
    required this.preview,
    required this.sessionLabel,
    this.overrideQuantities = const {},
    this.showEditableQuantities = false,
    this.onQuantityChanged,
  });

  final SalesPdfImportPreview preview;
  final String sessionLabel;
  final Map<String, String> overrideQuantities;
  final bool showEditableQuantities;
  final ValueChanged<_EditedSalesQuantity>? onQuantityChanged;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'en_GB',
      symbol: '£',
      decimalDigits: 2,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _DataLine(label: 'Source file', value: preview.sourceName),
        _DataLine(label: 'Session', value: sessionLabel),
        _DataLine(label: 'Bartender', value: preview.bartenderName),
        if ((preview.dateSelection ?? '').isNotEmpty)
          _DataLine(label: 'Report week', value: preview.dateSelection!),
        _DataLine(
          label: 'Report employee',
          value: preview.matchedReportName ?? 'No matching name found in PDF',
        ),
        _DataLine(
          label: 'Mode',
          value: preview.usedFallbackQuantities
              ? 'Fallback test quantities'
              : 'PDF-estimated cocktail quantities',
        ),
        _DataLine(
          label: 'Rows read',
          value: '${preview.parsedRowCount}',
        ),
        _DataLine(
          label: 'Exposure saved',
          value:
              '${preview.totalQuantitySold} cocktails · ${currency.format(preview.totalSalesValueGbp)}',
        ),
        const SizedBox(height: 12),
        if (preview.warnings.isNotEmpty) ...[
          Text('Warnings', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...preview.warnings.map(
            (warning) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(warning),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          'Cocktail quantities',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (preview.entries.isEmpty)
          const Text('No target cocktails were found to save from this PDF.')
        else
          ...preview.matchedCocktails.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showEditableQuantities)
                    _EditableSalesQuantityRow(
                      cocktailId: entry.cocktailId,
                      cocktailName: entry.cocktailName,
                      quantityText:
                          overrideQuantities[entry.cocktailId] ??
                          entry.estimatedQuantity.toString(),
                      onChanged: onQuantityChanged,
                    )
                  else
                    Text(
                      '${entry.cocktailName} · ${entry.estimatedQuantity}',
                    ),
                  Text(
                    '${currency.format(entry.salesValueGbp)} from ${entry.reportProductNames.isEmpty ? 'fallback test quantity' : entry.reportProductNames.join(', ')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    'Stored exposure: ${entry.estimatedQuantity} sold · ${currency.format(entry.salesValueGbp)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        if (preview.missingTargetCocktails.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Target cocktails not found',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(preview.missingTargetCocktails.join(', ')),
        ],
        if (preview.ignoredProducts.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Ignored PDF products',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(preview.ignoredProducts.take(12).join(', ')),
          if (preview.ignoredProducts.length > 12)
            Text(
              'Plus ${preview.ignoredProducts.length - 12} more ignored products.',
            ),
        ],
      ],
    );
  }
}

class _BartenderExposureCard extends StatelessWidget {
  const _BartenderExposureCard({required this.summary});

  final BartenderExposureSummary summary;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '£', decimalDigits: 2);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF293037)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary.bartenderName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            '${summary.totalCocktailsSold} cocktails saved · ${currency.format(summary.totalSalesValueGbp)} exposure value',
          ),
          Text(
            '${summary.sessionsCount} weekly import${summary.sessionsCount == 1 ? '' : 's'}${summary.latestWeek == null ? '' : ' · latest ${DateFormat('dd MMM').format(summary.latestWeek!)}'}',
          ),
          if (summary.topCocktails.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Top cocktails',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: summary.topCocktails
                  .map((item) => Chip(label: Text(item)))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.invite,
    required this.roleLabel,
    required this.onShowQr,
    required this.onCopyLink,
    required this.onDelete,
    required this.onToggleLive,
  });

  final VenueInvite invite;
  final String roleLabel;
  final Future<void> Function() onShowQr;
  final Future<void> Function() onCopyLink;
  final Future<void> Function() onDelete;
  final ValueChanged<bool> onToggleLive;

  @override
  Widget build(BuildContext context) {
    final subtitle =
        'Uses ${invite.currentUses}/${invite.maxUses} · Expires ${DateFormat('d MMM').format(invite.expiresAt)}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF293037)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 420;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$roleLabel invite',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(subtitle),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onShowQr,
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text('QR code'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onCopyLink,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy link'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          invite.disabled ? 'Paused' : 'Live',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        Switch(
                          value: !invite.disabled,
                          onChanged: onToggleLive,
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          invite.disabled ? 'Paused' : 'Live',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(width: 6),
                        Switch(
                          value: !invite.disabled,
                          onChanged: onToggleLive,
                        ),
                      ],
                    ),
            ],
          );
        },
      ),
    );
  }
}

class _SalesPdfImportReviewDialog extends StatefulWidget {
  const _SalesPdfImportReviewDialog({
    required this.controller,
    required this.bytes,
    required this.sourceFileName,
    required this.session,
    required this.bartenderName,
    required this.preview,
  });

  final AppController controller;
  final Uint8List bytes;
  final String sourceFileName;
  final WeeklyConcernSession session;
  final String bartenderName;
  final SalesPdfImportPreview preview;

  @override
  State<_SalesPdfImportReviewDialog> createState() =>
      _SalesPdfImportReviewDialogState();
}

class _SalesPdfImportReviewDialogState extends State<_SalesPdfImportReviewDialog> {
  late SalesPdfImportPreview _preview;
  late Map<String, String> _quantities;
  String? _selectedReportEmployee;
  bool _isRefreshingPreview = false;

  @override
  void initState() {
    super.initState();
    _preview = widget.preview;
    _selectedReportEmployee = widget.preview.matchedReportName;
    _quantities = {
      for (final entry in widget.preview.entries)
        entry.cocktailId: entry.quantitySold.toString(),
    };
  }

  bool get _canSave {
    if (_preview.entries.isEmpty) {
      return false;
    }
    for (final entry in _preview.entries) {
      final raw = (_quantities[entry.cocktailId] ?? '').trim();
      final parsed = int.tryParse(raw);
      if (parsed == null || parsed < 0) {
        return false;
      }
    }
    return true;
  }

  List<BartenderSalesEntry> get _editedEntries {
    return _preview.entries.map((entry) {
      final rawQuantity = _quantities[entry.cocktailId] ?? '';
      final parsedQuantity = int.tryParse(rawQuantity.trim());
      final quantity = parsedQuantity == null || parsedQuantity < 0
          ? entry.quantitySold
          : parsedQuantity;
      return BartenderSalesEntry(
        cocktailId: entry.cocktailId,
        cocktailName: entry.cocktailName,
        quantitySold: quantity,
        salesValueGbp: entry.salesValueGbp,
      );
    }).where((entry) => entry.quantitySold > 0).toList();
  }

  Future<void> _reloadPreviewForEmployee(String? employeeName) async {
    setState(() => _isRefreshingPreview = true);
    try {
      final refreshed = widget.controller.importBartenderSalesPdf(
        bytes: widget.bytes,
        fileName: widget.sourceFileName,
        weekId: widget.session.id,
        bartenderName: widget.bartenderName,
        reportEmployeeNameOverride: employeeName,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _preview = refreshed;
        _selectedReportEmployee = employeeName;
        _quantities = {
          for (final entry in refreshed.entries)
            entry.cocktailId: entry.quantitySold.toString(),
        };
      });
    } finally {
      if (mounted) {
        setState(() => _isRefreshingPreview = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Review PDF sales import'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_preview.availableReportEmployees.isNotEmpty) ...[
                DropdownButtonFormField<String?>(
                  initialValue: _selectedReportEmployee,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Use selected bartender name'),
                    ),
                    ..._preview.availableReportEmployees.map(
                      (name) => DropdownMenuItem<String?>(
                        value: name,
                        child: Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: _isRefreshingPreview
                      ? null
                      : (value) => _reloadPreviewForEmployee(value),
                  decoration: const InputDecoration(
                    labelText: 'Report employee to match',
                    helperText:
                        'Choose the employee name from the PDF if it differs from the bartender account name.',
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_isRefreshingPreview)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: LinearProgressIndicator(),
                ),
              _SalesPdfImportPreviewCard(
                preview: _preview,
                sessionLabel: widget.session.label,
                overrideQuantities: _quantities,
                showEditableQuantities: true,
                onQuantityChanged: (update) {
                  setState(() {
                    _quantities[update.cocktailId] = update.quantityText;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canSave
              ? () => Navigator.of(context).pop(
                    _SalesPdfReviewResult(entries: _editedEntries),
                  )
              : null,
          child: const Text('Save sales'),
        ),
      ],
    );
  }
}

class _SalesPdfReviewResult {
  const _SalesPdfReviewResult({this.entries = const []});

  final List<BartenderSalesEntry> entries;
}

class _EditableSalesQuantityRow extends StatelessWidget {
  const _EditableSalesQuantityRow({
    required this.cocktailId,
    required this.cocktailName,
    required this.quantityText,
    this.onChanged,
  });

  final String cocktailId;
  final String cocktailName;
  final String quantityText;
  final ValueChanged<_EditedSalesQuantity>? onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final quantityField = SizedBox(
          width: constraints.maxWidth < 360 ? double.infinity : 108,
          child: TextFormField(
            initialValue: quantityText,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Qty',
              isDense: true,
            ),
            onChanged: (value) {
              onChanged?.call(
                _EditedSalesQuantity(
                  cocktailId: cocktailId,
                  quantityText: value,
                ),
              );
            },
          ),
        );

        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cocktailName,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 10),
              quantityField,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                cocktailName,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(width: 12),
            quantityField,
          ],
        );
      },
    );
  }
}

class _EditedSalesQuantity {
  const _EditedSalesQuantity({
    required this.cocktailId,
    required this.quantityText,
  });

  final String cocktailId;
  final String quantityText;
}

class _DataLine extends StatelessWidget {
  const _DataLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 360) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(value),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              Expanded(child: Text(value)),
            ],
          );
        },
      ),
    );
  }
}
