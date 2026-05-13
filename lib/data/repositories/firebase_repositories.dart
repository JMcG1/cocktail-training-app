import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';

import '../../core/config/app_environment.dart';
import '../../core/utils/batch_recipe_graph.dart';
import '../../core/utils/pdf_recipe_extractor.dart';
import '../../core/utils/recipe_text_parser.dart';
import '../../core/utils/variance_math.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../firestore/firestore_paths.dart';
import '../firestore/firestore_serializers.dart';
import 'demo_repositories.dart';

class FirebaseManagerAuthRepository implements AuthRepository {
  FirebaseManagerAuthRepository({required this.environment});

  final AppEnvironment environment;
  AppUser? _currentUser;

  @override
  AppUser? get currentUser => _currentUser;

  @override
  Future<void> initialize() async {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      _currentUser = null;
      return;
    }
    _currentUser = await _buildUser(user);
  }

  @override
  Future<AppUser> createManagerAccount({
    required String email,
    required String password,
    required String displayName,
    required String venueName,
  }) async {
    final credential = await firebase_auth.FirebaseAuth.instance
        .createUserWithEmailAndPassword(email: email, password: password);
    final user = credential.user;
    if (user == null) {
      throw Exception('Unable to create the manager account.');
    }
    await user.updateDisplayName(displayName);
    final venueRef = FirebaseFirestore.instance.collection('venues').doc();
    final now = DateTime.now();
    await venueRef.set({
      'name': venueName.trim(),
      'ownerUid': user.uid,
      'createdAt': now.toIso8601String(),
      'active': true,
    });
    await FirebaseFirestore.instance
        .collection(FirestorePaths.users())
        .doc(user.uid)
        .set({
      'displayName': displayName.trim(),
      'role': UserRole.owner.name,
      'venueId': venueRef.id,
      'createdAt': now.toIso8601String(),
      'active': true,
      'email': email.trim(),
    });
    _currentUser = AppUser(
      id: user.uid,
      email: user.email ?? email.trim(),
      displayName: displayName.trim(),
      role: UserRole.owner,
      venueId: venueRef.id,
      venueName: venueName.trim(),
      createdAt: now,
      active: true,
    );
    return _currentUser!;
  }

  @override
  Future<AppUser> signInManager({
    required String email,
    required String password,
  }) async {
    final credential = await firebase_auth.FirebaseAuth.instance
        .signInWithEmailAndPassword(email: email, password: password);
    final user = credential.user;
    if (user == null) {
      throw Exception('Unable to sign in.');
    }
    _currentUser = await _buildUser(user);
    if (_currentUser!.role != UserRole.manager && _currentUser!.role != UserRole.owner) {
      await signOut();
      throw Exception('This account does not have manager access.');
    }
    return _currentUser!;
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {
    await firebase_auth.FirebaseAuth.instance.sendPasswordResetEmail(
      email: email.trim(),
    );
  }

  @override
  Future<void> signOut() async {
    await firebase_auth.FirebaseAuth.instance.signOut();
    _currentUser = null;
  }

  Future<AppUser> _buildUser(firebase_auth.User user) async {
    final doc = await FirebaseFirestore.instance
        .collection(FirestorePaths.users())
        .doc(user.uid)
        .get();
    final data = doc.data() ?? const <String, dynamic>{};
    final venueId = data['venueId'] as String? ?? environment.defaultVenueId;
    final roleString = (data['role'] as String? ?? 'manager').toLowerCase();
    final role = switch (roleString) {
      'owner' => UserRole.owner,
      'bartender' => UserRole.bartender,
      _ => UserRole.manager,
    };
    final venueDoc = await FirebaseFirestore.instance.collection('venues').doc(venueId).get();
    final venueData = venueDoc.data() ?? const <String, dynamic>{};
    return AppUser(
      id: user.uid,
      email: user.email ?? '',
      displayName: data['displayName'] as String? ?? user.displayName ?? 'Venue manager',
      role: role,
      venueId: venueId,
      venueName: venueData['name'] as String? ?? 'Venue',
      createdAt: DateTime.tryParse(data['createdAt'] as String? ?? '') ?? DateTime.now(),
      active: data['active'] as bool? ?? true,
    );
  }
}

class DemoAuthRepository implements AuthRepository {
  DemoAuthRepository({required this.environment});

  final AppEnvironment environment;
  AppUser? _currentUser;

  @override
  AppUser? get currentUser => _currentUser;

  @override
  Future<void> initialize() async {}

  @override
  Future<AppUser> createManagerAccount({
    required String email,
    required String password,
    required String displayName,
    required String venueName,
  }) async {
    throw Exception('Manager account creation is available only in Firebase mode.');
  }

  @override
  Future<AppUser> signInManager({
    required String email,
    required String password,
  }) async {
    if (email.trim().toLowerCase() == environment.demoManagerEmail.toLowerCase() &&
        password == environment.demoManagerPassword) {
      _currentUser = AppUser(
        id: 'demo-manager',
        email: environment.demoManagerEmail,
        displayName: 'Demo venue manager',
        role: UserRole.manager,
        venueId: environment.defaultVenueId,
        venueName: 'Demo venue',
        createdAt: DateTime.now(),
        active: true,
      );
      return _currentUser!;
    }
    throw Exception(
      'Use the demo manager credentials from the sign-in screen, or switch APP_MODE to firebase with live config.',
    );
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {}

  @override
  Future<void> signOut() async {
    _currentUser = null;
  }
}

class FirestoreTrainingRepository implements TrainingRepository {
  FirestoreTrainingRepository({required String venueId})
      : _textParser = RecipeTextParser(),
        _pdfExtractor = PdfRecipeExtractor(RecipeTextParser()),
        _venueId = venueId;

  String _venueId;
  final RecipeTextParser _textParser;
  final PdfRecipeExtractor _pdfExtractor;
  final List<Ingredient> _ingredients = [];
  final List<CocktailRecipe> _recipes = [];
  final List<BatchRecipe> _batches = [];
  final List<WeeklyConcernSession> _weeklySessions = [];
  final List<QuizSession> _quizSessions = [];
  final List<QuizAttempt> _quizAttempts = [];
  RecipeImportResult? _latestImportResult;
  int _idCounter = 0;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  @override
  List<Ingredient> get ingredients => List.unmodifiable(_ingredients);

  @override
  List<CocktailRecipe> get recipes => List.unmodifiable(_recipes);

  @override
  List<BatchRecipe> get batches => List.unmodifiable(_batches);

  @override
  List<WeeklyConcernSession> get weeklySessions => List.unmodifiable(_weeklySessions.reversed);

  @override
  List<QuizSession> get quizSessions => List.unmodifiable(_quizSessions.reversed);

  @override
  List<QuizAttempt> get quizAttempts => List.unmodifiable(_quizAttempts.reversed);

  @override
  RecipeImportResult? get latestImportResult => _latestImportResult;

  @override
  void configureVenue(String venueId) {
    _venueId = venueId;
  }

  @override
  Future<void> initialize() async {
    _weeklySessions.clear();
    _quizAttempts.clear();
    _latestImportResult = null;
    await _loadApprovedRecipesAndIngredients();
    await _loadPublicQuizSessions();
  }

  @override
  Future<void> loadManagerData() async {
    await Future.wait([
      _loadDrafts(),
      _loadWeeklySessionsAndSales(),
      _loadQuizAttempts(),
      _loadAllQuizSessions(),
    ]);
  }

  Future<void> _loadApprovedRecipesAndIngredients() async {
    final ingredientSnapshot =
        await _firestore.collection(FirestorePaths.ingredients(_venueId)).get();
    final recipeSnapshot = await _firestore.collection(FirestorePaths.recipes(_venueId)).get();
    final batchSnapshot = await _firestore.collection(FirestorePaths.batchRecipes(_venueId)).get();
    _ingredients
      ..clear()
      ..addAll(
        ingredientSnapshot.docs.map(
          (doc) => FirestoreSerializers.ingredientFromMap(doc.id, doc.data()),
        ),
      );
    _recipes
      ..clear()
      ..addAll(
        recipeSnapshot.docs
            .map((doc) => FirestoreSerializers.recipeFromMap(doc.id, doc.data()))
            .where((recipe) => recipe.isApproved),
      );
    _batches
      ..clear()
      ..addAll(
        batchSnapshot.docs
            .map((doc) => FirestoreSerializers.batchRecipeFromMap(doc.id, doc.data()))
            .where((recipe) => recipe.isApproved),
      );
    final relinkedCocktails = BatchGraphResolver.linkCocktailsToBatches(
      cocktails: _recipes,
      batches: _batches,
    );
    _recipes
      ..clear()
      ..addAll(relinkedCocktails);
  }

  Future<void> _loadDrafts() async {
    final snapshot = await _firestore.collection(FirestorePaths.recipeDrafts(_venueId)).get();
    final drafts = snapshot.docs
        .map((doc) => FirestoreSerializers.draftFromMap(doc.id, doc.data()))
        .where((draft) => draft.status == RecipeDraftStatus.pending)
        .toList();
    _latestImportResult = drafts.isEmpty
        ? null
        : _normalizeImportResult(RecipeImportResult(
            sourceName: 'Firestore review drafts',
            drafts: drafts,
            warnings: const [],
            requiresOcr: false,
            rawText: '',
            pageCount: 0,
          ));
  }

  Future<void> _loadWeeklySessionsAndSales() async {
    final sessionSnapshot =
        await _firestore.collection(FirestorePaths.stockConcernSessions(_venueId)).get();
    final salesSnapshot =
        await _firestore.collection(FirestorePaths.bartenderSales(_venueId)).get();
    final salesByWeek = <String, List<BartenderWeeklySales>>{};
    for (final doc in salesSnapshot.docs) {
      final data = doc.data();
      final weekId = data['weekId'] as String? ?? '';
      if (weekId.isEmpty) {
        continue;
      }
      salesByWeek.putIfAbsent(weekId, () => []).add(
            FirestoreSerializers.bartenderSalesFromMap(data),
          );
    }
    _weeklySessions
      ..clear()
      ..addAll(
        sessionSnapshot.docs.map(
          (doc) => FirestoreSerializers.weeklySessionFromMap(
            doc.id,
            doc.data(),
            bartenderSales: salesByWeek[doc.id] ?? const [],
          ),
        ),
      );
  }

  Future<void> _loadPublicQuizSessions() async {
    final snapshot = await _firestore
        .collection(FirestorePaths.quizSessions(_venueId))
        .where('isActive', isEqualTo: true)
        .get();
    _quizSessions
      ..clear()
      ..addAll(
        snapshot.docs.map((doc) => FirestoreSerializers.quizSessionFromMap(doc.id, doc.data())),
      );
  }

  Future<void> _loadAllQuizSessions() async {
    final snapshot = await _firestore.collection(FirestorePaths.quizSessions(_venueId)).get();
    _quizSessions
      ..clear()
      ..addAll(
        snapshot.docs.map((doc) => FirestoreSerializers.quizSessionFromMap(doc.id, doc.data())),
      );
  }

  Future<void> _loadQuizAttempts() async {
    final snapshot = await _firestore.collection(FirestorePaths.quizAttempts(_venueId)).get();
    _quizAttempts
      ..clear()
      ..addAll(
        snapshot.docs.map((doc) => FirestoreSerializers.quizAttemptFromMap(doc.id, doc.data())),
      );
  }

  @override
  Future<RecipeImportResult> extractRecipesFromPdf({
    required Uint8List bytes,
    required String fileName,
  }) async {
    _latestImportResult =
        _normalizeImportResult(_pdfExtractor.extract(bytes: bytes, fileName: fileName));
    return _latestImportResult!;
  }

  @override
  RecipeImportResult extractRecipesFromText({
    required String text,
    required String sourceName,
  }) {
    _latestImportResult =
        _normalizeImportResult(_textParser.parseImportText(source: text, sourceName: sourceName));
    return _latestImportResult!;
  }

  @override
  void clearImportPreview() {
    _latestImportResult = null;
  }

  @override
  Future<void> saveImportedDrafts(List<RecipeImportDraft> drafts) async {
    final approvedDrafts =
        drafts.where((draft) => draft.status == RecipeDraftStatus.approved).toList();
    final pendingDrafts =
        drafts.where((draft) => draft.status == RecipeDraftStatus.pending).toList();
    debugPrint(
      '[RecipeImport] Saving drafts venue=$_venueId approved=${approvedDrafts.length} pending=${pendingDrafts.length} total=${drafts.length}',
    );

    final batch = _firestore.batch();
    final draftCollection = _firestore.collection(FirestorePaths.recipeDrafts(_venueId));
    final recipeCollection = _firestore.collection(FirestorePaths.recipes(_venueId));
    final batchRecipeCollection = _firestore.collection(FirestorePaths.batchRecipes(_venueId));
    final ingredientCollection = _firestore.collection(FirestorePaths.ingredients(_venueId));

    for (final draft in drafts) {
      final draftDoc = draftCollection.doc(draft.id);
      if (draft.status == RecipeDraftStatus.deleted ||
          draft.status == RecipeDraftStatus.approved) {
        batch.delete(draftDoc);
      } else {
        batch.set(draftDoc, FirestoreSerializers.draftToMap(draft));
      }
    }

    final approvedBatchRecipes = approvedDrafts
        .where((draft) => draft.isBatch)
        .map((draft) => _normalizeBatch(draft.toBatchRecipe()))
        .toList();
    for (final batchRecipe in approvedBatchRecipes) {
      batch.set(
        batchRecipeCollection.doc(batchRecipe.id),
        FirestoreSerializers.batchRecipeToMap(batchRecipe),
      );
    }
    for (final batchRecipe in approvedBatchRecipes) {
      _storeBatchLocally(batchRecipe);
    }

    final normalizedApprovedRecipes = BatchGraphResolver.linkCocktailsToBatches(
      cocktails: approvedDrafts
          .where((draft) => !draft.isBatch)
          .map((draft) => _normalizeRecipe(draft.toRecipe()))
          .toList(),
      batches: _batches,
    );
    final ingredientsToPersist = <Ingredient>[];
    final seenIngredientNames = <String>{};
    for (final recipe in normalizedApprovedRecipes) {
      batch.set(recipeCollection.doc(recipe.id), FirestoreSerializers.recipeToMap(recipe));
      for (final ingredient in recipe.ingredients.where((item) => !item.isBatchReference)) {
        final normalizedName = ingredient.ingredientName.trim().toLowerCase();
        final alreadyStored = _ingredients.any(
          (item) => item.name.toLowerCase() == normalizedName,
        );
        if (alreadyStored || !seenIngredientNames.add(normalizedName)) {
          continue;
        }
        final pendingIngredient = Ingredient(
          id: _nextId('ingredient'),
          name: ingredient.ingredientName.trim(),
          bottleSizeMl: 700,
          bottleCost: 0,
        );
        ingredientsToPersist.add(pendingIngredient);
        batch.set(
          ingredientCollection.doc(pendingIngredient.id),
          FirestoreSerializers.ingredientToMap(pendingIngredient),
        );
      }
    }

    try {
      await batch.commit();
    } catch (error) {
      debugPrint('[RecipeImport] Firebase save failed: $error');
      rethrow;
    }

    for (final recipe in normalizedApprovedRecipes) {
      _storeRecipeLocally(recipe);
    }
    for (final ingredient in ingredientsToPersist) {
      _storeIngredientLocally(ingredient);
    }

    _latestImportResult = pendingDrafts.isEmpty
        ? null
        : _normalizeImportResult(RecipeImportResult(
            sourceName: _latestImportResult?.sourceName ?? 'Firestore review drafts',
            drafts: pendingDrafts,
            warnings: _latestImportResult?.warnings ?? const [],
            requiresOcr: false,
            rawText: _latestImportResult?.rawText ?? '',
            pageCount: _latestImportResult?.pageCount ?? 0,
          ));
    debugPrint('[RecipeImport] Firebase save completed venue=$_venueId');
  }

  @override
  void saveIngredient(Ingredient ingredient) {
    _storeIngredientLocally(ingredient);
    unawaited(
      _firestore
          .collection(FirestorePaths.ingredients(_venueId))
          .doc(ingredient.id)
          .set(FirestoreSerializers.ingredientToMap(ingredient)),
    );
  }

  @override
  void saveRecipe(CocktailRecipe recipe) {
    final normalized = _normalizeRecipe(recipe);
    _storeRecipeLocally(normalized);
    unawaited(
      _firestore
          .collection(FirestorePaths.recipes(_venueId))
          .doc(normalized.id)
          .set(FirestoreSerializers.recipeToMap(normalized)),
    );
  }

  @override
  void saveBatch(BatchRecipe batch) {
    final normalized = _normalizeBatch(batch);
    _storeBatchLocally(normalized);
    unawaited(
      _firestore
          .collection(FirestorePaths.batchRecipes(_venueId))
          .doc(normalized.id)
          .set(FirestoreSerializers.batchRecipeToMap(normalized)),
    );
  }

  CocktailRecipe _normalizeRecipe(CocktailRecipe recipe) {
    return BatchGraphResolver.linkCocktailsToBatches(
      cocktails: [
        recipe.copyWith(
      name: recipe.name.trim(),
      category: recipe.category.trim(),
      glassware: recipe.glassware.trim(),
      garnish: recipe.garnish.trim(),
      method: recipe.method.trim(),
      notes: recipe.notes.trim(),
      isApproved: true,
      ingredients: recipe.ingredients
          .where((item) => item.ingredientName.trim().isNotEmpty)
          .map((item) => item.copyWith(ingredientName: item.ingredientName.trim()))
          .toList(),
        ),
      ],
      batches: _batches,
    ).single;
  }

  BatchRecipe _normalizeBatch(BatchRecipe batch) {
    final linkedIngredients = batch.ingredients
        .where((item) => item.ingredientName.trim().isNotEmpty)
        .map((item) => item.copyWith(ingredientName: item.ingredientName.trim()))
        .map(
          (item) => BatchGraphResolver.linkIngredientToBatch(
            ingredient: item,
            batchIndex: BatchGraphResolver.buildBatchIndex(
              _batches.where((existing) => existing.id != batch.id),
            ),
          ),
        )
        .toList();
    return batch.copyWith(
      name: batch.name.trim(),
      category: batch.category.trim(),
      notes: batch.notes.trim(),
      isApproved: true,
      ingredients: linkedIngredients,
    );
  }

  void _storeRecipeLocally(CocktailRecipe recipe) {
    final index = _recipes.indexWhere((item) => item.id == recipe.id);
    if (index == -1) {
      _recipes.add(recipe);
    } else {
      _recipes[index] = recipe;
    }
  }

  void _storeBatchLocally(BatchRecipe batch) {
    final index = _batches.indexWhere((item) => item.id == batch.id);
    if (index == -1) {
      _batches.add(batch);
    } else {
      _batches[index] = batch;
    }
    final relinked = BatchGraphResolver.linkCocktailsToBatches(
      cocktails: _recipes,
      batches: _batches,
    );
    _recipes
      ..clear()
      ..addAll(relinked);
  }

  void _storeIngredientLocally(Ingredient ingredient) {
    final index = _ingredients.indexWhere(
      (item) => item.id == ingredient.id || item.name.toLowerCase() == ingredient.name.toLowerCase(),
    );
    if (index == -1) {
      _ingredients.add(ingredient);
    } else {
      _ingredients[index] = ingredient;
    }
  }

  @override
  WeeklyConcernSession createWeeklySession({
    required String label,
    required DateTime weekStart,
    required List<StockConcernItem> concerns,
  }) {
    final existing = _findMatchingWeeklySession(
      label: label,
      weekStart: weekStart,
      concerns: concerns,
    );
    if (existing != null) {
      return existing;
    }
    final concernNames = concerns
        .map((item) => BatchGraphResolver.normalizeKey(item.ingredientName))
        .toSet();
    final targetIds = _recipes
        .where(
          (recipe) => BatchGraphResolver.cocktailUsesConcernIngredient(
            cocktail: recipe,
            concernNames: concernNames,
            batches: _batches,
            ingredientsByName: _ingredientsByName,
          ),
        )
        .map((recipe) => recipe.id)
        .toList();

    final session = WeeklyConcernSession(
      id: _nextId('week'),
      label: label,
      weekStart: weekStart,
      concerns: concerns,
      targetCocktailIds: targetIds,
      bartenderSales: const [],
      quizSessionIds: const [],
    );
    _weeklySessions.add(session);
    unawaited(
      _firestore
          .collection(FirestorePaths.stockConcernSessions(_venueId))
          .doc(session.id)
          .set(FirestoreSerializers.weeklySessionToMap(session)),
    );
    return session;
  }

  @override
  void saveBartenderSales({
    required String weekId,
    required String bartenderName,
    required List<BartenderSalesEntry> entries,
  }) {
    final index = _weeklySessions.indexWhere((session) => session.id == weekId);
    if (index == -1) {
      return;
    }
    final current = _weeklySessions[index];
    final sales = [...current.bartenderSales];
    final salesIndex = sales.indexWhere(
      (record) => record.bartenderName.toLowerCase() == bartenderName.toLowerCase(),
    );
    final updated = BartenderWeeklySales(
      bartenderName: bartenderName,
      entries: entries.where((entry) => entry.quantitySold > 0).toList(),
    );
    if (salesIndex == -1) {
      sales.add(updated);
    } else {
      sales[salesIndex] = updated;
    }
    _weeklySessions[index] = current.copyWith(bartenderSales: sales);
    final salesDocId = '$weekId-${bartenderName.toLowerCase().replaceAll(' ', '-')}';
    unawaited(
      _firestore
          .collection(FirestorePaths.bartenderSales(_venueId))
          .doc(salesDocId)
          .set(FirestoreSerializers.bartenderSalesToMap(weekId, updated)),
    );
  }

  @override
  QuizSession generateStockQuizSession({
    required String weekId,
    required String bartenderName,
  }) {
    final existing = _quizSessions.cast<QuizSession?>().firstWhere(
          (session) =>
              session != null &&
              session.weekId == weekId &&
              session.bartenderName.toLowerCase() == bartenderName.toLowerCase() &&
              session.isActive,
          orElse: () => null,
        );
    if (existing != null) {
      return existing;
    }
    final generated = _generateStockQuizLocally(weekId: weekId, bartenderName: bartenderName);
    final quiz = generated.copyWith(weekId: weekId);
    _quizSessions.add(quiz);
    final weeklyIndex = _weeklySessions.indexWhere((session) => session.id == weekId);
    if (weeklyIndex != -1) {
      final weeklySession = _weeklySessions[weeklyIndex];
      _weeklySessions[weeklyIndex] = weeklySession.copyWith(
        quizSessionIds: [...weeklySession.quizSessionIds, quiz.id],
      );
      unawaited(
        _firestore
            .collection(FirestorePaths.stockConcernSessions(_venueId))
            .doc(weekId)
            .set(
              FirestoreSerializers.weeklySessionToMap(_weeklySessions[weeklyIndex]),
            ),
      );
    }
    unawaited(
      _firestore
          .collection(FirestorePaths.quizSessions(_venueId))
          .doc(quiz.id)
          .set(FirestoreSerializers.quizSessionToMap(quiz)),
    );
    return quiz;
  }

  QuizSession _generateStockQuizLocally({
    required String weekId,
    required String bartenderName,
  }) {
    final adapter = LocalTrainingRepository();
    for (final ingredient in _ingredients) {
      adapter.saveIngredient(ingredient);
    }
    for (final batch in _batches) {
      adapter.saveBatch(batch);
    }
    for (final recipe in _recipes) {
      adapter.saveRecipe(recipe);
    }
    for (final session in _weeklySessions) {
      final cloned = adapter.createWeeklySession(
        label: session.label,
        weekStart: session.weekStart,
        concerns: session.concerns,
      );
      for (final sales in session.bartenderSales) {
        adapter.saveBartenderSales(
          weekId: cloned.id,
          bartenderName: sales.bartenderName,
          entries: sales.entries,
        );
      }
      if (session.id == weekId) {
        return adapter.generateStockQuizSession(
          weekId: cloned.id,
          bartenderName: bartenderName,
        );
      }
    }
    throw StateError('Weekly session not found for quiz generation.');
  }

  @override
  QuizSession generatePracticeQuizSession({
    required String bartenderName,
    List<String>? focusRecipeIds,
  }) {
    final adapter = LocalTrainingRepository();
    for (final ingredient in _ingredients) {
      adapter.saveIngredient(ingredient);
    }
    for (final batch in _batches) {
      adapter.saveBatch(batch);
    }
    for (final recipe in _recipes) {
      adapter.saveRecipe(recipe);
    }
    final quiz = adapter.generatePracticeQuizSession(
      bartenderName: bartenderName,
      focusRecipeIds: focusRecipeIds,
    );
    _quizSessions.add(quiz);
    unawaited(
      _firestore
          .collection(FirestorePaths.quizSessions(_venueId))
          .doc(quiz.id)
          .set(FirestoreSerializers.quizSessionToMap(quiz)),
    );
    return quiz;
  }

  @override
  QuizAttempt submitQuizAttempt({
    required String sessionId,
    required String bartenderName,
    required Map<String, String> answers,
  }) {
    final existingAttempt = _quizAttempts.cast<QuizAttempt?>().firstWhere(
          (attempt) =>
              attempt != null &&
              attempt.sessionId == sessionId &&
              attempt.bartenderName.toLowerCase() == bartenderName.toLowerCase(),
          orElse: () => null,
        );
    if (existingAttempt != null) {
      return existingAttempt;
    }
    final sessionIndex = _quizSessions.indexWhere((session) => session.id == sessionId);
    final session = _quizSessions[sessionIndex];
    if (!session.isActive) {
      throw Exception('This quiz session is no longer active. Ask your manager for a fresh link.');
    }
    final weeklySession = session.weekId == null
        ? null
        : _weeklySessions.firstWhere((item) => item.id == session.weekId);
    final sales = weeklySession?.bartenderSales.firstWhere(
          (record) => record.bartenderName.toLowerCase() == bartenderName.toLowerCase(),
          orElse: () => BartenderWeeklySales(bartenderName: bartenderName, entries: const []),
        ) ??
        BartenderWeeklySales(bartenderName: bartenderName, entries: const []);
    final quantityByCocktail = {
      for (final entry in sales.entries) entry.cocktailId: entry.quantitySold,
    };
    final ingredientsByName = {
      for (final ingredient in _ingredients)
        BatchGraphResolver.normalizeKey(ingredient.name): ingredient,
    };

    final responses = session.questions.map((question) {
      final selectedAnswer = answers[question.id] ?? '';
      final isCorrect = selectedAnswer == question.correctAnswer;
      final quantitySold = quantityByCocktail[question.cocktailId] ?? 0;
      double? deltaMl;
      if (question.kind == QuestionKind.ingredientMeasure &&
          question.correctMeasureMl != null) {
        final selectedMl = _parseMeasure(selectedAnswer);
        if (selectedMl != null) {
          deltaMl = selectedMl - question.correctMeasureMl!;
        }
      }
      return QuestionResponse(
        question: question,
        selectedAnswer: selectedAnswer,
        isCorrect: isCorrect,
        quantitySold: quantitySold,
        deltaMl: deltaMl,
      );
    }).toList();

    final attempt = VarianceMath.buildAttempt(
      attemptId: _nextId('attempt'),
      sessionId: session.id,
      weekId: session.weekId,
      bartenderName: bartenderName,
      responses: responses,
      ingredientsByName: ingredientsByName,
      batches: _batches,
    );

    _quizAttempts.add(attempt);
    _quizSessions[sessionIndex] = session.copyWith(isActive: false);
    unawaited(
      _firestore
          .collection(FirestorePaths.quizAttempts(_venueId))
          .doc(attempt.id)
          .set(FirestoreSerializers.quizAttemptToMap(attempt)),
    );
    unawaited(
      _firestore
          .collection(FirestorePaths.quizSessions(_venueId))
          .doc(session.id)
          .set(FirestoreSerializers.quizSessionToMap(_quizSessions[sessionIndex])),
    );
    final totalVarianceValue = attempt.overpourLines.fold<double>(
      0,
      (total, line) => total + line.approximateValue,
    ) +
        attempt.batchOverpourLines.fold<double>(
          0,
          (total, line) => total + line.approximateValue,
        );
    unawaited(
      _firestore
          .collection(FirestorePaths.trendSummaries(_venueId))
          .doc(bartenderName.toLowerCase().replaceAll(' ', '-'))
          .set(
            FirestoreSerializers.trendSummaryToMap(
              bartenderName: bartenderName,
              latestScorePercent: attempt.scorePercent,
              potentialVarianceValue: totalVarianceValue,
            ),
          ),
    );
    return attempt;
  }

  @override
  QuizSession? findQuizSession(String sessionId) {
    for (final session in _quizSessions) {
      if (session.id == sessionId && session.isActive) {
        return session;
      }
    }
    return null;
  }

  @override
  void deactivateQuizSession(String sessionId) {
    final index = _quizSessions.indexWhere((session) => session.id == sessionId);
    if (index == -1) {
      return;
    }
    _quizSessions[index] = _quizSessions[index].copyWith(isActive: false);
    unawaited(
      _firestore
          .collection(FirestorePaths.quizSessions(_venueId))
          .doc(sessionId)
          .set(FirestoreSerializers.quizSessionToMap(_quizSessions[index])),
    );
  }

  double? _parseMeasure(String answer) {
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(answer);
    return match == null ? null : double.tryParse(match.group(1)!);
  }

  String _nextId(String prefix) {
    _idCounter += 1;
    return '$prefix-$_idCounter';
  }

  WeeklyConcernSession? _findMatchingWeeklySession({
    required String label,
    required DateTime weekStart,
    required List<StockConcernItem> concerns,
  }) {
    final concernKey = concerns
        .map((item) => item.ingredientName.toLowerCase())
        .toList()
      ..sort();
    for (final session in _weeklySessions) {
      final sessionKey = session.concerns
          .map((item) => item.ingredientName.toLowerCase())
          .toList()
        ..sort();
      if (_sameDay(session.weekStart, weekStart) &&
          session.label.trim().toLowerCase() == label.trim().toLowerCase() &&
          '$sessionKey' == '$concernKey') {
        return session;
      }
    }
    return null;
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Map<String, Ingredient> get _ingredientsByName => {
        for (final ingredient in _ingredients)
          BatchGraphResolver.normalizeKey(ingredient.name): ingredient,
      };

  RecipeImportResult _normalizeImportResult(RecipeImportResult result) {
    final linkedDrafts = BatchGraphResolver.linkDrafts(result.drafts);
    return RecipeImportResult(
      sourceName: result.sourceName,
      drafts: linkedDrafts,
      warnings: result.warnings,
      requiresOcr: result.requiresOcr,
      rawText: result.rawText,
      pageCount: result.pageCount,
    );
  }
}
