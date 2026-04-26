class ManagerOverview {
  const ManagerOverview({
    required this.totalStaff,
    required this.activeStaff,
    required this.totalQuizAttempts,
    required this.averageScore,
    required this.weakCocktailAreas,
  });

  final int totalStaff;
  final int activeStaff;
  final int totalQuizAttempts;
  final double averageScore;
  final List<String> weakCocktailAreas;
}
