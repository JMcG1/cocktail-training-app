import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

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
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Review PDF sales import'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: SalesPdfImportPreviewCard(
                preview: preview,
                sessionLabel: session.label,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: preview.hasEntries
                  ? () => Navigator.of(context).pop(true)
                  : null,
              child: const Text('Save sales'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        widget.controller.saveBartenderSales(
          weekId: session.id,
          bartenderName: bartenderName,
          entries: preview.entries,
        );
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved ${preview.entries.length} cocktail sales lines for $bartenderName.',
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
    final varianceByBartender =
        dashboard.potentialVarianceByBartender.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
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
        if (!widget.controller.usingFirebase) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Invite links, live joins, and saved team results need Firebase mode. In demo mode this area stays local to the current browser session.',
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
                  'Create invite',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (!widget.controller.usingFirebase)
                  const Text(
                    'Switch the deployed build to Firebase mode when you want live invites and join links.',
                  )
                else ...[
                  const Text(
                    'Invite links are venue-scoped and already decide whether the new joiner becomes a bartender or a manager.',
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
                      (invite) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${_roleLabel(invite.role)} invite'),
                        subtitle: Text(
                          'Uses ${invite.currentUses}/${invite.maxUses} · Expires ${DateFormat('d MMM').format(invite.expiresAt)}',
                        ),
                        trailing: SizedBox(
                          width: 220,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                onPressed: () async {
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
                                icon: const Icon(Icons.qr_code_2),
                                tooltip: 'Show invite QR code',
                              ),
                              IconButton(
                                onPressed: () async {
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
                                icon: const Icon(Icons.copy),
                                tooltip: 'Copy invite link',
                              ),
                              IconButton(
                                onPressed: () async {
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
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Delete invite',
                              ),
                              Switch(
                                value: !invite.disabled,
                                onChanged: (value) async {
                                  await widget.controller
                                      .setVenueInviteDisabled(
                                        inviteId: invite.id,
                                        disabled: !value,
                                      );
                                  if (mounted) {
                                    setState(() {});
                                  }
                                },
                              ),
                            ],
                          ),
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
                  'Launch a live QR quiz focused on spec measures for cocktails that use the ingredients you are worried about.',
                ),
                const SizedBox(height: 16),
                if (!widget.controller.usingFirebase)
                  const Text(
                    'Switch the deployed build to Firebase mode to launch shareable surprise quizzes.',
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
                      'Pick at least one ingredient, for example vodka, before launching the quiz.',
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
      ],
    );
  }
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

class SalesPdfImportPreviewCard extends StatelessWidget {
  const SalesPdfImportPreviewCard({
    super.key,
    required this.preview,
    required this.sessionLabel,
  });

  final SalesPdfImportPreview preview;
  final String sessionLabel;

  @override
  Widget build(BuildContext context) {
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
          ...preview.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('${entry.cocktailName} · ${entry.quantitySold}'),
            ),
          ),
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

class _DataLine extends StatelessWidget {
  const _DataLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
