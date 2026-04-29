import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cocktail_training/models/app_user.dart';
import 'package:cocktail_training/models/training_progress.dart';
import 'package:cocktail_training/models/user_role.dart';
import 'package:cocktail_training/services/backend_runtime_service.dart';
import 'package:cocktail_training/services/session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TrainingSessionType { study, blindRecall, quiz, service, exam }

class TrainingProgressService {
  TrainingProgressService._();

  static final TrainingProgressService instance = TrainingProgressService._();

  static const _localPriorityPrefix = 'venue_priority_cocktails_';
  static const _examResultCollection = 'examResults';
  static const _progressCollection = 'progress';
  static const _cocktailProgressCollection = 'cocktails';
  static const _staffCollection = 'staff';
  static const _userCollection = 'users';
  static const _venueCollection = 'venues';

  final SessionService _sessionService = SessionService.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  bool get _useFirebase => BackendRuntimeService.instance.useFirebaseAuth;

  String _storageKeyForUser(String? userId) {
    if (userId == null || userId.isEmpty) {
      return 'training_progress_guest_v2';
    }
    return 'training_progress_${userId}_v2';
  }

  DocumentReference<Map<String, dynamic>> _progressDoc(
    String venueId,
    String userId,
  ) {
    return _firestore
        .collection(_venueCollection)
        .doc(venueId)
        .collection(_progressCollection)
        .doc(userId);
  }

  CollectionReference<Map<String, dynamic>> _cocktailProgressDocs(
    String venueId,
    String userId,
  ) {
    return _progressDoc(
      venueId,
      userId,
    ).collection(_cocktailProgressCollection);
  }

  DocumentReference<Map<String, dynamic>> _staffDoc(
    String venueId,
    String uid,
  ) {
    return _firestore
        .collection(_venueCollection)
        .doc(venueId)
        .collection(_staffCollection)
        .doc(uid);
  }

  Future<TrainingProgress> loadProgress() async {
    final user = await _sessionService.getCurrentUser();
    if (user == null) {
      return loadProgressForUser(null);
    }
    return loadProgressForProfile(user);
  }

  Future<TrainingProgress> loadProgressForProfile(AppUser user) async {
    if (!_useFirebase) {
      return loadProgressForUser(user.id);
    }

    return _loadProgressFromFirebase(user.venueId, user.id);
  }

  Future<TrainingProgress> loadProgressForUser(String? userId) async {
    if (!_useFirebase || userId == null || userId.isEmpty) {
      final prefs = await _getPrefs();
      final raw = prefs.getString(_storageKeyForUser(userId));
      if (raw == null || raw.isEmpty) {
        return TrainingProgress.empty();
      }

      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        return TrainingProgress.fromJson(decoded);
      } catch (_) {
        return TrainingProgress.empty();
      }
    }

    final currentUser = await _sessionService.getCurrentUser();
    if (currentUser != null && currentUser.id == userId) {
      return _loadProgressFromFirebase(currentUser.venueId, userId);
    }

    final users = await _sessionService.loadUsersForVenue(
      currentUser?.venueId ?? '',
    );
    final profile = users.where((user) => user.id == userId).firstOrNull;
    if (profile == null) {
      return TrainingProgress.empty();
    }

    return _loadProgressFromFirebase(profile.venueId, userId);
  }

  Future<void> _saveProgress(TrainingProgress progress) async {
    final user = await _sessionService.getCurrentUser();
    await saveProgressForUser(user, progress);
  }

  Future<void> saveProgressForUser(
    AppUser? user,
    TrainingProgress progress,
  ) async {
    if (user == null) {
      final prefs = await _getPrefs();
      await prefs.setString(
        _storageKeyForUser(null),
        progress.toStorageString(),
      );
      return;
    }

    if (!_useFirebase) {
      final prefs = await _getPrefs();
      await prefs.setString(
        _storageKeyForUser(user.id),
        progress.toStorageString(),
      );
      return;
    }

    await _saveProgressToFirebase(user, progress);
  }

  Future<void> resetProgress() async {
    final user = await _sessionService.getCurrentUser();
    if (!_useFirebase || user == null) {
      final prefs = await _getPrefs();
      await prefs.remove(_storageKeyForUser(user?.id));
      return;
    }

    final summaryRef = _progressDoc(user.venueId, user.id);
    final cocktails = await _cocktailProgressDocs(user.venueId, user.id).get();
    final batch = _firestore.batch();
    for (final doc in cocktails.docs) {
      batch.delete(doc.reference);
    }
    batch.set(
      summaryRef,
      TrainingProgress.empty().toSummaryJson(),
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<List<String>> loadPriorityCocktailIds({String? venueId}) async {
    final user = await _sessionService.getCurrentUser();
    final effectiveVenueId = venueId ?? user?.venueId;
    if (effectiveVenueId == null || effectiveVenueId.isEmpty) {
      return const [];
    }

    if (!_useFirebase) {
      final prefs = await _getPrefs();
      return List<String>.from(
        prefs.getStringList('$_localPriorityPrefix$effectiveVenueId') ??
            const [],
      );
    }

    final snapshot = await _firestore
        .collection(_venueCollection)
        .doc(effectiveVenueId)
        .get();
    final data = snapshot.data();
    if (data == null) {
      return const [];
    }

    return List<String>.from(
      data['priorityCocktailIds'] as List<dynamic>? ?? const [],
    );
  }

  Future<void> savePriorityCocktailIds(List<String> cocktailIds) async {
    final user = await _sessionService.getCurrentUser();
    if (user == null) {
      return;
    }

    final cleaned = cocktailIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (!_useFirebase) {
      final prefs = await _getPrefs();
      await prefs.setStringList(
        '$_localPriorityPrefix${user.venueId}',
        cleaned,
      );
      return;
    }

    await _firestore.collection(_venueCollection).doc(user.venueId).set({
      'priorityCocktailIds': cleaned,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<TrainingProgress> startSession(TrainingSessionType type) async {
    final progress = await loadProgress();
    final now = DateTime.now();
    final dayKey = _dayKey(now);
    final updatedDays = [...progress.trainingDayKeys];
    if (!updatedDays.contains(dayKey)) {
      updatedDays.add(dayKey);
    }

    final updated = progress.copyWith(
      totalSessions: progress.totalSessions + 1,
      totalStudySessions:
          type == TrainingSessionType.study ||
              type == TrainingSessionType.blindRecall
          ? progress.totalStudySessions + 1
          : progress.totalStudySessions,
      totalQuizSessions:
          type == TrainingSessionType.quiz ||
              type == TrainingSessionType.service ||
              type == TrainingSessionType.exam
          ? progress.totalQuizSessions + 1
          : progress.totalQuizSessions,
      trainingDayKeys: updatedDays,
      lastTrainedAtMillis: now.millisecondsSinceEpoch,
    );

    await _saveProgress(_touchDailyActivity(updated, now, incrementBy: 0));
    return updated;
  }

  Future<TrainingProgress> recordStudyReview({
    required String cocktailId,
    required bool knewIt,
  }) async {
    final progress = await loadProgress();
    final now = DateTime.now().millisecondsSinceEpoch;
    final current =
        progress.cocktails[cocktailId] ?? CocktailProgress.empty(cocktailId);
    final updatedCocktail = _mergeCocktailProgress(
      current,
      attemptsDelta: 1,
      correctDelta: knewIt ? 1 : 0,
      wrongDelta: knewIt ? 0 : 1,
      studyAttemptsDelta: 1,
      knewCountDelta: knewIt ? 1 : 0,
      needPracticeDelta: knewIt ? 0 : 1,
      lastStudiedAtMillis: now,
      lastAttemptedAtMillis: now,
      lastWrongAtMillis: knewIt ? current.lastWrongAtMillis : now,
    );

    var updated = progress.copyWith(
      cocktails: {...progress.cocktails, cocktailId: updatedCocktail},
      totalStudyReviews: progress.totalStudyReviews + 1,
      lastTrainedAtMillis: now,
      xp: progress.xp + (knewIt ? 12 : 6),
    );

    updated = _touchDailyActivity(
      updated,
      DateTime.fromMillisecondsSinceEpoch(now),
    );
    updated = _applyAchievements(updated);
    await _saveProgress(updated);
    return updated;
  }

  Future<TrainingProgress> recordBlindRecallReview({
    required String cocktailId,
    required bool wasCorrect,
    int? responseMs,
  }) async {
    final progress = await loadProgress();
    final now = DateTime.now().millisecondsSinceEpoch;
    final current =
        progress.cocktails[cocktailId] ?? CocktailProgress.empty(cocktailId);
    final updatedCocktail = _mergeCocktailProgress(
      current,
      attemptsDelta: 1,
      correctDelta: wasCorrect ? 1 : 0,
      wrongDelta: wasCorrect ? 0 : 1,
      blindRecallAttemptsDelta: 1,
      blindRecallCorrectDelta: wasCorrect ? 1 : 0,
      responseMs: responseMs,
      lastStudiedAtMillis: now,
      lastAttemptedAtMillis: now,
      lastWrongAtMillis: wasCorrect ? current.lastWrongAtMillis : now,
    );

    var updated = progress.copyWith(
      cocktails: {...progress.cocktails, cocktailId: updatedCocktail},
      totalBlindRecallReviews: progress.totalBlindRecallReviews + 1,
      lastTrainedAtMillis: now,
      xp: progress.xp + (wasCorrect ? 16 : 8),
    );

    updated = _touchDailyActivity(
      updated,
      DateTime.fromMillisecondsSinceEpoch(now),
    );
    updated = _applyAchievements(updated);
    await _saveProgress(updated);
    return updated;
  }

  Future<TrainingProgress> recordQuizAnswer({
    required String cocktailId,
    required QuizTopic topic,
    required bool isCorrect,
    int? responseMs,
    bool isExam = false,
  }) async {
    final progress = await loadProgress();
    final current =
        progress.cocktails[cocktailId] ?? CocktailProgress.empty(cocktailId);
    final updatedTopicMisses = Map<String, int>.from(current.topicMisses);
    final updatedTopicTotals = Map<String, int>.from(progress.topicMissTotals);
    final now = DateTime.now().millisecondsSinceEpoch;

    if (isCorrect) {
      final existingMiss = updatedTopicMisses[topic.key] ?? 0;
      if (existingMiss > 0) {
        updatedTopicMisses[topic.key] = existingMiss - 1;
      }

      final totalMiss = updatedTopicTotals[topic.key] ?? 0;
      if (totalMiss > 0) {
        updatedTopicTotals[topic.key] = totalMiss - 1;
      }
    } else {
      updatedTopicMisses[topic.key] = (updatedTopicMisses[topic.key] ?? 0) + 1;
      updatedTopicTotals[topic.key] = (updatedTopicTotals[topic.key] ?? 0) + 1;
    }

    updatedTopicMisses.removeWhere((key, value) => value <= 0);
    updatedTopicTotals.removeWhere((key, value) => value <= 0);

    final updatedCocktail = _mergeCocktailProgress(
      current,
      attemptsDelta: 1,
      correctDelta: isCorrect ? 1 : 0,
      wrongDelta: isCorrect ? 0 : 1,
      quizCorrectDelta: isCorrect ? 1 : 0,
      quizIncorrectDelta: isCorrect ? 0 : 1,
      examAttemptsDelta: isExam ? 1 : 0,
      examCorrectDelta: isExam && isCorrect ? 1 : 0,
      topicMisses: updatedTopicMisses,
      responseMs: responseMs,
      lastQuizAtMillis: now,
      lastAttemptedAtMillis: now,
      lastWrongAtMillis: isCorrect ? current.lastWrongAtMillis : now,
    );

    var updated = progress.copyWith(
      cocktails: {...progress.cocktails, cocktailId: updatedCocktail},
      totalQuizQuestions: progress.totalQuizQuestions + 1,
      totalCorrectAnswers: isCorrect
          ? progress.totalCorrectAnswers + 1
          : progress.totalCorrectAnswers,
      topicMissTotals: updatedTopicTotals,
      lastTrainedAtMillis: now,
      xp: progress.xp + (isCorrect ? 18 : 7),
    );

    updated = _touchDailyActivity(
      updated,
      DateTime.fromMillisecondsSinceEpoch(now),
    );
    updated = _applyAchievements(updated);
    await _saveProgress(updated);
    return updated;
  }

  Future<TrainingProgress> recordServiceRound({
    required String cocktailId,
    required bool wasCorrect,
    required int responseMs,
  }) async {
    final progress = await loadProgress();
    final now = DateTime.now().millisecondsSinceEpoch;
    final current =
        progress.cocktails[cocktailId] ?? CocktailProgress.empty(cocktailId);
    final speedBonus = wasCorrect && responseMs <= 8000;

    final updatedCocktail = _mergeCocktailProgress(
      current,
      attemptsDelta: 1,
      correctDelta: wasCorrect ? 1 : 0,
      wrongDelta: wasCorrect ? 0 : 1,
      serviceAttemptsDelta: 1,
      serviceCorrectDelta: wasCorrect ? 1 : 0,
      speedBonusDelta: speedBonus ? 1 : 0,
      responseMs: responseMs,
      lastAttemptedAtMillis: now,
      lastWrongAtMillis: wasCorrect ? current.lastWrongAtMillis : now,
    );

    var updated = progress.copyWith(
      cocktails: {...progress.cocktails, cocktailId: updatedCocktail},
      totalServiceRounds: progress.totalServiceRounds + 1,
      totalServiceCorrect: wasCorrect
          ? progress.totalServiceCorrect + 1
          : progress.totalServiceCorrect,
      totalSpeedBonuses: speedBonus
          ? progress.totalSpeedBonuses + 1
          : progress.totalSpeedBonuses,
      lastTrainedAtMillis: now,
      xp: progress.xp + (wasCorrect ? 20 : 8) + (speedBonus ? 10 : 0),
    );

    updated = _touchDailyActivity(
      updated,
      DateTime.fromMillisecondsSinceEpoch(now),
    );
    updated = _applyAchievements(updated);
    await _saveProgress(updated);
    return updated;
  }

  Future<TrainingProgress> recordQuizSessionResult(QuizResult result) async {
    final progress = await loadProgress();
    final updatedResults = [
      result,
      ...progress.recentQuizResults,
    ].take(12).toList(growable: false);

    var updated = progress.copyWith(
      recentQuizResults: updatedResults,
      lastTrainedAtMillis: result.completedAtMillis,
      perfectRounds: result.isPerfect
          ? progress.perfectRounds + 1
          : progress.perfectRounds,
      xp: progress.xp + (result.isPerfect ? 40 : 0),
    );

    updated = _applyAchievements(updated);
    await _saveProgress(updated);
    return updated;
  }

  Future<ExamResult> recordExamResult({
    required int score,
    required int total,
    required int passMark,
  }) async {
    final user = await _sessionService.getCurrentUser();
    if (user == null) {
      throw StateError('No signed-in user for exam result.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final result = ExamResult(
      id: 'exam-$now',
      uid: user.id,
      displayName: user.name.isEmpty ? user.email : user.name,
      score: score,
      total: total,
      passMark: passMark,
      createdAtMillis: now,
    );

    var progress = await loadProgress();
    progress = progress.copyWith(
      totalExamAttempts: progress.totalExamAttempts + 1,
      recentExamResults: [
        result,
        ...progress.recentExamResults,
      ].take(8).toList(growable: false),
      lastTrainedAtMillis: now,
      xp: progress.xp + (result.passed ? 120 : 40),
    );

    progress = _touchDailyActivity(
      progress,
      DateTime.fromMillisecondsSinceEpoch(now),
    );
    progress = _applyAchievements(progress);
    await _saveProgress(progress);

    if (_useFirebase) {
      await _firestore
          .collection(_venueCollection)
          .doc(user.venueId)
          .collection(_examResultCollection)
          .doc(result.id)
          .set(result.toJson());
    }

    return result;
  }

  Future<ExamResult?> loadLatestExamResultForUser(AppUser user) async {
    final progress = await loadProgressForProfile(user);
    if (progress.recentExamResults.isNotEmpty) {
      return progress.recentExamResults.first;
    }

    if (!_useFirebase) {
      return null;
    }

    final query = await _firestore
        .collection(_venueCollection)
        .doc(user.venueId)
        .collection(_examResultCollection)
        .where('uid', isEqualTo: user.id)
        .orderBy('createdAtMillis', descending: true)
        .limit(1)
        .get();
    if (query.docs.isEmpty) {
      return null;
    }
    return ExamResult.fromJson(query.docs.first.data());
  }

  Future<TrainingProgress> _loadProgressFromFirebase(
    String venueId,
    String userId,
  ) async {
    final summarySnapshot = await _progressDoc(venueId, userId).get();
    final cocktailSnapshots = await _cocktailProgressDocs(
      venueId,
      userId,
    ).get();

    final cocktails = <String, CocktailProgress>{
      for (final doc in cocktailSnapshots.docs)
        doc.id: CocktailProgress.fromJson({
          ...doc.data(),
          'cocktailId': doc.id,
        }),
    };

    final summaryData = summarySnapshot.data();
    if (summaryData == null) {
      return TrainingProgress.empty().copyWith(cocktails: cocktails);
    }

    final payload = Map<String, dynamic>.from(summaryData)
      ..['cocktails'] = cocktails.map(
        (key, value) => MapEntry(key, value.toJson()),
      );

    return TrainingProgress.fromJson(payload);
  }

  Future<void> _saveProgressToFirebase(
    AppUser user,
    TrainingProgress progress,
  ) async {
    final summaryRef = _progressDoc(user.venueId, user.id);
    final batch = _firestore.batch();
    batch.set(summaryRef, progress.toSummaryJson(), SetOptions(merge: true));

    for (final entry in progress.cocktails.entries) {
      batch.set(
        _cocktailProgressDocs(user.venueId, user.id).doc(entry.key),
        entry.value.toJson(),
        SetOptions(merge: true),
      );
    }

    final latestExam = progress.recentExamResults.isEmpty
        ? null
        : progress.recentExamResults.first;

    batch.set(_staffDoc(user.venueId, user.id), {
      'displayName': user.name,
      'email': user.email,
      'role': user.role.key,
      'active': user.active,
      'lastActive': progress.lastTrainedAtMillis,
      'latestExamScore': latestExam?.percentage.round(),
      'latestExamPassed': latestExam?.passed,
      'xp': progress.xp,
      'level': progress.level,
      'masteredCount': progress.masteredCocktailIds.length,
      'weakCocktailIds': progress.weakCocktailIds.toList(growable: false),
    }, SetOptions(merge: true));

    batch.set(_firestore.collection(_userCollection).doc(user.id), {
      'lastActive': progress.lastTrainedAtMillis,
    }, SetOptions(merge: true));

    await batch.commit();
  }

  CocktailProgress _mergeCocktailProgress(
    CocktailProgress current, {
    int attemptsDelta = 0,
    int correctDelta = 0,
    int wrongDelta = 0,
    int studyAttemptsDelta = 0,
    int knewCountDelta = 0,
    int needPracticeDelta = 0,
    int quizCorrectDelta = 0,
    int quizIncorrectDelta = 0,
    int blindRecallAttemptsDelta = 0,
    int blindRecallCorrectDelta = 0,
    int serviceAttemptsDelta = 0,
    int serviceCorrectDelta = 0,
    int examAttemptsDelta = 0,
    int examCorrectDelta = 0,
    int speedBonusDelta = 0,
    Map<String, int>? topicMisses,
    int? responseMs,
    int? lastStudiedAtMillis,
    int? lastQuizAtMillis,
    int? lastAttemptedAtMillis,
    int? lastWrongAtMillis,
  }) {
    final nextAttempts = current.attempts + attemptsDelta;
    final nextCorrect = current.correctCount + correctDelta;
    final nextWrong = current.wrongCount + wrongDelta;
    final averageResponse = _mergeAverageResponse(
      currentAverage: current.averageResponseMs,
      currentAttempts: current.attempts,
      newResponseMs: responseMs,
    );
    final nextTopicMisses = topicMisses ?? current.topicMisses;
    final nextSpeedBonusCount = current.speedBonusCount + speedBonusDelta;
    final nextMastery = _calculateMasteryScore(
      attempts: nextAttempts,
      correctCount: nextCorrect,
      wrongCount: nextWrong,
      topicMisses: nextTopicMisses,
      speedBonusCount: nextSpeedBonusCount,
    );

    return current.copyWith(
      studyAttempts: current.studyAttempts + studyAttemptsDelta,
      knewCount: current.knewCount + knewCountDelta,
      needPracticeCount: current.needPracticeCount + needPracticeDelta,
      quizCorrect: current.quizCorrect + quizCorrectDelta,
      quizIncorrect: current.quizIncorrect + quizIncorrectDelta,
      topicMisses: nextTopicMisses,
      lastStudiedAtMillis: lastStudiedAtMillis,
      lastQuizAtMillis: lastQuizAtMillis,
      attempts: nextAttempts,
      correctCount: nextCorrect,
      wrongCount: nextWrong,
      masteryScore: nextMastery,
      averageResponseMs: averageResponse,
      lastAttemptedAtMillis: lastAttemptedAtMillis,
      lastWrongAtMillis: lastWrongAtMillis,
      blindRecallAttempts:
          current.blindRecallAttempts + blindRecallAttemptsDelta,
      blindRecallCorrect: current.blindRecallCorrect + blindRecallCorrectDelta,
      serviceAttempts: current.serviceAttempts + serviceAttemptsDelta,
      serviceCorrect: current.serviceCorrect + serviceCorrectDelta,
      examAttempts: current.examAttempts + examAttemptsDelta,
      examCorrect: current.examCorrect + examCorrectDelta,
      speedBonusCount: nextSpeedBonusCount,
    );
  }

  TrainingProgress _touchDailyActivity(
    TrainingProgress progress,
    DateTime timestamp, {
    int incrementBy = 1,
  }) {
    final dayKey = _dayKey(timestamp);
    final counts = Map<String, int>.from(progress.dailyActivityCounts);
    if (incrementBy > 0) {
      counts[dayKey] = (counts[dayKey] ?? 0) + incrementBy;
    } else {
      counts.putIfAbsent(dayKey, () => counts[dayKey] ?? 0);
    }
    final dayKeys = [...progress.trainingDayKeys];
    if (!dayKeys.contains(dayKey)) {
      dayKeys.add(dayKey);
    }
    return progress.copyWith(
      dailyActivityCounts: counts,
      trainingDayKeys: dayKeys,
      lastTrainedAtMillis: timestamp.millisecondsSinceEpoch,
    );
  }

  TrainingProgress _applyAchievements(TrainingProgress progress) {
    final unlocked = {...progress.achievementKeys};

    if (progress.perfectRounds > 0) {
      unlocked.add(TrainingAchievement.perfectRound.key);
    }
    if (progress.recentExamResults.any((result) => result.passed)) {
      unlocked.add(TrainingAchievement.serviceReady.key);
      unlocked.add(TrainingAchievement.firstPassCheckPassed.key);
    }
    if (progress.totalCorrectAnswers >= 30 || progress.accuracy >= 0.85) {
      unlocked.add(TrainingAchievement.specSharp.key);
    }
    if (progress.totalSpeedBonuses >= 5) {
      unlocked.add(TrainingAchievement.speedRail.key);
    }
    if (_hasClassicsMaster(progress)) {
      unlocked.add(TrainingAchievement.classicsMaster.key);
    }

    return progress.copyWith(achievementKeys: unlocked.toList(growable: false));
  }

  bool _hasClassicsMaster(TrainingProgress progress) {
    const classicIds = <String>{
      'margarita',
      'spicy-margarita',
      'mojito',
      'espresso-martini',
      'passionfruit-martini',
      'pina-colada',
    };

    final mastered = progress.masteredCocktailIds;
    final masteredClassics = classicIds.where(mastered.contains).length;
    return masteredClassics >= 3 || progress.masteredCocktailIds.length >= 8;
  }

  int? _mergeAverageResponse({
    required int? currentAverage,
    required int currentAttempts,
    required int? newResponseMs,
  }) {
    if (newResponseMs == null || newResponseMs <= 0) {
      return currentAverage;
    }

    if (currentAverage == null || currentAttempts <= 0) {
      return newResponseMs;
    }

    return (((currentAverage * currentAttempts) + newResponseMs) /
            (currentAttempts + 1))
        .round();
  }

  double _calculateMasteryScore({
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
      (total, value) => total + value,
    );
    final raw =
        (accuracy * 100) +
        (speedBonusCount * 2) -
        (wrongCount * 3) -
        (missPenalty * 2);
    return raw.clamp(0, 100).toDouble();
  }

  String _dayKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
