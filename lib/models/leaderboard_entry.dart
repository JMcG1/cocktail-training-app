class LeaderboardEntry {
  const LeaderboardEntry({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.totalQuestions,
    required this.correctAnswers,
    required this.cocktailsStudied,
    required this.studyCompletion,
    required this.streakDays,
    required this.weakAreasSummary,
    required this.recentActivityMillis,
  });

  final String userId;
  final String displayName;
  final String email;
  final int totalQuestions;
  final int correctAnswers;
  final int cocktailsStudied;
  final double studyCompletion;
  final int streakDays;
  final String weakAreasSummary;
  final int? recentActivityMillis;

  double get accuracy =>
      totalQuestions == 0 ? 0 : correctAnswers / totalQuestions;
  int get accuracyPercent => (accuracy * 100).round();
}

enum LeaderboardSort {
  accuracy,
  questionsAnswered,
  studyCompletion,
  recentActivity,
}

extension LeaderboardSortX on LeaderboardSort {
  String get label {
    switch (this) {
      case LeaderboardSort.accuracy:
        return 'Score';
      case LeaderboardSort.questionsAnswered:
        return 'Checks completed';
      case LeaderboardSort.studyCompletion:
        return 'Service-ready';
      case LeaderboardSort.recentActivity:
        return 'Last trained';
    }
  }
}
