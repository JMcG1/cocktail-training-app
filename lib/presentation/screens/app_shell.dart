import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/browser_app_recovery.dart';
import '../../core/utils/browser_connectivity.dart';
import '../../core/utils/bundled_cocktail_catalog_loader.dart';
import '../../data/firestore/firestore_serializers.dart';
import '../../domain/models/models.dart';
import '../controllers/app_controller.dart';

String? sessionIdFromUri(Uri uri) {
  final pathSegments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
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
  final pathSegments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
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

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final pathSegments = Uri.base.pathSegments.where((segment) => segment.isNotEmpty).toList();
    final sessionId = sessionIdFromUri(Uri.base);
    final inviteRoute = inviteRouteFromUri(Uri.base);

    if (pathSegments.isNotEmpty && pathSegments.first == 'quiz' && sessionId == null) {
      return const HelpfulRouteScreen();
    }
    if (sessionId != null) {
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
    text: widget.controller.isDemoAuthMode ? widget.controller.demoManagerEmail : '',
  );
  late final TextEditingController _passwordController = TextEditingController(
    text: widget.controller.isDemoAuthMode ? widget.controller.demoManagerPassword : '',
  );
  final TextEditingController _ownerNameController = TextEditingController();
  final TextEditingController _ownerVenueController = TextEditingController();
  final TextEditingController _ownerEmailController = TextEditingController();
  final TextEditingController _ownerPasswordController = TextEditingController();
  bool _showOwnerSetup = false;

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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostics copied.')),
    );
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
                                style: Theme.of(context).textTheme.headlineLarge,
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
                                decoration: const InputDecoration(labelText: 'Email'),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _passwordController,
                                obscureText: true,
                                decoration: const InputDecoration(labelText: 'Password'),
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
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Text('Log in'),
                              ),
                              const SizedBox(height: 10),
                              TextButton(
                                onPressed: widget.controller.isBusy
                                    ? null
                                    : () async {
                                        final email = _emailController.text.trim();
                                        if (email.isEmpty) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Add your email first so we know where to send the reset link.'),
                                            ),
                                          );
                                          return;
                                        }
                                        try {
                                          await widget.controller.sendPasswordReset(email: email);
                                        } catch (_) {}
                                      },
                                child: const Text('Forgot password? Send reset link'),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Access is invite-only. Managers create bartender invites, and the invite decides the role automatically.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 18),
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
                                    onPressed: _copyDiagnostics,
                                    child: const Text('Copy diagnostics'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              _BuildMarkerSummary(
                                buildMarker: widget.controller.buildMarker,
                                appVersionLabel: widget.controller.appVersionLabel,
                                catalogPathLabel: widget.controller.catalogPathLabel,
                                visibleRecipeCount: widget.controller.recipes.length,
                              ),
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
                                style: Theme.of(context).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'This app only shows approved cocktails, approved batches, and approved images. OCR, imports, draft review, and stock variance workflows are not part of this learning experience.',
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
                              SwitchListTile.adaptive(
                                value: _showOwnerSetup,
                                onChanged: (value) => setState(() => _showOwnerSetup = value),
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Show owner/admin setup'),
                                subtitle: const Text(
                                  'Keep this for bootstrap venue setup if your Firebase project still supports it.',
                                ),
                              ),
                              if (_showOwnerSetup) ...[
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _ownerNameController,
                                  decoration: const InputDecoration(labelText: 'Owner/admin name'),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _ownerVenueController,
                                  decoration: const InputDecoration(labelText: 'Venue name'),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _ownerEmailController,
                                  decoration: const InputDecoration(labelText: 'Owner/admin email'),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _ownerPasswordController,
                                  obscureText: true,
                                  decoration: const InputDecoration(labelText: 'Password'),
                                ),
                                const SizedBox(height: 14),
                                OutlinedButton(
                                  onPressed: widget.controller.isBusy
                                      ? null
                                      : () async {
                                          try {
                                            await widget.controller.createManagerAccount(
                                              email: _ownerEmailController.text.trim(),
                                              password: _ownerPasswordController.text,
                                              displayName: _ownerNameController.text.trim(),
                                              venueName: _ownerVenueController.text.trim(),
                                            );
                                          } catch (_) {}
                                        },
                                  child: const Text('Create owner/admin workspace'),
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
                          invite == null
                              ? 'This invite will create the role attached to the link.'
                              : 'This invite creates a ${invite.role.name} account for the venue.',
                        ),
                        const SizedBox(height: 18),
                        if (snapshot.connectionState == ConnectionState.waiting) ...[
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
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(labelText: 'Display name'),
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
                          decoration: const InputDecoration(labelText: 'Password'),
                        ),
                        if (widget.controller.errorMessage != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            widget.controller.errorMessage!,
                            style: TextStyle(
                              color: Theme.of(context).extension<AppStatusColors>()?.warning,
                            ),
                          ),
                        ],
                        if (widget.controller.successMessage != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            widget.controller.successMessage!,
                            style: TextStyle(
                              color: Theme.of(context).extension<AppStatusColors>()?.accent,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        ElevatedButton(
                          onPressed: widget.controller.isBusy || !(invite?.isRedeemable ?? true)
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
                              _inviteFuture = widget.controller.fetchVenueInvite(
                                venueId: widget.inviteRoute.venueId,
                                inviteId: widget.inviteRoute.inviteId,
                              );
                            });
                          },
                          child: const Text('Refresh invite'),
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
    return _LearningWorkspace(controller: widget.controller, showManagerTools: true);
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
        onDestinationSelected: (value) => setState(() => _selectedIndex = value),
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
  });

  final AppController controller;
  final String headerTitle;
  final String headerSubtitle;

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
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CocktailDetailScreen(
                    recipe: recipe,
                    batches: widget.controller.batches,
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
      return const Center(child: Text('Approved cocktails will appear here once the library loads.'));
    }
    final recipe = recipes[_index % recipes.length];
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
                _CocktailHero(recipe: recipe, imageHeight: 220),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (recipe.category.trim().isNotEmpty) Chip(label: Text(recipe.category)),
                    Chip(label: Text(recipe.glassware.isEmpty ? 'Glassware pending' : recipe.glassware)),
                    Chip(label: Text(recipe.garnish.isEmpty ? 'Garnish pending' : recipe.garnish)),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  recipe.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(recipe.notes.isEmpty ? 'Open the answer panel when you want the full spec.' : recipe.notes),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => setState(() => _showAnswers = !_showAnswers),
                  child: Text(_showAnswers ? 'Hide answers' : 'Reveal ingredients'),
                ),
                if (_showAnswers) ...[
                  const SizedBox(height: 16),
                  _RecipeSpecBlock(recipe: recipe, batches: widget.controller.batches),
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

  @override
  Widget build(BuildContext context) {
    final bartenderName = widget.controller.currentUser?.displayName ?? 'Bartender';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _HeaderCard(
          title: 'Quiz mode',
          subtitle:
              'Questions are generated from the approved cocktail and batch specs only. Batch amounts are treated like ingredients.',
        ),
        const SizedBox(height: 16),
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
                  const Text(
                    'Each round uses up to 10 approved questions covering measurements, ingredients, batch amounts, garnish, glassware, and method.',
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _completedAttempt = null;
                        _answers = {};
                        _activeSession = widget.controller.generatePracticeQuiz(
                          bartenderName: bartenderName,
                        );
                      });
                    },
                    child: const Text('Start quiz'),
                  ),
                ],
              ),
            ),
          )
        else
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
            _MetricCard(title: 'Quizzes', value: '${stats.quizCount}', caption: 'Completed rounds'),
            _MetricCard(title: 'Average score', value: '${stats.averageScore}%', caption: 'Across loaded quiz attempts'),
            _MetricCard(title: 'Confidence', value: stats.confidenceLabel, caption: 'Friendly pulse check'),
          ],
        ),
        const SizedBox(height: 16),
        _InsightListCard(
          title: 'Cocktails to revisit',
          emptyLabel: 'No weak cocktails yet. Start a quiz and your learning highlights will appear here.',
          items: stats.weakCocktails.entries.map((entry) => '${entry.key} · ${entry.value} misses').toList(),
        ),
        const SizedBox(height: 16),
        _InsightListCard(
          title: 'Ingredient focus areas',
          emptyLabel: 'Ingredient patterns will appear after a few quiz rounds.',
          items: stats.weakIngredients.entries.map((entry) => '${entry.key} · ${entry.value} misses').toList(),
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
  final TextEditingController _maxUsesController = TextEditingController(text: '1');
  int _expiryDays = 7;

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

  @override
  Widget build(BuildContext context) {
    final dashboard = widget.controller.buildDashboard();
    final bartenderCompletion = dashboard.bartenderAverageScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final weakCocktails = dashboard.misunderstoodCocktails.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final weakIngredients = dashboard.ingredientMisses.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final weakBatches = dashboard.potentialVarianceByBatch.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final inviteOptions = widget.controller.isOwnerAuthenticated
        ? const [UserRole.manager, UserRole.bartender]
        : const [UserRole.bartender];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _HeaderCard(
          title: 'Team view',
          subtitle:
              'Managers can coach against approved cocktail knowledge only. No variance, sales, OCR, or approval tooling appears here.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              title: 'Bartenders',
              value: '${dashboard.bartenderAverageScores.length}',
              caption: 'With loaded quiz history',
            ),
            _MetricCard(
              title: 'Average score',
              value: '${dashboard.venueAverageScore}%',
              caption: 'Across loaded team attempts',
            ),
            _MetricCard(
              title: 'Quiz completion',
              value: '${widget.controller.quizAttempts.length}',
              caption: 'Recorded quiz submissions',
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
                Text('Create invite', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<UserRole>(
                        value: _inviteRole,
                        items: inviteOptions
                            .map(
                              (role) => DropdownMenuItem(
                                value: role,
                                child: Text(role.name),
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
                        decoration: const InputDecoration(labelText: 'Max uses'),
                      ),
                    ),
                    SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<int>(
                        value: _expiryDays,
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
                        decoration: const InputDecoration(labelText: 'Expires in'),
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
                              expiresAt: DateTime.now().add(Duration(days: _expiryDays)),
                              maxUses: int.tryParse(_maxUsesController.text.trim()) ?? 1,
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
                Text('Live invites', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (widget.controller.venueInvites.isEmpty)
                  const Text('No invites have been created yet.')
                else
                  ...widget.controller.venueInvites.map(
                    (invite) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${invite.role.name} invite'),
                      subtitle: Text('Uses ${invite.currentUses}/${invite.maxUses} · Expires ${DateFormat('d MMM').format(invite.expiresAt)}'),
                      trailing: SizedBox(
                        width: 130,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              onPressed: () async {
                                final joinUrl = '${Uri.base.origin}/join/${invite.venueId}/${invite.id}';
                                await Clipboard.setData(ClipboardData(text: joinUrl));
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Invite link copied.')),
                                  );
                                }
                              },
                              icon: const Icon(Icons.copy),
                              tooltip: 'Copy invite link',
                            ),
                            Switch(
                              value: !invite.disabled,
                              onChanged: (value) async {
                                await widget.controller.setVenueInviteDisabled(
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
            ),
          ),
        ),
        const SizedBox(height: 16),
        _InsightListCard(
          title: 'Bartender average scores',
          emptyLabel: 'Team quiz history will appear here after the first submissions.',
          items: bartenderCompletion
              .map((entry) => '${entry.key} · ${entry.value}% average')
              .toList(),
        ),
        const SizedBox(height: 16),
        _InsightListCard(
          title: 'Weak cocktails',
          emptyLabel: 'No repeated cocktail misses are visible yet.',
          items: weakCocktails.take(8).map((entry) => '${entry.key} · ${entry.value} misses').toList(),
        ),
        const SizedBox(height: 16),
        _InsightListCard(
          title: 'Weak ingredient areas',
          emptyLabel: 'Ingredient trends will appear after a few quizzes.',
          items: weakIngredients.take(8).map((entry) => '${entry.key} · ${entry.value} misses').toList(),
        ),
        const SizedBox(height: 16),
        _InsightListCard(
          title: 'Weak batch areas',
          emptyLabel: 'Batch-specific patterns will appear once batch questions are answered.',
          items: weakBatches.take(8).map((entry) => '${entry.key} · ${entry.value.toStringAsFixed(0)}ml attention area').toList(),
        ),
      ],
    );
  }
}

class SettingsTab extends StatelessWidget {
  const SettingsTab({
    super.key,
    required this.controller,
    required this.isOnline,
  });

  final AppController controller;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _HeaderCard(
          title: 'Settings',
          subtitle:
              'Deployment and auth stay on the existing Cocktail Training Firebase and Cloudflare setup. This screen is for quick checks and cleanup only.',
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Build and data', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                _DataLine(label: 'Build', value: controller.buildMarker),
                _DataLine(label: 'Version', value: controller.appVersionLabel),
                _DataLine(label: 'Runtime', value: controller.runtimeModeLabel),
                _DataLine(label: 'Venue ID', value: controller.currentUser?.venueId ?? controller.catalogPathLabel),
                _DataLine(label: 'Live cocktails', value: '${controller.recipes.length}'),
                _DataLine(label: 'Live batches', value: '${controller.batches.length}'),
                _DataLine(label: 'Online', value: isOnline ? 'Yes' : 'No'),
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
                            text: weeklyResultsExportJson(controller.quizAttempts),
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
      ],
    );
  }
}

class CocktailDetailScreen extends StatelessWidget {
  const CocktailDetailScreen({
    super.key,
    required this.recipe,
    required this.batches,
  });

  final CocktailRecipe recipe;
  final List<BatchRecipe> batches;

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
                      if (recipe.category.trim().isNotEmpty) Chip(label: Text(recipe.category)),
                      if (recipe.glassware.trim().isNotEmpty) Chip(label: Text(recipe.glassware)),
                      if (recipe.garnish.trim().isNotEmpty) Chip(label: Text(recipe.garnish)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _RecipeSpecBlock(recipe: recipe, batches: batches),
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
    final bartenderName = widget.controller.currentUser?.displayName ?? 'Bartender';
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
                      content: Text('Score: ${attempt.scorePercent}%\n\n${attempt.encouragement}'),
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
    final allAnswered = session.questions.every((question) => (answers[question.id] ?? '').isNotEmpty);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('${session.questions.length} approved questions'),
            const SizedBox(height: 20),
            ...session.questions.map(
              (question) => Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(question.prompt, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    ...question.options.map(
                      (option) => RadioListTile<String>(
                        value: option,
                        groupValue: answers[question.id],
                        onChanged: (value) {
                          if (value != null) {
                            onAnswerChanged(question.id, value);
                          }
                        },
                        title: Text(option),
                        contentPadding: EdgeInsets.zero,
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
            Text('Latest result', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text('${attempt.scorePercent}%', style: Theme.of(context).textTheme.headlineLarge),
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
  });

  final CocktailRecipe recipe;
  final List<BatchRecipe> batches;

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
        _SpecLine(label: 'Method', value: recipe.method),
        _SpecLine(label: 'Glassware', value: recipe.glassware),
        _SpecLine(label: 'Garnish', value: recipe.garnish),
        if (recipe.notes.trim().isNotEmpty) _SpecLine(label: 'Notes', value: recipe.notes),
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
          Text('Linked batches', style: Theme.of(context).textTheme.titleMedium),
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
                      Text(batch.name, style: Theme.of(context).textTheme.titleMedium),
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
  });

  final CocktailRecipe recipe;
  final VoidCallback onTap;

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
                    const SizedBox(height: 10),
                    Text(
                      recipe.ingredients.take(3).map((item) => item.ingredientName).join(' • '),
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

class _CocktailHero extends StatelessWidget {
  const _CocktailHero({
    required this.recipe,
    required this.imageHeight,
  });

  final CocktailRecipe recipe;
  final double imageHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CocktailImage(recipe: recipe, size: double.infinity, height: imageHeight),
        const SizedBox(height: 14),
        Text(
          recipe.name,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ],
    );
  }
}

class _CocktailImage extends StatelessWidget {
  const _CocktailImage({
    required this.recipe,
    required this.size,
    this.height,
  });

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
              errorBuilder: (_, __, ___) => const _ImagePlaceholder(),
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
  const _SpecLine({
    required this.label,
    required this.value,
  });

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
            if (trailing != null) ...[
              const SizedBox(width: 16),
              trailing!,
            ],
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
  const _InfoMetric({
    required this.label,
    required this.value,
  });

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
          Text('Build $buildMarker', style: Theme.of(context).textTheme.labelLarge),
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

class _DataLine extends StatelessWidget {
  const _DataLine({
    required this.label,
    required this.value,
  });

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
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
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
      for (final response in attempt.responses.where((item) => !item.isCorrect)) {
        final recipeName =
            recipesById[response.question.cocktailId]?.name ?? response.question.cocktailName;
        weakCocktails.update(recipeName, (value) => value + 1, ifAbsent: () => 1);
        final ingredientName = (response.question.ingredientName ?? '').trim();
        if (ingredientName.isNotEmpty) {
          weakIngredients.update(ingredientName, (value) => value + 1, ifAbsent: () => 1);
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
      weakCocktails: {for (final entry in sortedCocktails.take(6)) entry.key: entry.value},
      weakIngredients: {
        for (final entry in sortedIngredients.take(6)) entry.key: entry.value,
      },
    );
  }
}
