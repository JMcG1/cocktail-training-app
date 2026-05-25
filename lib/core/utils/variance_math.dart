import '../../domain/models/models.dart';
import 'batch_recipe_graph.dart';

class VarianceMath {
  static QuizAttempt buildAttempt({
    required String attemptId,
    required String sessionId,
    required String? weekId,
    String? userId,
    required String bartenderName,
    required List<QuestionResponse> responses,
    required Map<String, Ingredient> ingredientsByName,
    required List<BatchRecipe> batches,
  }) {
    final overpourBuckets = <String, double>{};
    final underpourBuckets = <String, double>{};
    final batchOverpourBuckets = <String, double>{};
    final batchUnderpourBuckets = <String, double>{};
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
      final targetBuckets = deltaMl > 0 ? overpourBuckets : underpourBuckets;
      if (response.question.ingredientReferenceType ==
          IngredientReferenceType.batch) {
        final batchName = response.question.ingredientName ?? 'Unknown batch';
        final batchTargetBuckets = deltaMl > 0
            ? batchOverpourBuckets
            : batchUnderpourBuckets;
        batchTargetBuckets.update(
          batchName,
          (value) => value + totalMl,
          ifAbsent: () => totalMl,
        );
        final linkedIngredient = RecipeIngredient(
          ingredientName: batchName,
          measureMl: response.question.correctMeasureMl,
          referenceType: IngredientReferenceType.batch,
          linkedBatchId: response.question.linkedBatchId,
        );
        final decomposition = BatchGraphResolver.decomposeCocktailIngredient(
          linkedIngredient,
          batches: batches,
          ingredientsByName: ingredientsByName,
        );
        for (final component in decomposition.components) {
          final ratio = (response.question.correctMeasureMl ?? 0) <= 0
              ? 0
              : component.totalMl / (response.question.correctMeasureMl ?? 1);
          final projectedMl = totalMl * ratio;
          targetBuckets.update(
            component.ingredientName,
            (value) => value + projectedMl,
            ifAbsent: () => projectedMl,
          );
        }
      } else if (deltaMl != 0) {
        targetBuckets.update(
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
      userId: userId,
      bartenderName: bartenderName,
      submittedAt: DateTime.now(),
      scorePercent: scorePercent,
      responses: responses,
      overpourLines: _toVarianceLines(
        overpourBuckets,
        ingredientsByName,
        VarianceDirection.overpour,
        batches: batches,
      ),
      underpourLines: _toVarianceLines(
        underpourBuckets,
        ingredientsByName,
        VarianceDirection.underpour,
        batches: batches,
      ),
      batchOverpourLines: _toVarianceLines(
        batchOverpourBuckets,
        ingredientsByName,
        VarianceDirection.overpour,
        batches: batches,
        sourceType: VarianceSourceType.batch,
      ),
      batchUnderpourLines: _toVarianceLines(
        batchUnderpourBuckets,
        ingredientsByName,
        VarianceDirection.underpour,
        batches: batches,
        sourceType: VarianceSourceType.batch,
      ),
      coachingAreas: incorrectCocktails.take(3).toList(),
      encouragement: _buildEncouragement(scorePercent),
    );
  }

  static List<VarianceLine> _toVarianceLines(
    Map<String, double> buckets,
    Map<String, Ingredient> ingredientsByName,
    VarianceDirection direction, {
    required List<BatchRecipe> batches,
    VarianceSourceType sourceType = VarianceSourceType.ingredient,
  }) {
    return buckets.entries.map((entry) {
      final normalizedKey = BatchGraphResolver.normalizeKey(entry.key);
      final ingredient = ingredientsByName[normalizedKey];
      final approxValue = sourceType == VarianceSourceType.batch
          ? _batchCostPerMl(entry.key, batches, ingredientsByName) * entry.value
          : (ingredient == null ? 0.0 : ingredient.costPerMl * entry.value);
      return VarianceLine(
        ingredientName: ingredient?.name ?? entry.key,
        totalMl: entry.value,
        approximateValue: approxValue,
        direction: direction,
        sourceType: sourceType,
      );
    }).toList()..sort((a, b) => b.totalMl.compareTo(a.totalMl));
  }

  static double _batchCostPerMl(
    String batchName,
    List<BatchRecipe> batches,
    Map<String, Ingredient> ingredientsByName,
  ) {
    final batch = batches.cast<BatchRecipe?>().firstWhere(
      (item) =>
          item != null &&
          (BatchGraphResolver.normalizeKey(item.name) ==
                  BatchGraphResolver.normalizeKey(batchName) ||
              BatchGraphResolver.normalizeKey(item.id) ==
                  BatchGraphResolver.normalizeKey(batchName)),
      orElse: () => null,
    );
    if (batch == null) {
      return 0;
    }
    return BatchGraphResolver.summarizeBatchCost(
      batch: batch,
      ingredientsByName: ingredientsByName,
      batches: batches,
    ).costPerMl;
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
