import 'package:cocktail_training/models/cocktail.dart';
import 'package:cocktail_training/models/training_progress.dart';

class QuizQuestion {
  const QuizQuestion({
    required this.cocktailId,
    required this.cocktailName,
    required this.topic,
    required this.prompt,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    required this.cocktail,
  });

  final String cocktailId;
  final String cocktailName;
  final QuizTopic topic;
  final String prompt;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final Cocktail cocktail;

  String get correctAnswer => options[correctIndex];
}

class QuizSessionSummary {
  const QuizSessionSummary({
    required this.totalQuestions,
    required this.correctAnswers,
    required this.weakCocktailIds,
    required this.weakTopics,
  });

  final int totalQuestions;
  final int correctAnswers;
  final List<String> weakCocktailIds;
  final List<QuizTopic> weakTopics;

  double get accuracy => totalQuestions == 0 ? 0 : correctAnswers / totalQuestions;
}
