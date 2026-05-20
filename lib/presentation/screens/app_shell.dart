import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/browser_app_recovery.dart';
import '../../core/utils/browser_connectivity.dart';
import '../../core/utils/browser_storage.dart';
import '../../core/utils/curated_recipe_importer.dart';
import '../../core/utils/recipe_review_validator.dart';
import '../../core/utils/weekly_workflow_draft.dart';
import '../../data/firestore/firestore_serializers.dart';
import '../../domain/models/models.dart';
import '../controllers/app_controller.dart';

String _friendlyQuestionKind(String raw) {
  switch (raw) {
    case 'ingredientMeasure':
      return 'Ingredient measures';
    case 'ingredientChoice':
      return 'Ingredient recall';
    case 'cocktailByIngredient':
      return 'Cocktail matching';
    case 'garnish':
      return 'Garnish recalls';
    case 'glassware':
      return 'Glassware recalls';
    case 'method':
      return 'Method recalls';
    case 'batchAmount':
      return 'Batch amounts';
    default:
      return raw;
  }
}

String _recipeIngredientPreview(CocktailRecipe recipe) {
  final names = recipe.ingredients
      .map((ingredient) => ingredient.ingredientName.trim())
      .where((name) => name.isNotEmpty)
      .take(3)
      .toList();
  if (names.isEmpty) {
    return 'Spec details ready to open';
  }
  final preview = names.join(' • ');
  if (recipe.ingredients.length <= 3) {
    return preview;
  }
  return '$preview • +${recipe.ingredients.length - 3} more';
}

String _weeklyImprovementMessage(Map<String, int> weeklyConfidence) {
  final values = weeklyConfidence.values.toList();
  if (values.length < 2) {
    return 'Week-to-week improvement will be clearer once another stock-linked session cycle is complete.';
  }
  final latest = values.last;
  final previous = values[values.length - 2];
  final delta = latest - previous;
  if (delta == 0) {
    return 'Recipe confidence is holding steady week over week, which is a solid base to build on.';
  }
  final direction = delta > 0 ? 'improved' : 'shifted';
  return 'Recipe confidence has $direction by ${delta.abs()}% compared with the previous recorded week.';
}

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

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _guestTrainingMode = false;

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
      return BartenderQuizScreen(
        controller: widget.controller,
        sessionId: sessionId,
      );
    }
    if (inviteRoute != null) {
      return _InviteJoinScreen(
        controller: widget.controller,
        inviteRoute: inviteRoute,
      );
    }

    if (widget.controller.canAccessManagerWorkflows) {
      return ManagerWorkspace(controller: widget.controller);
    }

    if (widget.controller.isBartenderAuthenticated || _guestTrainingMode) {
      return TrainingWorkspace(
        controller: widget.controller,
        onExit: widget.controller.isBartenderAuthenticated
            ? () {
                widget.controller.signOut();
              }
            : () => setState(() => _guestTrainingMode = false),
      );
    }

    return LandingScreen(
      controller: widget.controller,
      onOpenTraining: () => setState(() => _guestTrainingMode = true),
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

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _refreshApp() async {
    await BrowserAppRecovery.refreshApp();
  }

  Future<void> _clearSavedAppData() async {
    await BrowserAppRecovery.clearSavedAppData();
  }

  Future<void> _copyDiagnostics() async {
    final diagnostics = BrowserAppRecovery.diagnostics(
      buildLabel: widget.controller.appBuildLabel,
      runtimeMode: widget.controller.runtimeModeLabel,
      isOnline: BrowserConnectivity.isOnline(),
    );
    await Clipboard.setData(ClipboardData(text: diagnostics));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Diagnostics copied so you can share the current app state.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColors =
        Theme.of(context).extension<AppStatusColors>() ??
        const AppStatusColors(
          highlight: Color(0xFF7CD4B3),
          warning: Color(0xFFE1A545),
          accent: Color(0xFF6FB6FF),
        );
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0E1012), Color(0xFF161B1F), Color(0xFF1A2524)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: Wrap(
                        spacing: 24,
                        runSpacing: 24,
                        children: [
                          SizedBox(
                            width: 510,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(28),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Welcome back to service support',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.headlineMedium,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Sign in to open your venue workspace, support spec confidence, and keep stock-focus prep clear for the team.',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyLarge,
                                    ),
                                    const SizedBox(height: 18),
                                    TextField(
                                      controller: _emailController,
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
                                    const SizedBox(height: 18),
                                    if (widget.controller.errorMessage != null)
                                      Text(
                                        widget.controller.errorMessage!,
                                        style: TextStyle(
                                          color: statusColors.warning,
                                        ),
                                      ),
                                    if (widget.controller.successMessage !=
                                        null) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        widget.controller.successMessage!,
                                        style: TextStyle(
                                          color: statusColors.highlight,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 12),
                                    ElevatedButton(
                                      onPressed: widget.controller.isBusy
                                          ? null
                                          : () async {
                                              try {
                                                await widget.controller
                                                    .signInManager(
                                                      email: _emailController
                                                          .text
                                                          .trim(),
                                                      password:
                                                          _passwordController
                                                              .text,
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
                                          : const Text('Open workspace'),
                                    ),
                                    const SizedBox(height: 14),
                                    TextButton(
                                      onPressed: widget.controller.isBusy
                                          ? null
                                          : () async {
                                              final email = _emailController
                                                  .text
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
                                                    .sendPasswordReset(
                                                      email: email,
                                                    );
                                              } catch (_) {}
                                            },
                                      child: const Text(
                                        'Forgot password? Send a reset link',
                                      ),
                                    ),
                                    Text(
                                      'Access is invite-only. If you need owner, manager, or bartender access, ask the venue owner/admin to send you a join link.',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      widget.controller.usingFirebase
                                          ? 'Live venue mode is active, so sign-in, specs, and session data come from Firebase.'
                                          : 'Demo mode is active. Specs, sessions, and practice results stay on this device until live mode is enabled.',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Build ${widget.controller.appBuildLabel}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 12,
                                      children: [
                                        OutlinedButton(
                                          onPressed: _refreshApp,
                                          child: const Text('Refresh app'),
                                        ),
                                        OutlinedButton(
                                          onPressed: _clearSavedAppData,
                                          child: const Text(
                                            'Clear saved app data',
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: _copyDiagnostics,
                                          child: const Text('Copy diagnostics'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 510,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(28),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          height: 46,
                                          width: 46,
                                          decoration: BoxDecoration(
                                            color: statusColors.highlight
                                                .withValues(alpha: 0.16),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.menu_book,
                                            color: statusColors.highlight,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Text(
                                            'Bartender practice space',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleLarge,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 18),
                                    const _MiniBullet(
                                      text:
                                          'Open the cocktail list, learn each spec like a bar sheet, and reveal details only when you want a quick check.',
                                    ),
                                    const _MiniBullet(
                                      text:
                                          'Run short practice rounds on measures, ingredients, garnish, glassware, batch amounts, and build method.',
                                    ),
                                    const _MiniBullet(
                                      text:
                                          'Use coaching suggestions to revisit the specs that would benefit most from another pass.',
                                    ),
                                    const SizedBox(height: 18),
                                    if (widget.controller.usingFirebase) ...[
                                      Text(
                                        'Practice opens after invite-based sign-in, or from an active session link shared by your manager.',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ] else
                                      OutlinedButton(
                                        onPressed: widget.onOpenTraining,
                                        child: const Text(
                                          'Open practice space',
                                        ),
                                      ),
                                    if (widget.controller.isDemoAuthMode) ...[
                                      const SizedBox(height: 20),
                                      const Divider(),
                                      const SizedBox(height: 14),
                                      SelectableText(
                                        'Demo email: ${widget.controller.demoManagerEmail}\nDemo password: ${widget.controller.demoManagerPassword}',
                                      ),
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
              );
            },
          ),
        ),
      ),
    );
  }
}

class _InviteJoinScreen extends StatefulWidget {
  const _InviteJoinScreen({
    required this.controller,
    required this.inviteRoute,
  });

  final AppController controller;
  final InviteRouteData inviteRoute;

  @override
  State<_InviteJoinScreen> createState() => _InviteJoinScreenState();
}

class _InviteJoinScreenState extends State<_InviteJoinScreen> {
  late final TextEditingController _nameController = TextEditingController();
  late final TextEditingController _emailController = TextEditingController();
  late final TextEditingController _passwordController =
      TextEditingController();
  late Future<VenueInvite?> _inviteFuture = widget.controller.fetchVenueInvite(
    venueId: widget.inviteRoute.venueId,
    inviteId: widget.inviteRoute.inviteId,
  );

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: FutureBuilder<VenueInvite?>(
                      future: _inviteFuture,
                      builder: (context, snapshot) {
                        final invite = snapshot.data;
                        final errorText = widget.controller.errorMessage;
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Join your venue',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineMedium,
                                ),
                                const SizedBox(height: 12),
                                if (widget.controller.currentUser != null) ...[
                                  Text(
                                    'Sign out of the current account before joining a new venue from this link.',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge,
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: widget.controller.isBusy
                                        ? null
                                        : () async {
                                            try {
                                              await widget.controller.signOut();
                                            } catch (_) {}
                                          },
                                    child: const Text('Sign out and continue'),
                                  ),
                                ] else if (snapshot.connectionState ==
                                    ConnectionState.waiting) ...[
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 24),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                                ] else if (invite == null) ...[
                                  Text(
                                    'This invite could not be matched. Ask your venue manager for a fresh join link or QR code.',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge,
                                  ),
                                ] else ...[
                                  Text(
                                    'This invite is set up for a ${invite.role.name} account. Your role and venue are set by the invite so everything lands in the right place.',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    invite.disabled
                                        ? 'This invite is currently paused.'
                                        : invite.isExpired
                                        ? 'This invite has expired.'
                                        : invite.isOverused
                                        ? 'This invite has already reached its usage limit.'
                                        : 'Add your details below to finish joining the venue.',
                                  ),
                                  const SizedBox(height: 18),
                                  TextField(
                                    controller: _nameController,
                                    decoration: const InputDecoration(
                                      labelText: 'Display name',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _emailController,
                                    decoration: const InputDecoration(
                                      labelText: 'Email',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _passwordController,
                                    obscureText: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Password',
                                    ),
                                  ),
                                  if (errorText != null) ...[
                                    const SizedBox(height: 14),
                                    Text(
                                      errorText,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                    ),
                                  ],
                                  if (widget.controller.successMessage !=
                                      null) ...[
                                    const SizedBox(height: 14),
                                    Text(
                                      widget.controller.successMessage!,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 18),
                                  ElevatedButton(
                                    onPressed:
                                        widget.controller.isBusy ||
                                            !invite.isRedeemable
                                        ? null
                                        : () async {
                                            try {
                                              await widget.controller
                                                  .redeemVenueInvite(
                                                    venueId: invite.venueId,
                                                    inviteId: invite.id,
                                                    email: _emailController.text
                                                        .trim(),
                                                    password:
                                                        _passwordController
                                                            .text,
                                                    displayName: _nameController
                                                        .text
                                                        .trim(),
                                                  );
                                            } catch (_) {
                                              setState(() {
                                                _inviteFuture = widget
                                                    .controller
                                                    .fetchVenueInvite(
                                                      venueId: widget
                                                          .inviteRoute
                                                          .venueId,
                                                      inviteId: widget
                                                          .inviteRoute
                                                          .inviteId,
                                                    );
                                              });
                                            }
                                          },
                                    child: widget.controller.isBusy
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text('Join this venue'),
                                  ),
                                ],
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
          },
        ),
      ),
    );
  }
}

class ManagerWorkspace extends StatefulWidget {
  const ManagerWorkspace({super.key, required this.controller});

  final AppController controller;

  @override
  State<ManagerWorkspace> createState() => _ManagerWorkspaceState();
}

class _ManagerWorkspaceState extends State<ManagerWorkspace> {
  int _index = 0;
  bool _isOnline = true;
  Timer? _connectivityTimer;
  String? _practiceSessionId;

  @override
  void initState() {
    super.initState();
    _isOnline = BrowserConnectivity.isOnline();
    _connectivityTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final online = BrowserConnectivity.isOnline();
      if (online != _isOnline && mounted) {
        setState(() => _isOnline = online);
      }
    });
  }

  @override
  void dispose() {
    _connectivityTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sections = <_WorkspaceSection>[
      _WorkspaceSection(
        page: ManagerDashboardTab(controller: widget.controller),
        destination: const NavigationDestination(
          icon: Icon(Icons.space_dashboard),
          label: 'Dashboard',
        ),
      ),
      _WorkspaceSection(
        page: ManagerLibraryTab(controller: widget.controller),
        destination: const NavigationDestination(
          icon: Icon(Icons.local_bar),
          label: 'Cocktail list',
        ),
      ),
      _WorkspaceSection(
        page: StudyModeTab(controller: widget.controller),
        destination: const NavigationDestination(
          icon: Icon(Icons.style),
          label: 'Study',
        ),
      ),
      _WorkspaceSection(
        page: PracticeTab(
          controller: widget.controller,
          activeSessionId: _practiceSessionId,
          onSessionChanged: (value) =>
              setState(() => _practiceSessionId = value),
        ),
        destination: const NavigationDestination(
          icon: Icon(Icons.quiz),
          label: 'Practice',
        ),
      ),
      _WorkspaceSection(
        page: WeakAreasTab(
          controller: widget.controller,
          onStartWeakAreaQuiz: () {
            final session = widget.controller.generatePracticeQuiz(
              bartenderName:
                  widget.controller.currentUser?.displayName.trim().isNotEmpty ==
                      true
                  ? widget.controller.currentUser!.displayName.trim()
                  : 'Training user',
              focusRecipeIds: widget.controller
                  .weakAreaRecipeSuggestions()
                  .map((item) => item.id)
                  .toList(),
            );
            setState(() {
              _practiceSessionId = session.id;
              _index = 3;
            });
          },
        ),
        destination: const NavigationDestination(
          icon: Icon(Icons.track_changes),
          label: 'Refreshers',
        ),
      ),
      if (widget.controller.canAccessAdminSetup)
        _WorkspaceSection(
          page: IngredientsTab(controller: widget.controller),
          destination: const NavigationDestination(
            icon: Icon(Icons.liquor),
            label: 'Pricing',
          ),
        ),
      _WorkspaceSection(
        page: WeeklyFocusTab(controller: widget.controller),
        destination: const NavigationDestination(
          icon: Icon(Icons.event_note),
          label: 'Stock focus',
        ),
      ),
      _WorkspaceSection(
        page: InsightsTab(controller: widget.controller),
        destination: const NavigationDestination(
          icon: Icon(Icons.insights),
          label: 'Insights',
        ),
      ),
      _WorkspaceSection(
        page: SettingsTab(controller: widget.controller, isOnline: _isOnline),
        destination: const NavigationDestination(
          icon: Icon(Icons.settings),
          label: 'Settings',
        ),
      ),
    ];
    final pages = sections.map((section) => section.page).toList();
    final destinations = sections
        .map((section) => section.destination)
        .toList();
    final selectedIndex = _index >= pages.length ? pages.length - 1 : _index;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stock Variance Coach',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              '${widget.controller.currentUser?.venueName ?? 'Venue'} • ${widget.controller.canAccessAdminSetup ? 'owner/admin space' : 'manager space'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => widget.controller.signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 980) {
              return Row(
                children: [
                  NavigationRail(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: (value) =>
                        setState(() => _index = value),
                    labelType: NavigationRailLabelType.all,
                    destinations: destinations
                        .map(
                          (item) => NavigationRailDestination(
                            icon: item.icon,
                            label: Text(item.label),
                          ),
                        )
                        .toList(),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: [
                        if (!_isOnline)
                          const _OfflineBanner(
                            message:
                                'You are offline right now. Workspace progress stays local so you can restore and save again when the connection returns.',
                          ),
                        Expanded(child: pages[selectedIndex]),
                      ],
                    ),
                  ),
                ],
              );
            }
            return Column(
              children: [
                if (!_isOnline)
                  const _OfflineBanner(
                    message:
                        'You are offline right now. Workspace progress stays local so you can restore and save again when the connection returns.',
                  ),
                Expanded(child: pages[selectedIndex]),
                NavigationBar(
                  selectedIndex: selectedIndex,
                  destinations: destinations,
                  onDestinationSelected: (value) =>
                      setState(() => _index = value),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class TrainingWorkspace extends StatefulWidget {
  const TrainingWorkspace({
    super.key,
    required this.controller,
    required this.onExit,
  });

  final AppController controller;
  final VoidCallback onExit;

  @override
  State<TrainingWorkspace> createState() => _TrainingWorkspaceState();
}

class _TrainingWorkspaceState extends State<TrainingWorkspace> {
  int _index = 0;
  String? _practiceSessionId;

  @override
  Widget build(BuildContext context) {
    final destinations = const [
      NavigationDestination(icon: Icon(Icons.local_bar), label: 'Library'),
      NavigationDestination(icon: Icon(Icons.style), label: 'Study'),
      NavigationDestination(icon: Icon(Icons.quiz), label: 'Practice'),
      NavigationDestination(
        icon: Icon(Icons.track_changes),
        label: 'Weak Areas',
      ),
    ];

    final pages = [
      CocktailLibraryTab(controller: widget.controller),
      StudyModeTab(controller: widget.controller),
      PracticeTab(
        controller: widget.controller,
        activeSessionId: _practiceSessionId,
        onSessionChanged: (value) => setState(() => _practiceSessionId = value),
      ),
      WeakAreasTab(
        controller: widget.controller,
        onStartWeakAreaQuiz: () {
          final session = widget.controller.generatePracticeQuiz(
            bartenderName: 'Training user',
            focusRecipeIds: widget.controller
                .weakAreaRecipeSuggestions()
                .map((item) => item.id)
                .toList(),
          );
          setState(() {
            _practiceSessionId = session.id;
            _index = 2;
          });
        },
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: widget.onExit,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Practice space'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: pages[_index]),
            NavigationBar(
              selectedIndex: _index,
              destinations: destinations,
              onDestinationSelected: (value) => setState(() => _index = value),
            ),
          ],
        ),
      ),
    );
  }
}

class ManagerDashboardTab extends StatelessWidget {
  const ManagerDashboardTab({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final dashboard = controller.buildDashboard();
    final checklist = controller.buildSetupChecklist();
    final currency = NumberFormat.currency(symbol: '£', decimalDigits: 2);
    final pendingReviewCount =
        controller.latestImportResult?.drafts.length ?? 0;
    final totalPotentialVariance = dashboard
        .potentialVarianceByIngredient
        .values
        .fold<double>(0, (sum, value) => sum + value);
    final averageConfidence = dashboard.latestPerBartender.isEmpty
        ? 0
        : (dashboard.latestPerBartender.values
                      .map((item) => item.scorePercent)
                      .reduce((a, b) => a + b) /
                  dashboard.latestPerBartender.length)
              .round();

    return _ScrollPage(
      title: 'Venue overview',
      subtitle:
          'Keep an eye on spec confidence, stock-focus practice, and the areas where a little more coaching would help most.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Panel(
            title: 'Setup checklist',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  checklist.isComplete
                      ? 'Nice work. The key setup pieces are in place.'
                      : '${checklist.completedCount}/${checklist.items.length} setup steps are in place so far.',
                ),
                const SizedBox(height: 14),
                ...checklist.items.map(
                  (item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      item.isComplete
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(item.title),
                    subtitle: Text(item.description),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _Panel(
            title: 'Launch checklist',
            child: Column(
              children: [
                _DataRowTile(
                  title: 'Firebase mode connected',
                  subtitle: 'Live venue data is connected and ready to use.',
                  trailing: controller.usingFirebase ? 'Ready' : 'Demo mode',
                ),
                _DataRowTile(
                  title: 'Venue created',
                  subtitle:
                      'The signed-in account is linked to the correct venue.',
                  trailing:
                      controller.currentUser?.venueId.trim().isNotEmpty == true
                      ? 'Ready'
                      : 'Pending',
                ),
                _DataRowTile(
                  title: 'Cocktail list ready',
                  subtitle:
                      'The saved cocktail list should be ready before service support starts.',
                  trailing: controller.recipes.isNotEmpty ? 'Ready' : 'Pending',
                ),
                _DataRowTile(
                  title: 'Ingredient costs entered',
                  subtitle:
                      'Key concern ingredients should have bottle pricing for more useful value projections.',
                  trailing:
                      controller.ingredients.any((item) => item.bottleCost > 0)
                      ? 'Ready'
                      : 'Pending',
                ),
                _DataRowTile(
                  title: 'First stock concern created',
                  subtitle:
                      'A weekly stock-focus session should be in place before team practice starts.',
                  trailing: controller.weeklySessions.isNotEmpty
                      ? 'Ready'
                      : 'Pending',
                ),
                _DataRowTile(
                  title: 'Bartender sales entered',
                  subtitle:
                      'Relevant sales should be captured for at least one bartender.',
                  trailing:
                      controller.weeklySessions.any(
                        (item) => item.bartenderSales.isNotEmpty,
                      )
                      ? 'Ready'
                      : 'Pending',
                ),
                _DataRowTile(
                  title: 'Session link shared',
                  subtitle:
                      'At least one active or closed stock-focus session should exist.',
                  trailing:
                      controller.quizSessions.any(
                        (item) => item.kind == QuizKind.stockVariance,
                      )
                      ? 'Ready'
                      : 'Pending',
                ),
                _DataRowTile(
                  title: 'First session completed',
                  subtitle:
                      'One completed session confirms the flow is ready before service.',
                  trailing:
                      controller.quizAttempts.any((item) => item.weekId != null)
                      ? 'Ready'
                      : 'Pending',
                ),
                _DataRowTile(
                  title: 'Dashboard reviewed',
                  subtitle:
                      'Use supportive insights to confirm the venue is ready to go.',
                  trailing: controller.quizAttempts.isNotEmpty
                      ? 'Ready'
                      : 'Pending',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 18,
            runSpacing: 18,
            children: [
              _MetricCard(
                title: 'Training cocktails',
                value: '${controller.recipes.length}',
                caption:
                    'These are the cocktails currently used in study, practice, and stock focus',
              ),
              _MetricCard(
                title: 'Live batches',
                value: '${controller.batches.length}',
                caption:
                    'Saved batches power linking, variance breakdowns, and shortage analysis',
              ),
              _MetricCard(
                title: 'Needs a quick look',
                value: '$pendingReviewCount',
                caption:
                    'These cocktails or batches still carry a source note that may need a quick check',
              ),
              _MetricCard(
                title: 'Latest confidence',
                value: '$averageConfidence%',
                caption:
                    'Average across the latest submitted practice sessions',
              ),
              _MetricCard(
                title: 'Session completion rate',
                value: '${dashboard.quizCompletionRate}%',
                caption: 'Weekly focus sessions with saved participation data',
              ),
              _MetricCard(
                title: 'Potential variance value',
                value: currency.format(totalPotentialVariance),
                caption:
                    'Projected from the specs entered in submitted stock-focus sessions',
              ),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 18,
            runSpacing: 18,
            children: [
              _Panel(
                width: 420,
                title: 'Latest bartender confidence',
                child: dashboard.latestPerBartender.isEmpty
                    ? const _EmptyText(
                        'Session history will appear here once bartenders complete a few rounds.',
                      )
                    : Column(
                        children: dashboard.latestPerBartender.entries
                            .map(
                              (entry) => _DataRowTile(
                                title: entry.key,
                                subtitle: entry.value.encouragement,
                                trailing: '${entry.value.scorePercent}%',
                              ),
                            )
                            .toList(),
                      ),
              ),
              _Panel(
                width: 420,
                title: 'Potential variance by bartender',
                child: dashboard.potentialVarianceByBartender.isEmpty
                    ? const _EmptyText(
                        'Bartender-level potential variance will appear after stock-focus sessions are submitted.',
                      )
                    : Column(
                        children:
                            (dashboard.potentialVarianceByBartender.entries
                                    .toList()
                                  ..sort((a, b) => b.value.compareTo(a.value)))
                                .take(6)
                                .map(
                                  (entry) => _DataRowTile(
                                    title: entry.key,
                                    subtitle:
                                        'Supportive projection from stock-focus responses and saved sales.',
                                    trailing: currency.format(entry.value),
                                  ),
                                )
                                .toList(),
                      ),
              ),
              _Panel(
                width: 420,
                title: 'Operational status',
                child: Column(
                  children: [
                    _DataRowTile(
                      title: 'Open stock-focus sessions',
                      subtitle:
                          'Sessions still waiting for at least one submitted response.',
                      trailing: '${dashboard.unresolvedStockSessions}',
                    ),
                    _DataRowTile(
                      title: 'Active session links',
                      subtitle:
                          'Live bartender links that can still be opened.',
                      trailing: '${dashboard.activeQuizSessions}',
                    ),
                    _DataRowTile(
                      title: 'Closed session links',
                      subtitle: 'Completed or manually closed bartender links.',
                      trailing: '${dashboard.closedQuizSessions}',
                    ),
                  ],
                ),
              ),
              _Panel(
                width: 420,
                title: 'Potential variance by ingredient',
                child: dashboard.potentialVarianceByIngredient.isEmpty
                    ? const _EmptyText(
                        'Potential variance appears after stock-focus sessions are completed.',
                      )
                    : Column(
                        children:
                            (dashboard.potentialVarianceByIngredient.entries
                                    .toList()
                                  ..sort((a, b) => b.value.compareTo(a.value)))
                                .take(6)
                                .map(
                                  (entry) => _DataRowTile(
                                    title: entry.key,
                                    subtitle:
                                        'Supportive projection based on session responses and recorded sales',
                                    trailing: currency.format(entry.value),
                                  ),
                                )
                                .toList(),
                      ),
              ),
              _Panel(
                width: 420,
                title: 'Potential batch variance',
                child: dashboard.potentialVarianceByBatch.isEmpty
                    ? const _EmptyText(
                        'Batch variance appears after stock-focus sessions include linked batch specs.',
                      )
                    : Column(
                        children:
                            (dashboard.potentialVarianceByBatch.entries.toList()
                                  ..sort((a, b) => b.value.compareTo(a.value)))
                                .take(6)
                                .map(
                                  (entry) => _DataRowTile(
                                    title: entry.key,
                                    subtitle:
                                        'Projected batch overpour or underpour volume from submitted answers and recorded sales.',
                                    trailing:
                                        '${entry.value.toStringAsFixed(0)}ml',
                                  ),
                                )
                                .toList(),
                      ),
              ),
              _Panel(
                width: 420,
                title: 'Underpour consistency opportunities',
                child: dashboard.underpourOpportunities.isEmpty
                    ? const _EmptyText(
                        'Consistency opportunities will appear after stock-focus sessions are completed.',
                      )
                    : Column(
                        children:
                            (dashboard.underpourOpportunities.entries.toList()
                                  ..sort((a, b) => b.value.compareTo(a.value)))
                                .take(6)
                                .map(
                                  (entry) => _DataRowTile(
                                    title: entry.key,
                                    subtitle:
                                        'Lighter-than-spec answers may affect pour consistency if repeated in service.',
                                    trailing:
                                        '${entry.value.toStringAsFixed(0)}ml',
                                  ),
                                )
                                .toList(),
                      ),
              ),
              _Panel(
                width: 420,
                title: 'Training focus areas',
                child: dashboard.trainingFocusAreas.isEmpty
                    ? const _EmptyText(
                        'Answer patterns will show the areas most worth revisiting after a few submitted sessions.',
                      )
                    : Column(
                        children:
                            (dashboard.trainingFocusAreas.entries.toList()
                                  ..sort((a, b) => b.value.compareTo(a.value)))
                                .map(
                                  (entry) => _DataRowTile(
                                    title: _friendlyQuestionKind(entry.key),
                                    subtitle:
                                        'Repeated misses here suggest a useful coaching focus for the next shift.',
                                    trailing: '${entry.value}',
                                  ),
                                )
                                .toList(),
                      ),
              ),
              _Panel(
                width: 420,
                title: 'Strongest improvement this week',
                child: dashboard.strongestImprovementLabel == null
                    ? const _EmptyText(
                        'Once bartenders have at least two quiz attempts, the clearest week-to-week lift will show here.',
                      )
                    : _DataRowTile(
                        title: dashboard.strongestImprovementLabel!,
                        subtitle:
                            'Most positive shift between the last two submitted quiz attempts.',
                        trailing: '+${dashboard.strongestImprovementDelta}%',
                      ),
              ),
              _Panel(
                width: 420,
                title: 'Suggested refreshers',
                child: dashboard.weakAreaSuggestions.isEmpty
                    ? const _EmptyText(
                        'Refresher suggestions will appear after a few sessions are completed.',
                      )
                    : Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: dashboard.weakAreaSuggestions
                            .map((recipe) => Chip(label: Text(recipe.name)))
                            .toList(),
                      ),
              ),
              _Panel(
                width: 420,
                title: 'Session completion status',
                child: dashboard.quizCompletionStatus.isEmpty
                    ? const _EmptyText(
                        'Weekly completion status will appear once sessions and bartender sales exist.',
                      )
                    : Column(
                        children: dashboard.quizCompletionStatus.entries
                            .map(
                              (entry) => _DataRowTile(
                                title: entry.key,
                                subtitle:
                                    'Targeted bartender participation for this session',
                                trailing: entry.value,
                              ),
                            )
                            .toList(),
                      ),
              ),
              _Panel(
                width: 420,
                title: 'Cocktails worth revisiting',
                child: dashboard.misunderstoodCocktails.isEmpty
                    ? const _EmptyText(
                        'Cocktails that keep coming up for a refresher will appear after real submissions.',
                      )
                    : Column(
                        children:
                            (dashboard.misunderstoodCocktails.entries.toList()
                                  ..sort((a, b) => b.value.compareTo(a.value)))
                                .take(6)
                                .map(
                                  (entry) => _DataRowTile(
                                    title: entry.key,
                                    subtitle:
                                        'This cocktail has come up repeatedly as a useful coaching focus.',
                                    trailing: '${entry.value}',
                                  ),
                                )
                                .toList(),
                      ),
              ),
              _Panel(
                width: 420,
                title: 'Week-over-week improvement',
                child: dashboard.weeklyConfidence.isEmpty
                    ? const _EmptyText(
                        'Weekly confidence trends will appear after at least one stock-linked session has been completed.',
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...dashboard.weeklyConfidence.entries.map(
                            (entry) => _DataRowTile(
                              title: entry.key,
                              subtitle:
                                  'Average recipe confidence for this weekly focus.',
                              trailing: '${entry.value}%',
                            ),
                          ),
                          if (dashboard.weeklyConfidence.length >= 2) ...[
                            const SizedBox(height: 12),
                            Text(
                              _weeklyImprovementMessage(
                                dashboard.weeklyConfidence,
                              ),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class RecipeImportTab extends StatefulWidget {
  const RecipeImportTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<RecipeImportTab> createState() => _RecipeImportTabState();
}

class _RecipeImportTabState extends State<RecipeImportTab> {
  final TextEditingController _ocrTextController = TextEditingController();
  final TextEditingController _manualTextController = TextEditingController();
  final TextEditingController _draftSearchController = TextEditingController();
  List<RecipeImportDraft> _drafts = [];
  RecipeConfidence? _draftConfidenceFilter;
  String _draftCategoryFilter = 'All categories';
  final CuratedImportConflictMode _curatedConflictMode =
      CuratedImportConflictMode.importOnlyNew;
  bool _overwriteVerifiedSpecs = true;
  Set<String> _draftIdsToSkipOnSave = const {};
  String? _reviewActionMessage;
  bool _reviewActionIsError = false;

  Iterable<RecipeImportDraft> get _visibleDrafts =>
      _drafts.where((draft) => draft.status != RecipeDraftStatus.deleted);

  RecipeReviewState _reviewState(RecipeImportDraft draft) =>
      RecipeReviewValidator.inspectDraft(draft);

  bool get _isCuratedPreview =>
      widget.controller.latestCuratedImportPlan != null;

  void _resetCuratedPreviewState() {
    _draftIdsToSkipOnSave = const {};
  }

  void _setReviewMessage(String message, {bool isError = false}) {
    setState(() {
      _reviewActionMessage = message;
      _reviewActionIsError = isError;
    });
  }

  bool _shouldSkipCuratedDraftOnSave(RecipeImportDraft draft) {
    if (_curatedConflictMode != CuratedImportConflictMode.skipExisting) {
      return false;
    }
    return _draftIdsToSkipOnSave.contains(draft.id);
  }

  void _replaceDraft(int index, RecipeImportDraft updated) {
    final current = _drafts[index];
    _drafts[index] = updated.copyWith(
      status: current.status == RecipeDraftStatus.approved
          ? RecipeDraftStatus.pending
          : current.status,
      wasManuallyReviewed: true,
    );
  }

  void _approveDraft(int index) {
    try {
      final approved = widget.controller.approveImportDraft(_drafts[index]);
      setState(() {
        _drafts[index] = approved;
        _reviewActionMessage =
            'Approved ${approved.name.isEmpty ? 'recipe draft' : approved.name} for import.';
        _reviewActionIsError = false;
      });
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      debugPrint('[RecipeImport] Approve failed: $message');
      _setReviewMessage(message, isError: true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _approveAllHighConfidence() {
    var approvedCount = 0;
    setState(() {
      for (var index = 0; index < _drafts.length; index += 1) {
        final draft = _drafts[index];
        if (draft.status == RecipeDraftStatus.deleted) {
          continue;
        }
        final review = _reviewState(draft);
        if (review.confidence == RecipeConfidence.highConfidence &&
            review.canApprove) {
          _drafts[index] = widget.controller.approveImportDraft(draft);
          approvedCount += 1;
        }
      }
      _reviewActionMessage = approvedCount == 0
          ? 'No high-confidence drafts were ready for approval yet.'
          : '$approvedCount high-confidence draft${approvedCount == 1 ? '' : 's'} approved for import.';
      _reviewActionIsError = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          approvedCount == 0
              ? 'No high-confidence drafts were ready for bulk approval yet.'
              : '$approvedCount high-confidence drafts are ready to import.',
        ),
      ),
    );
  }

  void _keepSuspiciousDraftsInReview() {
    setState(() {
      for (var index = 0; index < _drafts.length; index += 1) {
        final review = _reviewState(_drafts[index]);
        if (review.confidence == RecipeConfidence.possibleOcrIssue) {
          _drafts[index] = widget.controller.keepImportDraftInReview(
            _drafts[index],
          );
        }
      }
      _reviewActionMessage =
          'Suspicious OCR drafts have been kept in review so nothing uncertain goes live by accident.';
      _reviewActionIsError = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Suspicious OCR drafts have been kept in review so nothing uncertain goes live by accident.',
        ),
      ),
    );
  }

  Future<void> _confirmImport() async {
    final draftsToSave = _drafts
        .map(
          (draft) => _shouldSkipCuratedDraftOnSave(draft)
              ? widget.controller.deleteImportDraft(draft)
              : draft,
        )
        .toList();
    final approved = draftsToSave
        .where((draft) => draft.status == RecipeDraftStatus.approved)
        .toList();
    if (approved.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Approve at least one spec before publishing it into the live venue library.',
          ),
        ),
      );
      return;
    }
    try {
      await widget.controller.saveImportedDrafts(draftsToSave);
      if (!mounted) {
        return;
      }
      setState(() {
        _drafts =
            widget.controller.latestImportResult?.drafts
                .map((item) => item.copyWith())
                .toList() ??
            [];
        if (widget.controller.latestImportResult == null) {
          _resetCuratedPreviewState();
        }
        final skippedCount = draftsToSave
            .where((draft) => draft.status == RecipeDraftStatus.deleted)
            .length;
        _reviewActionMessage =
            '${approved.length} approved spec${approved.length == 1 ? '' : 's'} published.${skippedCount > 0 ? ' $skippedCount skipped draft${skippedCount == 1 ? '' : 's'} stayed out of the live library.' : ''}';
        _reviewActionIsError = false;
      });
      final skippedCount = draftsToSave
          .where((draft) => draft.status == RecipeDraftStatus.deleted)
          .length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${approved.length} approved spec${approved.length == 1 ? '' : 's'} published.${skippedCount > 0 ? ' $skippedCount skipped draft${skippedCount == 1 ? '' : 's'} stayed out of the live library.' : ''} Pending drafts remain in review until they are approved.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      final rawMessage =
          widget.controller.errorMessage ??
          error.toString().replaceFirst('Exception: ', '');
      final message = _friendlyImportSaveError(rawMessage);
      debugPrint('[RecipeImport] Save failed: $message');
      _setReviewMessage(message, isError: true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncFromController();
  }

  @override
  void didUpdateWidget(covariant RecipeImportTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFromController();
  }

  void _syncFromController() {
    final importResult = widget.controller.latestImportResult;
    if (importResult == null) {
      _drafts = [];
      _resetCuratedPreviewState();
      return;
    }
    final incomingIds = importResult.drafts.map((draft) => draft.id).toList();
    final currentIds = _drafts.map((draft) => draft.id).toList();
    if (incomingIds.join('|') != currentIds.join('|')) {
      _drafts = importResult.drafts.map((item) => item.copyWith()).toList();
    }
  }

  @override
  void dispose() {
    _ocrTextController.dispose();
    _manualTextController.dispose();
    _draftSearchController.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    final file = result?.files.firstOrNull;
    if (file?.bytes == null || !mounted) {
      return;
    }
    await widget.controller.importPdf(bytes: file!.bytes!, fileName: file.name);
    setState(() {
      _resetCuratedPreviewState();
      _reviewActionMessage = null;
      _reviewActionIsError = false;
      _drafts =
          widget.controller.latestImportResult?.drafts
              .map((item) => item.copyWith())
              .toList() ??
          [];
    });
  }

  Future<void> _pickOcrTextFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt'],
      withData: true,
    );
    final file = result?.files.firstOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null || !mounted) {
      return;
    }
    final text = String.fromCharCodes(bytes);
    final importResult = widget.controller.importFromOcrText(
      text: text,
      sourceName: file.name,
    );
    _ocrTextController.text = text;
    setState(() {
      _resetCuratedPreviewState();
      _reviewActionMessage = null;
      _reviewActionIsError = false;
      _drafts = importResult.drafts.map((item) => item.copyWith()).toList();
    });
  }

  Future<void> _importCuratedSpecs() async {
    final plan = await widget.controller.importCuratedSpecs(
      conflictMode: _curatedConflictMode,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _drafts = plan.importResult.drafts
          .map((item) => item.copyWith())
          .toList();
      _draftIdsToSkipOnSave =
          _curatedConflictMode == CuratedImportConflictMode.skipExisting
          ? {
              for (final draft in _drafts)
                if (draft.reviewFlags.any(
                  (flag) => flag.contains('will skip it on confirmation'),
                ))
                  draft.id,
            }
          : const {};
      _reviewActionMessage = null;
      _reviewActionIsError = false;
    });
  }

  Future<void> _syncVerifiedRecipeSet() async {
    try {
      final result = await widget.controller.syncVerifiedRecipes(
        overwriteExisting: _overwriteVerifiedSpecs,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _drafts = const [];
        _resetCuratedPreviewState();
        _reviewActionMessage =
            'Verified recipe set refreshed. ${result.cocktailsAdded + result.cocktailsUpdated + result.cocktailsSkipped} cocktail spec${result.cocktailsAdded + result.cocktailsUpdated + result.cocktailsSkipped == 1 ? '' : 's'} and ${result.batchesAdded + result.batchesUpdated + result.batchesSkipped} batch spec${result.batchesAdded + result.batchesUpdated + result.batchesSkipped == 1 ? '' : 's'} are ready for live training.';
        _reviewActionIsError = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verified recipe set refreshed for this venue.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message =
          widget.controller.errorMessage ??
          error.toString().replaceFirst('Exception: ', '');
      _setReviewMessage(message, isError: true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _friendlyImportSaveError(String rawMessage) {
    final normalized = rawMessage.toLowerCase();
    if (normalized.contains('permission') ||
        normalized.contains('insufficient')) {
      return 'We could not publish the approved specs because this account does not currently have permission to update the live venue library. Please check Firestore rules and owner/admin access, then try again.';
    }
    if (normalized.contains('network') || normalized.contains('offline')) {
      return 'We could not publish the approved specs because the app appears to be offline. Please reconnect and try again.';
    }
    return rawMessage.isEmpty
        ? 'We could not publish the approved specs right now. Please try again.'
        : rawMessage;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.canAccessAdminSetup) {
      return const _ScrollPage(
        title: 'Admin setup',
        subtitle:
            'Only the owner/admin can import, review, approve, and publish official specs.',
        child: _Panel(
          title: 'Owner/admin access required',
          child: _EmptyText(
            'Official spec imports, OCR tidy-up, batch approval, and publish controls stay with the owner/admin so venue managers can stay focused on weekly service support.',
          ),
        ),
      );
    }
    final importResult = widget.controller.latestImportResult;
    final counts = widget.controller.draftCounts(_drafts);
    final categoryOptions = [
      'All categories',
      ...{
        for (final draft in _drafts)
          if (draft.category.trim().isNotEmpty) draft.category.trim(),
      }.toList()..sort(),
    ];
    final filteredDrafts = widget.controller.filterDrafts(
      drafts: _drafts,
      query: _draftSearchController.text,
      confidence: _draftConfidenceFilter,
      category: _draftCategoryFilter,
    );

    return _ScrollPage(
      title: 'Admin setup',
      subtitle:
          'Use the verified recipe set for live service training, and keep OCR or PDF review as a separate back-office tidy-up path when needed.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 18,
            runSpacing: 18,
            children: [
              _Panel(
                width: 460,
                title: 'Verified recipe set',
                child: Builder(
                  builder: (context) {
                    final syncResult =
                        widget.controller.latestVerifiedSyncResult;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'The live library, study mode, practice rounds, and stock-focus sessions run from the verified recipe set checked into this app. Refresh it here whenever you want to re-apply the current source material without relying on the draft-approval queue.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 14),
                        CheckboxListTile(
                          value: _overwriteVerifiedSpecs,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Replace matching live specs with the verified source',
                          ),
                          subtitle: const Text(
                            'Leave this off to keep any existing venue edits untouched and add only missing verified items.',
                          ),
                          onChanged: (value) {
                            setState(
                              () => _overwriteVerifiedSpecs = value ?? false,
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: widget.controller.isBusy
                              ? null
                              : _syncVerifiedRecipeSet,
                          child: const Text('Sync verified recipe set'),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          widget.controller.recipes.isEmpty
                              ? 'No verified specs are live for this venue yet. Refreshing will load the curated source set into the live app.'
                              : 'Verified specs already power the live library for this venue. Refresh again whenever you want to re-apply the current curated source.',
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _StatusChip(
                              label: 'Live verified cocktails',
                              value: '${widget.controller.recipes.length}',
                              color: const Color(0xFF3B82F6),
                            ),
                            _StatusChip(
                              label: 'Live verified batches',
                              value: '${widget.controller.batches.length}',
                              color: const Color(0xFF4DBA87),
                            ),
                          ],
                        ),
                        if (syncResult != null) ...[
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _StatusChip(
                                label: 'Cocktails synced',
                                value:
                                    '${syncResult.cocktailsAdded + syncResult.cocktailsUpdated}',
                                color: const Color(0xFF3B82F6),
                              ),
                              _StatusChip(
                                label: 'Batches synced',
                                value:
                                    '${syncResult.batchesAdded + syncResult.batchesUpdated}',
                                color: const Color(0xFF4DBA87),
                              ),
                              _StatusChip(
                                label: 'Flagged specs',
                                value:
                                    '${syncResult.flaggedCocktails + syncResult.flaggedBatches}',
                                color: const Color(0xFFE1A545),
                              ),
                              _StatusChip(
                                label: 'Missing images',
                                value: '${syncResult.missingImages}',
                                color: const Color(0xFF718096),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 14),
                        TextButton(
                          onPressed: widget.controller.isBusy
                              ? null
                              : _importCuratedSpecs,
                          child: const Text('Preview curated drafts instead'),
                        ),
                        Text(
                          'Use the draft preview only when you need to inspect how the curated OCR dataset would look in the old review flow. It no longer controls the live bartender experience.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    );
                  },
                ),
              ),
              _Panel(
                width: 460,
                title: 'PDF import',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose the cocktail-spec PDF from your device. If the file has selectable text, the app will build review drafts automatically.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton(
                      onPressed: widget.controller.isBusy ? null : _pickPdf,
                      child: const Text('Choose PDF'),
                    ),
                    const SizedBox(height: 14),
                    if (importResult != null)
                      Text(
                        'Latest source: ${importResult.sourceName} • ${importResult.pageCount} pages',
                      ),
                    if (widget.controller.errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        widget.controller.errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _Panel(
                width: 460,
                title: 'OCR fallback and manual import',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _ocrTextController,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText:
                            'Paste OCR text from the PDF if direct extraction misses key lines',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton(
                          onPressed: _pickOcrTextFile,
                          child: const Text('Choose OCR text file'),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            final result = widget.controller.importFromOcrText(
                              text: _ocrTextController.text,
                              sourceName: 'OCR text paste',
                            );
                            setState(() {
                              _resetCuratedPreviewState();
                              _reviewActionMessage = null;
                              _reviewActionIsError = false;
                              _drafts = result.drafts
                                  .map((item) => item.copyWith())
                                  .toList();
                            });
                          },
                          child: const Text('Build review drafts'),
                        ),
                        TextButton(
                          onPressed: () {
                            final draft = widget.controller.parseRecipeFromText(
                              _manualTextController.text,
                            );
                            if (draft == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Add a cocktail name or at least one recognisable spec line so we can build a draft from it.',
                                  ),
                                ),
                              );
                              return;
                            }
                            setState(() {
                              _resetCuratedPreviewState();
                              _reviewActionMessage = null;
                              _reviewActionIsError = false;
                              _drafts = [..._drafts, draft];
                            });
                          },
                          child: const Text('Add manual spec draft'),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _resetCuratedPreviewState();
                              _reviewActionMessage = null;
                              _reviewActionIsError = false;
                              _drafts = [
                                ..._drafts,
                                RecipeImportDraft(
                                  id: 'draft-${DateTime.now().microsecondsSinceEpoch}',
                                  sourceLabel: 'Manual draft',
                                  pageLabel: 'Manual draft',
                                  name: '',
                                  category: '',
                                  glassware: '',
                                  garnish: '',
                                  method: '',
                                  notes: '',
                                  ingredients: const [
                                    RecipeIngredient(
                                      ingredientName: '',
                                      measureMl: null,
                                    ),
                                  ],
                                  reviewFlags: const [
                                    'Created manually and needs review before saving.',
                                  ],
                                  status: RecipeDraftStatus.pending,
                                  wasManuallyReviewed: true,
                                ),
                              ];
                            });
                          },
                          child: const Text('Start blank spec'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _manualTextController,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Manual structured recipe text',
                        hintText:
                            'Cocktail: House Collins\nGin 40ml\nLemon juice 20ml\nGarnish: Lemon wedge\nGlassware: Highball\nMethod: Build over ice',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (importResult != null) ...[
            const SizedBox(height: 24),
            _Panel(
              title: 'Import findings',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (importResult.warnings.isEmpty)
                    const Text('No extraction notes so far.')
                  else
                    ...importResult.warnings.map(
                      (warning) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('• $warning'),
                      ),
                    ),
                  if (importResult.requiresOcr) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'This PDF looks scanned or image-based. OCR will probably be needed before specs can be extracted automatically.',
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          _Panel(
            title: 'Review imported specs before saving',
            child: _visibleDrafts.isEmpty
                ? const _EmptyText(
                    'Import a PDF, paste OCR text, or start a blank spec to prepare review drafts.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Only approved specs go live into practice, stock focus, and variance calculations.',
                      ),
                      if (_isCuratedPreview) ...[
                        const SizedBox(height: 10),
                        Text(
                          _curatedConflictMode ==
                                  CuratedImportConflictMode.updateExisting
                              ? 'Matching curated recipes will update the existing venue specs in place after approval.'
                              : _curatedConflictMode ==
                                    CuratedImportConflictMode.skipExisting
                              ? 'Matching curated recipes can still be reviewed here, but this import mode will leave them untouched when you confirm.'
                              : 'Only net-new curated recipes are shown in this review batch.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (_reviewActionMessage != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _reviewActionMessage!,
                          style: TextStyle(
                            color: _reviewActionIsError
                                ? Theme.of(context).colorScheme.error
                                : const Color(0xFF4DBA87),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _StatusChip(
                            label: 'Showing',
                            value: '${filteredDrafts.length}/${_drafts.length}',
                            color: const Color(0xFF9F7AEA),
                          ),
                          _StatusChip(
                            label: 'High confidence',
                            value:
                                '${_visibleDrafts.where((draft) => _reviewState(draft).confidence == RecipeConfidence.highConfidence).length}',
                            color: const Color(0xFF4DBA87),
                          ),
                          _StatusChip(
                            label: 'Needs review',
                            value: '${counts.needsReview}',
                            color: const Color(0xFFE1A545),
                          ),
                          _StatusChip(
                            label: 'Possible OCR issue',
                            value: '${counts.possibleOcrIssue}',
                            color: const Color(0xFFE46F6F),
                          ),
                          _StatusChip(
                            label: 'Approved',
                            value: '${counts.approved}',
                            color: const Color(0xFF3B82F6),
                          ),
                          _StatusChip(
                            label: 'Removed',
                            value: '${counts.deleted}',
                            color: const Color(0xFF718096),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _SizedField(
                            width: 240,
                            child: TextField(
                              controller: _draftSearchController,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Search spec name',
                              ),
                            ),
                          ),
                          _SizedField(
                            width: 220,
                            child: DropdownButtonFormField<RecipeConfidence?>(
                              initialValue: _draftConfidenceFilter,
                              isExpanded: true,
                              items: const [
                                DropdownMenuItem(
                                  value: null,
                                  child: Text('All confidence states'),
                                ),
                                DropdownMenuItem(
                                  value: RecipeConfidence.highConfidence,
                                  child: Text('High confidence'),
                                ),
                                DropdownMenuItem(
                                  value: RecipeConfidence.needsReview,
                                  child: Text('Needs review'),
                                ),
                                DropdownMenuItem(
                                  value: RecipeConfidence.possibleOcrIssue,
                                  child: Text('Possible OCR issue'),
                                ),
                              ],
                              onChanged: (value) => setState(
                                () => _draftConfidenceFilter = value,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Confidence filter',
                              ),
                            ),
                          ),
                          _SizedField(
                            width: 220,
                            child: DropdownButtonFormField<String>(
                              initialValue: _draftCategoryFilter,
                              isExpanded: true,
                              items: categoryOptions
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: Text(value),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) => setState(
                                () => _draftCategoryFilter =
                                    value ?? 'All categories',
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Category filter',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ElevatedButton(
                            onPressed: _approveAllHighConfidence,
                            child: const Text(
                              'Approve all high-confidence specs',
                            ),
                          ),
                          OutlinedButton(
                            onPressed: _keepSuspiciousDraftsInReview,
                            child: const Text('Keep unclear drafts in review'),
                          ),
                          OutlinedButton(
                            onPressed:
                                counts.approved > 0 && !widget.controller.isBusy
                                ? _confirmImport
                                : null,
                            child: const Text('Publish approved specs'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (filteredDrafts.isEmpty)
                        const _EmptyText(
                          'No review drafts match these filters yet.',
                        )
                      else
                        ..._drafts
                            .asMap()
                            .entries
                            .where(
                              (entry) => filteredDrafts.contains(entry.value),
                            )
                            .map(
                              (entry) => _RecipeDraftEditorCard(
                                draft: entry.value,
                                reviewState: _reviewState(entry.value),
                                onChanged: (updated) => setState(
                                  () => _replaceDraft(entry.key, updated),
                                ),
                                onApprove: () => _approveDraft(entry.key),
                                onKeepInReview: () => setState(
                                  () => _drafts[entry.key] = widget.controller
                                      .keepImportDraftInReview(
                                        _drafts[entry.key],
                                      ),
                                ),
                                onRemove: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Ignore this draft?'),
                                      content: const Text(
                                        'Ignored drafts will stay out of training and stock workflows unless you import them again later.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(context).pop(false),
                                          child: const Text('Keep draft'),
                                        ),
                                        FilledButton.tonal(
                                          onPressed: () =>
                                              Navigator.of(context).pop(true),
                                          child: const Text('Ignore draft'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (!mounted || confirmed != true) {
                                    return;
                                  }
                                  setState(
                                    () => _drafts[entry.key] = widget.controller
                                        .deleteImportDraft(_drafts[entry.key]),
                                  );
                                },
                              ),
                            ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class ManagerLibraryTab extends StatefulWidget {
  const ManagerLibraryTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<ManagerLibraryTab> createState() => _ManagerLibraryTabState();
}

class _ManagerLibraryTabState extends State<ManagerLibraryTab> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedRecipeId;
  String? _selectedBatchId;
  _ApprovedLibraryView _libraryView = _ApprovedLibraryView.cocktails;
  int? _lastLoggedRecipeCount;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canEditLibrary = widget.controller.canAccessAdminSetup;
    final recipes = widget.controller.searchRecipes(_searchController.text);
    if (_lastLoggedRecipeCount != widget.controller.recipes.length) {
      _lastLoggedRecipeCount = widget.controller.recipes.length;
      developer.log(
        'Cocktail list screen count=${widget.controller.recipes.length} first=${widget.controller.recipes.isEmpty ? '<none>' : widget.controller.recipes.first.name}',
        name: 'TrainingCatalog',
      );
    }
    final batches = widget.controller.batches.where((batch) {
      final normalized = _searchController.text.trim().toLowerCase();
      if (normalized.isEmpty) {
        return true;
      }
      return batch.name.toLowerCase().contains(normalized) ||
          batch.category.toLowerCase().contains(normalized) ||
          batch.ingredients.any(
            (ingredient) =>
                ingredient.ingredientName.toLowerCase().contains(normalized),
          );
    }).toList();
    final selectedRecipe =
        widget.controller.recipesById[_selectedRecipeId ?? ''];
    final selectedBatch = widget.controller.batches
        .where((batch) => batch.id == _selectedBatchId)
        .cast<BatchRecipe?>()
        .firstWhere((batch) => batch != null, orElse: () => null);
    final latestSync = widget.controller.latestVerifiedSyncResult;
    return _ScrollPage(
      title: 'Cocktail list',
      subtitle: canEditLibrary
          ? 'The venue cocktail list is loaded automatically. Keep the specs tidy here and update details whenever service needs change.'
          : 'Browse the live cocktail specs used for training, stock focus, and supportive coaching.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canEditLibrary) ...[
            _Panel(
              width: 940,
              title: 'Training cocktails',
              child: Wrap(
                spacing: 18,
                runSpacing: 18,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 520,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'This venue starts with the checked-in cocktail list automatically. Use the editor below to keep each spec current for service, training, and stock focus.',
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.controller.didAutoPrepareCocktailList
                              ? 'This venue did not have any cocktails yet, so the starter cocktail list was prepared automatically.'
                              : latestSync == null
                              ? 'Saved cocktails already exist for this venue, so the current list is being used as-is.'
                              : '${latestSync.cocktailsAdded + latestSync.cocktailsUpdated} cocktail spec${latestSync.cocktailsAdded + latestSync.cocktailsUpdated == 1 ? '' : 's'} and ${latestSync.batchesAdded + latestSync.batchesUpdated} batch spec${latestSync.batchesAdded + latestSync.batchesUpdated == 1 ? '' : 's'} were prepared the last time the checked-in cocktail list was applied.',
                        ),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _StatusChip(
                        label: 'Cocktails live',
                        value: '${widget.controller.recipes.length}',
                        color: const Color(0xFF3B82F6),
                      ),
                      _StatusChip(
                        label: 'Batches live',
                        value: '${widget.controller.batches.length}',
                        color: const Color(0xFF4DBA87),
                      ),
                      _StatusChip(
                        label: 'Needs a quick look',
                        value:
                            '${widget.controller.recipes.where((item) => item.needsReview).length + widget.controller.batches.where((item) => item.needsReview).length}',
                        color: const Color(0xFFE1A545),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (canEditLibrary) ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ChoiceChip(
                  label: const Text('Cocktails'),
                  selected: _libraryView == _ApprovedLibraryView.cocktails,
                  onSelected: (_) => setState(
                    () => _libraryView = _ApprovedLibraryView.cocktails,
                  ),
                ),
                ChoiceChip(
                  label: const Text('Batches'),
                  selected: _libraryView == _ApprovedLibraryView.batches,
                  onSelected: (_) => setState(
                    () => _libraryView = _ApprovedLibraryView.batches,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
          ],
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: _libraryView == _ApprovedLibraryView.batches
                  ? 'Search batches, ingredients, or categories'
                  : 'Search cocktails, ingredients, or categories',
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 18,
            runSpacing: 18,
            children: [
              _Panel(
                width: 420,
                title: _libraryView == _ApprovedLibraryView.batches
                    ? 'Batch list'
                    : 'Cocktail list',
                child: _libraryView == _ApprovedLibraryView.batches
                    ? batches.isEmpty
                          ? const _EmptyText(
                              'No saved batches are stored yet. Add batch details here when you need them.',
                            )
                          : Column(
                              children: batches
                                  .map(
                                    (batch) => _DataRowTile(
                                      title: batch.name,
                                      subtitle:
                                          '${batch.category.isEmpty ? 'Uncategorised' : batch.category} • ${batch.ingredients.length} ingredients${batch.totalBatchVolumeMl == null ? '' : ' • ${batch.totalBatchVolumeMl!.toStringAsFixed(0)}ml total'}',
                                      trailing: 'Open',
                                      onTap: () => setState(
                                        () => _selectedBatchId = batch.id,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            )
                    : recipes.isEmpty
                    ? const _EmptyText(
                        'No cocktails are live yet. The starter cocktail list should appear automatically for a new venue, so try refreshing the app if it has not shown up yet.',
                      )
                    : Column(
                        children: recipes
                            .map(
                              (recipe) => _DataRowTile(
                                title: recipe.name,
                                subtitle:
                                    '${recipe.category.isEmpty ? 'Uncategorised' : recipe.category} • ${recipe.ingredients.length} ingredients${recipe.needsReview ? ' • needs a quick look' : ''}',
                                trailing: 'Open',
                                onTap: () => setState(
                                  () => _selectedRecipeId = recipe.id,
                                ),
                              ),
                            )
                            .toList(),
                      ),
              ),
              SizedBox(
                width: 500,
                child: _libraryView == _ApprovedLibraryView.batches
                    ? selectedBatch == null
                          ? const _Panel(
                              title: 'Batch detail',
                              child: _EmptyText(
                                'Select a batch to review or edit its detail.',
                              ),
                            )
                          : canEditLibrary
                          ? BatchEditorPanel(
                              batch: selectedBatch,
                              onSave: (updated) {
                                widget.controller.saveBatch(updated);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Batch updated.'),
                                  ),
                                );
                                setState(() {});
                              },
                            )
                          : BatchDetailPanel(batch: selectedBatch)
                    : selectedRecipe == null
                    ? const _Panel(
                        title: 'Cocktail spec',
                        child: _EmptyText(
                          'Select a cocktail to view or edit its live spec.',
                        ),
                      )
                    : canEditLibrary
                    ? RecipeEditorPanel(
                        recipe: selectedRecipe,
                        onSave: (updated) {
                          widget.controller.saveRecipe(updated);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Recipe updated.')),
                          );
                          setState(() {});
                        },
                      )
                    : RecipeDetailPanel(recipe: selectedRecipe),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class CocktailLibraryTab extends StatefulWidget {
  const CocktailLibraryTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<CocktailLibraryTab> createState() => _CocktailLibraryTabState();
}

class _CocktailLibraryTabState extends State<CocktailLibraryTab> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedRecipeId;
  String _categoryFilter = 'All categories';
  String _ingredientFilter = 'All ingredients';

  Future<void> _openQuickQuiz(CocktailRecipe recipe) async {
    final quiz = widget.controller.generatePracticeQuiz(
      bartenderName:
          widget.controller.currentUser?.displayName.trim().isNotEmpty == true
          ? widget.controller.currentUser!.displayName.trim()
          : 'Training user',
      focusRecipeIds: [recipe.id],
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text('Quiz me on ${recipe.name}')),
          body: SafeArea(
            child: QuizPlayerPanel(
              controller: widget.controller,
              session: quiz,
              onExit: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searched = widget.controller.searchRecipes(_searchController.text);
    final categoryValues = {
      for (final recipe in widget.controller.recipes)
        if (recipe.category.trim().isNotEmpty) recipe.category.trim(),
    }.toList()..sort();
    final ingredientValues = {
      for (final recipe in widget.controller.recipes)
        ...recipe.ingredients
            .map((ingredient) => ingredient.ingredientName.trim())
            .where((name) => name.isNotEmpty),
    }.toList()..sort();
    final categoryOptions = ['All categories', ...categoryValues];
    final ingredientOptions = ['All ingredients', ...ingredientValues];
    final results = searched.where((recipe) {
      final categoryMatches =
          _categoryFilter == 'All categories' ||
          recipe.category.trim() == _categoryFilter;
      final ingredientMatches =
          _ingredientFilter == 'All ingredients' ||
          recipe.ingredients.any(
            (ingredient) =>
                ingredient.ingredientName.trim() == _ingredientFilter,
          );
      return categoryMatches && ingredientMatches;
    }).toList();
    final selected =
        widget.controller.recipesById[_selectedRecipeId ?? ''] ??
        results.firstOrNull;
    return _ScrollPage(
      title: 'Cocktail list',
      subtitle:
          'Browse the live cocktail specs, then filter by category or ingredient for faster study.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatusChip(
                label: 'Training cocktails',
                value: '${widget.controller.recipes.length}',
                color: const Color(0xFF3B82F6),
              ),
              _StatusChip(
                label: 'Filtered results',
                value: '${results.length}',
                color: const Color(0xFF4DBA87),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Search cocktail name, category, or ingredient',
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _SizedField(
                width: 220,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _categoryFilter,
                  items: categoryOptions
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) => setState(
                    () => _categoryFilter = value ?? 'All categories',
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Category filter',
                  ),
                ),
              ),
              _SizedField(
                width: 220,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _ingredientFilter,
                  items: ingredientOptions
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) => setState(
                    () => _ingredientFilter = value ?? 'All ingredients',
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Ingredient filter',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 18,
            runSpacing: 18,
            children: [
              _Panel(
                width: 420,
                title: 'Cocktails',
                child: results.isEmpty
                    ? const _EmptyText(
                        'No cocktails match these filters yet. Try another ingredient or category.',
                      )
                    : Column(
                        children: results
                            .map(
                              (recipe) => Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: _CocktailLibraryCard(
                                  recipe: recipe,
                                  selected: selected?.id == recipe.id,
                                  onLearn: () => setState(
                                    () => _selectedRecipeId = recipe.id,
                                  ),
                                  onQuiz: () => _openQuickQuiz(recipe),
                                ),
                              ),
                            )
                            .toList(),
                      ),
              ),
              SizedBox(
                width: 520,
                child: selected == null
                    ? const _Panel(
                        title: 'Cocktail spec',
                        child: _EmptyText(
                          'Open a cocktail from the library to view its spec.',
                        ),
                      )
                    : RecipeDetailPanel(recipe: selected),
              ),
            ],
          ),
        ],
      ),
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
  String? _selectedRecipeId;
  Map<String, _StudyProgressEntry> _progressByRecipe = {};
  int? _lastLoggedRecipeCount;

  String get _studyProgressStorageKey {
    final venueId = widget.controller.currentUser?.venueId ?? 'public';
    final userId =
        widget.controller.currentUser?.id ??
        widget.controller.currentUser?.displayName ??
        'guest';
    return _studyProgressStorageKeyFor(venueId: venueId, userKey: userId);
  }

  @override
  void initState() {
    super.initState();
    _restoreProgress();
  }

  void _restoreProgress() {
    _progressByRecipe = _loadStudyProgressEntries(
      venueId: widget.controller.currentUser?.venueId ?? 'public',
      userKey:
          widget.controller.currentUser?.id ??
          widget.controller.currentUser?.displayName ??
          'guest',
    );
  }

  void _persistProgress() {
    BrowserStorage.setString(
      _studyProgressStorageKey,
      jsonEncode({
        for (final entry in _progressByRecipe.entries) entry.key: entry.value.toMap(),
      }),
    );
  }

  _StudyProgressEntry _progressFor(String recipeId) =>
      _progressByRecipe[recipeId] ?? const _StudyProgressEntry();

  void _saveProgress(String recipeId, _StudyProgressEntry entry) {
    setState(() {
      _progressByRecipe[recipeId] = entry;
    });
    _persistProgress();
  }

  @override
  Widget build(BuildContext context) {
    final recipes = widget.controller.recipes;
    if (_lastLoggedRecipeCount != recipes.length) {
      _lastLoggedRecipeCount = recipes.length;
      developer.log(
        'Study screen count=${recipes.length} first=${recipes.isEmpty ? '<none>' : recipes.first.name}',
        name: 'TrainingCatalog',
      );
    }
    final recipe =
        widget.controller.recipesById[_selectedRecipeId ?? ''] ??
        recipes.firstOrNull;
    final progress = recipe == null
        ? const _StudyProgressEntry()
        : _progressFor(recipe.id);
    final confidenceLabel = switch (progress.confidence) {
      _StudyConfidenceStatus.confident => 'Confident',
      _StudyConfidenceStatus.needsPractice => 'Needs practice',
      null => 'Not marked yet',
    };
    final lastPractisedText = progress.lastPractised == null
        ? 'Not practised yet'
        : 'Last practised ${DateFormat('d MMM, HH:mm').format(progress.lastPractised!.toLocal())}';
    final confidentCount = _progressByRecipe.values
        .where((entry) => entry.confidence == _StudyConfidenceStatus.confident)
        .length;
    final needsPracticeCount = _progressByRecipe.values
        .where(
          (entry) => entry.confidence == _StudyConfidenceStatus.needsPractice,
        )
        .length;
    return _ScrollPage(
      title: 'Study mode',
      subtitle:
          'Learn one cocktail at a time, hide or reveal the spec details, and leave yourself a simple confidence note for next time.',
      child: recipe == null
          ? const _Panel(
              title: 'No training cocktails yet',
              child: _EmptyText(
                'Load the cocktail list first, then study cards will appear here with the live specs.',
              ),
            )
          : Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: recipe.id,
                  items: recipes
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _selectedRecipeId = value),
                  decoration: const InputDecoration(
                    labelText: 'Choose a cocktail',
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _StatusChip(
                      label: 'Confident',
                      value: '$confidentCount',
                      color: const Color(0xFF4DBA87),
                    ),
                    _StatusChip(
                      label: 'Needs practice',
                      value: '$needsPracticeCount',
                      color: const Color(0xFFE1A545),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          recipe.name,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 10),
                        _RecipeHeroImage(recipe: recipe),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _StatusChip(
                              label: 'Your note',
                              value: confidenceLabel,
                              color: progress.confidence ==
                                      _StudyConfidenceStatus.confident
                                  ? const Color(0xFF4DBA87)
                                  : const Color(0xFFE1A545),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(lastPractisedText),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilterChip(
                              selected: progress.showIngredients,
                              label: const Text('Reveal ingredients'),
                              onSelected: (value) => _saveProgress(
                                recipe.id,
                                progress.copyWith(
                                  showIngredients: value,
                                  lastPractisedIso:
                                      DateTime.now().toIso8601String(),
                                ),
                              ),
                            ),
                            FilterChip(
                              selected: progress.showMeasures,
                              label: const Text('Reveal measures'),
                              onSelected: progress.showIngredients
                                  ? (value) => _saveProgress(
                                      recipe.id,
                                      progress.copyWith(
                                        showMeasures: value,
                                        lastPractisedIso:
                                            DateTime.now().toIso8601String(),
                                      ),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        RecipeDetailPanel(
                          recipe: recipe,
                          embedded: true,
                          revealIngredients: progress.showIngredients,
                          revealMeasures: progress.showMeasures,
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton.tonal(
                              onPressed: () => _saveProgress(
                                recipe.id,
                                progress.copyWith(
                                  confidence:
                                      _StudyConfidenceStatus.needsPractice,
                                  lastPractisedIso:
                                      DateTime.now().toIso8601String(),
                                ),
                              ),
                              child: const Text('Needs practice'),
                            ),
                            ElevatedButton(
                              onPressed: () => _saveProgress(
                                recipe.id,
                                progress.copyWith(
                                  confidence: _StudyConfidenceStatus.confident,
                                  lastPractisedIso:
                                      DateTime.now().toIso8601String(),
                                ),
                              ),
                              child: const Text('Confident'),
                            ),
                          ],
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

class PracticeTab extends StatefulWidget {
  const PracticeTab({
    super.key,
    required this.controller,
    required this.activeSessionId,
    required this.onSessionChanged,
  });

  final AppController controller;
  final String? activeSessionId;
  final ValueChanged<String?> onSessionChanged;

  @override
  State<PracticeTab> createState() => _PracticeTabState();
}

class _PracticeTabState extends State<PracticeTab> {
  final TextEditingController _nameController = TextEditingController(
    text: 'Training user',
  );

  String get _enteredBartenderName {
    final trimmed = _nameController.text.trim();
    return trimmed.isEmpty ? 'Training user' : trimmed;
  }

  List<String> _practiceFocusRecipeIds() {
    final venueId = widget.controller.currentUser?.venueId ?? 'public';
    final progressByRecipe = _loadStudyProgressEntries(
      venueId: venueId,
      userKey:
          widget.controller.currentUser?.id ??
          widget.controller.currentUser?.displayName ??
          _enteredBartenderName,
    );
    final rankedIds = <String>[];
    rankedIds.addAll(
      widget.controller
          .weakAreaRecipeSuggestions()
          .map((item) => item.id)
          .where((id) => !rankedIds.contains(id)),
    );
    rankedIds.addAll(
      widget.controller.recipes
          .where(
            (recipe) =>
                progressByRecipe[recipe.id]?.confidence ==
                _StudyConfidenceStatus.needsPractice,
          )
          .map((recipe) => recipe.id)
          .where((id) => !rankedIds.contains(id)),
    );
    rankedIds.addAll(
      widget.controller.recipes
          .where((recipe) => !progressByRecipe.containsKey(recipe.id))
          .map((recipe) => recipe.id)
          .where((id) => !rankedIds.contains(id)),
    );
    return rankedIds.take(6).toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.activeSessionId == null
        ? null
        : widget.controller.findQuizSession(widget.activeSessionId!);
    final latestPracticeAttempt = widget.controller.quizAttempts
        .where((attempt) => attempt.weekId == null)
        .cast<QuizAttempt?>()
        .firstWhere((attempt) => attempt != null, orElse: () => null);
    return _ScrollPage(
      title: 'Practice round',
      subtitle:
          'Build recipe confidence with quick, low-pressure practice across your live cocktail specs.',
      child: widget.controller.recipes.isEmpty
          ? const _Panel(
              title: 'No cocktails ready yet',
              child: _EmptyText(
                'Load the cocktail list first so practice questions can be built from your real service builds.',
              ),
            )
          : session == null
          ? _Panel(
              title: 'Start a practice round',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (latestPracticeAttempt != null) ...[
                    Text(
                      'Latest practice round: ${latestPracticeAttempt.scorePercent}% recipe confidence',
                    ),
                    const SizedBox(height: 10),
                    Text(latestPracticeAttempt.encouragement),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _StatusChip(
                          label: 'Coaching areas',
                          value:
                              '${latestPracticeAttempt.coachingAreas.length}',
                          color: const Color(0xFFE1A545),
                        ),
                        _StatusChip(
                          label: 'Questions answered',
                          value: '${latestPracticeAttempt.responses.length}',
                          color: const Color(0xFF4DBA87),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Your name'),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Rounds stay short at around 10 questions and lean toward cocktails you have not practised yet, specs marked needs practice, and recent coaching areas.',
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          final focusIds = _practiceFocusRecipeIds();
                          final quiz = widget.controller.generatePracticeQuiz(
                            bartenderName: _enteredBartenderName,
                            focusRecipeIds: focusIds.isEmpty ? null : focusIds,
                          );
                          widget.onSessionChanged(quiz.id);
                        },
                        child: const Text('Start practice round'),
                      ),
                      OutlinedButton(
                        onPressed: () {
                          final focusIds = widget.controller
                              .weakAreaRecipeSuggestions()
                              .map((item) => item.id)
                              .toList();
                          final quiz = widget.controller.generatePracticeQuiz(
                            bartenderName: _enteredBartenderName,
                            focusRecipeIds: focusIds.isEmpty ? null : focusIds,
                          );
                          widget.onSessionChanged(quiz.id);
                        },
                        child: const Text('Focus on coaching areas'),
                      ),
                    ],
                  ),
                ],
              ),
            )
          : QuizPlayerPanel(
              controller: widget.controller,
              session: session,
              onExit: () => widget.onSessionChanged(null),
            ),
    );
  }
}

class WeakAreasTab extends StatelessWidget {
  const WeakAreasTab({
    super.key,
    required this.controller,
    required this.onStartWeakAreaQuiz,
  });

  final AppController controller;
  final VoidCallback onStartWeakAreaQuiz;

  @override
  Widget build(BuildContext context) {
    final suggestions = controller.weakAreaRecipeSuggestions();
    return _ScrollPage(
      title: 'Coaching refreshers',
      subtitle:
          'Use previous session results to revisit the specs and cocktails that feel most worthwhile to practise again.',
      child: _Panel(
        title: 'Suggested refreshers',
        child: suggestions.isEmpty
            ? const _EmptyText(
                'Complete a practice or stock-focus session first to unlock tailored refresher suggestions.',
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: suggestions
                        .map((recipe) => Chip(label: Text(recipe.name)))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'These are the cocktails that have come up most often as coaching opportunities. Keep building confidence one spec at a time.',
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed: onStartWeakAreaQuiz,
                    child: const Text('Start refresher round'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _RecipeThumbnail extends StatelessWidget {
  const _RecipeThumbnail({required this.recipe});

  final CocktailRecipe recipe;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 72,
        height: 72,
        child: _RecipeImageFrame(recipe: recipe),
      ),
    );
  }
}

class _CocktailLibraryCard extends StatelessWidget {
  const _CocktailLibraryCard({
    required this.recipe,
    required this.selected,
    required this.onLearn,
    required this.onQuiz,
  });

  final CocktailRecipe recipe;
  final bool selected;
  final VoidCallback onLearn;
  final VoidCallback onQuiz;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected
              ? const Color(0xFF4DBA87).withValues(alpha: 0.75)
              : Colors.transparent,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RecipeThumbnail(recipe: recipe),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recipe.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge,
                        softWrap: true,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(
                            label: Text(
                              recipe.category.isEmpty
                                  ? 'Cocktail spec'
                                  : recipe.category,
                            ),
                          ),
                          if (recipe.needsReview)
                            const Chip(label: Text('Needs a quick look')),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _recipeIngredientPreview(recipe),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonal(
                  onPressed: onLearn,
                  child: const Text('Learn'),
                ),
                OutlinedButton(
                  onPressed: onQuiz,
                  child: const Text('Quiz me'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _StudyConfidenceStatus { needsPractice, confident }

class _StudyProgressEntry {
  const _StudyProgressEntry({
    this.showIngredients = false,
    this.showMeasures = false,
    this.confidence,
    this.lastPractisedIso,
  });

  final bool showIngredients;
  final bool showMeasures;
  final _StudyConfidenceStatus? confidence;
  final String? lastPractisedIso;

  DateTime? get lastPractised => lastPractisedIso == null
      ? null
      : DateTime.tryParse(lastPractisedIso!);

  _StudyProgressEntry copyWith({
    bool? showIngredients,
    bool? showMeasures,
    _StudyConfidenceStatus? confidence,
    bool clearConfidence = false,
    String? lastPractisedIso,
  }) {
    return _StudyProgressEntry(
      showIngredients: showIngredients ?? this.showIngredients,
      showMeasures: showMeasures ?? this.showMeasures,
      confidence: clearConfidence ? null : (confidence ?? this.confidence),
      lastPractisedIso: lastPractisedIso ?? this.lastPractisedIso,
    );
  }

  Map<String, dynamic> toMap() => {
    'showIngredients': showIngredients,
    'showMeasures': showMeasures,
    'confidence': confidence?.name,
    'lastPractisedIso': lastPractisedIso,
  };

  static _StudyProgressEntry fromMap(Map<String, dynamic> map) {
    final confidenceName = map['confidence'] as String?;
    _StudyConfidenceStatus? confidence;
    for (final value in _StudyConfidenceStatus.values) {
      if (value.name == confidenceName) {
        confidence = value;
        break;
      }
    }
    return _StudyProgressEntry(
      showIngredients: map['showIngredients'] == true,
      showMeasures: map['showMeasures'] == true,
      confidence: confidence,
      lastPractisedIso: map['lastPractisedIso'] as String?,
    );
  }
}

String _studyProgressStorageKeyFor({
  required String venueId,
  required String userKey,
}) => 'study-progress-$venueId-$userKey';

Map<String, _StudyProgressEntry> _loadStudyProgressEntries({
  required String venueId,
  required String userKey,
}) {
  final raw = BrowserStorage.getString(
    _studyProgressStorageKeyFor(venueId: venueId, userKey: userKey),
  );
  if (raw == null || raw.trim().isEmpty) {
    return const {};
  }
  try {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map(
      (key, value) => MapEntry(
        key,
        _StudyProgressEntry.fromMap((value as Map).cast<String, dynamic>()),
      ),
    );
  } catch (_) {
    return const {};
  }
}

class _RecipeHeroImage extends StatelessWidget {
  const _RecipeHeroImage({required this.recipe});

  final CocktailRecipe recipe;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: _RecipeImageFrame(recipe: recipe),
      ),
    );
  }
}

class _RecipeImageFrame extends StatelessWidget {
  const _RecipeImageFrame({required this.recipe});

  final CocktailRecipe recipe;

  @override
  Widget build(BuildContext context) {
    final colors =
        Theme.of(context).extension<AppStatusColors>() ??
        const AppStatusColors(
          highlight: Color(0xFF7CD4B3),
          warning: Color(0xFFE1A545),
          accent: Color(0xFF6FB6FF),
        );
    if ((recipe.imageAssetPath ?? '').trim().isNotEmpty &&
        !recipe.missingImage) {
      return Image.asset(
        recipe.imageAssetPath!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _MissingRecipeImage(colors: colors);
        },
      );
    }
    return _MissingRecipeImage(colors: colors);
  }
}

class _MissingRecipeImage extends StatelessWidget {
  const _MissingRecipeImage({required this.colors});

  final AppStatusColors colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.highlight.withValues(alpha: 0.26),
            colors.accent.withValues(alpha: 0.18),
            const Color(0xFF12181D),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_bar_outlined, color: colors.highlight, size: 34),
            const SizedBox(height: 10),
            Text(
              'Source image pending',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class IngredientsTab extends StatefulWidget {
  const IngredientsTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<IngredientsTab> createState() => _IngredientsTabState();
}

class _IngredientsTabState extends State<IngredientsTab> {
  final _nameController = TextEditingController();
  final _sizeController = TextEditingController(text: '700');
  final _costController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _sizeController.dispose();
    _costController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.canAccessAdminSetup) {
      return const _ScrollPage(
        title: 'Pricing',
        subtitle: 'Ingredient pricing is part of owner/admin setup.',
        child: _Panel(
          title: 'Owner/admin access required',
          child: _EmptyText(
            'Official ingredient pricing, missing-cost resolution, and batch costing stay with the owner/admin so venue managers can stay focused on weekly stock actions.',
          ),
        ),
      );
    }
    final currency = NumberFormat.currency(symbol: '£', decimalDigits: 2);
    return _ScrollPage(
      title: 'Pricing',
      subtitle:
          'Store bottle cost once during admin setup so variance projections can include a helpful approximate value.',
      child: Wrap(
        spacing: 18,
        runSpacing: 18,
        children: [
          _Panel(
            width: 420,
            title: 'Add or update ingredient',
            child: Column(
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Ingredient name',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _sizeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Bottle size ml',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _costController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Bottle cost £'),
                ),
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: () {
                    widget.controller.saveIngredient(
                      name: _nameController.text.trim(),
                      bottleSizeMl:
                          double.tryParse(_sizeController.text.trim()) ?? 0,
                      bottleCost:
                          double.tryParse(_costController.text.trim()) ?? 0,
                    );
                    _nameController.clear();
                    _costController.clear();
                    setState(() {});
                  },
                  child: const Text('Save ingredient'),
                ),
              ],
            ),
          ),
          _Panel(
            width: 500,
            title: 'Stored pricing',
            child: widget.controller.ingredients.isEmpty
                ? const _EmptyText(
                    'Ingredients from the live cocktail list will appear here as pricing is added.',
                  )
                : Column(
                    children: widget.controller.ingredients
                        .map(
                          (ingredient) => _DataRowTile(
                            title: ingredient.name,
                            subtitle:
                                '${ingredient.bottleSizeMl.toStringAsFixed(0)}ml bottle • ${currency.format(ingredient.bottleCost)}',
                            trailing:
                                '${currency.format(ingredient.costPerMl)}/ml',
                          ),
                        )
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class WeeklyFocusTab extends StatefulWidget {
  const WeeklyFocusTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<WeeklyFocusTab> createState() => _WeeklyFocusTabState();
}

class _WeeklyFocusTabState extends State<WeeklyFocusTab> {
  final TextEditingController _labelController = TextEditingController(
    text: 'Monday focus ${DateFormat('d MMM').format(DateTime.now())}',
  );
  final Map<String, bool> _selectedConcerns = {};
  final Map<String, TextEditingController> _shortControllers = {};
  final Map<String, TextEditingController> _impactControllers = {};
  final Map<String, TextEditingController> _noteControllers = {};
  final TextEditingController _bartenderController = TextEditingController();
  final Map<String, TextEditingController> _salesControllers = {};
  String? _selectedWeekId;
  bool _hasUnsavedLocalProgress = false;
  bool _didRestoreLocalProgress = false;

  String get _draftStorageKey =>
      'weekly-workflow-draft-${widget.controller.currentUser?.venueId ?? 'public'}';

  @override
  void initState() {
    super.initState();
    _restoreLocalDraft();
  }

  @override
  void dispose() {
    _labelController.dispose();
    _bartenderController.dispose();
    for (final controller in _shortControllers.values) {
      controller.dispose();
    }
    for (final controller in _impactControllers.values) {
      controller.dispose();
    }
    for (final controller in _noteControllers.values) {
      controller.dispose();
    }
    for (final controller in _salesControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _restoreLocalDraft() {
    final stored = BrowserStorage.getString(_draftStorageKey);
    if (stored == null || stored.trim().isEmpty) {
      return;
    }
    final draft = WeeklyWorkflowDraft.fromJson(stored);
    _selectedWeekId = draft.selectedWeekId;
    _selectedConcerns
      ..clear()
      ..addAll(draft.selectedConcerns);
    _replaceControllerValues(_shortControllers, draft.shortValues);
    _replaceControllerValues(_impactControllers, draft.impactValues);
    _replaceControllerValues(_noteControllers, draft.noteValues);
    _replaceControllerValues(_salesControllers, draft.salesValues);
    _bartenderController.text = draft.bartenderName;
    _hasUnsavedLocalProgress = draft.hasUnsavedProgress;
    _didRestoreLocalProgress = draft.hasUnsavedProgress;
  }

  void _replaceControllerValues(
    Map<String, TextEditingController> target,
    Map<String, String> values,
  ) {
    values.forEach((key, value) {
      target[key]?.text = value;
      target.putIfAbsent(key, () => TextEditingController(text: value));
    });
  }

  void _persistLocalDraft() {
    final draft = WeeklyWorkflowDraft(
      selectedWeekId: _selectedWeekId,
      selectedConcerns: Map<String, bool>.from(_selectedConcerns),
      shortValues: _controllerValues(_shortControllers),
      impactValues: _controllerValues(_impactControllers),
      noteValues: _controllerValues(_noteControllers),
      bartenderName: _bartenderController.text,
      salesValues: _controllerValues(_salesControllers),
    );
    if (!draft.hasUnsavedProgress) {
      BrowserStorage.remove(_draftStorageKey);
      _hasUnsavedLocalProgress = false;
      return;
    }
    BrowserStorage.setString(_draftStorageKey, draft.toJson());
    _hasUnsavedLocalProgress = true;
  }

  Map<String, String> _controllerValues(
    Map<String, TextEditingController> source,
  ) {
    return {
      for (final entry in source.entries)
        if (entry.value.text.trim().isNotEmpty) entry.key: entry.value.text,
    };
  }

  void _clearLocalDraft() {
    BrowserStorage.remove(_draftStorageKey);
    setState(() {
      _hasUnsavedLocalProgress = false;
      _didRestoreLocalProgress = false;
    });
  }

  WeeklyConcernSession? get _selectedSession => _selectedWeekId == null
      ? widget.controller.weeklySessions.firstOrNull
      : widget.controller.findWeeklySession(_selectedWeekId!);

  Iterable<String> get _availableConcernIngredients =>
      widget.controller.concernIngredientNames;

  List<CocktailRecipe> _relevantRecipes(WeeklyConcernSession session) => session
      .targetCocktailIds
      .map((id) => widget.controller.recipesById[id])
      .whereType<CocktailRecipe>()
      .toList();

  int _bartenderTotal(BartenderWeeklySales sales) =>
      sales.entries.fold<int>(0, (sum, entry) => sum + entry.quantitySold);

  int _cocktailTotal(WeeklyConcernSession session, CocktailRecipe recipe) {
    return session.bartenderSales.fold<int>(
      0,
      (sum, record) =>
          sum +
          record.entries
              .where((entry) => entry.cocktailId == recipe.id)
              .fold<int>(0, (inner, entry) => inner + entry.quantitySold),
    );
  }

  bool _hasInvalidQuantities(
    WeeklyConcernSession session,
    List<CocktailRecipe> relevantRecipes,
  ) {
    for (final recipe in relevantRecipes) {
      final raw =
          _salesControllers['${session.id}-${recipe.id}']?.text.trim() ?? '';
      if (raw.isEmpty) {
        continue;
      }
      final parsed = int.tryParse(raw);
      if (parsed == null || parsed < 0) {
        return true;
      }
    }
    return false;
  }

  Map<String, String> _rawSalesByCocktailId(
    WeeklyConcernSession session,
    List<CocktailRecipe> relevantRecipes,
  ) {
    return {
      for (final recipe in relevantRecipes)
        recipe.id: _salesControllers['${session.id}-${recipe.id}']?.text ?? '',
    };
  }

  void _clearSalesInputs(
    WeeklyConcernSession session,
    List<CocktailRecipe> relevantRecipes,
  ) {
    _bartenderController.clear();
    for (final recipe in relevantRecipes) {
      _salesControllers['${session.id}-${recipe.id}']?.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.canAccessManagerWorkflows) {
      return const _ScrollPage(
        title: 'Stock focus',
        subtitle:
            'Only the owner/admin or a venue manager can run operational stock workflows.',
        child: _Panel(
          title: 'Operational access required',
          child: _EmptyText(
            'Stock concerns, bartender sales, live session links, and coaching review stay inside the owner/admin and venue manager workflow.',
          ),
        ),
      );
    }
    final session = _selectedSession;
    final relevantRecipes = session == null
        ? <CocktailRecipe>[]
        : _relevantRecipes(session);
    final groupedRelevantRecipes = session == null
        ? <String, List<CocktailRecipe>>{}
        : widget.controller.relevantRecipesGroupedByConcern(session);
    final selectableIngredients = _availableConcernIngredients.toList();
    final workflow = widget.controller.stockWorkflowProgress(session);
    final selectedConcernNames =
        session?.concerns.map((item) => item.ingredientName).toList() ??
        const <String>[];
    final activeQuizCount = session == null
        ? 0
        : widget.controller.quizSessions
              .where((quiz) => quiz.weekId == session.id && quiz.isActive)
              .length;

    return _ScrollPage(
      title: 'Stock focus',
      subtitle:
          'Choose the ingredients that need attention, capture only the relevant bartender sales, and generate a focused practice session for the team.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_hasUnsavedLocalProgress)
            _Panel(
              title: 'Recovered local progress',
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _didRestoreLocalProgress
                          ? 'A local working draft was restored after refresh. Save it when ready, or clear it if you would rather start fresh.'
                          : 'Unsaved changes are being held locally in this browser so you can step away and come back without losing progress mid-shift.',
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _clearLocalDraft,
                    child: const Text('Clear local draft'),
                  ),
                ],
              ),
            ),
          if (_hasUnsavedLocalProgress) const SizedBox(height: 24),
          _Panel(
            title: 'Step-by-step journey',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _WorkflowStepCard(
                  index: 1,
                  title: 'Select stock concerns',
                  description: 'Choose ingredients from the live cocktail list only.',
                  isComplete: workflow.concernsSelected,
                ),
                _WorkflowStepCard(
                  index: 2,
                  title: 'Review affected cocktails',
                  description:
                      'See exactly why each cocktail is in this week’s focus pool.',
                  isComplete: workflow.cocktailsReviewed,
                ),
                _WorkflowStepCard(
                  index: 3,
                  title: 'Enter bartender sales',
                  description:
                      'Capture only the relevant cocktails for each bartender.',
                  isComplete: workflow.salesEntered,
                ),
                _WorkflowStepCard(
                  index: 4,
                  title: 'Share session',
                  description:
                      'Share the focused session link or QR-ready code.',
                  isComplete: workflow.quizLaunched,
                ),
                _WorkflowStepCard(
                  index: 5,
                  title: 'Review results',
                  description:
                      'Use supportive variance and confidence insights afterwards.',
                  isComplete: workflow.resultsAvailable,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (session != null)
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _StatusChip(
                  label: 'Selected concerns',
                  value: '${selectedConcernNames.length}',
                  color: const Color(0xFF3B82F6),
                ),
                _StatusChip(
                  label: 'Affected cocktails',
                  value: '${relevantRecipes.length}',
                  color: const Color(0xFF4DBA87),
                ),
                _StatusChip(
                  label: 'Active session links',
                  value: '$activeQuizCount',
                  color: const Color(0xFFE1A545),
                ),
              ],
            ),
          if (session != null && selectedConcernNames.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: selectedConcernNames
                  .map((name) => Chip(label: Text(name)))
                  .toList(),
            ),
          ],
          if (session != null) const SizedBox(height: 24),
          Wrap(
            spacing: 18,
            runSpacing: 18,
            children: [
              _Panel(
                width: 430,
                title: 'Create weekly concern session',
                child: selectableIngredients.isEmpty
                    ? const _EmptyText(
                        'Load the cocktail list before creating stock-focus sessions.',
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _labelController,
                            decoration: const InputDecoration(
                              labelText: 'Session label',
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Only ingredients currently used in the live cocktail list can be selected here.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          ...selectableIngredients.map((ingredientName) {
                            _selectedConcerns.putIfAbsent(
                              ingredientName,
                              () => false,
                            );
                            _shortControllers.putIfAbsent(
                              ingredientName,
                              () => TextEditingController(),
                            );
                            _impactControllers.putIfAbsent(
                              ingredientName,
                              () => TextEditingController(),
                            );
                            _noteControllers.putIfAbsent(
                              ingredientName,
                              () => TextEditingController(),
                            );
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CheckboxListTile(
                                    value: _selectedConcerns[ingredientName],
                                    contentPadding: EdgeInsets.zero,
                                    onChanged: (value) => setState(() {
                                      _selectedConcerns[ingredientName] =
                                          value ?? false;
                                      _persistLocalDraft();
                                    }),
                                    title: Text(ingredientName),
                                    subtitle: const Text(
                                      'Optional: amount short, estimated impact, and a short manager note',
                                    ),
                                  ),
                                  if (_selectedConcerns[ingredientName] ??
                                      false) ...[
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller:
                                                _shortControllers[ingredientName],
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            onChanged: (_) =>
                                                setState(_persistLocalDraft),
                                            decoration: const InputDecoration(
                                              labelText: 'Amount short ml',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: TextField(
                                            controller:
                                                _impactControllers[ingredientName],
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            onChanged: (_) =>
                                                setState(_persistLocalDraft),
                                            decoration: const InputDecoration(
                                              labelText: 'Estimated £ impact',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    TextField(
                                      controller:
                                          _noteControllers[ingredientName],
                                      onChanged: (_) =>
                                          setState(_persistLocalDraft),
                                      decoration: const InputDecoration(
                                        labelText: 'Manager note',
                                        hintText:
                                            'Optional context for the weekly prep note',
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }),
                          ElevatedButton(
                            onPressed: () {
                              final concerns = selectableIngredients
                                  .where(
                                    (ingredientName) =>
                                        _selectedConcerns[ingredientName] ??
                                        false,
                                  )
                                  .map(
                                    (ingredientName) => StockConcernItem(
                                      ingredientName: ingredientName,
                                      amountShortMl: double.tryParse(
                                        _shortControllers[ingredientName]
                                                ?.text ??
                                            '',
                                      ),
                                      estimatedImpact: double.tryParse(
                                        _impactControllers[ingredientName]
                                                ?.text ??
                                            '',
                                      ),
                                      notes: _noteControllers[ingredientName]
                                          ?.text
                                          .trim(),
                                    ),
                                  )
                                  .toList();
                              if (concerns.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Select at least one concern ingredient to create a session.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              final created = widget.controller
                                  .createWeeklySession(
                                    label: _labelController.text.trim(),
                                    weekStart: DateTime.now(),
                                    concerns: concerns,
                                  );
                              setState(() {
                                _selectedWeekId = created.id;
                                _selectedConcerns.updateAll(
                                  (key, value) => false,
                                );
                                for (final controller
                                    in _shortControllers.values) {
                                  controller.clear();
                                }
                                for (final controller
                                    in _impactControllers.values) {
                                  controller.clear();
                                }
                                for (final controller
                                    in _noteControllers.values) {
                                  controller.clear();
                                }
                              });
                              _persistLocalDraft();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Stock-focus session saved. The cocktail pool below is ready for review.',
                                  ),
                                ),
                              );
                            },
                            child: const Text('Create focus session'),
                          ),
                        ],
                      ),
              ),
              _Panel(
                width: 480,
                title: 'Relevant cocktail pool',
                child: session == null
                    ? const _EmptyText(
                        'Create a weekly concern session to see the affected cocktails.',
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: session.id,
                            items: widget.controller.weeklySessions
                                .map(
                                  (item) => DropdownMenuItem(
                                    value: item.id,
                                    child: Text(item.label),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) => setState(() {
                              _selectedWeekId = value;
                              _persistLocalDraft();
                            }),
                            decoration: const InputDecoration(
                              labelText: 'Working session',
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (session.concerns.isEmpty)
                            const _EmptyText(
                              'No concern ingredients have been selected for this session yet.',
                            )
                          else
                            ...session.concerns.map((concern) {
                              final matchingRecipes =
                                  groupedRelevantRecipes[concern
                                      .ingredientName] ??
                                  const <CocktailRecipe>[];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${concern.ingredientName} focus',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 6),
                                    if ((concern.notes ?? '').trim().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: Text(
                                          concern.notes!.trim(),
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ),
                                    if (matchingRecipes.isEmpty)
                                      const _EmptyText(
                                        'No cocktails currently match this ingredient.',
                                      )
                                    else
                                      ...matchingRecipes.map((recipe) {
                                        final matchingIngredients = recipe
                                            .ingredients
                                            .where(
                                              (ingredient) =>
                                                  ingredient.ingredientName
                                                      .toLowerCase() ==
                                                  concern.ingredientName
                                                      .toLowerCase(),
                                            )
                                            .toList();
                                        return _DataRowTile(
                                          title: recipe.name,
                                          subtitle: matchingIngredients
                                              .map(
                                                (ingredient) =>
                                                    ingredient.measureMl == null
                                                    ? 'Contains ${ingredient.ingredientName}'
                                                    : 'Contains ${ingredient.ingredientName} ${ingredient.measureMl!.toStringAsFixed(0)}ml',
                                              )
                                              .join(' • '),
                                        );
                                      }),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _Panel(
            title: 'Relevant sales entry',
            child: session == null
                ? const _EmptyText('Choose a weekly stock-focus session first.')
                : relevantRecipes.isEmpty
                ? const _EmptyText(
                    'No cocktails match this concern selection yet.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _bartenderController,
                        onChanged: (_) => setState(_persistLocalDraft),
                        decoration: const InputDecoration(
                          labelText: 'Bartender name',
                          helperText:
                              'Duplicate names are blocked so each bartender keeps one clear weekly record.',
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Only relevant cocktails appear below, which keeps weekly entry quick on mobile and tablet.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 14),
                      if (_hasInvalidQuantities(session, relevantRecipes))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Quantities must be whole numbers and cannot be negative.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ...relevantRecipes.map((recipe) {
                        final key = '${session.id}-${recipe.id}';
                        _salesControllers.putIfAbsent(
                          key,
                          () => TextEditingController(),
                        );
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        recipe.name,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Current session total: ${_cocktailTotal(session, recipe)}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 120,
                                  child: TextField(
                                    controller: _salesControllers[key],
                                    keyboardType: TextInputType.number,
                                    onChanged: (_) =>
                                        setState(_persistLocalDraft),
                                    decoration: const InputDecoration(
                                      labelText: 'Qty sold',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 14),
                      ElevatedButton(
                        onPressed: () {
                          final validation = widget.controller
                              .validateBartenderSales(
                                session: session,
                                bartenderName: _bartenderController.text,
                                rawQuantitiesByCocktailId:
                                    _rawSalesByCocktailId(
                                      session,
                                      relevantRecipes,
                                    ),
                              );
                          if (!validation.isValid) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  validation.message ??
                                      'Unable to save sales right now.',
                                ),
                              ),
                            );
                            return;
                          }
                          if (_hasInvalidQuantities(session, relevantRecipes)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Fix any invalid quantities before saving sales.',
                                ),
                              ),
                            );
                            return;
                          }
                          final entries = relevantRecipes
                              .map(
                                (recipe) => BartenderSalesEntry(
                                  cocktailId: recipe.id,
                                  cocktailName: recipe.name,
                                  quantitySold:
                                      int.tryParse(
                                        _salesControllers['${session.id}-${recipe.id}']
                                                ?.text ??
                                            '',
                                      ) ??
                                      0,
                                ),
                              )
                              .where((entry) => entry.quantitySold > 0)
                              .toList();
                          widget.controller.saveBartenderSales(
                            weekId: session.id,
                            bartenderName: _bartenderController.text.trim(),
                            entries: entries,
                          );
                          _clearSalesInputs(session, relevantRecipes);
                          _persistLocalDraft();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Bartender sales saved. You can add the next bartender straight away.',
                              ),
                            ),
                          );
                          setState(() {});
                        },
                        child: const Text('Save bartender sales'),
                      ),
                      const SizedBox(height: 18),
                      if (session.bartenderSales.isEmpty)
                        const _EmptyText(
                          'No bartender sales are saved yet. Add one bartender at a time, then launch focused practice links from the saved totals below.',
                        )
                      else ...[
                        Text(
                          'Saved bartender totals',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        ...session.bartenderSales.map(
                          (record) => _DataRowTile(
                            title: record.bartenderName,
                            subtitle:
                                '${record.entries.length} relevant cocktails recorded • ${_bartenderTotal(record)} serves total',
                            trailing: 'Saved',
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Cocktail totals in this session',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        ...relevantRecipes.map(
                          (recipe) => _DataRowTile(
                            title: recipe.name,
                            subtitle:
                                'Only sales for relevant cocktails are tracked here.',
                            trailing: '${_cocktailTotal(session, recipe)}',
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 24),
          _Panel(
            title: 'Generate focused stock practice',
            child: session == null
                ? const _EmptyText('Create a weekly stock-focus session first.')
                : session.bartenderSales.isEmpty
                ? const _EmptyText(
                    'Add bartender sales before generating session links.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: session.bartenderSales
                        .map(
                          (record) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        record.bartenderName,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                    ),
                                    FilledButton(
                                      onPressed: () {
                                        final quiz = widget.controller
                                            .generateStockQuiz(
                                              weekId: session.id,
                                              bartenderName:
                                                  record.bartenderName,
                                            );
                                        final shareLink = Uri.base
                                            .replace(
                                              path: '/quiz/${quiz.id}',
                                              queryParameters: const {},
                                            )
                                            .toString();
                                        Clipboard.setData(
                                          ClipboardData(text: shareLink),
                                        );
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Session link copied: $shareLink',
                                            ),
                                          ),
                                        );
                                        setState(() {});
                                      },
                                      child: const Text(
                                        'Create and copy session link',
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton(
                                      onPressed: () {
                                        final activeSession = widget
                                            .controller
                                            .quizSessions
                                            .firstWhere(
                                              (quiz) =>
                                                  quiz.weekId == session.id &&
                                                  quiz.bartenderName
                                                          .toLowerCase() ==
                                                      record.bartenderName
                                                          .toLowerCase() &&
                                                  quiz.isActive,
                                              orElse: () => QuizSession(
                                                id: '',
                                                title: '',
                                                bartenderName: '',
                                                kind: QuizKind.stockVariance,
                                                isActive: false,
                                                createdAt: DateTime(2000),
                                                questions: [],
                                              ),
                                            );
                                        if (activeSession.id.isEmpty) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'No active session is open for this bartender yet.',
                                              ),
                                            ),
                                          );
                                          return;
                                        }
                                        widget.controller.deactivateQuizSession(
                                          activeSession.id,
                                        );
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Session closed. The bartender link now shows a clear closed message.',
                                            ),
                                          ),
                                        );
                                        setState(() {});
                                      },
                                      child: const Text('Close session'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Questions are built from the live cocktail list linked to the current concern ingredients, with measure specs prioritised first.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: record.entries
                                      .map(
                                        (entry) => Chip(
                                          label: Text(
                                            '${entry.cocktailName} • ${entry.quantitySold}',
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Session code: ${record.bartenderName.toUpperCase().replaceAll(' ', '').characters.take(3).toString()}-${session.id.split('-').last.toUpperCase()}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'This bartender link only opens while the session stays active.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class InsightsTab extends StatelessWidget {
  const InsightsTab({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final attempts = controller.quizAttempts;
    final currency = NumberFormat.currency(symbol: '£', decimalDigits: 2);
    final dashboard = controller.buildDashboard();
    return _ScrollPage(
      title: 'Trends over time',
      subtitle:
          'Review confidence trends, coaching themes, and supportive variance projections over time.',
      child: Column(
        children: [
          _Panel(
            title: 'Bartender vs venue average',
            child: dashboard.bartenderAverageScores.isEmpty
                ? const _EmptyText(
                    'Bartender averages will appear after multiple submitted sessions.',
                  )
                : Column(
                    children: dashboard.bartenderAverageScores.entries
                        .map(
                          (entry) => _DataRowTile(
                            title: entry.key,
                            subtitle:
                                'Venue average is ${dashboard.venueAverageScore}%. This comparison stays supportive and coaching-focused.',
                            trailing: '${entry.value}%',
                          ),
                        )
                        .toList(),
                  ),
          ),
          const SizedBox(height: 18),
          _Panel(
            title: 'Ingredient confidence over time',
            child: dashboard.ingredientConfidenceByWeek.isEmpty
                ? const _EmptyText(
                    'Ingredient confidence trends will appear after stock-linked sessions are saved over multiple weeks.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: dashboard.ingredientConfidenceByWeek.entries
                        .map(
                          (entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.key,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                ...entry.value.entries.map(
                                  (ingredientEntry) => _DataRowTile(
                                    title: ingredientEntry.key,
                                    subtitle:
                                        'Ingredient-specific recipe confidence for that weekly focus.',
                                    trailing: '${ingredientEntry.value}%',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          const SizedBox(height: 18),
          _Panel(
            title: 'Recurring weak ingredients',
            child: dashboard.ingredientMisses.isEmpty
                ? const _EmptyText(
                    'Ingredient-specific coaching opportunities will appear after session results are saved.',
                  )
                : Column(
                    children:
                        (dashboard.ingredientMisses.entries.toList()
                              ..sort((a, b) => b.value.compareTo(a.value)))
                            .take(6)
                            .map(
                              (entry) => _DataRowTile(
                                title: entry.key,
                                subtitle:
                                    'Repeated misses suggest this ingredient spec is worth revisiting in training.',
                                trailing: '${entry.value}',
                              ),
                            )
                            .toList(),
                  ),
          ),
          const SizedBox(height: 18),
          _Panel(
            title: 'Recent session results',
            child: attempts.isEmpty
                ? const _EmptyText(
                    'Session history will appear here as bartenders complete practice and stock-focus rounds.',
                  )
                : Column(
                    children: attempts
                        .map(
                          (attempt) => _DataRowTile(
                            title:
                                '${attempt.bartenderName} • ${attempt.scorePercent}% recipe confidence',
                            subtitle:
                                '${DateFormat('d MMM, HH:mm').format(attempt.submittedAt)} • ${attempt.encouragement}',
                            trailing: currency.format(
                              attempt.overpourLines.fold<double>(
                                0,
                                (sum, line) => sum + line.approximateValue,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          const SizedBox(height: 18),
          _Panel(
            title: 'Training focus summary',
            child: dashboard.trainingFocusAreas.isEmpty
                ? const _EmptyText(
                    'Coaching themes will appear once a few sessions have been submitted.',
                  )
                : Column(
                    children: dashboard.trainingFocusAreas.entries
                        .map(
                          (entry) => _DataRowTile(
                            title: _friendlyQuestionKind(entry.key),
                            subtitle:
                                'Supportive count of where recipe confidence most often needs another pass.',
                            trailing: '${entry.value}',
                          ),
                        )
                        .toList(),
                  ),
          ),
          const SizedBox(height: 18),
          _Panel(
            title: 'Weekly comparison',
            child: dashboard.weeklyConfidence.isEmpty
                ? const _EmptyText(
                    'Weekly comparisons will appear once at least one stock-linked session has been completed.',
                  )
                : Column(
                    children: dashboard.weeklyConfidence.entries
                        .map(
                          (entry) => _DataRowTile(
                            title: entry.key,
                            subtitle:
                                'Average recipe confidence for recorded sessions in this weekly focus',
                            trailing: '${entry.value}%',
                          ),
                        )
                        .toList(),
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
  late final Future<QuizSession?> _sessionFuture = widget.controller
      .fetchQuizSession(widget.sessionId);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuizSession?>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: SafeArea(
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final session = snapshot.data;
        if (session == null) {
          return Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'This session link is unavailable right now. It may have closed, expired, or been replaced. Ask your manager for a fresh active link.',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: Text(session.title)),
          body: SafeArea(
            child: QuizPlayerPanel(
              controller: widget.controller,
              session: session,
              onExit: () {},
              hideExit: true,
            ),
          ),
        );
      },
    );
  }
}

class HelpfulRouteScreen extends StatelessWidget {
  const HelpfulRouteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'That page could not be found.',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Head back to the home page for your venue workspace, or open a valid bartender session link.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class QuizPlayerPanel extends StatefulWidget {
  const QuizPlayerPanel({
    super.key,
    required this.controller,
    required this.session,
    required this.onExit,
    this.hideExit = false,
  });

  final AppController controller;
  final QuizSession session;
  final VoidCallback onExit;
  final bool hideExit;

  @override
  State<QuizPlayerPanel> createState() => _QuizPlayerPanelState();
}

class _QuizPlayerPanelState extends State<QuizPlayerPanel> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.session.bartenderName,
  );
  final Map<String, String> _answers = {};

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final latestAttempt = widget.controller.latestAttempt;
    if (latestAttempt != null && latestAttempt.sessionId == widget.session.id) {
      return QuizResultsPanel(
        attempt: latestAttempt,
        onDone: widget.onExit,
        hideExit: widget.hideExit,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.session.kind == QuizKind.stockVariance
                      ? 'Focused stock practice'
                      : 'Practice round',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  widget.session.kind == QuizKind.stockVariance
                      ? 'This short round focuses on cocktails linked to the current concern ingredients.'
                      : 'Nice work making time for practice. This quick round keeps specs fresh before or during a shift.',
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Your name'),
                ),
                const SizedBox(height: 14),
                Text(
                  'Progress: ${_answers.length}/${widget.session.questions.length} answered',
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: widget.session.questions.isEmpty
                      ? 0
                      : _answers.length / widget.session.questions.length,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        ...widget.session.questions.asMap().entries.map(
          (entry) => Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Question ${entry.key + 1} of ${widget.session.questions.length}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    entry.value.prompt,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 14),
                  RadioGroup<String>(
                    groupValue: _answers[entry.value.id],
                    onChanged: (value) =>
                        setState(() => _answers[entry.value.id] = value ?? ''),
                    child: Column(
                      children: entry.value.options
                          .map(
                            (option) => RadioListTile<String>(
                              value: option,
                              title: Text(option),
                              contentPadding: EdgeInsets.zero,
                              visualDensity: const VisualDensity(vertical: 1),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            if (_answers.length != widget.session.questions.length) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Answer each question first, then we can show your results.',
                  ),
                ),
              );
              return;
            }
            widget.controller.submitQuizAttempt(
              sessionId: widget.session.id,
              bartenderName: _nameController.text.trim().isEmpty
                  ? widget.session.bartenderName
                  : _nameController.text.trim(),
              answers: _answers,
            );
            setState(() {});
          },
          child: const Text('Finish practice'),
        ),
      ],
    );
  }
}

class QuizResultsPanel extends StatelessWidget {
  const QuizResultsPanel({
    super.key,
    required this.attempt,
    required this.onDone,
    this.hideExit = false,
  });

  final QuizAttempt attempt;
  final VoidCallback onDone;
  final bool hideExit;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '£', decimalDigits: 2);
    final cocktailsToRevise = attempt.responses
        .where((response) => !response.isCorrect)
        .map((response) => response.question.cocktailName)
        .toSet()
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${attempt.bartenderName}, your recipe confidence today is ${attempt.scorePercent}%',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 10),
                Text(attempt.encouragement),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _StatusChip(
                      label: 'Questions right',
                      value:
                          '${attempt.responses.where((response) => response.isCorrect).length}/${attempt.responses.length}',
                      color: const Color(0xFF4DBA87),
                    ),
                    _StatusChip(
                      label: 'Needs another look',
                      value:
                          '${attempt.responses.where((response) => !response.isCorrect).length}',
                      color: const Color(0xFFE1A545),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        _Panel(
          title: 'Strong on today',
          child: attempt.responses.where((response) => response.isCorrect).isEmpty
              ? const _EmptyText(
                  'Nothing felt fully locked in on this round yet, which is fine. Use the answer review below and give those specs another pass.',
                )
              : Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: attempt.responses
                      .where((response) => response.isCorrect)
                      .map(
                        (response) => Chip(
                          label: Text(
                            '${response.question.cocktailName} • ${_friendlyQuestionKind(response.question.kind.name)}',
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 18),
        _Panel(
          title: 'Answer review',
          child: Column(
            children: attempt.responses
                .map(
                  (response) => _DataRowTile(
                    title: response.question.prompt,
                    subtitle:
                        'Correct: ${response.question.correctAnswer} • Your answer: ${response.selectedAnswer}',
                    trailing: response.isCorrect
                        ? 'Nice work'
                        : 'Needs practice',
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 18),
        _Panel(
          title: 'Potential variance',
          child: attempt.overpourLines.isEmpty
              ? const _EmptyText(
                  'No over-spec potential variance was projected from this response set.',
                )
              : Column(
                  children: attempt.overpourLines
                      .map(
                        (line) => _DataRowTile(
                          title: line.ingredientName,
                          subtitle:
                              'If cocktails were made using these specs, potential variance could be ${line.totalMl.toStringAsFixed(0)}ml.',
                          trailing: currency.format(line.approximateValue),
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 18),
        _Panel(
          title: 'Quality consistency opportunities',
          child: attempt.underpourLines.isEmpty
              ? const _EmptyText(
                  'No under-spec consistency opportunities stood out here.',
                )
              : Column(
                  children: attempt.underpourLines
                      .map(
                        (line) => _DataRowTile(
                          title: line.ingredientName,
                          subtitle:
                              'A lighter pour pattern could affect consistency across about ${line.totalMl.toStringAsFixed(0)}ml of serves.',
                          trailing: 'Review spec',
                        ),
                      )
                      .toList(),
                ),
        ),
        if (attempt.coachingAreas.isNotEmpty) ...[
          const SizedBox(height: 18),
          _Panel(
            title: 'Worth revisiting',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: attempt.coachingAreas
                  .map((item) => Chip(label: Text(item)))
                  .toList(),
            ),
          ),
          const SizedBox(height: 18),
          _Panel(
            title: 'Focus before your next shift',
            child: Text(
              'A few specs need another look. Start with ${attempt.coachingAreas.take(3).join(', ')}, then run another short round when you are ready.',
            ),
          ),
        ],
        if (cocktailsToRevise.isNotEmpty) ...[
          const SizedBox(height: 18),
          _Panel(
            title: 'Cocktails to revise next',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: cocktailsToRevise
                  .map((name) => Chip(label: Text(name)))
                  .toList(),
            ),
          ),
        ],
        if (!hideExit) ...[
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: onDone,
            child: const Text('Back to training'),
          ),
        ],
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
  final TextEditingController _inviteExpiryDaysController =
      TextEditingController(text: '7');
  final TextEditingController _inviteMaxUsesController = TextEditingController(
    text: '1',
  );
  UserRole _inviteRole = UserRole.bartender;

  @override
  void dispose() {
    _inviteExpiryDaysController.dispose();
    _inviteMaxUsesController.dispose();
    super.dispose();
  }

  String _buildDiagnostics() {
    final base = BrowserAppRecovery.diagnostics(
      buildLabel: widget.controller.appBuildLabel,
      runtimeMode: widget.controller.runtimeModeLabel,
      isOnline: widget.isOnline,
    );
    final user = widget.controller.currentUser;
    final latestSync = widget.controller.latestVerifiedSyncResult;
    final syncSummary = latestSync == null
        ? 'verifiedSync=loaded-on-sign-in'
        : 'verifiedSync='
              'cocktails:${latestSync.cocktailsAdded + latestSync.cocktailsUpdated},'
              'batches:${latestSync.batchesAdded + latestSync.batchesUpdated},'
              'flagged:${latestSync.flaggedCocktails + latestSync.flaggedBatches},'
              'missingImages:${latestSync.missingImages}';
    return [
      base,
      'role=${user?.role.name ?? 'guest'}',
      'venueId=${user?.venueId.isNotEmpty == true ? user!.venueId : 'unassigned'}',
      'venueName=${user?.venueName ?? 'Venue'}',
      'recipes=${widget.controller.recipes.length}',
      'batches=${widget.controller.batches.length}',
      'ingredients=${widget.controller.ingredients.length}',
      syncSummary,
    ].join('\n');
  }

  Future<void> _copyDiagnostics() async {
    final diagnostics = _buildDiagnostics();
    await Clipboard.setData(ClipboardData(text: diagnostics));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Diagnostics copied so you can share the current app state.',
        ),
      ),
    );
  }

  Future<void> _refreshApp() async {
    await BrowserAppRecovery.refreshApp();
  }

  Future<void> _clearSavedAppData() async {
    await BrowserAppRecovery.clearSavedAppData();
  }

  @override
  Widget build(BuildContext context) {
    final canAccessAdminSetup = widget.controller.canAccessAdminSetup;
    final currentUser = widget.controller.currentUser;
    final latestSync = widget.controller.latestVerifiedSyncResult;
    final syncStatus = latestSync == null
        ? (widget.controller.didAutoPrepareCocktailList
              ? 'The starter cocktail list was prepared automatically for this venue.'
              : 'Saved venue cocktails are being used as the live list.')
        : '${latestSync.cocktailsAdded + latestSync.cocktailsUpdated} '
              'cocktail spec${latestSync.cocktailsAdded + latestSync.cocktailsUpdated == 1 ? '' : 's'} '
              'and ${latestSync.batchesAdded + latestSync.batchesUpdated} '
              'batch spec${latestSync.batchesAdded + latestSync.batchesUpdated == 1 ? '' : 's'} '
              'were prepared the last time the checked-in list was applied.';
    return _ScrollPage(
      title: canAccessAdminSetup
          ? 'Admin and venue settings'
          : 'Service support settings',
      subtitle: canAccessAdminSetup
          ? 'Keep admin setup, venue access, connection status, and export guidance easy to check before service.'
          : 'Keep venue access, connection status, and export guidance easy to check before service.',
      child: Wrap(
        spacing: 18,
        runSpacing: 18,
        children: [
          _Panel(
            width: 420,
            title: 'Venue settings',
            child: Column(
              children: [
                _DataRowTile(
                  title: 'Venue',
                  subtitle: 'Current venue scope',
                  trailing: widget.controller.currentUser?.venueName ?? 'Venue',
                ),
                _DataRowTile(
                  title: 'Mode',
                  subtitle: 'Runtime configuration for this build',
                  trailing: widget.controller.runtimeModeLabel,
                ),
                _DataRowTile(
                  title: 'Connection',
                  subtitle: 'Firestore connectivity for live venue use',
                  trailing: widget.isOnline ? 'Online' : 'Offline',
                ),
                _DataRowTile(
                  title: 'Build',
                  subtitle: 'App version for rollout tracking',
                  trailing: widget.controller.appBuildLabel,
                ),
                _DataRowTile(
                  title: 'Role',
                  subtitle: 'Current signed-in access level',
                  trailing: currentUser?.role.name ?? 'Guest',
                ),
                _DataRowTile(
                  title: 'Venue ID',
                  subtitle: 'Firestore scope for this signed-in workspace',
                  trailing: currentUser?.venueId.isNotEmpty == true
                      ? currentUser!.venueId
                      : 'Not linked yet',
                ),
              ],
            ),
          ),
          _Panel(
            width: 420,
            title: canAccessAdminSetup
                ? 'Admin diagnostics'
                : 'Workspace diagnostics',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  canAccessAdminSetup
                      ? 'Use this snapshot before updating specs, troubleshooting a rollout, or checking whether the live cocktail list is ready in this venue.'
                      : 'Use this snapshot when you need quick support with venue access, connectivity, or the live recipe library.',
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _StatusChip(
                      label: 'Live cocktails',
                      value: '${widget.controller.recipes.length}',
                      color: const Color(0xFF3B82F6),
                    ),
                    _StatusChip(
                      label: 'Live batches',
                      value: '${widget.controller.batches.length}',
                      color: const Color(0xFF4DBA87),
                    ),
                    _StatusChip(
                      label: 'Tracked ingredients',
                      value: '${widget.controller.ingredients.length}',
                      color: const Color(0xFFE1A545),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _DataRowTile(
                  title: 'Cocktail list',
                  subtitle: 'Current live cocktail-list status',
                  trailing: widget.controller.recipes.isEmpty
                      ? 'Still preparing'
                      : 'Ready',
                ),
                _DataRowTile(
                  title: 'Latest setup',
                  subtitle: syncStatus,
                  trailing: latestSync == null ? 'Auto' : 'Applied',
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton(
                      onPressed: _refreshApp,
                      child: const Text('Refresh app'),
                    ),
                    OutlinedButton(
                      onPressed: _clearSavedAppData,
                      child: const Text('Clear saved app data'),
                    ),
                    OutlinedButton(
                      onPressed: _copyDiagnostics,
                      child: const Text('Copy diagnostics'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _Panel(
            width: 420,
            title: canAccessAdminSetup
                ? 'Cocktail setup guidance'
                : 'Operational guidance',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Export and backup guidance'),
                const SizedBox(height: 8),
                const Text(
                  'Keep OCR source files, reviewed text exports, and Firebase project access with at least one owner account.',
                ),
                const SizedBox(height: 12),
                Text(
                  canAccessAdminSetup
                      ? 'Approval guidance'
                      : 'Library guidance',
                ),
                const SizedBox(height: 8),
                Text(
                  canAccessAdminSetup
                      ? 'The live cocktail list, batch details, and pricing should stay clean and practical for service. If a spec needs attention, update the saved cocktail detail instead of guessing.'
                      : 'The cocktail list is shared centrally. Venue managers should use it for stock focus, sales entry, practice links, and coaching rather than changing the core spec build.',
                ),
                const SizedBox(height: 12),
                const Text('Connectivity guidance'),
                const SizedBox(height: 8),
                const Text(
                  'If the app goes offline during service, local workflow progress is kept in this browser so it can be restored and saved once connectivity returns.',
                ),
              ],
            ),
          ),
          if (widget.controller.canManageVenueInvites)
            _Panel(
              width: 420,
              title: 'Venue invites',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    canAccessAdminSetup
                        ? 'Create invite-only links for managers or bartenders without exposing owner/admin setup access.'
                        : 'Create invite-only links for your venue so new teammates land in the correct role automatically.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<UserRole>(
                    initialValue: _inviteRole,
                    decoration: const InputDecoration(labelText: 'Invite role'),
                    items: const [
                      DropdownMenuItem(
                        value: UserRole.bartender,
                        child: Text('Bartender'),
                      ),
                      DropdownMenuItem(
                        value: UserRole.manager,
                        child: Text('Manager'),
                      ),
                    ],
                    onChanged: widget.controller.isBusy
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _inviteRole = value);
                            }
                          },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _inviteExpiryDaysController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Expires in days',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _inviteMaxUsesController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Maximum uses',
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: widget.controller.isBusy
                        ? null
                        : () async {
                            final expiryDays = int.tryParse(
                              _inviteExpiryDaysController.text.trim(),
                            );
                            final maxUses = int.tryParse(
                              _inviteMaxUsesController.text.trim(),
                            );
                            if ((expiryDays ?? 0) <= 0 || (maxUses ?? 0) <= 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Use whole numbers above zero for expiry days and maximum uses.',
                                  ),
                                ),
                              );
                              return;
                            }
                            try {
                              final invite = await widget.controller
                                  .createVenueInvite(
                                    role: _inviteRole,
                                    expiresAt: DateTime.now().add(
                                      Duration(days: expiryDays!),
                                    ),
                                    maxUses: maxUses!,
                                  );
                              final shareLink = Uri.base
                                  .replace(
                                    path:
                                        '/join/${invite.venueId}/${invite.id}',
                                    queryParameters: const {},
                                  )
                                  .toString();
                              await Clipboard.setData(
                                ClipboardData(text: shareLink),
                              );
                              if (!mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    widget.controller.successMessage ??
                                        'Invite created and copied: $shareLink',
                                  ),
                                ),
                              );
                              setState(() {});
                            } catch (error) {
                              if (!mounted) {
                                return;
                              }
                              final message =
                                  widget.controller.errorMessage ??
                                  error.toString().replaceFirst(
                                    'Exception: ',
                                    '',
                                  );
                              ScaffoldMessenger.of(
                                this.context,
                              ).showSnackBar(SnackBar(content: Text(message)));
                            }
                          },
                    child: const Text('Create and copy invite link'),
                  ),
                  const SizedBox(height: 18),
                  if (widget.controller.venueInvites.isEmpty)
                    const _EmptyText(
                      'Active and paused invite links for this venue will appear here.',
                    )
                  else
                    Column(
                      children: widget.controller.venueInvites
                          .map(
                            (invite) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${invite.role.name[0].toUpperCase()}${invite.role.name.substring(1)} invite',
                              ),
                              subtitle: Text(
                                '${invite.currentUses}/${invite.maxUses} uses • Expires ${DateFormat('d MMM yyyy, HH:mm').format(invite.expiresAt)}',
                              ),
                              trailing: Wrap(
                                spacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(invite.disabled ? 'Paused' : 'Active'),
                                  IconButton(
                                    tooltip: 'Copy invite link',
                                    onPressed: () async {
                                      final shareLink = Uri.base
                                          .replace(
                                            path:
                                                '/join/${invite.venueId}/${invite.id}',
                                            queryParameters: const {},
                                          )
                                          .toString();
                                      await Clipboard.setData(
                                        ClipboardData(text: shareLink),
                                      );
                                      if (!mounted) {
                                        return;
                                      }
                                      ScaffoldMessenger.of(
                                        this.context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Invite link copied for QR sharing or direct join.',
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.link),
                                  ),
                                  IconButton(
                                    tooltip: 'Show invite QR',
                                    onPressed: () {
                                      final shareLink = Uri.base
                                          .replace(
                                            path:
                                                '/join/${invite.venueId}/${invite.id}',
                                            queryParameters: const {},
                                          )
                                          .toString();
                                      showDialog<void>(
                                        context: context,
                                        builder: (dialogContext) {
                                          return AlertDialog(
                                            title: const Text('Invite QR'),
                                            content: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                QrImageView(
                                                  data: shareLink,
                                                  size: 220,
                                                ),
                                                const SizedBox(height: 16),
                                                SelectableText(shareLink),
                                              ],
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.of(
                                                  dialogContext,
                                                ).pop(),
                                                child: const Text('Close'),
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                    },
                                    icon: const Icon(Icons.qr_code_2),
                                  ),
                                  Switch(
                                    value: !invite.disabled,
                                    onChanged: widget.controller.isBusy
                                        ? null
                                        : (value) async {
                                            try {
                                              await widget.controller
                                                  .setVenueInviteDisabled(
                                                    inviteId: invite.id,
                                                    disabled: !value,
                                                  );
                                              if (!mounted) {
                                                return;
                                              }
                                              ScaffoldMessenger.of(
                                                this.context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    widget
                                                            .controller
                                                            .successMessage ??
                                                        'Invite updated.',
                                                  ),
                                                ),
                                              );
                                              setState(() {});
                                            } catch (error) {
                                              if (!mounted) {
                                                return;
                                              }
                                              final message =
                                                  widget
                                                      .controller
                                                      .errorMessage ??
                                                  error.toString().replaceFirst(
                                                    'Exception: ',
                                                    '',
                                                  );
                                              ScaffoldMessenger.of(
                                                this.context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(message),
                                                ),
                                              );
                                            }
                                          },
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
            ),
          if (canAccessAdminSetup)
            _Panel(
              width: 420,
              title: 'Venue access overview',
              child: widget.controller.venueUsers.isEmpty
                  ? const _EmptyText(
                      'Owner and venue user accounts for this venue will appear here.',
                    )
                  : Column(
                      children: widget.controller.venueUsers.map((user) {
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(user.displayName),
                          subtitle: Text('${user.email} • ${user.role.name}'),
                          trailing: user.role == UserRole.owner
                              ? const Chip(label: Text('Owner'))
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(user.active ? 'Active' : 'Paused'),
                                    const SizedBox(width: 8),
                                    Switch(
                                      value: user.active,
                                      onChanged: widget.controller.isBusy
                                          ? null
                                          : (value) async {
                                              try {
                                                await widget.controller
                                                    .setVenueUserActive(
                                                      userId: user.id,
                                                      active: value,
                                                    );
                                                if (!mounted) {
                                                  return;
                                                }
                                                ScaffoldMessenger.of(
                                                  this.context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      widget
                                                              .controller
                                                              .successMessage ??
                                                          'Venue access updated.',
                                                    ),
                                                  ),
                                                );
                                                setState(() {});
                                              } catch (error) {
                                                if (!mounted) {
                                                  return;
                                                }
                                                final message =
                                                    widget
                                                        .controller
                                                        .errorMessage ??
                                                    error
                                                        .toString()
                                                        .replaceFirst(
                                                          'Exception: ',
                                                          '',
                                                        );
                                                ScaffoldMessenger.of(
                                                  this.context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(message),
                                                  ),
                                                );
                                              }
                                            },
                                    ),
                                  ],
                                ),
                        );
                      }).toList(),
                    ),
            ),
          _Panel(
            width: 420,
            title: 'Export and backup',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Use these quick exports for local backups or offline review. Firestore remains the main source of truth.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton(
                      onPressed: widget.controller.recipes.isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(
                                  text: approvedRecipesExportJson(
                                    widget.controller.recipes,
                                  ),
                                ),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Approved recipe export copied as JSON.',
                                    ),
                                  ),
                                );
                              }
                            },
                      child: const Text('Copy cocktail list JSON'),
                    ),
                    OutlinedButton(
                      onPressed: widget.controller.quizAttempts.isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(
                                  text: weeklyResultsExportJson(
                                    widget.controller.quizAttempts,
                                  ),
                                ),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Weekly results export copied as JSON.',
                                    ),
                                  ),
                                );
                              }
                            },
                      child: const Text('Copy weekly results JSON'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _Panel(
            width: 420,
            title: 'Account actions',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  canAccessAdminSetup
                      ? 'Use a confirmation before signing out so admin setup work and service context are not lost unexpectedly.'
                      : 'Use a confirmation before signing out during service so working context is not lost unexpectedly.',
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(
                          canAccessAdminSetup
                              ? 'Sign out of owner/admin space?'
                              : 'Sign out of manager space?',
                        ),
                        content: Text(
                          canAccessAdminSetup
                              ? 'Any unsaved admin setup changes should be checked first. Locally stored workflow drafts stay in this browser until you clear them.'
                              : 'Any unsaved live-service notes should be checked first. Locally stored workflow drafts stay in this browser until you clear them.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Stay signed in'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Sign out'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await widget.controller.signOut();
                    }
                  },
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RecipeDetailPanel extends StatelessWidget {
  const RecipeDetailPanel({
    super.key,
    required this.recipe,
    this.embedded = false,
    this.revealIngredients = true,
    this.revealMeasures = true,
  });

  final CocktailRecipe recipe;
  final bool embedded;
  final bool revealIngredients;
  final bool revealMeasures;

  @override
  Widget build(BuildContext context) {
    final directIngredients = recipe.ingredients
        .where((ingredient) => !ingredient.isBatchReference)
        .toList();
    final batchIngredients = recipe.ingredients
        .where((ingredient) => ingredient.isBatchReference)
        .toList();
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!embedded)
          Text(recipe.name, style: Theme.of(context).textTheme.headlineMedium),
        if (!embedded) const SizedBox(height: 12),
        _RecipeHeroImage(recipe: recipe),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (recipe.category.isNotEmpty) Chip(label: Text(recipe.category)),
            if (recipe.glassware.isNotEmpty)
              Chip(label: Text('Glass: ${recipe.glassware}')),
            if (recipe.garnish.isNotEmpty)
              Chip(label: Text('Garnish: ${recipe.garnish}')),
            if (recipe.needsReview)
              const Chip(label: Text('Needs a quick look')),
          ],
        ),
        const SizedBox(height: 16),
        Text('What goes in it', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (!revealIngredients)
          const Text(
            'Keep the ingredients hidden for now, then reveal them when you want to check your memory.',
          )
        else
          ...directIngredients.map(
            (ingredient) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                revealMeasures
                    ? (ingredient.measureMl == null
                          ? ingredient.ingredientName
                          : '${ingredient.ingredientName} • ${ingredient.measureMl!.toStringAsFixed(0)}ml${ingredient.preparationNote?.isNotEmpty == true ? ' • ${ingredient.preparationNote}' : ''}')
                    : '${ingredient.ingredientName}${ingredient.preparationNote?.isNotEmpty == true ? ' • ${ingredient.preparationNote}' : ''}',
              ),
            ),
          ),
        if (batchIngredients.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Batch', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...batchIngredients.map(
            (ingredient) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                revealMeasures
                    ? '${ingredient.ingredientName} • ${ingredient.measureMl?.toStringAsFixed(0) ?? '—'}ml'
                    : ingredient.ingredientName,
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (recipe.method.isNotEmpty) Text('How to make it: ${recipe.method}'),
        if (recipe.glassware.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Glass: ${recipe.glassware}'),
        ],
        if (recipe.garnish.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Garnish: ${recipe.garnish}'),
        ],
        if (recipe.notes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Quick note: ${recipe.notes}'),
        ],
      ],
    );

    if (embedded) {
      return content;
    }
    return _Panel(title: 'Cocktail spec', child: content);
  }
}

class BatchDetailPanel extends StatelessWidget {
  const BatchDetailPanel({super.key, required this.batch});

  final BatchRecipe batch;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Batch detail',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(batch.name, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (batch.category.isNotEmpty) Chip(label: Text(batch.category)),
              if (batch.totalBatchVolumeMl != null)
                Chip(
                  label: Text(
                    'Total: ${batch.totalBatchVolumeMl!.toStringAsFixed(0)}ml',
                  ),
                ),
              if (batch.needsReview)
                const Chip(label: Text('Needs a quick look')),
            ],
          ),
          const SizedBox(height: 16),
          Text('Ingredients', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...batch.ingredients.map(
            (ingredient) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                ingredient.measureMl == null
                    ? ingredient.ingredientName
                    : '${ingredient.ingredientName} • ${ingredient.measureMl!.toStringAsFixed(0)}ml${ingredient.preparationNote?.isNotEmpty == true ? ' • ${ingredient.preparationNote}' : ''}',
              ),
            ),
          ),
          if (batch.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Notes: ${batch.notes}'),
          ],
        ],
      ),
    );
  }
}

class RecipeEditorPanel extends StatefulWidget {
  const RecipeEditorPanel({
    super.key,
    required this.recipe,
    required this.onSave,
  });

  final CocktailRecipe recipe;
  final ValueChanged<CocktailRecipe> onSave;

  @override
  State<RecipeEditorPanel> createState() => _RecipeEditorPanelState();
}

class _RecipeEditorPanelState extends State<RecipeEditorPanel> {
  late CocktailRecipe _recipe = widget.recipe;

  @override
  void didUpdateWidget(covariant RecipeEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recipe.id != widget.recipe.id) {
      _recipe = widget.recipe;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Edit cocktail spec',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RecipeHeroImage(recipe: _recipe),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: _recipe.name,
            decoration: const InputDecoration(labelText: 'Cocktail name'),
            onChanged: (value) => _recipe = _recipe.copyWith(name: value),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _recipe.category,
            decoration: const InputDecoration(labelText: 'Category'),
            onChanged: (value) => _recipe = _recipe.copyWith(category: value),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _recipe.glassware,
            decoration: const InputDecoration(labelText: 'Glassware'),
            onChanged: (value) => _recipe = _recipe.copyWith(glassware: value),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _recipe.garnish,
            decoration: const InputDecoration(labelText: 'Garnish'),
            onChanged: (value) => _recipe = _recipe.copyWith(garnish: value),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _recipe.method,
            decoration: const InputDecoration(labelText: 'Build method'),
            onChanged: (value) => _recipe = _recipe.copyWith(method: value),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _recipe.notes,
            decoration: const InputDecoration(labelText: 'Prep notes'),
            maxLines: 3,
            onChanged: (value) => _recipe = _recipe.copyWith(notes: value),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _recipe.imageAssetPath ?? '',
            decoration: const InputDecoration(
              labelText: 'Image asset path',
              helperText:
                  'Use the checked-in cocktail image path when this spec has a source photo.',
            ),
            onChanged: (value) => _recipe = _recipe.copyWith(
              imageAssetPath: value.trim().isEmpty ? null : value.trim(),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Use placeholder image'),
            subtitle: const Text(
              'Turn this on only if a verified source photo is not available yet.',
            ),
            value: _recipe.missingImage,
            onChanged: (value) => setState(
              () => _recipe = _recipe.copyWith(missingImage: value),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Ingredients and batch amounts',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          ..._recipe.ingredients.asMap().entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: entry.value.ingredientName,
                          decoration: InputDecoration(
                            labelText: entry.value.isBatchReference
                                ? 'Batch name'
                                : 'Ingredient',
                          ),
                          onChanged: (value) {
                            final updated = [..._recipe.ingredients];
                            updated[entry.key] = updated[entry.key].copyWith(
                              ingredientName: value,
                            );
                            setState(
                              () => _recipe = _recipe.copyWith(
                                ingredients: updated,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 120,
                        child: TextFormField(
                          initialValue:
                              entry.value.measureMl?.toStringAsFixed(0) ?? '',
                          decoration: InputDecoration(
                            labelText: entry.value.isBatchReference
                                ? 'Batch amount'
                                : 'Amount (ml)',
                          ),
                          onChanged: (value) {
                            final updated = [..._recipe.ingredients];
                            updated[entry.key] = updated[entry.key].copyWith(
                              measureMl: double.tryParse(value),
                            );
                            setState(
                              () => _recipe = _recipe.copyWith(
                                ingredients: updated,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Remove line',
                        onPressed: () {
                          final updated = [..._recipe.ingredients]
                            ..removeAt(entry.key);
                          setState(
                            () => _recipe = _recipe.copyWith(
                              ingredients: updated,
                            ),
                          );
                        },
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: entry.value.preparationNote ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Prep note',
                    ),
                    onChanged: (value) {
                      final updated = [..._recipe.ingredients];
                      updated[entry.key] = updated[entry.key].copyWith(
                        preparationNote: value.trim().isEmpty
                            ? null
                            : value.trim(),
                      );
                      setState(
                        () => _recipe = _recipe.copyWith(
                          ingredients: updated,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              setState(
                () => _recipe = _recipe.copyWith(
                  ingredients: [
                    ..._recipe.ingredients,
                    const RecipeIngredient(ingredientName: '', measureMl: null),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Add ingredient'),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => widget.onSave(_recipe),
            child: const Text('Save recipe'),
          ),
        ],
      ),
    );
  }
}

class _RecipeDraftEditorCard extends StatefulWidget {
  const _RecipeDraftEditorCard({
    required this.draft,
    required this.reviewState,
    required this.onChanged,
    required this.onApprove,
    required this.onKeepInReview,
    required this.onRemove,
  });

  final RecipeImportDraft draft;
  final RecipeReviewState reviewState;
  final ValueChanged<RecipeImportDraft> onChanged;
  final VoidCallback onApprove;
  final VoidCallback onKeepInReview;
  final VoidCallback onRemove;

  @override
  State<_RecipeDraftEditorCard> createState() => _RecipeDraftEditorCardState();
}

class BatchEditorPanel extends StatefulWidget {
  const BatchEditorPanel({
    super.key,
    required this.batch,
    required this.onSave,
  });

  final BatchRecipe batch;
  final ValueChanged<BatchRecipe> onSave;

  @override
  State<BatchEditorPanel> createState() => _BatchEditorPanelState();
}

class _BatchEditorPanelState extends State<BatchEditorPanel> {
  late BatchRecipe _batch = widget.batch;

  @override
  void didUpdateWidget(covariant BatchEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.batch.id != widget.batch.id) {
      _batch = widget.batch;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Edit batch spec',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            initialValue: _batch.name,
            decoration: const InputDecoration(labelText: 'Batch name'),
            onChanged: (value) => _batch = _batch.copyWith(name: value),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _batch.category,
            decoration: const InputDecoration(labelText: 'Category'),
            onChanged: (value) => _batch = _batch.copyWith(category: value),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _batch.totalBatchVolumeMl?.toStringAsFixed(0) ?? '',
            decoration: const InputDecoration(
              labelText: 'Total batch volume (ml)',
            ),
            onChanged: (value) => _batch = _batch.copyWith(
              totalBatchVolumeMl: double.tryParse(value),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _batch.notes,
            decoration: const InputDecoration(labelText: 'Prep notes'),
            maxLines: 3,
            onChanged: (value) => _batch = _batch.copyWith(notes: value),
          ),
          const SizedBox(height: 16),
          Text(
            'Batch build',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          ..._batch.ingredients.asMap().entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: entry.value.ingredientName,
                          decoration: const InputDecoration(
                            labelText: 'Ingredient',
                          ),
                          onChanged: (value) {
                            final updated = [..._batch.ingredients];
                            updated[entry.key] = updated[entry.key].copyWith(
                              ingredientName: value,
                            );
                            setState(
                              () => _batch = _batch.copyWith(
                                ingredients: updated,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 120,
                        child: TextFormField(
                          initialValue:
                              entry.value.measureMl?.toStringAsFixed(0) ?? '',
                          decoration: const InputDecoration(labelText: 'Ml'),
                          onChanged: (value) {
                            final updated = [..._batch.ingredients];
                            updated[entry.key] = updated[entry.key].copyWith(
                              measureMl: double.tryParse(value),
                            );
                            setState(
                              () => _batch = _batch.copyWith(
                                ingredients: updated,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Remove line',
                        onPressed: () {
                          final updated = [..._batch.ingredients]
                            ..removeAt(entry.key);
                          setState(
                            () => _batch = _batch.copyWith(
                              ingredients: updated,
                            ),
                          );
                        },
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: entry.value.preparationNote ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Prep note',
                    ),
                    onChanged: (value) {
                      final updated = [..._batch.ingredients];
                      updated[entry.key] = updated[entry.key].copyWith(
                        preparationNote: value.trim().isEmpty
                            ? null
                            : value.trim(),
                      );
                      setState(
                        () => _batch = _batch.copyWith(
                          ingredients: updated,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              setState(
                () => _batch = _batch.copyWith(
                  ingredients: [
                    ..._batch.ingredients,
                    const RecipeIngredient(ingredientName: '', measureMl: null),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Add ingredient'),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => widget.onSave(_batch),
            child: const Text('Save batch'),
          ),
        ],
      ),
    );
  }
}

class _RecipeDraftEditorCardState extends State<_RecipeDraftEditorCard> {
  late RecipeImportDraft _draft = widget.draft;

  @override
  void didUpdateWidget(covariant _RecipeDraftEditorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.draft, widget.draft)) {
      _draft = widget.draft;
    }
  }

  void _notify() => widget.onChanged(_draft);

  @override
  Widget build(BuildContext context) {
    final itemLabel = _draft.isBatch ? 'batch' : 'recipe';
    final confidenceLabel = switch (widget.reviewState.confidence) {
      RecipeConfidence.highConfidence => 'High confidence',
      RecipeConfidence.needsReview => 'Needs review',
      RecipeConfidence.possibleOcrIssue => 'Possible OCR issue',
    };
    final confidenceColor = switch (widget.reviewState.confidence) {
      RecipeConfidence.highConfidence => const Color(0xFF4DBA87),
      RecipeConfidence.needsReview => const Color(0xFFE1A545),
      RecipeConfidence.possibleOcrIssue => const Color(0xFFE46F6F),
    };
    final statusLabel = switch (_draft.status) {
      RecipeDraftStatus.pending => 'In review',
      RecipeDraftStatus.approved => 'Approved',
      RecipeDraftStatus.deleted => 'Removed',
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _draft.name.isEmpty
                            ? 'Untitled spec draft'
                            : _draft.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(
                            label: Text(confidenceLabel),
                            backgroundColor: confidenceColor.withValues(
                              alpha: 0.16,
                            ),
                            side: BorderSide(
                              color: confidenceColor.withValues(alpha: 0.4),
                            ),
                          ),
                          Chip(label: Text(statusLabel)),
                          if (_draft.wasManuallyReviewed)
                            const Chip(label: Text('Reviewed by hand')),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'approve':
                        widget.onApprove();
                        break;
                      case 'review':
                        widget.onKeepInReview();
                        break;
                      case 'delete':
                        widget.onRemove();
                        break;
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'approve',
                      child: Text('Approve spec'),
                    ),
                    PopupMenuItem(
                      value: 'review',
                      child: Text('Keep in review'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Remove false positive'),
                    ),
                  ],
                ),
              ],
            ),
            Text('${_draft.sourceLabel} • ${_draft.pageLabel}'),
            if (widget.reviewState.issues.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...widget.reviewState.issues.map(
                (issue) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '• ${issue.message}',
                    style: TextStyle(
                      color: issue.isPossibleOcrIssue
                          ? const Color(0xFFE46F6F)
                          : issue.isBlocking
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            TextFormField(
              initialValue: _draft.name,
              decoration: InputDecoration(
                labelText: _draft.isBatch ? 'Batch name' : 'Cocktail name',
              ),
              onChanged: (value) {
                _draft = _draft.copyWith(name: value);
                _notify();
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _draft.category,
              decoration: const InputDecoration(labelText: 'Category'),
              onChanged: (value) {
                _draft = _draft.copyWith(category: value);
                _notify();
              },
            ),
            const SizedBox(height: 12),
            if (_draft.isBatch)
              _SizedField(
                width: 220,
                child: TextFormField(
                  initialValue:
                      _draft.totalBatchVolumeMl?.toStringAsFixed(0) ?? '',
                  decoration: const InputDecoration(
                    labelText: 'Total batch volume (ml)',
                  ),
                  onChanged: (value) {
                    _draft = _draft.copyWith(
                      totalBatchVolumeMl: double.tryParse(value),
                    );
                    _notify();
                  },
                ),
              )
            else ...[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _SizedField(
                    width: 220,
                    child: TextFormField(
                      initialValue: _draft.glassware,
                      decoration: const InputDecoration(labelText: 'Glassware'),
                      onChanged: (value) {
                        _draft = _draft.copyWith(glassware: value);
                        _notify();
                      },
                    ),
                  ),
                  _SizedField(
                    width: 220,
                    child: TextFormField(
                      initialValue: _draft.garnish,
                      decoration: const InputDecoration(labelText: 'Garnish'),
                      onChanged: (value) {
                        _draft = _draft.copyWith(garnish: value);
                        _notify();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _draft.method,
                decoration: const InputDecoration(labelText: 'Method'),
                maxLines: 2,
                onChanged: (value) {
                  _draft = _draft.copyWith(method: value);
                  _notify();
                },
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _draft.notes,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 3,
              onChanged: (value) {
                _draft = _draft.copyWith(notes: value);
                _notify();
              },
            ),
            const SizedBox(height: 16),
            Text('Ingredients', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            ..._draft.ingredients.asMap().entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: entry.value.ingredientName,
                            decoration: const InputDecoration(
                              labelText: 'Ingredient name',
                            ),
                            onChanged: (value) {
                              final updated = [..._draft.ingredients];
                              updated[entry.key] = updated[entry.key].copyWith(
                                ingredientName: value,
                              );
                              _draft = _draft.copyWith(ingredients: updated);
                              _notify();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 110,
                          child: TextFormField(
                            initialValue:
                                entry.value.measureMl?.toStringAsFixed(0) ?? '',
                            decoration: const InputDecoration(labelText: 'Ml'),
                            onChanged: (value) {
                              final updated = [..._draft.ingredients];
                              updated[entry.key] = updated[entry.key].copyWith(
                                measureMl: double.tryParse(value),
                              );
                              _draft = _draft.copyWith(ingredients: updated);
                              _notify();
                            },
                          ),
                        ),
                      ],
                    ),
                    if (entry.value.preparationNote?.isNotEmpty == true) ...[
                      const SizedBox(height: 6),
                      Text(
                        entry.value.preparationNote!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                _draft = _draft.copyWith(
                  ingredients: [
                    ..._draft.ingredients,
                    const RecipeIngredient(ingredientName: '', measureMl: null),
                  ],
                );
                _notify();
                setState(() {});
              },
              icon: const Icon(Icons.add),
              label: const Text('Add ingredient line'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton(
                  onPressed: widget.reviewState.canApprove
                      ? widget.onApprove
                      : null,
                  child: Text('Approve $itemLabel'),
                ),
                OutlinedButton(
                  onPressed: widget.onKeepInReview,
                  child: const Text('Keep in review'),
                ),
                TextButton(
                  onPressed: widget.onRemove,
                  child: const Text('Remove false positive'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _ApprovedLibraryView { cocktails, batches }

class _WorkspaceSection {
  const _WorkspaceSection({required this.page, required this.destination});

  final Widget page;
  final NavigationDestination destination;
}

class _ScrollPage extends StatelessWidget {
  const _ScrollPage({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 10),
                Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        child,
      ],
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
      width: 245,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 16),
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 10),
              Text(caption, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      backgroundColor: color.withValues(alpha: 0.14),
      side: BorderSide(color: color.withValues(alpha: 0.35)),
      label: Text('$label: $value'),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFE1A545).withValues(alpha: 0.16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.cloud_off),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _WorkflowStepCard extends StatelessWidget {
  const _WorkflowStepCard({
    required this.index,
    required this.title,
    required this.description,
    required this.isComplete,
  });

  final int index;
  final String title;
  final String description;
  final bool isComplete;

  @override
  Widget build(BuildContext context) {
    final color = isComplete
        ? const Color(0xFF4DBA87)
        : const Color(0xFFE1A545);
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: color.withValues(alpha: 0.18),
                child: Text('$index', style: TextStyle(color: color)),
              ),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(description, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
              Text(
                isComplete ? 'Ready' : 'Next up',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.width});

  final String title;
  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final panel = Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
    if (width == null) {
      return panel;
    }
    return SizedBox(width: width, child: panel);
  }
}

class _DataRowTile extends StatelessWidget {
  const _DataRowTile({
    required this.title,
    required this.subtitle,
    this.trailing = '',
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: trailing.isEmpty ? null : Text(trailing),
      onTap: onTap,
    );
  }
}

class _MiniBullet extends StatelessWidget {
  const _MiniBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 8),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _EmptyText extends StatelessWidget {
  const _EmptyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.bodyMedium);
  }
}

class _SizedField extends StatelessWidget {
  const _SizedField({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width, child: child);
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
