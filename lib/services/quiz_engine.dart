import 'dart:math';

import 'package:cocktail_training/models/cocktail.dart';
import 'package:cocktail_training/models/quiz_question.dart';
import 'package:cocktail_training/models/training_progress.dart';

class QuizEngine {
  QuizEngine({
    Random? random,
  }) : _random = random ?? Random();

  final Random _random;

  List<QuizQuestion> buildSession({
    required List<Cocktail> cocktails,
    required TrainingProgress progress,
    int questionCount = 12,
    Set<String>? focusCocktailIds,
  }) {
    final allQuestions = _buildQuestionPool(
      cocktails: cocktails,
      progress: progress,
      focusCocktailIds: focusCocktailIds,
    );

    if (allQuestions.isEmpty) {
      return const [];
    }

    allQuestions.shuffle(_random);

    final selected = <QuizQuestion>[];
    final seenPrompts = <String>{};

    for (final question in allQuestions) {
      final promptKey = '${question.topic.key}:${question.prompt.toLowerCase()}';
      if (seenPrompts.add(promptKey)) {
        selected.add(question);
      }
      if (selected.length >= questionCount) {
        break;
      }
    }

    return selected;
  }

  List<QuizQuestion> _buildQuestionPool({
    required List<Cocktail> cocktails,
    required TrainingProgress progress,
    Set<String>? focusCocktailIds,
  }) {
    final filteredCocktails = focusCocktailIds == null || focusCocktailIds.isEmpty
        ? cocktails
        : cocktails.where((cocktail) => focusCocktailIds.contains(cocktail.id)).toList();

    final sourceCocktails = filteredCocktails.isEmpty ? cocktails : filteredCocktails;
    final weightedCocktails = [...sourceCocktails]
      ..sort((a, b) => _priorityForCocktail(progress, b.id).compareTo(_priorityForCocktail(progress, a.id)));

    final questionPool = <QuizQuestion>[];
    for (final cocktail in weightedCocktails) {
      questionPool.addAll(_buildCocktailQuestions(cocktail, cocktails));
    }

    questionPool.sort((a, b) {
      final priorityCompare = _questionPriority(progress, b).compareTo(_questionPriority(progress, a));
      if (priorityCompare != 0) {
        return priorityCompare;
      }
      return a.cocktailName.compareTo(b.cocktailName);
    });

    return questionPool;
  }

  List<QuizQuestion> _buildCocktailQuestions(Cocktail cocktail, List<Cocktail> allCocktails) {
    final questions = <QuizQuestion>[];
    final uniqueIngredients = _ingredientNames(cocktail);
    final allIngredientNames = allCocktails.expand(_ingredientNames).toSet().toList(growable: false);
    final allMethodSteps = allCocktails
        .expand((item) => item.methodSteps)
        .map(_cleanText)
        .where((step) => step.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (_cleanText(cocktail.glassware).isNotEmpty) {
      final options = _multipleChoiceOptions(
        correct: cocktail.glassware,
        pool: allCocktails.map((item) => item.glassware),
        fallback: const ['Highball', 'Rocks', 'Coupe', 'Shot glass'],
      );

      if (options.length >= 4) {
        questions.add(
          QuizQuestion(
            cocktailId: cocktail.id,
            cocktailName: cocktail.name,
            topic: QuizTopic.glassware,
            prompt: 'What glassware does ${cocktail.name} use?',
            options: options,
            correctIndex: options.indexOf(_cleanText(cocktail.glassware)),
            explanation: '${cocktail.name} is served in ${_cleanText(cocktail.glassware)}.',
            cocktail: cocktail,
          ),
        );
      }
    }

    if (_cleanText(cocktail.garnish).isNotEmpty) {
      final options = _multipleChoiceOptions(
        correct: cocktail.garnish,
        pool: allCocktails.map((item) => item.garnish),
        fallback: const ['Lime wedge', 'Orange zest', 'Mint bouquet', 'No garnish'],
      );

      if (options.length >= 4) {
        questions.add(
          QuizQuestion(
            cocktailId: cocktail.id,
            cocktailName: cocktail.name,
            topic: QuizTopic.garnish,
            prompt: 'What garnish does ${cocktail.name} use?',
            options: options,
            correctIndex: options.indexOf(_cleanText(cocktail.garnish)),
            explanation: '${cocktail.name} is finished with ${_cleanText(cocktail.garnish)}.',
            cocktail: cocktail,
          ),
        );
      }
    }

    if (uniqueIngredients.isNotEmpty) {
      final ingredient = uniqueIngredients[_random.nextInt(uniqueIngredients.length)];
      final options = _multipleChoiceOptions(
        correct: ingredient,
        pool: allIngredientNames,
        fallback: const ['Fresh lime juice', 'Sugar syrup', 'Soda water', 'Bitters'],
      );

      if (options.length >= 4) {
        questions.add(
          QuizQuestion(
            cocktailId: cocktail.id,
            cocktailName: cocktail.name,
            topic: QuizTopic.ingredients,
            prompt: 'Which ingredient is in ${cocktail.name}?',
            options: options,
            correctIndex: options.indexOf(_cleanText(ingredient)),
            explanation: '${cocktail.name} includes ${_cleanText(ingredient)}.',
            cocktail: cocktail,
          ),
        );
      }

      final ingredientUsers = allCocktails.where((item) => _ingredientNames(item).contains(ingredient)).toList();
      if (ingredientUsers.isNotEmpty) {
        final options = _multipleChoiceOptions(
          correct: cocktail.name,
          pool: ingredientUsers.map((item) => item.name),
          fallback: allCocktails.map((item) => item.name),
        );

        if (options.length >= 4) {
          questions.add(
            QuizQuestion(
              cocktailId: cocktail.id,
              cocktailName: cocktail.name,
              topic: QuizTopic.ingredients,
              prompt: 'Which cocktail uses ${_cleanText(ingredient)}?',
              options: options,
              correctIndex: options.indexOf(cocktail.name),
              explanation: '${cocktail.name} uses ${_cleanText(ingredient)} in its spec.',
              cocktail: cocktail,
            ),
          );
        }
      }
    }

    final validMethodSteps = cocktail.methodSteps.map(_cleanText).where((step) => step.isNotEmpty).toList();
    if (validMethodSteps.isNotEmpty) {
      final step = validMethodSteps[_random.nextInt(validMethodSteps.length)];
      final options = _multipleChoiceOptions(
        correct: step,
        pool: allMethodSteps,
        fallback: const [
          'Shake hard with cubed ice.',
          'Top with soda.',
          'Fine strain into the glass.',
          'Garnish before service.',
        ],
      );

      if (options.length >= 4) {
        questions.add(
          QuizQuestion(
            cocktailId: cocktail.id,
            cocktailName: cocktail.name,
            topic: QuizTopic.method,
            prompt: 'Which method step belongs to ${cocktail.name}?',
            options: options,
            correctIndex: options.indexOf(step),
            explanation: 'One of the service steps for ${cocktail.name} is: $step',
            cocktail: cocktail,
          ),
        );
      }
    }

    if (_cleanText(cocktail.buildStyleLabel).isNotEmpty) {
      final options = _multipleChoiceOptions(
        correct: cocktail.buildStyleLabel,
        pool: allCocktails.map((item) => item.buildStyleLabel),
        fallback: const ['Shaken', 'Built', 'Stirred', 'Layered'],
      );

      if (options.length >= 4) {
        questions.add(
          QuizQuestion(
            cocktailId: cocktail.id,
            cocktailName: cocktail.name,
            topic: QuizTopic.buildStyle,
            prompt: 'Which build style is ${cocktail.name}?',
            options: options,
            correctIndex: options.indexOf(_cleanText(cocktail.buildStyleLabel)),
            explanation: '${cocktail.name} is prepared as a ${_cleanText(cocktail.buildStyleLabel)} serve.',
            cocktail: cocktail,
          ),
        );
      }
    }

    return questions;
  }

  int _priorityForCocktail(TrainingProgress progress, String cocktailId) {
    final cocktailProgress = progress.cocktails[cocktailId];
    if (cocktailProgress == null) {
      return 3;
    }

    var score = 0;
    score += cocktailProgress.needPracticeCount * 3;
    score += cocktailProgress.quizIncorrect * 4;
    score += cocktailProgress.totalTopicMisses * 2;
    score -= cocktailProgress.knewCount;
    score -= cocktailProgress.quizCorrect;
    if (!cocktailProgress.hasStudied) {
      score += 2;
    }
    return score;
  }

  int _questionPriority(TrainingProgress progress, QuizQuestion question) {
    final cocktailProgress = progress.cocktails[question.cocktailId];
    final cocktailPriority = _priorityForCocktail(progress, question.cocktailId) * 10;
    final topicMisses = cocktailProgress?.topicMisses[question.topic.key] ?? 0;
    final globalTopicMisses = progress.topicMissTotals[question.topic.key] ?? 0;
    return cocktailPriority + topicMisses * 4 + globalTopicMisses;
  }

  List<String> _ingredientNames(Cocktail cocktail) {
    return cocktail.ingredients
        .map((ingredient) => _cleanText(ingredient.name))
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  List<String> _multipleChoiceOptions({
    required String correct,
    required Iterable<String> pool,
    Iterable<String> fallback = const [],
  }) {
    final correctValue = _cleanText(correct);
    if (correctValue.isEmpty) {
      return const [];
    }

    final options = <String>[correctValue];
    final seen = <String>{correctValue.toLowerCase()};
    final candidates = <String>[
      ...pool.map(_cleanText),
      ...fallback.map(_cleanText),
    ]..shuffle(_random);

    for (final value in candidates) {
      if (value.isEmpty) {
        continue;
      }

      final normalized = value.toLowerCase();
      if (seen.contains(normalized)) {
        continue;
      }

      options.add(value);
      seen.add(normalized);

      if (options.length == 4) {
        break;
      }
    }

    if (options.length < 4) {
      return const [];
    }

    options.shuffle(_random);
    return options;
  }

  String _cleanText(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }
}
