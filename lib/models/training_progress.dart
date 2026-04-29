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

enum TrainingAchievement {
  perfectRound,
  serviceReady,
  specSharp,
  speedRail,
  classicsMaster,
  firstPassCheckPassed,
}

extension TrainingAchievementX on TrainingAchievement {
  String get key => name;

  String get label {
    switch (this) {
      case TrainingAchievement.perfectRound:
        return 'Perfect Round';
      case TrainingAchievement.serviceReady:
        return 'Service Ready';
      case TrainingAchievement.specSharp:
        return 'Spec Sharp';
      case TrainingAchievement.speedRail:
        return 'Speed Rail';
      case TrainingAchievement.classicsMaster:
        return 'Classics Master';
      case TrainingAchievement.firstPassCheckPassed:
        return 'First Pass Check Passed';
    }
  }

  String get description {
    switch (this) {
      case TrainingAchievement.perfectRound:
        return 'Finished a full check without a miss.';
      case TrainingAchievement.serviceReady:
        return 'Passed a service readiness check.';
      case TrainingAchievement.specSharp:
        return 'Built a strong run of accurate spec work.';
      case TrainingAchievement.speedRail:
        return 'Stacked quick wins in service mode.';
      case TrainingAchievement.classicsMaster:
        return 'Mastered the venue classics.';
      case TrainingAchievement.firstPassCheckPassed:
        return 'Passed your first formal pass check.';
    }
  }

  static TrainingAchievement? fromKey(String value) {
    for (final achievement in TrainingAchievement.values) {
      if (achievement.key == value) {
        return achievement;
      }
    }
    return null;
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

  bool get isPerfect => totalQuestions > 0 && correctAnswers == totalQuestions;

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

class ExamResult {
  const ExamResult({
    required this.id,
    required this.uid,
    required this.displayName,
    required this.score,
    required this.total,
    required this.passMark,
    required this.createdAtMillis,
  });

  factory ExamResult.fromJson(Map<String, dynamic> json) {
    return ExamResult(
      id: json['id'] as String? ?? '',
      uid: json['uid'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      score: json['score'] as int? ?? 0,
      total: json['total'] as int? ?? 0,
      passMark: json['passMark'] as int? ?? 80,
      createdAtMillis: json['createdAtMillis'] as int? ?? 0,
    );
  }

  final String id;
  final String uid;
  final String displayName;
  final int score;
  final int total;
  final int passMark;
  final int createdAtMillis;

  double get percentage => total == 0 ? 0 : (score / total) * 100;
  bool get passed => percentage >= passMark;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uid': uid,
      'displayName': displayName,
      'score': score,
      'total': total,
      'passMark': passMark,
      'percentage': percentage.round(),
      'passed': passed,
      'createdAtMillis': createdAtMillis,
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
    required this.attempts,
    required this.correctCount,
    required this.wrongCount,
    required this.masteryScore,
    required this.averageResponseMs,
    required this.lastAttemptedAtMillis,
    required this.lastWrongAtMillis,
    required this.blindRecallAttempts,
    required this.blindRecallCorrect,
    required this.serviceAttempts,
    required this.serviceCorrect,
    required this.examAttempts,
    required this.examCorrect,
    required this.speedBonusCount,
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
      attempts: 0,
      correctCount: 0,
      wrongCount: 0,
      masteryScore: 0,
      averageResponseMs: null,
      lastAttemptedAtMillis: null,
      lastWrongAtMillis: null,
      blindRecallAttempts: 0,
      blindRecallCorrect: 0,
      serviceAttempts: 0,
      serviceCorrect: 0,
      examAttempts: 0,
      examCorrect: 0,
      speedBonusCount: 0,
    );
  }

  factory CocktailProgress.fromJson(Map<String, dynamic> json) {
    final studyAttempts = json['studyAttempts'] as int? ?? 0;
    final knewCount = json['knewCount'] as int? ?? 0;
    final needPracticeCount = json['needPracticeCount'] as int? ?? 0;
    final quizCorrect = json['quizCorrect'] as int? ?? 0;
    final quizIncorrect = json['quizIncorrect'] as int? ?? 0;
    final blindRecallAttempts = json['blindRecallAttempts'] as int? ?? 0;
    final blindRecallCorrect = json['blindRecallCorrect'] as int? ?? 0;
    final serviceAttempts = json['serviceAttempts'] as int? ?? 0;
    final serviceCorrect = json['serviceCorrect'] as int? ?? 0;
    final examAttempts = json['examAttempts'] as int? ?? 0;
    final examCorrect = json['examCorrect'] as int? ?? 0;
    final attempts =
        json['attempts'] as int? ??
        studyAttempts +
            quizCorrect +
            quizIncorrect +
            blindRecallAttempts +
            serviceAttempts +
            examAttempts;
    final correctCount =
        json['correctCount'] as int? ??
        knewCount +
            quizCorrect +
            blindRecallCorrect +
            serviceCorrect +
            examCorrect;
    final wrongCount =
        json['wrongCount'] as int? ??
        needPracticeCount +
            quizIncorrect +
            (blindRecallAttempts - blindRecallCorrect).clamp(
              0,
              blindRecallAttempts,
            ) +
            (serviceAttempts - serviceCorrect).clamp(0, serviceAttempts) +
            (examAttempts - examCorrect).clamp(0, examAttempts);
    final masteryScore =
        (json['masteryScore'] as num?)?.toDouble() ??
        _deriveMasteryScore(
          attempts: attempts,
          correctCount: correctCount,
          wrongCount: wrongCount,
          topicMisses: Map<String, int>.from(
            json['topicMisses'] as Map? ?? const {},
          ),
          speedBonusCount: json['speedBonusCount'] as int? ?? 0,
        );

    return CocktailProgress(
      cocktailId: json['cocktailId'] as String? ?? '',
      studyAttempts: studyAttempts,
      knewCount: knewCount,
      needPracticeCount: needPracticeCount,
      quizCorrect: quizCorrect,
      quizIncorrect: quizIncorrect,
      topicMisses: Map<String, int>.from(
        json['topicMisses'] as Map? ?? const {},
      ),
      lastStudiedAtMillis: json['lastStudiedAtMillis'] as int?,
      lastQuizAtMillis: json['lastQuizAtMillis'] as int?,
      attempts: attempts,
      correctCount: correctCount,
      wrongCount: wrongCount,
      masteryScore: masteryScore,
      averageResponseMs: json['averageResponseMs'] as int?,
      lastAttemptedAtMillis:
          json['lastAttemptedAtMillis'] as int? ??
          json['lastQuizAtMillis'] as int? ??
          json['lastStudiedAtMillis'] as int?,
      lastWrongAtMillis: json['lastWrongAtMillis'] as int?,
      blindRecallAttempts: blindRecallAttempts,
      blindRecallCorrect: blindRecallCorrect,
      serviceAttempts: serviceAttempts,
      serviceCorrect: serviceCorrect,
      examAttempts: examAttempts,
      examCorrect: examCorrect,
      speedBonusCount: json['speedBonusCount'] as int? ?? 0,
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
  final int attempts;
  final int correctCount;
  final int wrongCount;
  final double masteryScore;
  final int? averageResponseMs;
  final int? lastAttemptedAtMillis;
  final int? lastWrongAtMillis;
  final int blindRecallAttempts;
  final int blindRecallCorrect;
  final int serviceAttempts;
  final int serviceCorrect;
  final int examAttempts;
  final int examCorrect;
  final int speedBonusCount;

  bool get hasStudied => attempts > 0;
  bool get hasQuizHistory => quizCorrect + quizIncorrect + examAttempts > 0;
  int get totalQuizAttempts => quizCorrect + quizIncorrect;
  int get totalTopicMisses =>
      topicMisses.values.fold<int>(0, (sum, value) => sum + value);
  int get confidenceScore => masteryScore.round();
  bool get needsReview => masteryScore < 60 || totalTopicMisses > 0;
  bool get isMastered => attempts >= 3 && masteryScore >= 85 && !needsReview;

  CocktailProgress copyWith({
    int? studyAttempts,
    int? knewCount,
    int? needPracticeCount,
    int? quizCorrect,
    int? quizIncorrect,
    Map<String, int>? topicMisses,
    int? lastStudiedAtMillis,
    int? lastQuizAtMillis,
    int? attempts,
    int? correctCount,
    int? wrongCount,
    double? masteryScore,
    int? averageResponseMs,
    int? lastAttemptedAtMillis,
    int? lastWrongAtMillis,
    int? blindRecallAttempts,
    int? blindRecallCorrect,
    int? serviceAttempts,
    int? serviceCorrect,
    int? examAttempts,
    int? examCorrect,
    int? speedBonusCount,
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
      attempts: attempts ?? this.attempts,
      correctCount: correctCount ?? this.correctCount,
      wrongCount: wrongCount ?? this.wrongCount,
      masteryScore: masteryScore ?? this.masteryScore,
      averageResponseMs: averageResponseMs ?? this.averageResponseMs,
      lastAttemptedAtMillis:
          lastAttemptedAtMillis ?? this.lastAttemptedAtMillis,
      lastWrongAtMillis: lastWrongAtMillis ?? this.lastWrongAtMillis,
      blindRecallAttempts: blindRecallAttempts ?? this.blindRecallAttempts,
      blindRecallCorrect: blindRecallCorrect ?? this.blindRecallCorrect,
      serviceAttempts: serviceAttempts ?? this.serviceAttempts,
      serviceCorrect: serviceCorrect ?? this.serviceCorrect,
      examAttempts: examAttempts ?? this.examAttempts,
      examCorrect: examCorrect ?? this.examCorrect,
      speedBonusCount: speedBonusCount ?? this.speedBonusCount,
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
      'attempts': attempts,
      'correctCount': correctCount,
      'wrongCount': wrongCount,
      'masteryScore': masteryScore,
      'averageResponseMs': averageResponseMs,
      'lastAttemptedAtMillis': lastAttemptedAtMillis,
      'lastWrongAtMillis': lastWrongAtMillis,
      'blindRecallAttempts': blindRecallAttempts,
      'blindRecallCorrect': blindRecallCorrect,
      'serviceAttempts': serviceAttempts,
      'serviceCorrect': serviceCorrect,
      'examAttempts': examAttempts,
      'examCorrect': examCorrect,
      'speedBonusCount': speedBonusCount,
    };
  }

  static double _deriveMasteryScore({
    required int attempts,
    required int correctCount,
    required int wrongCount,
    required Map<String, int> topicMisses,
    required int speedBonusCount,
  }) {
    if (attempts <= 0) {
      return 0;
    }

    final accuracy = correctCount / attempts;
    final missPenalty = topicMisses.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    final raw =
        (accuracy * 100) +
        (speedBonusCount * 2) -
        (wrongCount * 3) -
        (missPenalty * 2);
    return raw.clamp(0, 100).toDouble();
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
    required this.totalBlindRecallReviews,
    required this.totalServiceRounds,
    required this.totalServiceCorrect,
    required this.totalExamAttempts,
    required this.xp,
    required this.dailyGoalTarget,
    required this.dailyActivityCounts,
    required this.achievementKeys,
    required this.recentExamResults,
    required this.perfectRounds,
    required this.totalSpeedBonuses,
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
      totalBlindRecallReviews: 0,
      totalServiceRounds: 0,
      totalServiceCorrect: 0,
      totalExamAttempts: 0,
      xp: 0,
      dailyGoalTarget: 12,
      dailyActivityCounts: {},
      achievementKeys: [],
      recentExamResults: [],
      perfectRounds: 0,
      totalSpeedBonuses: 0,
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
      totalBlindRecallReviews: json['totalBlindRecallReviews'] as int? ?? 0,
      totalServiceRounds: json['totalServiceRounds'] as int? ?? 0,
      totalServiceCorrect: json['totalServiceCorrect'] as int? ?? 0,
      totalExamAttempts: json['totalExamAttempts'] as int? ?? 0,
      xp: json['xp'] as int? ?? 0,
      dailyGoalTarget: json['dailyGoalTarget'] as int? ?? 12,
      dailyActivityCounts: Map<String, int>.from(
        json['dailyActivityCounts'] as Map? ?? const {},
      ),
      achievementKeys: List<String>.from(
        json['achievementKeys'] as List<dynamic>? ?? const [],
      ),
      recentExamResults:
          (json['recentExamResults'] as List<dynamic>? ?? const [])
              .map(
                (item) =>
                    ExamResult.fromJson(Map<String, dynamic>.from(item as Map)),
              )
              .toList(growable: false),
      perfectRounds: json['perfectRounds'] as int? ?? 0,
      totalSpeedBonuses: json['totalSpeedBonuses'] as int? ?? 0,
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
  final int totalBlindRecallReviews;
  final int totalServiceRounds;
  final int totalServiceCorrect;
  final int totalExamAttempts;
  final int xp;
  final int dailyGoalTarget;
  final Map<String, int> dailyActivityCounts;
  final List<String> achievementKeys;
  final List<ExamResult> recentExamResults;
  final int perfectRounds;
  final int totalSpeedBonuses;

  double get accuracy =>
      totalQuizQuestions == 0 ? 0 : totalCorrectAnswers / totalQuizQuestions;
  int get level => (xp ~/ 250) + 1;

  Set<String> get studiedCocktailIds => cocktails.entries
      .where((entry) => entry.value.hasStudied || entry.value.hasQuizHistory)
      .map((entry) => entry.key)
      .toSet();

  Set<String> get masteredCocktailIds => cocktails.entries
      .where((entry) => entry.value.isMastered)
      .map((entry) => entry.key)
      .toSet();

  Set<String> get weakCocktailIds => cocktails.entries
      .where((entry) => entry.value.needsReview)
      .map((entry) => entry.key)
      .toSet();

  List<TrainingAchievement> get achievements => achievementKeys
      .map(TrainingAchievementX.fromKey)
      .whereType<TrainingAchievement>()
      .toList(growable: false);

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
    int? totalBlindRecallReviews,
    int? totalServiceRounds,
    int? totalServiceCorrect,
    int? totalExamAttempts,
    int? xp,
    int? dailyGoalTarget,
    Map<String, int>? dailyActivityCounts,
    List<String>? achievementKeys,
    List<ExamResult>? recentExamResults,
    int? perfectRounds,
    int? totalSpeedBonuses,
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
      totalBlindRecallReviews:
          totalBlindRecallReviews ?? this.totalBlindRecallReviews,
      totalServiceRounds: totalServiceRounds ?? this.totalServiceRounds,
      totalServiceCorrect: totalServiceCorrect ?? this.totalServiceCorrect,
      totalExamAttempts: totalExamAttempts ?? this.totalExamAttempts,
      xp: xp ?? this.xp,
      dailyGoalTarget: dailyGoalTarget ?? this.dailyGoalTarget,
      dailyActivityCounts: dailyActivityCounts ?? this.dailyActivityCounts,
      achievementKeys: achievementKeys ?? this.achievementKeys,
      recentExamResults: recentExamResults ?? this.recentExamResults,
      perfectRounds: perfectRounds ?? this.perfectRounds,
      totalSpeedBonuses: totalSpeedBonuses ?? this.totalSpeedBonuses,
    );
  }

  String toStorageString() => jsonEncode(toJson());

  Map<String, dynamic> toSummaryJson() {
    return {
      'totalStudyReviews': totalStudyReviews,
      'totalStudySessions': totalStudySessions,
      'totalQuizQuestions': totalQuizQuestions,
      'totalCorrectAnswers': totalCorrectAnswers,
      'totalQuizSessions': totalQuizSessions,
      'totalSessions': totalSessions,
      'topicMissTotals': topicMissTotals,
      'recentQuizResults': recentQuizResults
          .map((item) => item.toJson())
          .toList(growable: false),
      'trainingDayKeys': trainingDayKeys,
      'lastTrainedAtMillis': lastTrainedAtMillis,
      'totalBlindRecallReviews': totalBlindRecallReviews,
      'totalServiceRounds': totalServiceRounds,
      'totalServiceCorrect': totalServiceCorrect,
      'totalExamAttempts': totalExamAttempts,
      'xp': xp,
      'level': level,
      'dailyGoalTarget': dailyGoalTarget,
      'dailyActivityCounts': dailyActivityCounts,
      'achievementKeys': achievementKeys,
      'recentExamResults': recentExamResults
          .map((item) => item.toJson())
          .toList(growable: false),
      'perfectRounds': perfectRounds,
      'totalSpeedBonuses': totalSpeedBonuses,
      'accuracy': accuracy,
      'masteredCount': masteredCocktailIds.length,
      'weakCocktailIds': weakCocktailIds.toList(growable: false),
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'cocktails': cocktails.map((key, value) => MapEntry(key, value.toJson())),
      ...toSummaryJson(),
    };
  }
}
