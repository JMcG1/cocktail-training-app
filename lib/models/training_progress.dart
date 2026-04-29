import 'dart:convert';

enum QuizTopic { ingredients, method, garnish, glassware, buildStyle }

extension QuizTopicX on QuizTopic {
  String get key => name;

  String get label {
    switch (this) {
      case QuizTopic.ingredients:
        return 'Ingredients';
      case QuizTopic.method:
        return 'Method';
      case QuizTopic.garnish:
        return 'Garnish';
      case QuizTopic.glassware:
        return 'Glassware';
      case QuizTopic.buildStyle:
        return 'Build style';
    }
  }

  static QuizTopic fromKey(String value) {
    return QuizTopic.values.firstWhere(
      (topic) => topic.key == value,
      orElse: () => QuizTopic.ingredients,
    );
  }
}

class QuizResult {
  const QuizResult({
    required this.completedAtMillis,
    required this.totalQuestions,
    required this.correctAnswers,
    required this.weakCocktailIds,
    required this.weakTopics,
  });

  factory QuizResult.fromJson(Map<String, dynamic> json) {
    return QuizResult(
      completedAtMillis: json['completedAtMillis'] as int? ?? 0,
      totalQuestions: json['totalQuestions'] as int? ?? 0,
      correctAnswers: json['correctAnswers'] as int? ?? 0,
      weakCocktailIds: List<String>.from(
        json['weakCocktailIds'] as List<dynamic>? ?? const [],
      ),
      weakTopics: List<String>.from(
        json['weakTopics'] as List<dynamic>? ?? const [],
      ),
    );
  }

  final int completedAtMillis;
  final int totalQuestions;
  final int correctAnswers;
  final List<String> weakCocktailIds;
  final List<String> weakTopics;

  double get accuracy =>
      totalQuestions == 0 ? 0 : correctAnswers / totalQuestions;

  Map<String, dynamic> toJson() {
    return {
      'completedAtMillis': completedAtMillis,
      'totalQuestions': totalQuestions,
      'correctAnswers': correctAnswers,
      'weakCocktailIds': weakCocktailIds,
      'weakTopics': weakTopics,
    };
  }
}

class CocktailProgress {
  const CocktailProgress({
    required this.cocktailId,
    required this.studyAttempts,
    required this.knewCount,
    required this.needPracticeCount,
    required this.quizCorrect,
    required this.quizIncorrect,
    required this.topicMisses,
    required this.lastStudiedAtMillis,
    required this.lastQuizAtMillis,
  });

  factory CocktailProgress.empty(String cocktailId) {
    return CocktailProgress(
      cocktailId: cocktailId,
      studyAttempts: 0,
      knewCount: 0,
      needPracticeCount: 0,
      quizCorrect: 0,
      quizIncorrect: 0,
      topicMisses: const {},
      lastStudiedAtMillis: null,
      lastQuizAtMillis: null,
    );
  }

  factory CocktailProgress.fromJson(Map<String, dynamic> json) {
    return CocktailProgress(
      cocktailId: json['cocktailId'] as String? ?? '',
      studyAttempts: json['studyAttempts'] as int? ?? 0,
      knewCount: json['knewCount'] as int? ?? 0,
      needPracticeCount: json['needPracticeCount'] as int? ?? 0,
      quizCorrect: json['quizCorrect'] as int? ?? 0,
      quizIncorrect: json['quizIncorrect'] as int? ?? 0,
      topicMisses: Map<String, int>.from(
        json['topicMisses'] as Map? ?? const {},
      ),
      lastStudiedAtMillis: json['lastStudiedAtMillis'] as int?,
      lastQuizAtMillis: json['lastQuizAtMillis'] as int?,
    );
  }

  final String cocktailId;
  final int studyAttempts;
  final int knewCount;
  final int needPracticeCount;
  final int quizCorrect;
  final int quizIncorrect;
  final Map<String, int> topicMisses;
  final int? lastStudiedAtMillis;
  final int? lastQuizAtMillis;

  bool get hasStudied => studyAttempts > 0;
  bool get hasQuizHistory => quizCorrect + quizIncorrect > 0;
  int get totalQuizAttempts => quizCorrect + quizIncorrect;
  int get confidenceScore =>
      knewCount + quizCorrect - needPracticeCount - (quizIncorrect * 2);
  int get totalTopicMisses =>
      topicMisses.values.fold<int>(0, (sum, value) => sum + value);

  bool get needsReview => confidenceScore < 0 || totalTopicMisses > 0;

  CocktailProgress copyWith({
    int? studyAttempts,
    int? knewCount,
    int? needPracticeCount,
    int? quizCorrect,
    int? quizIncorrect,
    Map<String, int>? topicMisses,
    int? lastStudiedAtMillis,
    int? lastQuizAtMillis,
  }) {
    return CocktailProgress(
      cocktailId: cocktailId,
      studyAttempts: studyAttempts ?? this.studyAttempts,
      knewCount: knewCount ?? this.knewCount,
      needPracticeCount: needPracticeCount ?? this.needPracticeCount,
      quizCorrect: quizCorrect ?? this.quizCorrect,
      quizIncorrect: quizIncorrect ?? this.quizIncorrect,
      topicMisses: topicMisses ?? this.topicMisses,
      lastStudiedAtMillis: lastStudiedAtMillis ?? this.lastStudiedAtMillis,
      lastQuizAtMillis: lastQuizAtMillis ?? this.lastQuizAtMillis,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cocktailId': cocktailId,
      'studyAttempts': studyAttempts,
      'knewCount': knewCount,
      'needPracticeCount': needPracticeCount,
      'quizCorrect': quizCorrect,
      'quizIncorrect': quizIncorrect,
      'topicMisses': topicMisses,
      'lastStudiedAtMillis': lastStudiedAtMillis,
      'lastQuizAtMillis': lastQuizAtMillis,
    };
  }
}

class TrainingProgress {
  const TrainingProgress({
    required this.cocktails,
    required this.totalStudyReviews,
    required this.totalStudySessions,
    required this.totalQuizQuestions,
    required this.totalCorrectAnswers,
    required this.totalQuizSessions,
    required this.totalSessions,
    required this.topicMissTotals,
    required this.recentQuizResults,
    required this.trainingDayKeys,
    required this.lastTrainedAtMillis,
  });

  factory TrainingProgress.empty() {
    return const TrainingProgress(
      cocktails: {},
      totalStudyReviews: 0,
      totalStudySessions: 0,
      totalQuizQuestions: 0,
      totalCorrectAnswers: 0,
      totalQuizSessions: 0,
      totalSessions: 0,
      topicMissTotals: {},
      recentQuizResults: [],
      trainingDayKeys: [],
      lastTrainedAtMillis: null,
    );
  }

  factory TrainingProgress.fromJson(Map<String, dynamic> json) {
    final cocktailsJson = Map<String, dynamic>.from(
      json['cocktails'] as Map? ?? const {},
    );
    return TrainingProgress(
      cocktails: cocktailsJson.map(
        (key, value) => MapEntry(
          key,
          CocktailProgress.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      ),
      totalStudyReviews: json['totalStudyReviews'] as int? ?? 0,
      totalStudySessions: json['totalStudySessions'] as int? ?? 0,
      totalQuizQuestions: json['totalQuizQuestions'] as int? ?? 0,
      totalCorrectAnswers: json['totalCorrectAnswers'] as int? ?? 0,
      totalQuizSessions: json['totalQuizSessions'] as int? ?? 0,
      totalSessions: json['totalSessions'] as int? ?? 0,
      topicMissTotals: Map<String, int>.from(
        json['topicMissTotals'] as Map? ?? const {},
      ),
      recentQuizResults:
          (json['recentQuizResults'] as List<dynamic>? ?? const [])
              .map(
                (item) =>
                    QuizResult.fromJson(Map<String, dynamic>.from(item as Map)),
              )
              .toList(growable: false),
      trainingDayKeys: List<String>.from(
        json['trainingDayKeys'] as List<dynamic>? ?? const [],
      ),
      lastTrainedAtMillis: json['lastTrainedAtMillis'] as int?,
    );
  }

  final Map<String, CocktailProgress> cocktails;
  final int totalStudyReviews;
  final int totalStudySessions;
  final int totalQuizQuestions;
  final int totalCorrectAnswers;
  final int totalQuizSessions;
  final int totalSessions;
  final Map<String, int> topicMissTotals;
  final List<QuizResult> recentQuizResults;
  final List<String> trainingDayKeys;
  final int? lastTrainedAtMillis;

  double get accuracy =>
      totalQuizQuestions == 0 ? 0 : totalCorrectAnswers / totalQuizQuestions;

  Set<String> get studiedCocktailIds => cocktails.entries
      .where((entry) => entry.value.hasStudied || entry.value.hasQuizHistory)
      .map((entry) => entry.key)
      .toSet();

  TrainingProgress copyWith({
    Map<String, CocktailProgress>? cocktails,
    int? totalStudyReviews,
    int? totalStudySessions,
    int? totalQuizQuestions,
    int? totalCorrectAnswers,
    int? totalQuizSessions,
    int? totalSessions,
    Map<String, int>? topicMissTotals,
    List<QuizResult>? recentQuizResults,
    List<String>? trainingDayKeys,
    int? lastTrainedAtMillis,
  }) {
    return TrainingProgress(
      cocktails: cocktails ?? this.cocktails,
      totalStudyReviews: totalStudyReviews ?? this.totalStudyReviews,
      totalStudySessions: totalStudySessions ?? this.totalStudySessions,
      totalQuizQuestions: totalQuizQuestions ?? this.totalQuizQuestions,
      totalCorrectAnswers: totalCorrectAnswers ?? this.totalCorrectAnswers,
      totalQuizSessions: totalQuizSessions ?? this.totalQuizSessions,
      totalSessions: totalSessions ?? this.totalSessions,
      topicMissTotals: topicMissTotals ?? this.topicMissTotals,
      recentQuizResults: recentQuizResults ?? this.recentQuizResults,
      trainingDayKeys: trainingDayKeys ?? this.trainingDayKeys,
      lastTrainedAtMillis: lastTrainedAtMillis ?? this.lastTrainedAtMillis,
    );
  }

  String toStorageString() => jsonEncode(toJson());

  Map<String, dynamic> toJson() {
    return {
      'cocktails': cocktails.map((key, value) => MapEntry(key, value.toJson())),
      'totalStudyReviews': totalStudyReviews,
      'totalStudySessions': totalStudySessions,
      'totalQuizQuestions': totalQuizQuestions,
      'totalCorrectAnswers': totalCorrectAnswers,
      'totalQuizSessions': totalQuizSessions,
      'totalSessions': totalSessions,
      'topicMissTotals': topicMissTotals,
      'recentQuizResults': recentQuizResults
          .map((item) => item.toJson())
          .toList(),
      'trainingDayKeys': trainingDayKeys,
      'lastTrainedAtMillis': lastTrainedAtMillis,
    };
  }
}
