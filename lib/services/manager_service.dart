import 'package:cocktail_training/models/app_user.dart';
import 'package:cocktail_training/models/cocktail.dart';
import 'package:cocktail_training/models/leaderboard_entry.dart';
import 'package:cocktail_training/models/manager_overview.dart';
import 'package:cocktail_training/models/training_progress.dart';
import 'package:cocktail_training/models/user_role.dart';
import 'package:cocktail_training/services/session_service.dart';
import 'package:cocktail_training/services/training_progress_service.dart';

class ManagerService {
  ManagerService._();

  static final ManagerService instance = ManagerService._();

  final SessionService _sessionService = SessionService.instance;
  final TrainingProgressService _trainingProgressService =
      TrainingProgressService.instance;

  Future<ManagerOverview> loadOverview({
    required AppUser manager,
    required List<Cocktail> cocktails,
  }) async {
    final staffUsers = await _loadVenueStaff(manager.venueId);
    if (staffUsers.isEmpty) {
      return const ManagerOverview(
        totalStaff: 0,
        activeStaff: 0,
        totalQuizAttempts: 0,
        averageScore: 0,
        weakCocktailAreas: [],
      );
    }

    var totalQuizAttempts = 0;
    var totalCorrectAnswers = 0;
    final weakCounts = <String, int>{};

    for (final user in staffUsers) {
      final progress = await _trainingProgressService.loadProgressForUser(
        user.id,
      );
      totalQuizAttempts += progress.totalQuizQuestions;
      totalCorrectAnswers += progress.totalCorrectAnswers;

      for (final weakName in _weakCocktailNames(progress, cocktails)) {
        weakCounts[weakName] = (weakCounts[weakName] ?? 0) + 1;
      }
    }

    final sortedWeakAreas = weakCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ManagerOverview(
      totalStaff: staffUsers.length,
      activeStaff: staffUsers.where((user) => user.active).length,
      totalQuizAttempts: totalQuizAttempts,
      averageScore: totalQuizAttempts == 0
          ? 0
          : totalCorrectAnswers / totalQuizAttempts,
      weakCocktailAreas: sortedWeakAreas
          .take(5)
          .map((entry) => entry.key)
          .toList(growable: false),
    );
  }

  Future<List<LeaderboardEntry>> loadLeaderboard({
    required AppUser manager,
    required List<Cocktail> cocktails,
    required LeaderboardSort sortBy,
  }) async {
    final staffUsers = await _loadVenueStaff(manager.venueId);
    final entries = <LeaderboardEntry>[];

    for (final user in staffUsers) {
      final progress = await _trainingProgressService.loadProgressForUser(
        user.id,
      );
      final recentResult = progress.recentQuizResults.isEmpty
          ? null
          : progress.recentQuizResults.first;
      final lastActivity =
          <int?>[
            progress.lastTrainedAtMillis,
            recentResult?.completedAtMillis,
            user.lastSignInAtMillis,
          ].whereType<int>().fold<int?>(null, (latest, value) {
            if (latest == null || value > latest) {
              return value;
            }
            return latest;
          });

      entries.add(
        LeaderboardEntry(
          userId: user.id,
          displayName: user.name.isEmpty ? user.email : user.name,
          email: user.email,
          totalQuestions: progress.totalQuizQuestions,
          correctAnswers: progress.totalCorrectAnswers,
          cocktailsStudied: progress.studiedCocktailIds.length,
          studyCompletion: cocktails.isEmpty
              ? 0
              : progress.studiedCocktailIds.length / cocktails.length,
          streakDays: _calculateStreak(progress.trainingDayKeys),
          weakAreasSummary: _weakAreaSummary(progress),
          recentActivityMillis: lastActivity,
        ),
      );
    }

    entries.sort((a, b) => _compareEntries(a, b, sortBy));
    return entries;
  }

  Future<List<AppUser>> _loadVenueStaff(String venueId) async {
    final users = await _sessionService.loadUsersForVenue(venueId);
    return users
        .where((user) => user.role == UserRole.staff)
        .toList(growable: false);
  }

  List<String> _weakCocktailNames(
    TrainingProgress progress,
    List<Cocktail> cocktails,
  ) {
    final cocktailMap = {
      for (final cocktail in cocktails) cocktail.id: cocktail.name,
    };
    final weak =
        progress.cocktails.values.where((item) => item.needsReview).toList()
          ..sort((a, b) => b.totalTopicMisses.compareTo(a.totalTopicMisses));

    return weak
        .take(5)
        .map((item) => cocktailMap[item.cocktailId] ?? item.cocktailId)
        .toList(growable: false);
  }

  String _weakAreaSummary(TrainingProgress progress) {
    if (progress.topicMissTotals.isEmpty) {
      return 'No weak areas recorded';
    }

    final topic = QuizTopic.values
        .map((item) => MapEntry(item, progress.topicMissTotals[item.key] ?? 0))
        .reduce((a, b) => a.value >= b.value ? a : b);
    if (topic.value <= 0) {
      return 'No weak areas recorded';
    }
    return topic.key.label;
  }

  int _calculateStreak(List<String> trainingDayKeys) {
    if (trainingDayKeys.isEmpty) {
      return 0;
    }

    final parsed =
        trainingDayKeys
            .map(DateTime.tryParse)
            .whereType<DateTime>()
            .map((date) => DateTime(date.year, date.month, date.day))
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));

    if (parsed.isEmpty) {
      return 0;
    }

    final today = DateTime.now();
    var cursor = DateTime(today.year, today.month, today.day);
    var streak = 0;

    for (final day in parsed) {
      if (day == cursor) {
        streak += 1;
        cursor = cursor.subtract(const Duration(days: 1));
      } else if (streak == 0 &&
          day == cursor.subtract(const Duration(days: 1))) {
        streak = 1;
        cursor = day.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }

    return streak;
  }

  int _compareEntries(
    LeaderboardEntry a,
    LeaderboardEntry b,
    LeaderboardSort sortBy,
  ) {
    switch (sortBy) {
      case LeaderboardSort.questionsAnswered:
        final compare = b.totalQuestions.compareTo(a.totalQuestions);
        if (compare != 0) {
          return compare;
        }
        break;
      case LeaderboardSort.studyCompletion:
        final compare = b.studyCompletion.compareTo(a.studyCompletion);
        if (compare != 0) {
          return compare;
        }
        break;
      case LeaderboardSort.recentActivity:
        final compare = (b.recentActivityMillis ?? 0).compareTo(
          a.recentActivityMillis ?? 0,
        );
        if (compare != 0) {
          return compare;
        }
        break;
      case LeaderboardSort.accuracy:
        final compare = b.accuracy.compareTo(a.accuracy);
        if (compare != 0) {
          return compare;
        }
        break;
    }

    final accuracyCompare = b.accuracy.compareTo(a.accuracy);
    if (accuracyCompare != 0) {
      return accuracyCompare;
    }

    final questionCompare = b.totalQuestions.compareTo(a.totalQuestions);
    if (questionCompare != 0) {
      return questionCompare;
    }

    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  }
}
