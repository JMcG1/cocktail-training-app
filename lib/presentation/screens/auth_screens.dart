import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/browser_app_recovery.dart';
import '../../core/utils/browser_connectivity.dart';
import '../../core/utils/bundled_cocktail_catalog_loader.dart';
import '../../domain/models/models.dart';
import '../controllers/app_controller.dart';
import 'shell_route_helpers.dart';
import 'shell_support_widgets.dart';

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
                                  BuildMarkerSummary(
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
                              InfoMetric(
                                label: 'Approved cocktails',
                                value: '${widget.controller.recipes.length}',
                              ),
                              const SizedBox(height: 12),
                              InfoMetric(
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
