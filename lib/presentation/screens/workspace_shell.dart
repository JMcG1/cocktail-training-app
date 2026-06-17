import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/utils/browser_connectivity.dart';
import '../../core/utils/browser_history.dart';
import '../../core/utils/workspace_tab_history.dart';
import '../controllers/app_controller.dart';
import 'library_progress_tabs.dart';
import 'manager_team_tab.dart';
import 'quiz_tabs.dart';
import 'settings_tab.dart';
import 'shell_route_helpers.dart';
import 'study_mode_tab.dart';

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
  late final WorkspaceTabHistory _tabHistory;

  bool get _showSettingsMenu => widget.showManagerTools;

  @override
  void initState() {
    super.initState();
    _selectedIndex = _indexFromFragment(currentBrowserFragment());
    _tabHistory = WorkspaceTabHistory(initialIndex: _selectedIndex);
    addBrowserHistoryListener(_handleBrowserFragmentChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      primeBrowserHistory(_fragmentForIndex(_selectedIndex));
      replaceBrowserFragment(_fragmentForIndex(_selectedIndex));
    });
  }

  @override
  void dispose() {
    removeBrowserHistoryListener(_handleBrowserFragmentChange);
    super.dispose();
  }

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
        body: QuizModeTab(
          controller: widget.controller,
          buildQuizLink: (session) =>
              quizLinkUriFromBase(Uri.base, session).toString(),
          openShareDialog: (context, title, url) =>
              showShareLinkDialog(context: context, title: title, url: url),
        ),
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        final previousIndex = _tabHistory.popPrevious();
        if (previousIndex != null) {
          replaceBrowserFragment(_fragmentForIndex(previousIndex));
          setState(() => _selectedIndex = previousIndex);
          return;
        }
        if (_selectedIndex != 0) {
          replaceBrowserFragment(_fragmentForIndex(0));
          _tabHistory.visit(0);
          setState(() => _selectedIndex = 0);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Cocktail Training - ${page.title}'),
          actions: [
            PopupMenuButton<String>(
              onSelected: (value) async {
                switch (value) {
                  case 'settings':
                    if (!_showSettingsMenu) {
                      return;
                    }
                    final previousFragment = currentBrowserFragment();
                    const settingsFragment = 'settings';
                    pushBrowserFragment(settingsFragment);
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _SettingsRouteScreen(
                          controller: widget.controller,
                          expectedFragment: settingsFragment,
                        ),
                      ),
                    );
                    if (!context.mounted) {
                      return;
                    }
                    replaceBrowserFragment(previousFragment);
                    break;
                  case 'logout':
                    await widget.controller.signOut();
                    break;
                }
              },
              itemBuilder: (context) => [
                if (_showSettingsMenu)
                  const PopupMenuItem(
                    value: 'settings',
                    child: Text('Settings'),
                  ),
                const PopupMenuItem(value: 'logout', child: Text('Log out')),
              ],
            ),
          ],
        ),
        body: SafeArea(child: page.body),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (value) {
            if (value == _selectedIndex) {
              return;
            }
            pushBrowserFragment(_fragmentForIndex(value));
            _tabHistory.visit(value);
            setState(() => _selectedIndex = value);
          },
          destinations: pages.map((item) => item.destination).toList(),
        ),
      ),
    );
  }

  void _handleBrowserFragmentChange(String fragment) {
    if (!mounted) {
      return;
    }
    final targetIndex = _indexFromFragment(fragment);
    if (targetIndex != _selectedIndex) {
      _tabHistory.syncFromBrowser(targetIndex);
      setState(() => _selectedIndex = targetIndex);
    }
  }

  int _indexFromFragment(String fragment) {
    switch (fragment) {
      case 'team':
        return widget.showManagerTools ? 4 : 0;
      case 'progress':
        return 3;
      case 'quiz':
        return 2;
      case 'study':
        return 1;
      case 'library':
        return 0;
      case 'settings':
        return _selectedIndex;
      default:
        return 0;
    }
  }

  String _fragmentForIndex(int index) {
    switch (index) {
      case 3:
        return 'progress';
      case 2:
        return 'quiz';
      case 1:
        return 'study';
      case 4:
        return widget.showManagerTools ? 'team' : 'library';
      case 0:
      default:
        return 'library';
    }
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

class _SettingsRouteScreen extends StatefulWidget {
  const _SettingsRouteScreen({
    required this.controller,
    required this.expectedFragment,
  });

  final AppController controller;
  final String expectedFragment;

  @override
  State<_SettingsRouteScreen> createState() => _SettingsRouteScreenState();
}

class _SettingsRouteScreenState extends State<_SettingsRouteScreen> {
  @override
  void initState() {
    super.initState();
    addBrowserHistoryListener(_handleBrowserFragmentChange);
  }

  @override
  void dispose() {
    removeBrowserHistoryListener(_handleBrowserFragmentChange);
    super.dispose();
  }

  void _handleBrowserFragmentChange(String fragment) {
    if (!mounted || fragment == widget.expectedFragment) {
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SettingsTab(
        controller: widget.controller,
        isOnline: BrowserConnectivity.isOnline(),
      ),
    );
  }
}
