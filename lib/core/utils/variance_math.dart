import '../../domain/models/models.dart';

class VarianceMath {
  static QuizAttempt buildAttempt({
    required String attemptId,
    required String sessionId,
    required String? weekId,
    required String bartenderName,
    required List<QuestionResponse> responses,
    required Map<String, Ingredient> ingredientsByName,
  }) {
    final overpourBuckets = <String, double>{};
    final underpourBuckets = <String, double>{};
    final incorrectCocktails = <String>{};

    var correctAnswers = 0;
    for (final response in responses) {
      if (response.isCorrect) {
        correctAnswers += 1;
      } else {
        incorrectCocktails.add(response.question.cocktailName);
      }

      final deltaMl = response.deltaMl;
      if (deltaMl == null || response.quantitySold == 0) {
        continue;
      }

      // Potential variance is projected from the difference between the stored
      // spec and the submitted answer, multiplied by the recorded sales count.
      final totalMl = deltaMl.abs() * response.quantitySold;
      if (deltaMl > 0) {
        overpourBuckets.update(
          response.question.ingredientName ?? 'Unknown ingredient',
          (value) => value + totalMl,
          ifAbsent: () => totalMl,
        );
      } else if (deltaMl < 0) {
        underpourBuckets.update(
          response.question.ingredientName ?? 'Unknown ingredient',
          (value) => value + totalMl,
          ifAbsent: () => totalMl,
        );
      }
    }

    final scorePercent = responses.isEmpty
        ? 0
        : ((correctAnswers / responses.length) * 100).round();

    return QuizAttempt(
      id: attemptId,
      sessionId: sessionId,
      weekId: weekId,
      bartenderName: bartenderName,
      submittedAt: DateTime.now(),
      scorePercent: scorePercent,
      responses: responses,
      overpourLines: _toVarianceLines(
        overpourBuckets,
        ingredientsByName,
        VarianceDirection.overpour,
      ),
      underpourLines: _toVarianceLines(
        underpourBuckets,
        ingredientsByName,
        VarianceDirection.underpour,
      ),
      coachingAreas: incorrectCocktails.take(3).toList(),
      encouragement: _buildEncouragement(scorePercent),
    );
  }

  static List<VarianceLine> _toVarianceLines(
    Map<String, double> buckets,
    Map<String, Ingredient> ingredientsByName,
    VarianceDirection direction,
  ) {
    return buckets.entries
        .map((entry) {
          final ingredient = ingredientsByName[entry.key.toLowerCase()];
          final approxValue = ingredient == null
              ? 0.0
              : ingredient.costPerMl * entry.value;
          return VarianceLine(
            ingredientName: ingredient?.name ?? entry.key,
            totalMl: entry.value,
            approximateValue: approxValue,
            direction: direction,
          );
        })
        .toList()
      ..sort((a, b) => b.totalMl.compareTo(a.totalMl));
  }

  static String _buildEncouragement(int scorePercent) {
    if (scorePercent >= 85) {
      return 'Nice work. Recipe confidence looks strong, and only a light refresher seems worthwhile.';
    }
    if (scorePercent >= 65) {
      return 'Solid progress. A little more practice on the highlighted specs could tighten consistency quickly.';
    }
    return 'This session surfaced a few worthwhile training focus areas. Keep practising these specs and confidence should build fast.';
  }
}
