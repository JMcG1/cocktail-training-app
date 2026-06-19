import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import 'auth_screens.dart';
import 'quiz_tabs.dart';
import 'shell_route_helpers.dart';
import 'workspace_shell.dart';

export 'settings_tab.dart';
export 'shell_route_helpers.dart';
export 'auth_screens.dart';
export 'workspace_shell.dart';

Widget buildAppHomeScreen(AppController controller) {
  if (controller.canAccessManagerWorkflows) {
    return ManagerWorkspace(controller: controller);
  }
  if (controller.canAccessBartenderWorkflows) {
    return TrainingWorkspace(controller: controller);
  }
  return LandingScreen(controller: controller, onOpenTraining: () {});
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
      return BartenderQuizScreen(
        controller: controller,
        sessionId: sessionId,
        homeBuilder: () => buildAppHomeScreen(controller),
      );
    }
    if (inviteRoute != null && controller.currentUser == null) {
      return InviteJoinScreen(controller: controller, inviteRoute: inviteRoute);
    }
    return buildAppHomeScreen(controller);
  }
}
