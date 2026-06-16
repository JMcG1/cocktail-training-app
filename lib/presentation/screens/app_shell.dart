import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/browser_app_recovery.dart';
import '../../core/utils/browser_connectivity.dart';
import '../../core/utils/bundled_cocktail_catalog_loader.dart';
import '../../core/utils/commodity_csv_ingredient_importer.dart';
import '../../data/firestore/firestore_serializers.dart';
import '../../domain/models/models.dart';
import '../controllers/app_controller.dart';

String? sessionIdFromUri(Uri uri) {
  final pathSegments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  return uri.queryParameters['session'] ??
      (pathSegments.length >= 2 && pathSegments.first == 'quiz'
          ? pathSegments[1]
          : null);
}

class InviteRouteData {
  const InviteRouteData({required this.venueId, required this.inviteId});

  final String venueId;
  final String inviteId;
}

InviteRouteData? inviteRouteFromUri(Uri uri) {
  final pathSegments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (pathSegments.length >= 3 && pathSegments.first == 'join') {
    return InviteRouteData(venueId: pathSegments[1], inviteId: pathSegments[2]);
  }
  final venueId = uri.queryParameters['venue'];
  final inviteId = uri.queryParameters['invite'];
  if ((venueId ?? '').isNotEmpty && (inviteId ?? '').isNotEmpty) {
    return InviteRouteData(venueId: venueId!, inviteId: inviteId!);
  }
  return null;
}

Uri inviteLinkUriFromBase(Uri baseUri, VenueInvite invite) {
  return baseUri.replace(
    queryParameters: {'venue': invite.venueId, 'invite': invite.id},
    fragment: null,
  );
}

Uri quizLinkUriFromBase(Uri baseUri, QuizSession session) {
  final preservedSegments = baseUri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  return baseUri.replace(
    pathSegments: [...preservedSegments, 'quiz', session.id],
    queryParameters: null,
    fragment: null,
  );
}

String approvedRecipesExportJson(List<CocktailRecipe> recipes) {
  return const JsonEncoder.withIndent('  ').convert(
    recipes
        .map(
          (recipe) => {
            'id': recipe.id,
            ...FirestoreSerializers.recipeToMap(recipe),
          },
        )
        .toList(),
  );
}

String weeklyResultsExportJson(List<QuizAttempt> attempts) {
  return const JsonEncoder.withIndent('  ').convert(
    attempts
        .map(
          (attempt) => {
            'id': attempt.id,
            ...FirestoreSerializers.quizAttemptToMap(attempt),
          },
        )
        .toList(),
  );
}

Future<void> showShareLinkDialog({
  required BuildContext context,
  required String title,
  required String url,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(url, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: QrImageView(
              data: url,
              version: QrVersions.auto,
              size: 180,
              backgroundColor: Colors.white,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (!context.mounted) {
              return;
            }
            Navigator.of(context).pop();
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Link copied.')));
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copy link'),
        ),
      ],
    ),
  );
}

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final pathSegments = Uri.base.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    final sessionId = sessionIdFromUri(Uri.base);
    final inviteRoute = inviteRouteFromUri(Uri.base);

    if (pathSegments.isNotEmpty &&
        pathSegments.first == 'quiz' &&
        sessionId == null) {
      return const HelpfulRouteScreen();
    }
    if (sessionId != null) {
      if (controller.currentUser == null) {
        return const QuizSignInRequiredScreen();
      }
      return BartenderQuizScreen(controller: controller, sessionId: sessionId);
    }
    if (inviteRoute != null) {
      return InviteJoinScreen(controller: controller, inviteRoute: inviteRoute);
    }
    if (controller.canAccessManagerWorkflows) {
      return ManagerWorkspace(controller: controller);
    }
    if (controller.isBartenderAuthenticated) {
      return TrainingWorkspace(controller: controller);
    }
    return LandingScreen(controller: controller, onOpenTraining: () {});
  }
}

class HelpfulRouteScreen extends StatelessWidget {
  const HelpfulRouteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.link_off, size: 40),
                    const SizedBox(height: 16),
                    Text(
                      'This quiz link is incomplete',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Open the full quiz link from your manager or return to the Cocktail Training login page.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class QuizSignInRequiredScreen extends StatelessWidget {
  const QuizSignInRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 40),
                    const SizedBox(height: 16),
                    Text(
                      'Sign in to open this quiz',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Quiz results only save against signed-in staff accounts. Log in with your venue email, then reopen the link if needed.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LandingScreen extends StatefulWidget {
  const LandingScreen({
    super.key,
    required this.controller,
    required this.onOpenTraining,
  });

  final AppController controller;
  final VoidCallback onOpenTraining;

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  late final TextEditingController _emailController = TextEditingController(
    text: widget.controller.isDemoAuthMode
        ? widget.controller.demoManagerEmail
        : '',
  );
  late final TextEditingController _passwordController = TextEditingController(
    text: widget.controller.isDemoAuthMode
        ? widget.controller.demoManagerPassword
        : '',
  );
  final TextEditingController _ownerNameController = TextEditingController();
  final TextEditingController _ownerVenueController = TextEditingController();
  final TextEditingController _ownerEmailController = TextEditingController();
  final TextEditingController _ownerPasswordController =
      TextEditingController();
  bool _showOwnerSetup = false;
  bool _showSignInHelp = false;
  bool _showTechnicalDetails = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _ownerNameController.dispose();
    _ownerVenueController.dispose();
    _ownerEmailController.dispose();
    _ownerPasswordController.dispose();
    super.dispose();
  }

  Future<void> _copyDiagnostics() async {
    final diagnostics = BundledCocktailCatalogLoader.lastDiagnostics;
    final text = [
      'build=${widget.controller.buildMarker}',
      'version=${widget.controller.appVersionLabel}',
      'mode=${widget.controller.runtimeModeLabel}',
      'online=${BrowserConnectivity.isOnline()}',
      'cocktails=${widget.controller.recipes.length}',
      'batches=${widget.controller.batches.length}',
      'catalogLoaded=${diagnostics.loaded}',
      'catalogSource=${diagnostics.source}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Diagnostics copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final statusColors =
        Theme.of(context).extension<AppStatusColors>() ??
        const AppStatusColors(
          highlight: Color(0xFFE7C67A),
          warning: Color(0xFFF3A35C),
          accent: Color(0xFF54C7B8),
        );
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0E1113), Color(0xFF12181B), Color(0xFF1A2325)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  alignment: WrapAlignment.center,
                  children: [
                    SizedBox(
                      width: 520,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cocktail Training',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineLarge,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Sign in with your existing Cocktail Training account to study approved specs, batches, and quiz progress.',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              const SizedBox(height: 24),
                              TextField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _passwordController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'Password',
                                ),
                              ),
                              if (widget.controller.errorMessage != null) ...[
                                const SizedBox(height: 14),
                                Text(
                                  widget.controller.errorMessage!,
                                  style: TextStyle(color: statusColors.warning),
                                ),
                              ],
                              if (widget.controller.successMessage != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  widget.controller.successMessage!,
                                  style: TextStyle(color: statusColors.accent),
                                ),
                              ],
                              const SizedBox(height: 18),
                              ElevatedButton(
                                onPressed: widget.controller.isBusy
                                    ? null
                                    : () async {
                                        try {
                                          await widget.controller.signInManager(
                                            email: _emailController.text.trim(),
                                            password: _passwordController.text,
                                          );
                                        } catch (_) {}
                                      },
                                child: widget.controller.isBusy
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Log in'),
                              ),
                              const SizedBox(height: 10),
                              TextButton(
                                onPressed: widget.controller.isBusy
                                    ? null
                                    : () async {
                                        final email = _emailController.text
                                            .trim();
                                        if (email.isEmpty) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Add your email first so we know where to send the reset link.',
                                              ),
                                            ),
                                          );
                                          return;
                                        }
                                        try {
                                          await widget.controller
                                              .sendPasswordReset(email: email);
                                        } catch (_) {}
                                      },
                                child: const Text(
                                  'Forgot password? Send reset link',
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Access is invite-only. Managers create bartender invites, and the invite decides the role automatically.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 18),
                              TextButton(
                                onPressed: () => setState(
                                  () => _showSignInHelp = !_showSignInHelp,
                                ),
                                child: Text(
                                  _showSignInHelp
                                      ? 'Hide sign-in help'
                                      : 'Having trouble signing in?',
                                ),
                              ),
                              if (_showSignInHelp) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'If the page looks out of date or sign-in gets stuck, refresh the app first. Only clear saved app data if support asks you to.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    OutlinedButton(
                                      onPressed: () async {
                                        await BrowserAppRecovery.refreshApp();
                                      },
                                      child: const Text('Refresh app'),
                                    ),
                                    OutlinedButton(
                                      onPressed: () async {
                                        await BrowserAppRecovery.clearSavedAppData();
                                      },
                                      child: const Text('Clear saved app data'),
                                    ),
                                    TextButton(
                                      onPressed: () => setState(
                                        () => _showTechnicalDetails =
                                            !_showTechnicalDetails,
                                      ),
                                      child: Text(
                                        _showTechnicalDetails
                                            ? 'Hide technical details'
                                            : 'Show technical details',
                                      ),
                                    ),
                                  ],
                                ),
                                if (_showTechnicalDetails) ...[
                                  const SizedBox(height: 12),
                                  TextButton(
                                    onPressed: _copyDiagnostics,
                                    child: const Text('Copy technical details'),
                                  ),
                                  const SizedBox(height: 12),
                                  _BuildMarkerSummary(
                                    buildMarker: widget.controller.buildMarker,
                                    appVersionLabel:
                                        widget.controller.appVersionLabel,
                                    catalogPathLabel:
                                        widget.controller.catalogPathLabel,
                                    visibleRecipeCount:
                                        widget.controller.recipes.length,
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 520,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Approved learning library',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Everything here is part of the approved training library for your venue, so bartenders and managers can study the same up-to-date specs before service.',
                              ),
                              const SizedBox(height: 18),
                              _InfoMetric(
                                label: 'Approved cocktails',
                                value: '${widget.controller.recipes.length}',
                              ),
                              const SizedBox(height: 12),
                              _InfoMetric(
                                label: 'Approved batches',
                                value: '${widget.controller.batches.length}',
                              ),
                              const SizedBox(height: 18),
                              if (widget.controller.allowOwnerBootstrap) ...[
                                SwitchListTile.adaptive(
                                  value: _showOwnerSetup,
                                  onChanged: (value) =>
                                      setState(() => _showOwnerSetup = value),
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Show owner/admin setup'),
                                  subtitle: const Text(
                                    'Use this only when a venue still needs first-time owner setup.',
                                  ),
                                ),
                                if (_showOwnerSetup) ...[
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _ownerNameController,
                                    decoration: const InputDecoration(
                                      labelText: 'Owner/admin name',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _ownerVenueController,
                                    decoration: const InputDecoration(
                                      labelText: 'Venue name',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _ownerEmailController,
                                    decoration: const InputDecoration(
                                      labelText: 'Owner/admin email',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _ownerPasswordController,
                                    obscureText: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Password',
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  OutlinedButton(
                                    onPressed: widget.controller.isBusy
                                        ? null
                                        : () async {
                                            try {
                                              await widget.controller
                                                  .createManagerAccount(
                                                    email: _ownerEmailController
                                                        .text
                                                        .trim(),
                                                    password:
                                                        _ownerPasswordController
                                                            .text,
                                                    displayName:
                                                        _ownerNameController
                                                            .text
                                                            .trim(),
                                                    venueName:
                                                        _ownerVenueController
                                                            .text
                                                            .trim(),
                                                  );
                                            } catch (_) {}
                                          },
                                    child: const Text(
                                      'Create owner/admin workspace',
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class InviteJoinScreen extends StatefulWidget {
  const InviteJoinScreen({
    super.key,
    required this.controller,
    required this.inviteRoute,
  });

  final AppController controller;
  final InviteRouteData inviteRoute;

  @override
  State<InviteJoinScreen> createState() => _InviteJoinScreenState();
}

class _InviteJoinScreenState extends State<InviteJoinScreen> {
  late Future<VenueInvite?> _inviteFuture = widget.controller.fetchVenueInvite(
    venueId: widget.inviteRoute.venueId,
    inviteId: widget.inviteRoute.inviteId,
  );
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _copyJoinDiagnostics() async {
    final diagnostics = [
      'build=${widget.controller.buildMarker}',
      'url=${Uri.base}',
      'venueId=${widget.inviteRoute.venueId}',
      'inviteId=${widget.inviteRoute.inviteId}',
      'error=${widget.controller.errorMessage ?? '<none>'}',
      'success=${widget.controller.successMessage ?? '<none>'}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: diagnostics));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Join diagnostics copied.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: FutureBuilder<VenueInvite?>(
              future: _inviteFuture,
              builder: (context, snapshot) {
                final invite = snapshot.data;
                final inviteMissing =
                    !snapshot.hasError &&
                    snapshot.connectionState == ConnectionState.done &&
                    invite == null;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Join Cocktail Training',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          snapshot.hasError
                              ? 'We could not load this invite right now.'
                              : inviteMissing
                              ? 'This invite link does not exist or is no longer available.'
                              : invite == null
                              ? 'This invite will create the role attached to the link.'
                              : 'This invite creates a ${invite.role.name} account for the venue.',
                        ),
                        const SizedBox(height: 18),
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) ...[
                          const LinearProgressIndicator(),
                          const SizedBox(height: 18),
                        ],
                        if (invite != null) ...[
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(label: Text('Role: ${invite.role.name}')),
                              Chip(
                                label: Text(
                                  invite.disabled
                                      ? 'Paused'
                                      : invite.isExpired
                                      ? 'Expired'
                                      : invite.isOverused
                                      ? 'Fully used'
                                      : 'Live',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                        ],
                        if (snapshot.hasError) ...[
                          Text(
                            'Refresh the invite or ask your manager to copy a fresh link.',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).extension<AppStatusColors>()?.warning,
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Display name',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'Email'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                          ),
                        ),
                        if (widget.controller.errorMessage != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            widget.controller.errorMessage!,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).extension<AppStatusColors>()?.warning,
                            ),
                          ),
                        ],
                        if (widget.controller.successMessage != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            widget.controller.successMessage!,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).extension<AppStatusColors>()?.accent,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        ElevatedButton(
                          onPressed:
                              widget.controller.isBusy ||
                                  snapshot.connectionState ==
                                      ConnectionState.waiting ||
                                  snapshot.hasError ||
                                  invite == null ||
                                  !invite.isRedeemable
                              ? null
                              : () async {
                                  try {
                                    await widget.controller.redeemVenueInvite(
                                      venueId: widget.inviteRoute.venueId,
                                      inviteId: widget.inviteRoute.inviteId,
                                      email: _emailController.text.trim(),
                                      password: _passwordController.text,
                                      displayName: _nameController.text.trim(),
                                    );
                                  } catch (_) {}
                                },
                          child: const Text('Join venue'),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _inviteFuture = widget.controller
                                  .fetchVenueInvite(
                                    venueId: widget.inviteRoute.venueId,
                                    inviteId: widget.inviteRoute.inviteId,
                                  );
                            });
                          },
                          child: const Text('Refresh invite'),
                        ),
                        TextButton(
                          onPressed: _copyJoinDiagnostics,
                          child: const Text('Copy join diagnostics'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class TrainingWorkspace extends StatelessWidget {
  const TrainingWorkspace({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return _LearningWorkspace(controller: controller, showManagerTools: false);
  }
}

class ManagerWorkspace extends StatefulWidget {
  const ManagerWorkspace({super.key, required this.controller});

  final AppController controller;

  @override
  State<ManagerWorkspace> createState() => _ManagerWorkspaceState();
}

class _ManagerWorkspaceState extends State<ManagerWorkspace> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.warmWorkspaceDataIfNeeded());
  }

  @override
  Widget build(BuildContext context) {
    return _LearningWorkspace(
      controller: widget.controller,
      showManagerTools: true,
    );
  }
}

class _LearningWorkspace extends StatefulWidget {
  const _LearningWorkspace({
    required this.controller,
    required this.showManagerTools,
  });

  final AppController controller;
  final bool showManagerTools;

  @override
  State<_LearningWorkspace> createState() => _LearningWorkspaceState();
}

class _LearningWorkspaceState extends State<_LearningWorkspace> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <_WorkspacePage>[
      _WorkspacePage(
        title: 'Library',
        body: widget.showManagerTools
            ? ManagerLibraryTab(controller: widget.controller)
            : CocktailLibraryTab(controller: widget.controller),
        destination: const NavigationDestination(
          icon: Icon(Icons.local_bar_outlined),
          selectedIcon: Icon(Icons.local_bar),
          label: 'Library',
        ),
      ),
      _WorkspacePage(
        title: 'Study',
        body: StudyModeTab(controller: widget.controller),
        destination: const NavigationDestination(
          icon: Icon(Icons.menu_book_outlined),
          selectedIcon: Icon(Icons.menu_book),
          label: 'Study',
        ),
      ),
      _WorkspacePage(
        title: 'Quiz',
        body: QuizModeTab(controller: widget.controller),
        destination: const NavigationDestination(
          icon: Icon(Icons.quiz_outlined),
          selectedIcon: Icon(Icons.quiz),
          label: 'Quiz',
        ),
      ),
      _WorkspacePage(
        title: 'Progress',
        body: ProgressTab(
          controller: widget.controller,
          managerView: widget.showManagerTools,
        ),
        destination: const NavigationDestination(
          icon: Icon(Icons.insights_outlined),
          selectedIcon: Icon(Icons.insights),
          label: 'Progress',
        ),
      ),
      if (widget.showManagerTools)
        _WorkspacePage(
          title: 'Team',
          body: ManagerTeamTab(controller: widget.controller),
          destination: const NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Team',
          ),
        ),
    ];
    final page = pages[_selectedIndex];
    return Scaffold(
      appBar: AppBar(
        title: Text('Cocktail Training · ${page.title}'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'settings':
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('Settings')),
                        body: SettingsTab(
                          controller: widget.controller,
                          isOnline: BrowserConnectivity.isOnline(),
                        ),
                      ),
                    ),
                  );
                  break;
                case 'logout':
                  await widget.controller.signOut();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'settings', child: Text('Settings')),
              PopupMenuItem(value: 'logout', child: Text('Log out')),
            ],
          ),
        ],
      ),
      body: SafeArea(child: page.body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (value) =>
            setState(() => _selectedIndex = value),
        destinations: pages.map((item) => item.destination).toList(),
      ),
    );
  }
}

class _WorkspacePage {
  const _WorkspacePage({
    required this.title,
    required this.body,
    required this.destination,
  });

  final String title;
  final Widget body;
  final NavigationDestination destination;
}

class ManagerLibraryTab extends StatelessWidget {
  const ManagerLibraryTab({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return CocktailLibraryTab(
      controller: controller,
      headerTitle: 'Approved cocktail library',
      headerSubtitle:
          'Managers see the same approved cocktail and batch learning data as bartenders.',
      showPrices: true,
    );
  }
}

class CocktailLibraryTab extends StatefulWidget {
  const CocktailLibraryTab({
    super.key,
    required this.controller,
    this.headerTitle = 'Approved cocktail library',
    this.headerSubtitle =
        'Browse approved cocktails only. Open a card for ingredients, garnish, glassware, method, and linked batch details.',
    this.showPrices = false,
  });

  final AppController controller;
  final String headerTitle;
  final String headerSubtitle;
  final bool showPrices;

  @override
  State<CocktailLibraryTab> createState() => _CocktailLibraryTabState();
}

class _CocktailLibraryTabState extends State<CocktailLibraryTab> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = widget.controller.searchRecipes(_searchController.text);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _HeaderCard(
          title: widget.headerTitle,
          subtitle: widget.headerSubtitle,
          trailing: _InfoMetric(
            label: 'Cocktails',
            value: '${widget.controller.recipes.length}',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Search cocktails, categories, or ingredients',
          ),
        ),
        const SizedBox(height: 16),
        if (results.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('No approved cocktails matched that search yet.'),
            ),
          ),
        ...results.map(
          (recipe) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _CocktailCard(
              recipe: recipe,
              showPrice: widget.showPrices,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CocktailDetailScreen(
                    recipe: recipe,
                    batches: widget.controller.batches,
                    showPrice: widget.showPrices,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class StudyModeTab extends StatefulWidget {
  const StudyModeTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<StudyModeTab> createState() => _StudyModeTabState();
}

class _StudyModeTabState extends State<StudyModeTab> {
  int _index = 0;
  bool _showAnswers = false;

  @override
  Widget build(BuildContext context) {
    final recipes = widget.controller.recipes;
    if (recipes.isEmpty) {
      return const Center(
        child: Text(
          'Approved cocktails will appear here once the library loads.',
        ),
      );
    }
    final recipe = recipes[_index % recipes.length];
    final compactLayout = MediaQuery.sizeOf(context).height < 760;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _HeaderCard(
          title: 'Study mode',
          subtitle:
              'Use this quick mobile-friendly study view to work through specs, garnish, glassware, method, and linked batch knowledge.',
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CocktailHero(
                  recipe: recipe,
                  imageHeight: compactLayout ? 140 : 220,
                ),
                SizedBox(height: compactLayout ? 12 : 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (recipe.category.trim().isNotEmpty)
                      Chip(label: Text(recipe.category)),
                    Chip(
                      label: Text(
                        recipe.glassware.isEmpty
                            ? 'Glassware pending'
                            : recipe.glassware,
                      ),
                    ),
                    Chip(
                      label: Text(
                        recipe.garnish.isEmpty
                            ? 'Garnish pending'
                            : recipe.garnish,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  recipe.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                SizedBox(height: compactLayout ? 8 : 12),
                Text(
                  recipe.notes.isEmpty
                      ? 'Open the answer panel when you want the full spec.'
                      : recipe.notes,
                  maxLines: compactLayout ? 3 : null,
                  overflow: compactLayout ? TextOverflow.ellipsis : null,
                ),
                SizedBox(height: compactLayout ? 12 : 16),
                ElevatedButton(
                  onPressed: () => setState(() => _showAnswers = !_showAnswers),
                  child: Text(
                    _showAnswers ? 'Hide answers' : 'Reveal ingredients',
                  ),
                ),
                if (_showAnswers) ...[
                  const SizedBox(height: 16),
                  _RecipeSpecBlock(
                    recipe: recipe,
                    batches: widget.controller.batches,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() {
                  _showAnswers = false;
                  _index = (_index - 1) % recipes.length;
                }),
                child: const Text('Previous'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () => setState(() {
                  _showAnswers = false;
                  _index = (_index + 1) % recipes.length;
                }),
                child: const Text('Next cocktail'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class QuizModeTab extends StatefulWidget {
  const QuizModeTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<QuizModeTab> createState() => _QuizModeTabState();
}

class _QuizModeTabState extends State<QuizModeTab> {
  QuizSession? _activeSession;
  Map<String, String> _answers = {};
  QuizAttempt? _completedAttempt;
  QuizFocus _selectedPracticeFocus = QuizFocus.specs;

  @override
  Widget build(BuildContext context) {
    final bartenderName =
        widget.controller.currentUser?.displayName ?? 'Bartender';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _HeaderCard(
          title: 'Quiz mode',
          subtitle:
              'Questions are generated from the approved cocktail and batch specs only. Batch amounts are treated like ingredients.',
        ),
        const SizedBox(height: 16),
        if (!widget.controller.usingFirebase) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Demo mode keeps quizzes on this device only. Shareable quiz links and QR codes appear when the app is running in Firebase mode.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_completedAttempt != null) ...[
          _AttemptSummaryCard(attempt: _completedAttempt!),
          const SizedBox(height: 16),
        ],
        if (_activeSession == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Start a quick quiz',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _selectedPracticeFocus == QuizFocus.specs
                        ? 'Specs quiz focuses on measures and batch amounts from approved recipes.'
                        : 'Garnish and glass quiz checks service details without mixing in spec-measure questions.',
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<QuizFocus>(
                    segments: const [
                      ButtonSegment<QuizFocus>(
                        value: QuizFocus.specs,
                        label: Text('Specs'),
                      ),
                      ButtonSegment<QuizFocus>(
                        value: QuizFocus.garnishGlassware,
                        label: Text('Garnish & glass'),
                      ),
                    ],
                    selected: {_selectedPracticeFocus},
                    onSelectionChanged: (selection) {
                      setState(() {
                        _selectedPracticeFocus = selection.first;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _completedAttempt = null;
                        _answers = {};
                        _activeSession = widget.controller.generatePracticeQuiz(
                          bartenderName: bartenderName,
                          focus: _selectedPracticeFocus,
                        );
                      });
                    },
                    child: Text(
                      _selectedPracticeFocus == QuizFocus.specs
                          ? 'Start specs quiz'
                          : 'Start garnish and glass quiz',
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Column(
            children: [
              if (widget.controller.usingFirebase) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'This quiz can be shared with a live link or QR code while the session stays active.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final shareUrl = quizLinkUriFromBase(
                              Uri.base,
                              _activeSession!,
                            ).toString();
                            await showShareLinkDialog(
                              context: context,
                              title: 'Share quiz link',
                              url: shareUrl,
                            );
                          },
                          icon: const Icon(Icons.qr_code_2),
                          label: const Text('Show QR code'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _QuizSessionCard(
                session: _activeSession!,
                answers: _answers,
                onAnswerChanged: (questionId, answer) {
                  setState(() => _answers[questionId] = answer);
                },
                onSubmit: () {
                  final attempt = widget.controller.submitQuizAttempt(
                    sessionId: _activeSession!.id,
                    bartenderName: bartenderName,
                    answers: _answers,
                  );
                  setState(() {
                    _completedAttempt = attempt;
                    _activeSession = null;
                    _answers = {};
                  });
                },
              ),
            ],
          ),
      ],
    );
  }
}

class ProgressTab extends StatelessWidget {
  const ProgressTab({
    super.key,
    required this.controller,
    required this.managerView,
  });

  final AppController controller;
  final bool managerView;

  @override
  Widget build(BuildContext context) {
    final attempts = controller.quizAttempts;
    final stats = _ProgressStats.fromAttempts(
      attempts: attempts,
      recipesById: controller.recipesById,
    );
    final subtitle = managerView
        ? 'A calm read on recent learning confidence. Team-wide coaching detail lives in the Team tab.'
        : 'Your quiz history stays here so you can see what is feeling solid and what deserves a little more practice.';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _HeaderCard(title: 'Progress', subtitle: subtitle),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              title: 'Quizzes',
              value: '${stats.quizCount}',
              caption: 'Completed rounds',
            ),
            _MetricCard(
              title: 'Average score',
              value: '${stats.averageScore}%',
              caption: 'Across loaded quiz attempts',
            ),
            _MetricCard(
              title: 'Confidence',
              value: stats.confidenceLabel,
              caption: 'Friendly pulse check',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _InsightListCard(
          title: 'Cocktails to revisit',
          emptyLabel:
              'No weak cocktails yet. Start a quiz and your learning highlights will appear here.',
          items: stats.weakCocktails.entries
              .map((entry) => '${entry.key} · ${entry.value} misses')
              .toList(),
        ),
        const SizedBox(height: 16),
        _InsightListCard(
          title: 'Ingredient focus areas',
          emptyLabel:
              'Ingredient patterns will appear after a few quiz rounds.',
          items: stats.weakIngredients.entries
              .map((entry) => '${entry.key} · ${entry.value} misses')
              .toList(),
        ),
      ],
    );
  }
}

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
    if (!widget.controller.isOwnerAuthenticated) {
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
    final bartenderUsers = teamMembers
        .where((user) => user.role == UserRole.bartender && user.active)
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final selectedBartenderName =
        _surpriseBartenderName ??
        (bartenderUsers.isNotEmpty ? bartenderUsers.first.displayName : null);
    _surpriseBartenderName = selectedBartenderName;
    final totalEstimatedCostImpact = dashboard.potentialVarianceByBartender
        .values
        .fold<double>(0, (sum, value) => sum + value);

    final inviteOptions = const [UserRole.manager, UserRole.bartender];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _HeaderCard(
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
            _MetricCard(
              title: 'Team members',
              value: '${teamMembers.length}',
              caption: '$bartenderCount bartenders in this venue',
            ),
            _MetricCard(
              title: 'Average score',
              value: '${dashboard.venueAverageScore}%',
              caption: 'Across loaded team attempts',
            ),
            _MetricCard(
              title: 'Completion rate',
              value: '${dashboard.quizCompletionRate}%',
              caption: 'Weekly quiz completion',
            ),
            _MetricCard(
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
                                  if (!context.mounted) return;
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
                                tooltip: 'Delete invite link',
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
                    decoration: const InputDecoration(
                      labelText: 'Bartender',
                    ),
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
                    onPressed: _surpriseConcernNames.isEmpty ||
                            (_surpriseBartenderName ?? '').isEmpty
                        ? null
                        : () async {
                            final labelIngredients = _surpriseConcernNames
                                .take(2)
                                .join(' + ');
                            final session = widget.controller
                                .createWeeklySession(
                                  label:
                                      'Surprise quiz · ${_surpriseBartenderName!} · $labelIngredients',
                                  weekStart: DateTime.now(),
                                  concerns: _surpriseConcernNames
                                      .map(
                                        (name) => StockConcernItem(
                                          ingredientName: name,
                                        ),
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
                            if (!mounted) return;
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
                                        await widget.controller
                                            .setVenueUserActive(
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
                                        title: const Text(
                                          'Remove staff access?',
                                        ),
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
        _InsightListCard(
          title: 'Bartender average scores',
          emptyLabel:
              'Team quiz history will appear here after the first submissions.',
          items: bartenderCompletion
              .map((entry) => '${entry.key} · ${entry.value}% average')
              .toList(),
        ),
        const SizedBox(height: 16),
        _InsightListCard(
          title: 'Estimated cost impact opportunities',
          emptyLabel:
              'Estimated impact highlights will appear after quiz submissions are saved.',
          items: varianceByBartender
              .take(8)
              .map((entry) => '${entry.key} · ${currency.format(entry.value)}')
              .toList(),
        ),
        const SizedBox(height: 16),
        _InsightListCard(
          title: 'Weak cocktails',
          emptyLabel: 'No repeated cocktail misses are visible yet.',
          items: weakCocktails
              .take(8)
              .map((entry) => '${entry.key} · ${entry.value} misses')
              .toList(),
        ),
        const SizedBox(height: 16),
        _InsightListCard(
          title: 'Weak ingredient areas',
          emptyLabel: 'Ingredient trends will appear after a few quizzes.',
          items: weakIngredients
              .take(8)
              .map((entry) => '${entry.key} · ${entry.value} misses')
              .toList(),
        ),
        const SizedBox(height: 16),
        _InsightListCard(
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

class SettingsTab extends StatefulWidget {
  const SettingsTab({
    super.key,
    required this.controller,
    required this.isOnline,
  });

  final AppController controller;
  final bool isOnline;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  bool _isImporting = false;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final approvedIngredients = _approvedIngredients(controller);
    final missingIngredients = approvedIngredients
        .where((ingredient) => !ingredient.hasCompletePricing)
        .toList();
    final pricedCount = approvedIngredients
        .where((ingredient) => ingredient.hasCompletePricing)
        .length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _HeaderCard(
          title: 'Settings',
          subtitle:
              'Check app status, refresh the workspace if something looks stale, and keep ingredient cost details up to date.',
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'App status',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                _DataLine(label: 'Build', value: controller.buildMarker),
                _DataLine(label: 'Version', value: controller.appVersionLabel),
                _DataLine(label: 'Runtime', value: controller.runtimeModeLabel),
                _DataLine(
                  label: 'Backend',
                  value: controller.backendProfileLabel,
                ),
                _DataLine(
                  label: 'Venue ID',
                  value:
                      controller.currentUser?.venueId ??
                      controller.catalogPathLabel,
                ),
                _DataLine(
                  label: 'Live cocktails',
                  value: '${controller.recipes.length}',
                ),
                _DataLine(
                  label: 'Live batches',
                  value: '${controller.batches.length}',
                ),
                _DataLine(
                  label: 'Online',
                  value: widget.isOnline ? 'Yes' : 'No',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton(
                      onPressed: () async {
                        await BrowserAppRecovery.refreshApp();
                      },
                      child: const Text('Refresh app'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        await BrowserAppRecovery.clearSavedAppData();
                      },
                      child: const Text('Clear saved app data'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text: weeklyResultsExportJson(
                              controller.quizAttempts,
                            ),
                          ),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Quiz data copied.')),
                          );
                        }
                      },
                      child: const Text('Copy diagnostics'),
                    ),
                  ],
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
                  'Ingredient costs',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pre-fill bottle size and bottle price for approved cocktail ingredients from the commodity CSV, then fine-tune anything manually in the same place.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _InfoMetric(
                      label: 'Approved ingredients',
                      value: '${approvedIngredients.length}',
                    ),
                    _InfoMetric(label: 'Priced', value: '$pricedCount'),
                    _InfoMetric(
                      label: 'Missing',
                      value: '${approvedIngredients.length - pricedCount}',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: controller.canAccessAdminSetup && !_isImporting
                          ? _importCommodityCsv
                          : null,
                      icon: _isImporting
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file_outlined),
                      label: const Text('Import prices from commodity CSV'),
                    ),
                    if (!controller.canAccessAdminSetup)
                      const Text(
                        'Owner/admin access is required to change ingredient costs.',
                      ),
                  ],
                ),
                if (controller.latestCommodityIngredientImportResult !=
                    null) ...[
                  const SizedBox(height: 16),
                  _CommodityImportSummaryCard(
                    result: controller.latestCommodityIngredientImportResult!,
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Needs pricing',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  missingIngredients.isEmpty
                      ? 'Every approved ingredient has a bottle size and bottle price saved.'
                      : 'These approved ingredients still need bottle size, bottle price, or both.',
                ),
                if (missingIngredients.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...missingIngredients.map(
                    (ingredient) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MissingIngredientCostRow(
                        ingredient: ingredient,
                        canEdit: controller.canAccessAdminSetup,
                        onEdit: () => _editIngredient(ingredient),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Manual adjustments',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use manual edits to correct pack sizes, bottle prices, or anything the commodity CSV could not match cleanly.',
                ),
                const SizedBox(height: 12),
                ...approvedIngredients.map(
                  (ingredient) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _IngredientCostRow(
                      ingredient: ingredient,
                      canEdit: controller.canAccessAdminSetup,
                      onEdit: () => _editIngredient(ingredient),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Ingredient> _approvedIngredients(AppController controller) {
    final usedNames = <String>{
      for (final recipe in controller.recipes)
        ...recipe.ingredients
            .map((item) => item.ingredientName.trim())
            .where((name) => name.isNotEmpty),
      for (final batch in controller.batches)
        ...batch.ingredients
            .map((item) => item.ingredientName.trim())
            .where((name) => name.isNotEmpty),
    };
    final byKey = {
      for (final ingredient in controller.ingredients)
        _normalizeIngredientName(ingredient.name): ingredient,
    };
    final approved = [
      for (final name in usedNames)
        byKey[_normalizeIngredientName(name)] ??
            Ingredient(
              id: 'pending-${_normalizeIngredientName(name)}',
              name: name,
              bottleSizeMl: 0,
              bottleCost: 0,
            ),
    ]..sort((left, right) => left.name.compareTo(right.name));
    return approved;
  }

  Future<void> _importCommodityCsv() async {
    setState(() => _isImporting = true);
    try {
      final pick = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true,
        dialogTitle: 'Select commodity CSV',
      );
      if (!mounted || pick == null || pick.files.isEmpty) {
        return;
      }
      final file = pick.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw Exception('The selected CSV could not be read.');
      }
      final csvText = utf8.decode(bytes, allowMalformed: true);
      final result = await widget.controller
          .importIngredientCostsFromCommodityCsv(csvText);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${result.matchedIngredients.length} ingredient prices. ${result.unmatchedIngredientNames.length} still need manual entry.',
          ),
        ),
      );
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
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _editIngredient(Ingredient ingredient) async {
    final sizeController = TextEditingController(
      text: ingredient.bottleSizeMl == 0
          ? ''
          : ingredient.bottleSizeMl.toStringAsFixed(
              ingredient.bottleSizeMl.truncateToDouble() ==
                      ingredient.bottleSizeMl
                  ? 0
                  : 2,
            ),
    );
    final priceController = TextEditingController(
      text: ingredient.bottleCost == 0
          ? ''
          : ingredient.bottleCost.toStringAsFixed(2),
    );
    var isGarnish = ingredient.isGarnish;
    String? validationMessage;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Edit ${ingredient.name}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: sizeController,
                    decoration: const InputDecoration(
                      labelText: 'Bottle size (ml)',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceController,
                    decoration: const InputDecoration(
                      labelText: 'Bottle price',
                      prefixText: '£',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: isGarnish,
                    title: const Text('Mark as garnish'),
                    subtitle: const Text(
                      'Garnish items can be kept at zero bottle size and zero price.',
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        isGarnish = value;
                        validationMessage = null;
                      });
                    },
                  ),
                  if (validationMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      validationMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final rawBottleSize = sizeController.text.trim();
                    final rawBottleCost = priceController.text.trim();
                    final bottleSizeMl =
                        rawBottleSize.isEmpty
                            ? 0
                            : double.tryParse(rawBottleSize);
                    final bottleCost =
                        rawBottleCost.isEmpty
                            ? 0
                            : double.tryParse(rawBottleCost);
                    final invalidStandardIngredient =
                        !isGarnish &&
                        (bottleSizeMl == null ||
                            bottleSizeMl <= 0 ||
                            bottleCost == null ||
                            bottleCost <= 0);
                    final invalidGarnish =
                        isGarnish &&
                        (bottleSizeMl == null ||
                            bottleSizeMl < 0 ||
                            bottleCost == null ||
                            bottleCost < 0);
                    if (invalidStandardIngredient || invalidGarnish) {
                      setDialogState(() {
                        validationMessage =
                            isGarnish
                                ? 'Enter zero or a positive value for garnish bottle size and bottle price.'
                                : 'Enter a valid bottle size in ml and a bottle price above zero.';
                      });
                      return;
                    }
                    widget.controller.saveIngredient(
                      name: ingredient.name,
                      bottleSizeMl: bottleSizeMl!.toDouble(),
                      bottleCost: bottleCost!.toDouble(),
                      isGarnish: isGarnish,
                    );
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    sizeController.dispose();
    priceController.dispose();

    if (saved == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${ingredient.name} updated.')));
    }
  }
}

class CocktailDetailScreen extends StatelessWidget {
  const CocktailDetailScreen({
    super.key,
    required this.recipe,
    required this.batches,
    this.showPrice = false,
  });

  final CocktailRecipe recipe;
  final List<BatchRecipe> batches;
  final bool showPrice;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(recipe.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CocktailHero(recipe: recipe, imageHeight: 240),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (recipe.category.trim().isNotEmpty)
                        Chip(label: Text(recipe.category)),
                      if (recipe.glassware.trim().isNotEmpty)
                        Chip(label: Text(recipe.glassware)),
                      if (recipe.garnish.trim().isNotEmpty)
                        Chip(label: Text(recipe.garnish)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _RecipeSpecBlock(
                    recipe: recipe,
                    batches: batches,
                    showPrice: showPrice,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BartenderQuizScreen extends StatefulWidget {
  const BartenderQuizScreen({
    super.key,
    required this.controller,
    required this.sessionId,
  });

  final AppController controller;
  final String sessionId;

  @override
  State<BartenderQuizScreen> createState() => _BartenderQuizScreenState();
}

class _BartenderQuizScreenState extends State<BartenderQuizScreen> {
  QuizSession? _session;
  bool _loading = true;
  String? _error;
  final Map<String, String> _answers = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final session =
          widget.controller.findQuizSession(widget.sessionId) ??
          await widget.controller.fetchQuizSession(widget.sessionId);
      if (!mounted) {
        return;
      }
      setState(() {
        _session = session;
        _loading = false;
        if (session == null) {
          _error = 'This quiz is no longer available.';
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bartenderName =
        widget.controller.currentUser?.displayName ?? 'Bartender';
    return Scaffold(
      appBar: AppBar(title: const Text('Cocktail quiz')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                ),
              )
            : _QuizSessionCard(
                session: _session!,
                answers: _answers,
                onAnswerChanged: (questionId, answer) {
                  setState(() => _answers[questionId] = answer);
                },
                onSubmit: () {
                  final attempt = widget.controller.submitQuizAttempt(
                    sessionId: _session!.id,
                    bartenderName: bartenderName,
                    answers: _answers,
                  );
                  showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Quiz complete'),
                      content: Text(
                        'Score: ${attempt.scorePercent}%\n\n${attempt.encouragement}',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _QuizSessionCard extends StatelessWidget {
  const _QuizSessionCard({
    required this.session,
    required this.answers,
    required this.onAnswerChanged,
    required this.onSubmit,
  });

  final QuizSession session;
  final Map<String, String> answers;
  final void Function(String questionId, String answer) onAnswerChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final allAnswered = session.questions.every(
      (question) => (answers[question.id] ?? '').isNotEmpty,
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '${session.questions.length} approved questions · ${_quizFocusLabel(session.focus)}',
                ),
                const SizedBox(height: 20),
              ...session.questions.map(
                (question) => Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        question.prompt,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      ...question.options.map(
                        (option) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => onAnswerChanged(question.id, option),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: answers[question.id] == option
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                            .colorScheme
                                            .outlineVariant,
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    answers[question.id] == option
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: Text(option)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: allAnswered ? onSubmit : null,
                child: const Text('Submit quiz'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttemptSummaryCard extends StatelessWidget {
  const _AttemptSummaryCard({required this.attempt});

  final QuizAttempt attempt;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Latest result',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              '${attempt.scorePercent}%',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 10),
            Text(attempt.encouragement),
          ],
        ),
      ),
    );
  }
}

class _RecipeSpecBlock extends StatelessWidget {
  const _RecipeSpecBlock({
    required this.recipe,
    required this.batches,
    this.showPrice = false,
  });

  final CocktailRecipe recipe;
  final List<BatchRecipe> batches;
  final bool showPrice;

  @override
  Widget build(BuildContext context) {
    final linkedBatches = recipe.ingredients
        .where((ingredient) => ingredient.isBatchReference)
        .map(
          (ingredient) => batches.cast<BatchRecipe?>().firstWhere(
            (batch) => batch != null && batch.id == ingredient.linkedBatchId,
            orElse: () => null,
          ),
        )
        .whereType<BatchRecipe>()
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showPrice)
          _SpecLine(
            label: 'Price',
            value: recipe.priceGbp == null
                ? 'Missing from Signature Cocktails price list'
                : _formatPriceGbp(recipe.priceGbp!),
          ),
        _SpecLine(label: 'Method', value: recipe.method),
        _SpecLine(label: 'Glassware', value: recipe.glassware),
        _SpecLine(label: 'Garnish', value: recipe.garnish),
        if (recipe.notes.trim().isNotEmpty)
          _SpecLine(label: 'Notes', value: recipe.notes),
        const SizedBox(height: 18),
        Text('Ingredients', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        ...recipe.ingredients.map(
          (ingredient) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _IngredientLine(ingredient: ingredient),
          ),
        ),
        if (linkedBatches.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Linked batches',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          ...linkedBatches.map(
            (batch) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        batch.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        batch.totalBatchVolumeMl == null
                            ? 'Batch total not listed'
                            : 'Batch total: ${batch.totalBatchVolumeMl!.toStringAsFixed(0)}ml',
                      ),
                      const SizedBox(height: 10),
                      ...batch.ingredients.map(
                        (ingredient) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _IngredientLine(ingredient: ingredient),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CocktailCard extends StatelessWidget {
  const _CocktailCard({
    required this.recipe,
    required this.onTap,
    this.showPrice = false,
  });

  final CocktailRecipe recipe;
  final VoidCallback onTap;
  final bool showPrice;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CocktailImage(recipe: recipe, size: 88),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (recipe.category.trim().isNotEmpty)
                      Text(
                        recipe.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    if (showPrice) ...[
                      const SizedBox(height: 8),
                      Text(
                        recipe.priceGbp == null
                            ? 'Price missing from source list'
                            : _formatPriceGbp(recipe.priceGbp!),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      recipe.ingredients
                          .take(3)
                          .map((item) => item.ingredientName)
                          .join(' • '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatPriceGbp(double priceGbp) {
  return NumberFormat.currency(
    locale: 'en_GB',
    symbol: '£',
    decimalDigits: 2,
  ).format(priceGbp);
}

class _CocktailHero extends StatelessWidget {
  const _CocktailHero({required this.recipe, required this.imageHeight});

  final CocktailRecipe recipe;
  final double imageHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CocktailImage(
          recipe: recipe,
          size: double.infinity,
          height: imageHeight,
        ),
        const SizedBox(height: 14),
        Text(recipe.name, style: Theme.of(context).textTheme.headlineSmall),
      ],
    );
  }
}

class _CocktailImage extends StatelessWidget {
  const _CocktailImage({required this.recipe, required this.size, this.height});

  final CocktailRecipe recipe;
  final double size;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final imagePath = recipe.imageAssetPath;
    final image = imagePath == null || imagePath.isEmpty
        ? const _ImagePlaceholder()
        : ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              imagePath,
              width: size == double.infinity ? null : size,
              height: height ?? size,
              fit: BoxFit.cover,
              errorBuilder: (_, error, stackTrace) => const _ImagePlaceholder(),
            ),
          );
    return SizedBox(
      width: size == double.infinity ? double.infinity : size,
      height: height ?? size,
      child: image,
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F2428),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Center(child: Icon(Icons.local_bar, size: 36)),
    );
  }
}

class _IngredientLine extends StatelessWidget {
  const _IngredientLine({required this.ingredient});

  final RecipeIngredient ingredient;

  @override
  Widget build(BuildContext context) {
    final amount = ingredient.measureMl == null
        ? ''
        : '${ingredient.measureMl!.toStringAsFixed(0)}ml';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 7),
          child: Icon(Icons.circle, size: 8),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            amount.isEmpty
                ? ingredient.ingredientName
                : '$amount ${ingredient.ingredientName}',
          ),
        ),
      ],
    );
  }
}

class _SpecLine extends StatelessWidget {
  const _SpecLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value.isEmpty ? 'Not listed' : value),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 10),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 16), trailing!],
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.caption,
  });

  final String title;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 12),
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(caption, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _InsightListCard extends StatelessWidget {
  const _InsightListCard({
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

class _InfoMetric extends StatelessWidget {
  const _InfoMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2428),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF293037)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

class _BuildMarkerSummary extends StatelessWidget {
  const _BuildMarkerSummary({
    required this.buildMarker,
    required this.appVersionLabel,
    required this.catalogPathLabel,
    required this.visibleRecipeCount,
  });

  final String buildMarker;
  final String appVersionLabel;
  final String catalogPathLabel;
  final int visibleRecipeCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101417),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF293037)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Build $buildMarker',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          Text(appVersionLabel),
          const SizedBox(height: 6),
          Text(catalogPathLabel),
          const SizedBox(height: 6),
          Text('Visible cocktails: $visibleRecipeCount'),
        ],
      ),
    );
  }
}

class _CommodityImportSummaryCard extends StatelessWidget {
  const _CommodityImportSummaryCard({required this.result});

  final CommodityIngredientImportResult result;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '£', decimalDigits: 2);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101417),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF293037)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Latest import summary',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Text(
            'Matched ${result.matchedIngredients.length} ingredients. ${result.unmatchedIngredientNames.length} still need manual entry.',
          ),
          if (result.matchedIngredients.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Matched ingredients',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            ...result.matchedIngredients.map(
              (match) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${match.ingredient.name} · ${_formatMl(match.bottleSizeMl)} · ${currency.format(match.bottlePrice)} · ${match.sourceProductName}',
                ),
              ),
            ),
          ],
          if (result.unmatchedIngredientNames.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Unmatched ingredients needing manual entry',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: result.unmatchedIngredientNames
                  .map((name) => Chip(label: Text(name)))
                  .toList(),
            ),
          ],
        ],
      ),
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

class _IngredientCostRow extends StatelessWidget {
  const _IngredientCostRow({
    required this.ingredient,
    required this.canEdit,
    required this.onEdit,
  });

  final Ingredient ingredient;
  final bool canEdit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final price = ingredient.isGarnish && ingredient.bottleCost == 0
        ? 'Garnish'
        : ingredient.bottleCost > 0
        ? NumberFormat.currency(
            symbol: '£',
            decimalDigits: 2,
          ).format(ingredient.bottleCost)
        : 'Missing';
    final size = ingredient.isGarnish && ingredient.bottleSizeMl == 0
        ? 'Garnish'
        : ingredient.bottleSizeMl > 0
        ? _formatMl(ingredient.bottleSizeMl)
        : 'Missing';
    final costPerMl = ingredient.isGarnish
        ? 'Intentionally zero'
        : ingredient.bottleSizeMl > 0 && ingredient.bottleCost > 0
        ? '${(ingredient.costPerMl).toStringAsFixed(4)}/ml'
        : 'Waiting for pricing';

    Widget details() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ingredient.name,
            style: Theme.of(context).textTheme.titleMedium,
            softWrap: true,
          ),
          const SizedBox(height: 6),
          if (ingredient.isGarnish)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Chip(
                label: const Text('Garnish'),
                visualDensity: VisualDensity.compact,
              ),
            ),
          Text('Bottle size: $size'),
          Text('Bottle price: $price'),
          Text('Ingredient cost: $costPerMl'),
        ],
      );
    }

    Widget editButton({bool fullWidth = false}) {
      return SizedBox(
        width: fullWidth ? double.infinity : null,
        child: OutlinedButton(
          onPressed: canEdit ? onEdit : null,
          child: const Text('Edit'),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF293037)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useStackedLayout = constraints.maxWidth < 520;
          if (useStackedLayout) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                details(),
                const SizedBox(height: 12),
                editButton(fullWidth: true),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: details()),
              const SizedBox(width: 12),
              editButton(),
            ],
          );
        },
      ),
    );
  }
}

class _MissingIngredientCostRow extends StatelessWidget {
  const _MissingIngredientCostRow({
    required this.ingredient,
    required this.canEdit,
    required this.onEdit,
  });

  final Ingredient ingredient;
  final bool canEdit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final missingParts = <String>[
      if (ingredient.bottleSizeMl <= 0 && !ingredient.isGarnish) 'bottle size',
      if (ingredient.bottleCost <= 0 && !ingredient.isGarnish) 'bottle price',
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF5B4630)),
        color: const Color(0x14F2B56B),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useStackedLayout = constraints.maxWidth < 520;

          Widget content() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ingredient.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Missing ${missingParts.join(' and ')}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ],
            );
          }

          Widget button({bool fullWidth = false}) {
            return SizedBox(
              width: fullWidth ? double.infinity : null,
              child: OutlinedButton(
                onPressed: canEdit ? onEdit : null,
                child: const Text('Edit'),
              ),
            );
          }

          if (useStackedLayout) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                content(),
                const SizedBox(height: 12),
                button(fullWidth: true),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: content()),
              const SizedBox(width: 12),
              button(),
            ],
          );
        },
      ),
    );
  }
}

String _formatMl(double value) {
  if (value.truncateToDouble() == value) {
    return '${value.toStringAsFixed(0)}ml';
  }
  return '${value.toStringAsFixed(2)}ml';
}

String _quizFocusLabel(QuizFocus focus) {
  return switch (focus) {
    QuizFocus.specs => 'Specs focus',
    QuizFocus.garnishGlassware => 'Garnish and glass focus',
  };
}

String _normalizeIngredientName(String value) {
  return value
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r"[^a-z0-9']+"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _ProgressStats {
  const _ProgressStats({
    required this.quizCount,
    required this.averageScore,
    required this.confidenceLabel,
    required this.weakCocktails,
    required this.weakIngredients,
  });

  final int quizCount;
  final int averageScore;
  final String confidenceLabel;
  final Map<String, int> weakCocktails;
  final Map<String, int> weakIngredients;

  factory _ProgressStats.fromAttempts({
    required List<QuizAttempt> attempts,
    required Map<String, CocktailRecipe> recipesById,
  }) {
    if (attempts.isEmpty) {
      return const _ProgressStats(
        quizCount: 0,
        averageScore: 0,
        confidenceLabel: 'Just getting started',
        weakCocktails: {},
        weakIngredients: {},
      );
    }

    final weakCocktails = <String, int>{};
    final weakIngredients = <String, int>{};
    var totalScore = 0;

    for (final attempt in attempts) {
      totalScore += attempt.scorePercent;
      for (final response in attempt.responses.where(
        (item) => !item.isCorrect,
      )) {
        final recipeName =
            recipesById[response.question.cocktailId]?.name ??
            response.question.cocktailName;
        weakCocktails.update(
          recipeName,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
        final ingredientName = (response.question.ingredientName ?? '').trim();
        if (ingredientName.isNotEmpty) {
          weakIngredients.update(
            ingredientName,
            (value) => value + 1,
            ifAbsent: () => 1,
          );
        }
      }
    }

    final sortedCocktails = weakCocktails.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sortedIngredients = weakIngredients.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final averageScore = (totalScore / attempts.length).round();

    return _ProgressStats(
      quizCount: attempts.length,
      averageScore: averageScore,
      confidenceLabel: averageScore >= 85
          ? 'Feeling strong'
          : averageScore >= 65
          ? 'Building well'
          : 'Worth a refresher',
      weakCocktails: {
        for (final entry in sortedCocktails.take(6)) entry.key: entry.value,
      },
      weakIngredients: {
        for (final entry in sortedIngredients.take(6)) entry.key: entry.value,
      },
    );
  }
}
