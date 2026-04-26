import 'package:cocktail_training/models/app_user.dart';
import 'package:cocktail_training/models/cocktail.dart';
import 'package:cocktail_training/models/user_role.dart';
import 'package:cocktail_training/repositories/cocktail_repository.dart';
import 'package:cocktail_training/screens/auth/join_screen.dart';
import 'package:cocktail_training/screens/cocktail_detail_screen.dart';
import 'package:cocktail_training/screens/home_screen.dart';
import 'package:cocktail_training/screens/invite_links_screen.dart';
import 'package:cocktail_training/screens/leaderboard_screen.dart';
import 'package:cocktail_training/screens/login_screen.dart';
import 'package:cocktail_training/screens/manager_dashboard_screen.dart';
import 'package:cocktail_training/screens/progress_screen.dart';
import 'package:cocktail_training/screens/quiz_mode_screen.dart';
import 'package:cocktail_training/screens/study_mode_screen.dart';
import 'package:cocktail_training/services/role_guard.dart';
import 'package:cocktail_training/services/session_service.dart';
import 'package:cocktail_training/theme/app_theme.dart';
import 'package:cocktail_training/widgets/premium_backdrop.dart';
import 'package:flutter/material.dart';

class CocktailTrainingApp extends StatelessWidget {
  const CocktailTrainingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: SessionService.instance.initialize(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: _LoadingScreen(),
          );
        }

        return MaterialApp(
          title: 'CocktailTraining',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.theme,
          home: const _LaunchScreen(),
          onGenerateRoute: _generateRoute,
        );
      },
    );
  }

  Route<dynamic> _generateRoute(RouteSettings settings) {
    final rawName = settings.name ?? '/';
    final uri = Uri.tryParse(rawName);
    final path = _normaliseRoutePath(uri?.path ?? rawName);

    Widget page;

    switch (path) {
      case '/login':
        page = const LoginScreen();
        break;

      case '/join':
        page = const JoinScreen();
        break;

      case '/app':
        page = const AuthGate();
        break;

      case '/manager':
        page = const _ManagerRouteGate();
        break;

      case '/manager/invites':
        page = const _InviteLinksRouteGate();
        break;

      case '/manager/leaderboard':
        page = const _LeaderboardRouteGate();
        break;

      case '/':
      case '':
        page = const _LaunchScreen();
        break;

      default:
        page = const _LaunchScreen();
        break;
    }

    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => page,
    );
  }

  static String _normaliseRoutePath(String route) {
    var cleaned = route.trim();

    if (cleaned.isEmpty) {
      return '/';
    }

    if (cleaned.startsWith('#')) {
      cleaned = cleaned.substring(1);
    }

    if (cleaned.contains('?')) {
      cleaned = cleaned.split('?').first;
    }

    if (cleaned.isEmpty) {
      return '/';
    }

    if (!cleaned.startsWith('/')) {
      cleaned = '/$cleaned';
    }

    return cleaned;
  }
}

class _LaunchScreen extends StatelessWidget {
  const _LaunchScreen();

  @override
  Widget build(BuildContext context) {
    final launchTarget = _LaunchTarget.fromUri(Uri.base);

    if (launchTarget.isJoin) {
      return const JoinScreen();
    }
    if (launchTarget.isManagerInvites) {
      return const _InviteLinksRouteGate();
    }
    if (launchTarget.isManagerLeaderboard) {
      return const _LeaderboardRouteGate();
    }
    if (launchTarget.isManagerDashboard) {
      return const _ManagerRouteGate();
    }

    return const AuthGate();
  }
}

class _LaunchTarget {
  const _LaunchTarget._({
    required this.isJoin,
    required this.isManagerDashboard,
    required this.isManagerInvites,
    required this.isManagerLeaderboard,
  });

  factory _LaunchTarget.fromUri(Uri uri) {
    final directPath = _normalizeRoute(uri.path);
    final fragmentRoute = _normalizeFragmentRoute(uri.fragment);
    final rawUri = uri.toString().toLowerCase();

    final hasInviteToken =
        uri.queryParameters.containsKey('token') ||
            uri.queryParameters.containsKey('code') ||
            uri.queryParameters.containsKey('invite') ||
            rawUri.contains('?token=') ||
            rawUri.contains('&token=') ||
            rawUri.contains('?code=') ||
            rawUri.contains('&code=') ||
            rawUri.contains('?invite=') ||
            rawUri.contains('&invite=');

    final isJoin =
        directPath == '/join' ||
            fragmentRoute == '/join' ||
            fragmentRoute.startsWith('/join/') ||
            rawUri.contains('#/join?') ||
            rawUri.contains('#join?') ||
            (hasInviteToken &&
                (directPath == '/' ||
                    directPath.isEmpty ||
                    fragmentRoute == '/' ||
                    fragmentRoute.isEmpty));

    final isManagerInvites =
        directPath == '/manager/invites' ||
            fragmentRoute == '/manager/invites';

    final isManagerLeaderboard =
        directPath == '/manager/leaderboard' ||
            fragmentRoute == '/manager/leaderboard';

    final isManagerDashboard =
        directPath == '/manager' || fragmentRoute == '/manager';

    return _LaunchTarget._(
      isJoin: isJoin,
      isManagerDashboard: isManagerDashboard,
      isManagerInvites: isManagerInvites,
      isManagerLeaderboard: isManagerLeaderboard,
    );
  }

  final bool isJoin;
  final bool isManagerDashboard;
  final bool isManagerInvites;
  final bool isManagerLeaderboard;

  static String _normalizeFragmentRoute(String fragment) {
    if (fragment.isEmpty) {
      return '';
    }

    final routeOnly = fragment.split('?').first.trim();
    return _normalizeRoute(routeOnly);
  }

  static String _normalizeRoute(String route) {
    final trimmed = route.trim();

    if (trimmed.isEmpty) {
      return '';
    }

    final withoutHash =
    trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;

    final withoutQuery = withoutHash.contains('?')
        ? withoutHash.split('?').first
        : withoutHash;

    if (withoutQuery.startsWith('/')) {
      return withoutQuery;
    }

    return '/$withoutQuery';
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = const CocktailRepository();

    return StreamBuilder<AppUser?>(
      stream: SessionService.instance.authStateChanges,
      initialData: SessionService.instance.currentUser,
      builder: (context, authSnapshot) {
        final currentUser = authSnapshot.data;

        if (currentUser == null) {
          return const LoginScreen();
        }

        return FutureBuilder<List<Cocktail>>(
          future: repository.loadCocktails(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _LoadingScreen();
            }

            if (snapshot.hasError) {
              return const Scaffold(
                body: Center(child: Text('Failed to load cocktails')),
              );
            }

            return TrainingShell(
              cocktails: snapshot.data ?? const [],
              currentUser: currentUser,
            );
          },
        );
      },
    );
  }
}

class TrainingShell extends StatefulWidget {
  const TrainingShell({
    super.key,
    required this.cocktails,
    required this.currentUser,
  });

  final List<Cocktail> cocktails;
  final AppUser currentUser;

  @override
  State<TrainingShell> createState() => _TrainingShellState();
}

class _TrainingShellState extends State<TrainingShell> {
  int _selectedIndex = 0;
  bool _signingOut = false;
  final List<int> _tabHistory = <int>[0];

  static const _baseTabs = <_ShellTab>[
    _ShellTab(
      label: 'Library',
      icon: Icons.local_bar_outlined,
      selectedIcon: Icons.local_bar,
    ),
    _ShellTab(
      label: 'Study',
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book,
    ),
    _ShellTab(
      label: 'Quiz',
      icon: Icons.verified_outlined,
      selectedIcon: Icons.verified,
    ),
    _ShellTab(
      label: 'Progress',
      compactLabel: 'Stats',
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights,
    ),
  ];

  static const _managerTab = _ShellTab(
    label: 'Manager',
    compactLabel: 'Admin',
    icon: Icons.admin_panel_settings_outlined,
    selectedIcon: Icons.admin_panel_settings,
  );

  void _openCocktailDetail(Cocktail cocktail) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CocktailDetailScreen(cocktail: cocktail),
      ),
    );
  }

  Future<void> _signOut() async {
    if (_signingOut) {
      return;
    }

    setState(() {
      _signingOut = true;
    });

    try {
      await SessionService.instance.signOut();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('We couldn’t sign you out right now.'),
            ),
          );
      }
    } finally {
      if (mounted) {
        setState(() {
          _signingOut = false;
        });
      }
    }
  }

  void _selectTab(int index) {
    if (_selectedIndex == index) {
      return;
    }

    setState(() {
      _selectedIndex = index;
      _tabHistory.remove(index);
      _tabHistory.add(index);
    });
  }

  void _handleBackNavigation() {
    if (_tabHistory.length > 1) {
      setState(() {
        _tabHistory.removeLast();
        _selectedIndex = _tabHistory.last;
      });
      return;
    }

    if (_selectedIndex != 0) {
      setState(() {
        _selectedIndex = 0;
        _tabHistory
          ..clear()
          ..add(0);
      });
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final useCompactNavLabels = screenWidth < 430;
    final tabs = [
      ..._baseTabs,
      if (widget.currentUser.isManager) _managerTab,
    ];

    final pages = <Widget>[
      HomeScreen(
        cocktails: widget.cocktails,
        onSelectCocktail: _openCocktailDetail,
      ),
      StudyModeScreen(cocktails: widget.cocktails),
      QuizModeScreen(cocktails: widget.cocktails),
      ProgressScreen(cocktails: widget.cocktails),
      if (widget.currentUser.isManager)
        ManagerDashboardScreen(
          currentUser: widget.currentUser,
          cocktails: widget.cocktails,
        ),
    ];

    final safeIndex = _selectedIndex >= pages.length ? 0 : _selectedIndex;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }

        _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: KeyedSubtree(
                  key: ValueKey(safeIndex),
                  child: pages[safeIndex],
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: PopupMenuButton<_ShellMenuAction>(
                    enabled: !_signingOut,
                    tooltip: 'Account',
                    color: const Color(0xFF171E27),
                    onSelected: (value) {
                      if (value == _ShellMenuAction.logout) {
                        _signOut();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<_ShellMenuAction>(
                        enabled: false,
                        height: 56,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              widget.currentUser.name,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              widget.currentUser.role.label,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: _ShellMenuAction.logout,
                        child: Row(
                          children: [
                            Icon(Icons.logout),
                            SizedBox(width: 10),
                            Text('Log out'),
                          ],
                        ),
                      ),
                    ],
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF11161D).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.14),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Center(
                        child: _signingOut
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                widget.currentUser.isManager
                                    ? Icons.admin_panel_settings_outlined
                                    : Icons.person_outline,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF11161D).withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Row(
                        children: List.generate(tabs.length, (index) {
                          final tab = tabs[index];
                          final label = useCompactNavLabels
                              ? tab.compactLabel
                              : tab.label;
                          final selected = index == safeIndex;

                          return Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _selectTab(index),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(selected ? tab.selectedIcon : tab.icon),
                                    const SizedBox(height: 6),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          label,
                                          maxLines: 1,
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellTab {
  const _ShellTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    String? compactLabel,
  }) : compactLabel = compactLabel ?? label;

  final String label;
  final String compactLabel;
  final IconData icon;
  final IconData selectedIcon;
}

enum _ShellMenuAction { logout }

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PremiumBackdrop(
        child: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _ManagerRouteGate extends StatelessWidget {
  const _ManagerRouteGate();

  @override
  Widget build(BuildContext context) {
    return _ProtectedCocktailRoute(
      requireManager: true,
      builder: (currentUser, cocktails) => ManagerDashboardScreen(
        currentUser: currentUser!,
        cocktails: cocktails,
      ),
    );
  }
}

class _InviteLinksRouteGate extends StatelessWidget {
  const _InviteLinksRouteGate();

  @override
  Widget build(BuildContext context) {
    return _ProtectedCocktailRoute(
      requireManager: true,
      builder: (currentUser, cocktails) =>
          InviteLinksScreen(currentUser: currentUser!),
    );
  }
}

class _LeaderboardRouteGate extends StatelessWidget {
  const _LeaderboardRouteGate();

  @override
  Widget build(BuildContext context) {
    return _ProtectedCocktailRoute(
      requireManager: true,
      builder: (currentUser, cocktails) => LeaderboardScreen(
        currentUser: currentUser!,
        cocktails: cocktails,
      ),
    );
  }
}

class _ProtectedCocktailRoute extends StatelessWidget {
  const _ProtectedCocktailRoute({
    required this.builder,
    this.requireManager = false,
  });

  final Widget Function(AppUser? currentUser, List<Cocktail> cocktails) builder;
  final bool requireManager;

  @override
  Widget build(BuildContext context) {
    final repository = const CocktailRepository();

    return FutureBuilder<AppUser?>(
      future: SessionService.instance.getCurrentUser(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState != ConnectionState.done) {
          return const _LoadingScreen();
        }

        final currentUser = userSnapshot.data;

        if (currentUser == null) {
          return const LoginScreen();
        }

        if (requireManager && !RoleGuard.canAccessManagerTools(currentUser)) {
          return const _RedirectHomeScreen();
        }

        return FutureBuilder<List<Cocktail>>(
          future: repository.loadCocktails(),
          builder: (context, cocktailSnapshot) {
            if (cocktailSnapshot.connectionState != ConnectionState.done) {
              return const _LoadingScreen();
            }

            return builder(currentUser, cocktailSnapshot.data ?? const []);
          },
        );
      },
    );
  }
}

class _RedirectHomeScreen extends StatefulWidget {
  const _RedirectHomeScreen();

  @override
  State<_RedirectHomeScreen> createState() => _RedirectHomeScreenState();
}

class _RedirectHomeScreenState extends State<_RedirectHomeScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final messenger = ScaffoldMessenger.maybeOf(context);

      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Manager access required for that screen.'),
        ),
      );

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const AuthGate()),
            (route) => false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const _LoadingScreen();
  }
}
