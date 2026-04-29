class ManagerOverview {
  const ManagerOverview({
    required this.totalStaff,
    required this.activeStaff,
    required this.totalQuizAttempts,
    required this.averageScore,
    required this.weakCocktailAreas,
    required this.latestExamPasses,
    required this.priorityCocktailIds,
  });

  final int totalStaff;
  final int activeStaff;
  final int totalQuizAttempts;
  final double averageScore;
  final List<String> weakCocktailAreas;
  final int latestExamPasses;
  final List<String> priorityCocktailIds;
}
