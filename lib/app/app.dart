import 'package:cocktail_training/models/app_user.dart';
import 'package:cocktail_training/models/cocktail.dart';
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
          home: const AuthGate(),
          routes: {
            '/login': (context) => const LoginScreen(),
            '/join': (context) => const JoinScreen(),
            '/manager': (context) => const _ManagerRouteGate(),
            '/manager/invites': (context) => const _InviteLinksRouteGate(),
            '/manager/leaderboard': (context) => const _LeaderboardRouteGate(),
          },
        );
      },
    );
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
                body: Center(
                  child: Text('Failed to load cocktails'),
                ),
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
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights,
    ),
  ];

  static const _managerTab = _ShellTab(
    label: 'Manager',
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

  @override
  Widget build(BuildContext context) {
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

    return Scaffold(
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      children: List.generate(tabs.length, (index) {
                        final tab = tabs[index];
                        final selected = index == safeIndex;

                        return Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              setState(() {
                                _selectedIndex = index;
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    selected ? tab.selectedIcon : tab.icon,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(tab.label),
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
    );
  }
}

class _ShellTab {
  const _ShellTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PremiumBackdrop(
        child: const Center(
          child: CircularProgressIndicator(),
        ),
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
        currentUser: currentUser,
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
      builder: (currentUser, cocktails) => InviteLinksScreen(
        currentUser: currentUser,
      ),
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
        currentUser: currentUser,
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
        if (requireManager &&
            !RoleGuard.canAccessManagerTools(currentUser)) {
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
        MaterialPageRoute<void>(
          builder: (_) => const AuthGate(),
        ),
        (route) => false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const _LoadingScreen();
  }
}
