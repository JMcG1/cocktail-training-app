import 'dart:convert';

import 'package:cocktail_training/models/training_progress.dart';
import 'package:cocktail_training/services/session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TrainingSessionType { study, quiz }

class TrainingProgressService {
  TrainingProgressService._();

  static final TrainingProgressService instance = TrainingProgressService._();

  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  String _storageKeyForUser(String? userId) {
    if (userId == null || userId.isEmpty) {
      return 'training_progress_guest_v1';
    }
    return 'training_progress_${userId}_v1';
  }

  Future<TrainingProgress> loadProgress() async {
    final userId = SessionService.instance.currentUser?.id;
    return loadProgressForUser(userId);
  }

  Future<TrainingProgress> loadProgressForUser(String? userId) async {
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

  Future<void> _saveProgress(TrainingProgress progress) async {
    final userId = SessionService.instance.currentUser?.id;
    await saveProgressForUser(userId, progress);
  }

  Future<void> saveProgressForUser(String? userId, TrainingProgress progress) async {
    final prefs = await _getPrefs();
    await prefs.setString(_storageKeyForUser(userId), progress.toStorageString());
  }

  Future<void> resetProgress() async {
    final prefs = await _getPrefs();
    final userId = SessionService.instance.currentUser?.id;
    await prefs.remove(_storageKeyForUser(userId));
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
      totalStudySessions: type == TrainingSessionType.study
          ? progress.totalStudySessions + 1
          : progress.totalStudySessions,
      totalQuizSessions:
          type == TrainingSessionType.quiz ? progress.totalQuizSessions + 1 : progress.totalQuizSessions,
      trainingDayKeys: updatedDays,
      lastTrainedAtMillis: now.millisecondsSinceEpoch,
    );

    await _saveProgress(updated);
    return updated;
  }

  Future<TrainingProgress> recordStudyReview({
    required String cocktailId,
    required bool knewIt,
  }) async {
    final progress = await loadProgress();
    final current = progress.cocktails[cocktailId] ?? CocktailProgress.empty(cocktailId);
    final updatedCocktail = current.copyWith(
      studyAttempts: current.studyAttempts + 1,
      knewCount: knewIt ? current.knewCount + 1 : current.knewCount,
      needPracticeCount: knewIt ? current.needPracticeCount : current.needPracticeCount + 1,
      lastStudiedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );

    final updated = progress.copyWith(
      cocktails: {
        ...progress.cocktails,
        cocktailId: updatedCocktail,
      },
      totalStudyReviews: progress.totalStudyReviews + 1,
      lastTrainedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );

    await _saveProgress(updated);
    return updated;
  }

  Future<TrainingProgress> recordQuizAnswer({
    required String cocktailId,
    required QuizTopic topic,
    required bool isCorrect,
  }) async {
    final progress = await loadProgress();
    final current = progress.cocktails[cocktailId] ?? CocktailProgress.empty(cocktailId);
    final updatedTopicMisses = Map<String, int>.from(current.topicMisses);
    final updatedTopicTotals = Map<String, int>.from(progress.topicMissTotals);

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

    final updatedCocktail = current.copyWith(
      quizCorrect: isCorrect ? current.quizCorrect + 1 : current.quizCorrect,
      quizIncorrect: isCorrect ? current.quizIncorrect : current.quizIncorrect + 1,
      topicMisses: updatedTopicMisses,
      lastQuizAtMillis: DateTime.now().millisecondsSinceEpoch,
    );

    final updated = progress.copyWith(
      cocktails: {
        ...progress.cocktails,
        cocktailId: updatedCocktail,
      },
      totalQuizQuestions: progress.totalQuizQuestions + 1,
      totalCorrectAnswers: isCorrect ? progress.totalCorrectAnswers + 1 : progress.totalCorrectAnswers,
      topicMissTotals: updatedTopicTotals,
      lastTrainedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );

    await _saveProgress(updated);
    return updated;
  }

  Future<TrainingProgress> recordQuizSessionResult(QuizResult result) async {
    final progress = await loadProgress();
    final updatedResults = [
      result,
      ...progress.recentQuizResults,
    ].take(12).toList(growable: false);

    final updated = progress.copyWith(
      recentQuizResults: updatedResults,
      lastTrainedAtMillis: result.completedAtMillis,
    );

    await _saveProgress(updated);
    return updated;
  }

  String _dayKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
