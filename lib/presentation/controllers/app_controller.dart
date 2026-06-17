import 'dart:collection';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/config/app_environment.dart';
import '../../core/utils/batch_recipe_graph.dart';
import '../../core/utils/bundled_cocktail_catalog_loader.dart';
import '../../core/utils/commodity_csv_ingredient_importer.dart';
import '../../core/utils/curated_recipe_importer.dart';
import '../../core/utils/manager_trial_helpers.dart';
import '../../core/utils/recipe_review_validator.dart';
import '../../core/utils/recipe_text_parser.dart';
import '../../core/utils/sales_pdf_importer.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';

class AppController extends ChangeNotifier {
  AppController({
    required AuthRepository authRepository,
    required TrainingRepository trainingRepository,
    required AppEnvironment environment,
  }) : _authRepository = authRepository,
       _trainingRepository = trainingRepository,
       _environment = environment,
       _recipeTextParser = RecipeTextParser(),
       _curatedRecipeImporter = const CuratedRecipeImporter();

  final AuthRepository _authRepository;
  final TrainingRepository _trainingRepository;
  final AppEnvironment _environment;
  final RecipeTextParser _recipeTextParser;
  final CuratedRecipeImporter _curatedRecipeImporter;
  final CommodityCsvIngredientImporter _commodityCsvIngredientImporter =
      const CommodityCsvIngredientImporter();
  final SalesPdfImporter _salesPdfImporter = const SalesPdfImporter();

  bool _isBusy = false;
  String? _errorMessage;
  QuizAttempt? _latestAttempt;
  bool _usingFirebase = false;
  String? _successMessage;
  RecipeImportResult? _latestImportResult;
  CuratedImportPlan? _latestCuratedImportPlan;
  VerifiedRecipeSyncResult? _latestVerifiedSyncResult;
  CommodityIngredientImportResult? _latestCommodityIngredientImportResult;
  bool _didAutoPrepareCocktailList = false;
  List<AppUser> _venueUsers = const [];
  List<VenueInvite> _venueInvites = const [];
  List<CocktailRecipe> _bundledRecipes = const [];
  List<BatchRecipe> _bundledBatches = const [];
  List<Ingredient> _bundledIngredients = const [];
  Future<void>? _workspaceWarmFuture;

  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  AppUser? get currentUser => _authRepository.currentUser;
  bool get isDemoAuthMode => !_environment.hasFirebaseConfig;
  String get demoManagerEmail => _environment.demoManagerEmail;
  String get demoManagerPassword => _environment.demoManagerPassword;
  List<Ingredient> get ingredients {
    final merged = _mergedIngredients;
    return merged.isNotEmpty ? merged : _trainingRepository.ingredients;
  }

  List<CocktailRecipe> get recipes {
    final merged = _mergedRecipes;
    return merged.isNotEmpty ? merged : _trainingRepository.recipes;
  }

  List<BatchRecipe> get batches {
    final merged = _mergedBatches;
    return merged.isNotEmpty ? merged : _trainingRepository.batches;
  }

  List<WeeklyConcernSession> get weeklySessions =>
      _trainingRepository.weeklySessions;
  List<QuizSession> get quizSessions => _trainingRepository.quizSessions;
  List<QuizAttempt> get quizAttempts => _trainingRepository.quizAttempts;
  RecipeImportResult? get latestImportResult => _latestImportResult;
  QuizAttempt? get latestAttempt => _latestAttempt;
  bool get usingFirebase => _usingFirebase;
  String? get successMessage => _successMessage;
  CuratedImportPlan? get latestCuratedImportPlan => _latestCuratedImportPlan;
  VerifiedRecipeSyncResult? get latestVerifiedSyncResult =>
      _latestVerifiedSyncResult;
  CommodityIngredientImportResult? get latestCommodityIngredientImportResult =>
      _latestCommodityIngredientImportResult;
  bool get didAutoPrepareCocktailList => _didAutoPrepareCocktailList;
  List<AppUser> get venueUsers => List.unmodifiable(_venueUsers);
  List<VenueInvite> get venueInvites => List.unmodifiable(_venueInvites);
  List<QuizAttempt> get personalQuizAttempts {
    final user = currentUser;
    if (user == null) {
      return const [];
    }
    final byUserId = quizAttempts
        .where((attempt) => attempt.userId == user.id)
        .toList();
    if (byUserId.isNotEmpty) {
      return List.unmodifiable(byUserId);
    }
    final normalizedName = user.displayName.trim().toLowerCase();
    return List.unmodifiable(
      quizAttempts.where(
        (attempt) => attempt.bartenderName.trim().toLowerCase() == normalizedName,
      ),
    );
  }
  String get appBuildLabel => _environment.appBuildLabel;
  String get appBuildTimestamp => _environment.appBuildTimestamp;
  String get appVersionLabel => _environment.appVersionLabel;
  String get buildMarker => _environment.buildMarker;
  String get runtimeModeLabel =>
      usingFirebase ? 'Firebase mode (Auth + Firestore)' : 'Demo mode';
  String get backendProfileLabel => usingFirebase
      ? 'Cloudflare Pages + Firebase Auth + Firestore (Spark-friendly target)'
      : 'Local browser-only demo data';
  String get catalogPathLabel => 'Library/Study direct JSON path active';
  bool get allowOwnerBootstrap => _environment.allowOwnerBootstrap;
  int get bundledRecipeCount => _bundledRecipes.length;
  int get bundledBatchCount => _bundledBatches.length;
  bool get bundledCatalogLoaded => _bundledRecipes.isNotEmpty;
  bool get isOwnerAuthenticated => currentUser?.role == UserRole.owner;
  bool get isManagerAuthenticated =>
      currentUser?.role.includes(UserRole.manager) ?? false;
  bool get isBartenderAuthenticated =>
      currentUser?.role.includes(UserRole.bartender) ?? false;
  bool get canAccessBartenderWorkflows =>
      currentUser?.role.canAccessBartenderWorkflows ?? false;
  bool get canAccessAdminSetup =>
      currentUser?.role.canAccessAdminSetup ?? false;
  bool get canAccessManagerWorkflows =>
      currentUser?.role.canAccessManagerWorkflows ?? false;
  bool get canManageVenueInvites => canAccessManagerWorkflows;
  bool get canAccessApprovedLibrary =>
      currentUser != null || recipes.isNotEmpty;
  bool get needsVenueOnboarding =>
      canAccessManagerWorkflows &&
      currentUser!.venueId.trim().isEmpty;

  List<CocktailRecipe> get _mergedRecipes {
    if (_bundledRecipes.isEmpty) {
      return _trainingRepository.recipes;
    }
    if (_trainingRepository.recipes.isEmpty) {
      return _bundledRecipes;
    }
    final overrides = {
      for (final recipe in _trainingRepository.recipes) recipe.id: recipe,
    };
    final merged = [
      for (final recipe in _bundledRecipes) overrides[recipe.id] ?? recipe,
      ..._trainingRepository.recipes.where(
        (recipe) => !_bundledRecipes.any((bundled) => bundled.id == recipe.id),
      ),
    ];
    return List.unmodifiable(merged);
  }

  List<BatchRecipe> get _mergedBatches {
    if (_bundledBatches.isEmpty) {
      return _trainingRepository.batches;
    }
    if (_trainingRepository.batches.isEmpty) {
      return _bundledBatches;
    }
    final overrides = {
      for (final batch in _trainingRepository.batches) batch.id: batch,
    };
    final merged = [
      for (final batch in _bundledBatches) overrides[batch.id] ?? batch,
      ..._trainingRepository.batches.where(
        (batch) => !_bundledBatches.any((bundled) => bundled.id == batch.id),
      ),
    ];
    return List.unmodifiable(merged);
  }

  List<Ingredient> get _mergedIngredients {
    if (_bundledIngredients.isEmpty) {
      return _trainingRepository.ingredients;
    }
    if (_trainingRepository.ingredients.isEmpty) {
      return _bundledIngredients;
    }
    final overridesByName = {
      for (final ingredient in _trainingRepository.ingredients)
        BatchGraphResolver.normalizeKey(ingredient.name): ingredient,
    };
    final merged = [
      for (final ingredient in _bundledIngredients)
        overridesByName[BatchGraphResolver.normalizeKey(ingredient.name)] ??
            ingredient,
      ..._trainingRepository.ingredients.where(
        (ingredient) => !_bundledIngredients.any(
          (bundled) =>
              BatchGraphResolver.normalizeKey(bundled.name) ==
              BatchGraphResolver.normalizeKey(ingredient.name),
        ),
      ),
    ];
    return List.unmodifiable(merged);
  }

  Future<void> initialize({bool usingFirebase = false}) async {
    _usingFirebase = usingFirebase;
    _logStartup('Startup begin runtime=$runtimeModeLabel');
    try {
      await _ensureBundledCatalogReady();
    } catch (error, stackTrace) {
      _logStartup(
        'Bundled cocktail catalog preload failed',
        error: error,
        stackTrace: stackTrace,
      );
      _errorMessage ??= _friendlyTrainingDataMessage(error);
    }
    try {
      await _authRepository.initialize();
      _logStartup(
        'Auth initialize complete user=${currentUser?.email ?? '<signed-out>'} role=${currentUser?.role.name ?? '<none>'}',
      );
    } catch (error, stackTrace) {
      _logStartup(
        'Auth initialize failed',
        error: error,
        stackTrace: stackTrace,
      );
      _errorMessage = _friendlyStartupMessage(error);
      try {
        await _authRepository.signOut();
      } catch (_) {}
    }
    _trainingRepository.configureVenue(
      currentUser?.venueId ?? _environment.defaultVenueId,
    );
    try {
      await _trainingRepository.initialize();
      _logStartup(
        'Cocktail list load complete cocktails=${recipes.length} batches=${batches.length} ingredients=${ingredients.length}',
      );
    } catch (error, stackTrace) {
      _logStartup(
        'Cocktail list load failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (_bundledRecipes.isEmpty) {
        _errorMessage ??= _friendlyTrainingDataMessage(error);
      }
    }
    await _loadRoleScopedTrainingData();
    await _primeVerifiedRecipeSet();
    _latestImportResult = _trainingRepository.latestImportResult;
    _latestCuratedImportPlan = null;
    notifyListeners();
  }

  Future<void> _ensureBundledCatalogReady() async {
    if (_bundledRecipes.isNotEmpty) {
      return;
    }
    final catalog = await BundledCocktailCatalogLoader.load();
    _bundledRecipes = List.unmodifiable(catalog.recipes);
    _bundledBatches = List.unmodifiable(catalog.batches);
    _bundledIngredients = List.unmodifiable(
      _buildBundledIngredients(
        recipes: catalog.recipes,
        batches: catalog.batches,
      ),
    );
    _logStartup(
      'Bundled cocktail catalog ready cocktails=${_bundledRecipes.length} batches=${_bundledBatches.length} first=${_bundledRecipes.isEmpty ? '<none>' : _bundledRecipes.first.name}',
    );
  }

  List<Ingredient> _buildBundledIngredients({
    required List<CocktailRecipe> recipes,
    required List<BatchRecipe> batches,
  }) {
    final names = <String>{
      for (final recipe in recipes)
        ...recipe.ingredients
            .map((item) => item.ingredientName.trim())
            .where((name) => name.isNotEmpty),
      for (final batch in batches)
        ...batch.ingredients
            .map((item) => item.ingredientName.trim())
            .where((name) => name.isNotEmpty),
    }.toList()..sort();
    return [
      for (final name in names)
        Ingredient(
          id: 'bundled-${BatchGraphResolver.normalizeKey(name)}',
          name: name,
          bottleSizeMl: 0,
          bottleCost: 0,
        ),
    ];
  }

  Future<bool> createManagerAccount({
    required String email,
    required String password,
    required String displayName,
    required String venueName,
  }) async {
    return _wrapBusy(() async {
      _successMessage = null;
      final user = await _authRepository.createManagerAccount(
        email: email,
        password: password,
        displayName: displayName,
        venueName: venueName,
      );
      await _completeSignedInSetup(user);
      _successMessage =
          'Welcome to $venueName. Your venue workspace is ready when you are.';
      return true;
    });
  }

  Future<bool> signInManager({
    required String email,
    required String password,
  }) async {
    return _wrapBusy(() async {
      _successMessage = null;
      final user = await _authRepository.signInManager(
        email: email,
        password: password,
      );
      await _completeSignedInSetup(user);
      _successMessage = switch (user.role) {
        UserRole.owner =>
          'You are signed in. Cocktail training, team progress, and invite tools are ready.',
        UserRole.manager =>
          'You are signed in. Team learning and invite tools are ready.',
        UserRole.bartender =>
          'You are signed in. Cocktail training is ready whenever you want a refresher.',
      };
      return true;
    });
  }

  Future<void> createVenueManagerAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await _wrapBusy(() async {
      _requireOwnerAccess(
        'Only the owner/admin can set up additional venue manager accounts.',
      );
      final owner = currentUser!;
      await _authRepository.createVenueManagerAccount(
        venueId: owner.venueId,
        venueName: owner.venueName,
        email: email,
        password: password,
        displayName: displayName,
      );
      await _refreshVenueUsersIfNeeded(force: true);
      _successMessage =
          '$displayName can now sign in as a venue manager for ${owner.venueName}.';
    });
  }

  Future<VenueInvite> createVenueInvite({
    required UserRole role,
    required DateTime expiresAt,
    required int maxUses,
  }) async {
    return _wrapBusy(() async {
      _requireInviteManagementAccess(
        'Only the owner/admin or a venue manager can create invite links.',
      );
      final actor = currentUser!;
      if (role == UserRole.owner) {
        throw Exception(
          'Owner/admin access is issued separately and cannot be created from venue invites.',
        );
      }
      final invite = await _authRepository.createVenueInvite(
        venueId: actor.venueId,
        role: role,
        createdBy: actor.id,
        expiresAt: expiresAt,
        maxUses: maxUses,
      );
      await _refreshVenueInvitesIfNeeded(force: true);
      _successMessage =
          '${role.name[0].toUpperCase()}${role.name.substring(1)} invite ready for ${actor.venueName}.';
      return invite;
    });
  }

  Future<void> setVenueInviteDisabled({
    required String inviteId,
    required bool disabled,
  }) async {
    await _wrapBusy(() async {
      _requireInviteManagementAccess(
        'Only the owner/admin or a venue manager can update invite links.',
      );
      await _authRepository.setVenueInviteDisabled(
        venueId: currentUser!.venueId,
        inviteId: inviteId,
        disabled: disabled,
      );
      await _refreshVenueInvitesIfNeeded(force: true);
      _successMessage = disabled
          ? 'Invite paused. New teammates will not be able to use it until it is switched back on.'
          : 'Invite is live again and ready to share.';
    });
  }

  Future<void> deleteVenueInvite({required String inviteId}) async {
    await _wrapBusy(() async {
      _requireInviteManagementAccess(
        'Only the owner/admin or a venue manager can delete invite links.',
      );
      await _authRepository.deleteVenueInvite(
        venueId: currentUser!.venueId,
        inviteId: inviteId,
      );
      await _refreshVenueInvitesIfNeeded(force: true);
      _successMessage = 'Invite deleted.';
    });
  }

  Future<VenueInvite?> fetchVenueInvite({
    required String venueId,
    required String inviteId,
  }) {
    return _authRepository.fetchVenueInvite(
      venueId: venueId,
      inviteId: inviteId,
    );
  }

  Future<bool> redeemVenueInvite({
    required String venueId,
    required String inviteId,
    required String email,
    required String password,
    required String displayName,
  }) async {
    return _wrapBusy(() async {
      _successMessage = null;
      final user = await _authRepository.redeemVenueInvite(
        venueId: venueId,
        inviteId: inviteId,
        email: email,
        password: password,
        displayName: displayName,
      );
      await _completeSignedInSetup(user);
      _successMessage = switch (user.role) {
        UserRole.owner =>
          'You are signed in. Cocktail training, team progress, and invite tools are ready.',
        UserRole.manager =>
          'You are signed in. Team learning and invite tools are ready.',
        UserRole.bartender =>
          'You are signed in. Cocktail training is ready whenever you want a refresher.',
      };
      return true;
    });
  }

  Future<void> setVenueUserActive({
    required String userId,
    required bool active,
  }) async {
    await _wrapBusy(() async {
      _requireOwnerAccess(
        'Only the owner/admin can manage venue staff access.',
      );
      await _authRepository.setVenueUserActive(
        venueId: currentUser!.venueId,
        userId: userId,
        active: active,
      );
      await _refreshVenueUsersIfNeeded(force: true);
      _successMessage = active
          ? 'Venue staff access restored.'
          : 'Venue staff access paused.';
    });
  }

  Future<void> deleteVenueUser({required String userId}) async {
    await _wrapBusy(() async {
      _requireOwnerAccess('Only the owner/admin can remove staff access.');
      if (currentUser?.id == userId) {
        throw Exception(
          'You cannot remove the account you are currently using.',
        );
      }
      await _authRepository.deleteVenueUser(
        venueId: currentUser!.venueId,
        userId: userId,
      );
      await _refreshVenueUsersIfNeeded(force: true);
      _successMessage = 'Staff access has been removed for this venue.';
    });
  }

  Future<void> sendPasswordReset({required String email}) async {
    await _wrapBusy(() async {
      await _authRepository.sendPasswordReset(email: email);
      _successMessage =
          'If that address is linked to an account, a password reset link is on its way.';
    });
  }

  Future<void> signOut() async {
    await _wrapBusy(() async {
      await _authRepository.signOut();
      _trainingRepository.configureVenue(_environment.defaultVenueId);
      await _trainingRepository.initialize();
      _workspaceWarmFuture = null;
      _latestAttempt = null;
      _venueUsers = const [];
      _venueInvites = const [];
      _successMessage = 'Signed out successfully.';
    });
  }

  Future<void> _completeSignedInSetup(AppUser user) async {
    _trainingRepository.configureVenue(user.venueId);
    await _trainingRepository.initialize();
    await _loadRoleScopedTrainingData();
    await _primeVerifiedRecipeSet();
    _workspaceWarmFuture = null;
    _latestAttempt = null;
    _venueUsers = const [];
    _venueInvites = const [];
  }

  Future<void> warmWorkspaceDataIfNeeded({bool force = false}) {
    if (!canAccessManagerWorkflows) {
      return Future.value();
    }
    if (force) {
      _workspaceWarmFuture = null;
    }
    return _workspaceWarmFuture ??= _warmWorkspaceDataInternal();
  }

  Future<void> _warmWorkspaceDataInternal() async {
    try {
      await _trainingRepository.loadManagerData();
      if (canAccessAdminSetup) {
        await _trainingRepository.loadAdminData();
      }
      _logStartup(
        'Workspace data warm load complete sessions=${weeklySessions.length} quizzes=${quizSessions.length} attempts=${quizAttempts.length}',
      );
    } catch (error, stackTrace) {
      _logStartup(
        'Workspace data warm load failed',
        error: error,
        stackTrace: stackTrace,
      );
    }

    try {
      await _refreshVenueUsersIfNeeded(force: true);
    } catch (error, stackTrace) {
      _logStartup(
        'Venue teammate warm load failed',
        error: error,
        stackTrace: stackTrace,
      );
    }

    try {
      await _refreshVenueInvitesIfNeeded(force: true);
    } catch (error, stackTrace) {
      _logStartup(
        'Venue invite warm load failed',
        error: error,
        stackTrace: stackTrace,
      );
    }

    notifyListeners();
  }

  RecipeImportDraft? parseRecipeFromText(String source) {
    _requireOwnerAccess(
      'Only the owner/admin can check or tidy imported specs.',
    );
    return _recipeTextParser.parseSingleRecipe(
      source: source,
      fallbackId: 'recipe-${DateTime.now().microsecondsSinceEpoch}',
      sourceName: 'Manual entry',
    );
  }

  Future<RecipeImportResult> importPdf({
    required Uint8List bytes,
    required String fileName,
  }) async {
    _requireOwnerAccess('Only the owner/admin can import recipe specs.');
    final result = await _wrapBusy(
      () => _trainingRepository.extractRecipesFromPdf(
        bytes: bytes,
        fileName: fileName,
      ),
    );
    _latestImportResult = result;
    _latestCuratedImportPlan = null;
    notifyListeners();
    return result;
  }

  RecipeImportResult importFromOcrText({
    required String text,
    required String sourceName,
  }) {
    _requireOwnerAccess('Only the owner/admin can import OCR recipe specs.');
    final result = _trainingRepository.extractRecipesFromText(
      text: text,
      sourceName: sourceName,
    );
    _latestImportResult = result;
    _latestCuratedImportPlan = null;
    notifyListeners();
    return result;
  }

  Future<CuratedImportPlan> importCuratedSpecs({
    required CuratedImportConflictMode conflictMode,
  }) async {
    _requireOwnerAccess('Only the owner/admin can import curated specs.');
    final plan = await _wrapBusy(() async {
      final jsonText = await rootBundle.loadString(
        CuratedRecipeImporter.assetPath,
      );
      final batchJsonText = await rootBundle.loadString(
        CuratedRecipeImporter.batchAssetPath,
      );
      return _curatedRecipeImporter.buildPlan(
        cocktailJsonText: jsonText,
        batchJsonText: batchJsonText,
        existingRecipes: _trainingRepository.recipes,
        existingBatches: _trainingRepository.batches,
        conflictMode: conflictMode,
      );
    });
    _latestCuratedImportPlan = plan;
    _latestImportResult = plan.importResult;
    notifyListeners();
    return plan;
  }

  Future<VerifiedRecipeSyncResult> syncVerifiedRecipes({
    bool overwriteExisting = false,
  }) async {
    _requireOwnerAccess(
      'Only the owner/admin can refresh the accepted cocktail list.',
    );
    final result = await _wrapBusy(() async {
      final jsonText = await rootBundle.loadString(
        CuratedRecipeImporter.cocktailAssetPath,
      );
      final batchJsonText = await rootBundle.loadString(
        CuratedRecipeImporter.batchAssetPath,
      );
      final catalog = _curatedRecipeImporter.buildVerifiedCatalog(
        cocktailJsonText: jsonText,
        batchJsonText: batchJsonText,
      );
      return _trainingRepository.syncVerifiedRecipes(
        recipes: catalog.recipes,
        batches: catalog.batches,
        overwriteExisting: overwriteExisting,
      );
    });
    _latestVerifiedSyncResult = result;
    _didAutoPrepareCocktailList = false;
    _latestImportResult = null;
    _latestCuratedImportPlan = null;
    _successMessage =
        'Accepted cocktail list refreshed. ${result.cocktailsAdded + result.cocktailsUpdated + result.cocktailsSkipped} cocktail spec${result.cocktailsAdded + result.cocktailsUpdated + result.cocktailsSkipped == 1 ? '' : 's'} and ${result.batchesAdded + result.batchesUpdated + result.batchesSkipped} batch spec${result.batchesAdded + result.batchesUpdated + result.batchesSkipped == 1 ? '' : 's'} are ready for training.';
    notifyListeners();
    return result;
  }

  Future<void> _primeVerifiedRecipeSet() async {
    if (currentUser == null) {
      return;
    }
    _didAutoPrepareCocktailList = false;
    if (recipes.isEmpty) {
      try {
        final recovered = await _trainingRepository
            .ensureBundledCatalogLoaded();
        if (recovered) {
          _didAutoPrepareCocktailList = true;
          _logStartup(
            'Cocktail list recovered from bundled catalog cocktails=${recipes.length} batches=${batches.length}',
          );
          return;
        }
      } catch (error, stackTrace) {
        _logStartup(
          'Bundled cocktail catalog recovery failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
      developer.log(
        'The shared cocktail list was not available during startup.',
        name: 'AppController',
        level: 900,
        error: StateError('No cocktails loaded'),
      );
      _errorMessage ??=
          'The cocktail list is not ready yet. Refresh the app in a moment if it does not appear.';
    }
  }

  void _logStartup(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: 'AppControllerStartup',
      level: error == null ? 800 : 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void clearImportPreview() {
    _requireOwnerAccess(
      'Only the owner/admin can clear or replace spec review drafts.',
    );
    _trainingRepository.clearImportPreview();
    _latestImportResult = null;
    _latestCuratedImportPlan = null;
    notifyListeners();
  }

  RecipeImportDraft approveImportDraft(RecipeImportDraft draft) {
    _requireOwnerAccess('Only the owner/admin can approve recipes or batches.');
    final review = RecipeReviewValidator.inspectDraft(draft);
    if (!review.canApprove) {
      throw Exception(
        'This spec still has a few details to resolve before it can be approved.',
      );
    }
    debugPrint(
      '[RecipeImport] Approving draft id=${draft.id} name="${draft.name}" confidence=${review.confidence.name}',
    );
    return draft.copyWith(
      status: RecipeDraftStatus.approved,
      wasManuallyReviewed: true,
    );
  }

  RecipeImportDraft keepImportDraftInReview(RecipeImportDraft draft) {
    _requireOwnerAccess('Only the owner/admin can review imported specs.');
    debugPrint(
      '[RecipeImport] Keeping draft in review id=${draft.id} name="${draft.name}"',
    );
    return draft.copyWith(
      status: RecipeDraftStatus.pending,
      wasManuallyReviewed: true,
    );
  }

  RecipeImportDraft deleteImportDraft(RecipeImportDraft draft) {
    _requireOwnerAccess('Only the owner/admin can remove import drafts.');
    debugPrint(
      '[RecipeImport] Deleting draft id=${draft.id} name="${draft.name}"',
    );
    return draft.copyWith(
      status: RecipeDraftStatus.deleted,
      wasManuallyReviewed: true,
    );
  }

  Future<void> saveImportedDrafts(List<RecipeImportDraft> drafts) async {
    _requireOwnerAccess('Only the owner/admin can publish approved specs.');
    final approvedCount = drafts
        .where((draft) => draft.status == RecipeDraftStatus.approved)
        .length;
    final pendingCount = drafts
        .where((draft) => draft.status == RecipeDraftStatus.pending)
        .length;
    final deletedCount = drafts
        .where((draft) => draft.status == RecipeDraftStatus.deleted)
        .length;
    debugPrint(
      '[RecipeImport] Save requested approved=$approvedCount pending=$pendingCount deleted=$deletedCount',
    );
    await _wrapBusy(() async {
      await _trainingRepository.saveImportedDrafts(drafts);
      _latestImportResult = _trainingRepository.latestImportResult;
      if (_latestImportResult == null) {
        _latestCuratedImportPlan = null;
      }
    });
    debugPrint(
      '[RecipeImport] Save finished approved=$approvedCount pending=$pendingCount',
    );
    notifyListeners();
  }

  Future<void> saveIngredient({
    required String name,
    required double bottleSizeMl,
    required double bottleCost,
    bool isGarnish = false,
  }) async {
    _requireOwnerAccess('Only the owner/admin can manage ingredient pricing.');
    final existing = ingredients.cast<Ingredient?>().firstWhere(
      (item) => item!.name.toLowerCase() == name.toLowerCase(),
      orElse: () => null,
    );
    await _wrapBusy(() async {
      await _trainingRepository.saveIngredient(
        Ingredient(
          id:
              existing?.id ??
              'ingredient-${DateTime.now().microsecondsSinceEpoch}',
          name: name,
          bottleSizeMl: bottleSizeMl,
          bottleCost: bottleCost,
          isGarnish: isGarnish,
        ),
      );
      _successMessage = 'Saved ingredient pricing for $name.';
    });
  }

  Future<CommodityIngredientImportResult> importIngredientCostsFromCommodityCsv(
    String csvText,
  ) async {
    _requireOwnerAccess('Only the owner/admin can manage ingredient pricing.');
    return _wrapBusy(() async {
      final result = _commodityCsvIngredientImporter.buildImportPlan(
        csvText: csvText,
        ingredients: ingredients,
        recipes: recipes,
        batches: batches,
      );
      for (final match in result.matchedIngredients) {
        await _trainingRepository.saveIngredient(match.ingredient);
      }
      _latestCommodityIngredientImportResult = result;
      _successMessage =
          'Imported ${result.matchedIngredients.length} ingredient prices from the commodity CSV.';
      return result;
    }).then((result) {
      notifyListeners();
      return result;
    });
  }

  void saveRecipe(CocktailRecipe recipe) {
    _requireOwnerAccess(
      'Only the owner/admin can edit official cocktail specs.',
    );
    _trainingRepository.saveRecipe(recipe);
    notifyListeners();
  }

  void saveBatch(BatchRecipe batch) {
    _requireOwnerAccess('Only the owner/admin can edit approved batch specs.');
    _trainingRepository.saveBatch(batch);
    notifyListeners();
  }

  WeeklyConcernSession createWeeklySession({
    required String label,
    required DateTime weekStart,
    required List<StockConcernItem> concerns,
  }) {
    _requireOperationalAccess(
      'Only the owner/admin or a venue manager can create stock-focus sessions.',
    );
    final result = _trainingRepository.createWeeklySession(
      label: label,
      weekStart: weekStart,
      concerns: concerns,
    );
    notifyListeners();
    return result;
  }

  void saveBartenderSales({
    required String weekId,
    required String bartenderName,
    required List<BartenderSalesEntry> entries,
  }) {
    _requireOperationalAccess(
      'Only the owner/admin or a venue manager can enter bartender sales.',
    );
    _trainingRepository.saveBartenderSales(
      weekId: weekId,
      bartenderName: bartenderName,
      entries: entries,
    );
    notifyListeners();
  }

  SalesPdfImportPreview importBartenderSalesPdf({
    required Uint8List bytes,
    required String fileName,
    required String weekId,
    required String bartenderName,
  }) {
    _requireOperationalAccess(
      'Only the owner/admin or a venue manager can import bartender sales from a PDF.',
    );
    final session = findWeeklySession(weekId);
    if (session == null) {
      throw Exception(
        'The selected stock-focus session could not be found. Create or refresh the session before importing sales.',
      );
    }
    return _salesPdfImporter.extractForBartender(
      bytes: bytes,
      fileName: fileName,
      bartenderName: bartenderName,
      session: session,
      approvedRecipes: recipes,
    );
  }

  QuizSession generateStockQuiz({
    required String weekId,
    required String bartenderName,
    QuizFocus focus = QuizFocus.specs,
  }) {
    _requireOperationalAccess(
      'Only the owner/admin or a venue manager can launch stock practice sessions.',
    );
    final session = _trainingRepository.generateStockQuizSession(
      weekId: weekId,
      bartenderName: bartenderName,
      focus: focus,
    );
    notifyListeners();
    return session;
  }

  QuizSession generatePracticeQuiz({
    required String bartenderName,
    List<String>? focusRecipeIds,
    QuizFocus focus = QuizFocus.specs,
  }) {
    final session = _trainingRepository.generatePracticeQuizSession(
      bartenderName: bartenderName,
      focusRecipeIds: focusRecipeIds,
      focus: focus,
    );
    notifyListeners();
    return session;
  }

  QuizSession? findQuizSession(String sessionId) {
    return _trainingRepository.findQuizSession(sessionId);
  }

  Future<QuizSession?> fetchQuizSession(String sessionId) {
    return _trainingRepository.fetchQuizSession(sessionId);
  }

  void deactivateQuizSession(String sessionId) {
    _requireOperationalAccess(
      'Only the owner/admin or a venue manager can close live practice sessions.',
    );
    _trainingRepository.deactivateQuizSession(sessionId);
    notifyListeners();
  }

  QuizAttempt submitQuizAttempt({
    required String sessionId,
    required String bartenderName,
    required Map<String, String> answers,
  }) {
    final attempt = _trainingRepository.submitQuizAttempt(
      sessionId: sessionId,
      userId: currentUser?.id,
      bartenderName: bartenderName,
      answers: answers,
    );
    _latestAttempt = attempt;
    notifyListeners();
    return attempt;
  }

  WeeklyConcernSession? findWeeklySession(String id) {
    for (final session in weeklySessions) {
      if (session.id == id) {
        return session;
      }
    }
    return null;
  }

  Map<String, CocktailRecipe> get recipesById =>
      UnmodifiableMapView({for (final recipe in recipes) recipe.id: recipe});

  List<String> get concernIngredientNames {
    final names = <String>{
      for (final recipe in recipes)
        ...recipe.ingredients
            .map((ingredient) => ingredient.ingredientName.trim())
            .where((name) => name.isNotEmpty),
      for (final batch in batches)
        ...batch.ingredients
            .map((ingredient) => ingredient.ingredientName.trim())
            .where((name) => name.isNotEmpty),
    }.toList()..sort();
    return names;
  }

  List<CocktailRecipe> relevantRecipesForConcernNames(
    Iterable<String> concernNames,
  ) {
    final normalized = concernNames.map((name) => name.toLowerCase()).toSet();
    return recipes
        .where(
          (recipe) => BatchGraphResolver.cocktailUsesConcernIngredient(
            cocktail: recipe,
            concernNames: normalized
                .map(BatchGraphResolver.normalizeKey)
                .toSet(),
            batches: batches,
            ingredientsByName: {
              for (final ingredient in ingredients)
                BatchGraphResolver.normalizeKey(ingredient.name): ingredient,
            },
          ),
        )
        .toList();
  }

  Map<String, List<CocktailRecipe>> relevantRecipesGroupedByConcern(
    WeeklyConcernSession session,
  ) {
    final grouped = <String, List<CocktailRecipe>>{};
    for (final concern in session.concerns) {
      grouped[concern.ingredientName] = recipes
          .where(
            (recipe) => BatchGraphResolver.cocktailUsesConcernIngredient(
              cocktail: recipe,
              concernNames: {
                BatchGraphResolver.normalizeKey(concern.ingredientName),
              },
              batches: batches,
              ingredientsByName: {
                for (final ingredient in ingredients)
                  BatchGraphResolver.normalizeKey(ingredient.name): ingredient,
              },
            ),
          )
          .toList();
    }
    return grouped;
  }

  List<CocktailRecipe> searchRecipes(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return recipes;
    }
    return recipes
        .where(
          (recipe) =>
              recipe.name.toLowerCase().contains(normalized) ||
              recipe.category.toLowerCase().contains(normalized) ||
              recipe.ingredients.any(
                (ingredient) => ingredient.ingredientName
                    .toLowerCase()
                    .contains(normalized),
              ),
        )
        .toList();
  }

  List<CocktailRecipe> weakAreaRecipeSuggestions() {
    final counts = <String, int>{};
    for (final attempt in quizAttempts) {
      for (final response in attempt.responses.where(
        (item) => !item.isCorrect,
      )) {
        counts.update(
          response.question.cocktailId,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }
    final ids = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ids
        .map((entry) => recipesById[entry.key])
        .whereType<CocktailRecipe>()
        .take(6)
        .toList();
  }

  RecipeDraftCounts draftCounts(List<RecipeImportDraft> drafts) {
    return ManagerTrialHelpers.countDrafts(drafts);
  }

  List<RecipeImportDraft> filterDrafts({
    required List<RecipeImportDraft> drafts,
    String query = '',
    RecipeConfidence? confidence,
    String? category,
    bool includeDeleted = false,
  }) {
    return ManagerTrialHelpers.filterDrafts(
      drafts: drafts,
      query: query,
      confidence: confidence,
      category: category,
      includeDeleted: includeDeleted,
    );
  }

  SalesValidationResult validateBartenderSales({
    required WeeklyConcernSession session,
    required String bartenderName,
    required Map<String, String> rawQuantitiesByCocktailId,
  }) {
    return ManagerTrialHelpers.validateBartenderSales(
      session: session,
      bartenderName: bartenderName,
      rawQuantitiesByCocktailId: rawQuantitiesByCocktailId,
    );
  }

  StockWorkflowProgress stockWorkflowProgress(WeeklyConcernSession? session) {
    return ManagerTrialHelpers.buildStockWorkflowProgress(
      session: session,
      quizSessions: quizSessions,
      quizAttempts: quizAttempts,
    );
  }

  DashboardViewData buildDashboard() {
    final attempts = quizAttempts;
    final latestPerBartender = <String, QuizAttempt>{};
    final potentialVarianceByIngredient = <String, double>{};
    final potentialVarianceByBatch = <String, double>{};
    final potentialVarianceByBartender = <String, double>{};
    final misunderstoodCocktails = <String, int>{};
    final trainingFocusAreas = <String, int>{};
    final underpourOpportunities = <String, double>{};
    final quizCompletionStatus = <String, String>{};
    final weeklyConfidence = <String, int>{};
    final ingredientConfidenceByWeek = <String, Map<String, int>>{};
    final bartenderAverageScores = <String, int>{};
    final ingredientMisses = <String, int>{};
    final bartenderAttempts = <String, List<QuizAttempt>>{};

    for (final attempt in attempts) {
      latestPerBartender.putIfAbsent(attempt.bartenderName, () => attempt);
      bartenderAttempts
          .putIfAbsent(attempt.bartenderName, () => [])
          .add(attempt);
      final bartenderTotal =
          attempt.overpourLines.fold<double>(
            0,
            (sum, line) => sum + line.approximateValue,
          ) +
          attempt.batchOverpourLines.fold<double>(
            0,
            (sum, line) => sum + line.approximateValue,
          );
      potentialVarianceByBartender.update(
        attempt.bartenderName,
        (value) => value + bartenderTotal,
        ifAbsent: () => bartenderTotal,
      );

      for (final line in attempt.overpourLines) {
        potentialVarianceByIngredient.update(
          line.ingredientName,
          (value) => value + line.approximateValue,
          ifAbsent: () => line.approximateValue,
        );
      }
      for (final line in attempt.batchOverpourLines) {
        potentialVarianceByBatch.update(
          line.ingredientName,
          (value) => value + line.totalMl,
          ifAbsent: () => line.totalMl,
        );
      }
      for (final line in attempt.underpourLines) {
        underpourOpportunities.update(
          line.ingredientName,
          (value) => value + line.totalMl,
          ifAbsent: () => line.totalMl,
        );
      }

      for (final response in attempt.responses.where(
        (item) => !item.isCorrect,
      )) {
        misunderstoodCocktails.update(
          response.question.cocktailName,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
        trainingFocusAreas.update(
          response.question.kind.name,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
        if ((response.question.ingredientName ?? '').trim().isNotEmpty) {
          ingredientMisses.update(
            response.question.ingredientName!.trim(),
            (value) => value + 1,
            ifAbsent: () => 1,
          );
        }
      }

      if (attempt.weekId != null) {
        final label =
            findWeeklySession(attempt.weekId!)?.label ?? attempt.weekId!;
        weeklyConfidence.update(
          label,
          (value) => ((value + attempt.scorePercent) / 2).round(),
          ifAbsent: () => attempt.scorePercent,
        );
        final ingredientWeekMap = ingredientConfidenceByWeek.putIfAbsent(
          label,
          () => {},
        );
        final ingredientStats = <String, List<bool>>{};
        for (final response in attempt.responses.where(
          (item) =>
              item.question.kind == QuestionKind.ingredientMeasure &&
              (item.question.ingredientName ?? '').trim().isNotEmpty,
        )) {
          ingredientStats
              .putIfAbsent(response.question.ingredientName!.trim(), () => [])
              .add(response.isCorrect);
        }
        ingredientStats.forEach((ingredient, values) {
          final percent =
              ((values.where((item) => item).length / values.length) * 100)
                  .round();
          ingredientWeekMap.update(
            ingredient,
            (existing) => ((existing + percent) / 2).round(),
            ifAbsent: () => percent,
          );
        });
      }
    }

    bartenderAttempts.forEach((bartender, items) {
      final average =
          (items
                      .map((attempt) => attempt.scorePercent)
                      .reduce((a, b) => a + b) /
                  items.length)
              .round();
      bartenderAverageScores[bartender] = average;
    });

    for (final session in weeklySessions) {
      final completed = attempts
          .where((attempt) => attempt.weekId == session.id)
          .map((attempt) => attempt.bartenderName.toLowerCase())
          .toSet();
      final invited = session.bartenderSales
          .map((sales) => sales.bartenderName.toLowerCase())
          .toSet();
      quizCompletionStatus[session.label] = invited.isEmpty
          ? 'No bartender sales yet'
          : '${completed.length}/${invited.length} completed';
    }

    final quizCompletionRate = weeklySessions.isEmpty
        ? 0
        : ((weeklySessions
                          .where((session) => session.bartenderSales.isNotEmpty)
                          .length /
                      weeklySessions.length) *
                  100)
              .round();
    final venueAverageScore = attempts.isEmpty
        ? 0
        : (attempts
                      .map((attempt) => attempt.scorePercent)
                      .reduce((a, b) => a + b) /
                  attempts.length)
              .round();
    final strongestImprovement = _strongestImprovement(bartenderAttempts);
    final activeQuizSessions = quizSessions
        .where((session) => session.isActive)
        .length;
    final closedQuizSessions = quizSessions
        .where((session) => !session.isActive)
        .length;
    final unresolvedStockSessions = weeklySessions.where((session) {
      final hasAttempt = attempts.any(
        (attempt) => attempt.weekId == session.id,
      );
      return !hasAttempt;
    }).length;

    return DashboardViewData(
      latestSessions: weeklySessions.take(2).toList(),
      latestPerBartender: latestPerBartender,
      potentialVarianceByIngredient: potentialVarianceByIngredient,
      potentialVarianceByBatch: potentialVarianceByBatch,
      potentialVarianceByBartender: potentialVarianceByBartender,
      misunderstoodCocktails: misunderstoodCocktails,
      trainingFocusAreas: trainingFocusAreas,
      weakAreaSuggestions: weakAreaRecipeSuggestions(),
      underpourOpportunities: underpourOpportunities,
      quizCompletionStatus: quizCompletionStatus,
      weeklyConfidence: weeklyConfidence,
      ingredientConfidenceByWeek: ingredientConfidenceByWeek,
      bartenderAverageScores: bartenderAverageScores,
      ingredientMisses: ingredientMisses,
      venueAverageScore: venueAverageScore,
      quizCompletionRate: quizCompletionRate,
      activeQuizSessions: activeQuizSessions,
      closedQuizSessions: closedQuizSessions,
      unresolvedStockSessions: unresolvedStockSessions,
      strongestImprovementLabel: strongestImprovement.$1,
      strongestImprovementDelta: strongestImprovement.$2,
    );
  }

  SetupChecklistData buildSetupChecklist() {
    final hasApprovedRecipes = recipes.isNotEmpty;
    final hasIngredientCosts = ingredients.any(
      (ingredient) => ingredient.bottleCost > 0,
    );
    final hasStockSession = weeklySessions.isNotEmpty;
    final hasSales = weeklySessions.any(
      (session) => session.bartenderSales.isNotEmpty,
    );
    final hasQuiz = quizSessions.any(
      (session) => session.kind == QuizKind.stockVariance,
    );
    final hasAttempt = quizAttempts.any((attempt) => attempt.weekId != null);
    final items = [
      SetupChecklistItem(
        title: 'Cocktail list ready',
        description:
            'The shared cocktail list should be available automatically for practice, stock focus, and coaching.',
        isComplete: hasApprovedRecipes,
      ),
      SetupChecklistItem(
        title: 'Add ingredient costs',
        description:
            'Add bottle costs so potential variance can include a helpful value estimate.',
        isComplete: hasIngredientCosts,
      ),
      SetupChecklistItem(
        title: 'Create your first stock concern session',
        description:
            'Choose the ingredients that need attention after stock take.',
        isComplete: hasStockSession,
      ),
      SetupChecklistItem(
        title: 'Enter bartender sales',
        description: 'Capture only the relevant cocktails for each bartender.',
        isComplete: hasSales,
      ),
      SetupChecklistItem(
        title: 'Share a focused session link',
        description:
            'Share an active session link for the current weekly focus.',
        isComplete: hasQuiz,
      ),
      SetupChecklistItem(
        title: 'Collect the first session response',
        description:
            'Once a bartender submits a session, your insights will start filling in.',
        isComplete: hasAttempt,
      ),
    ];
    return SetupChecklistData(items: items);
  }

  Future<T> _wrapBusy<T>(Future<T> Function() action) async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await action();
    } catch (error) {
      _errorMessage = _friendlyUserMessage(error);
      rethrow;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  String _friendlyUserMessage(Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    final normalized = raw.toLowerCase();

    if (normalized.contains('sign out of the current account before joining')) {
      return 'Sign out of the current account before using an invite link.';
    }
    if (normalized.contains('invite') &&
        normalized.contains('could not be found')) {
      return 'That invite link could not be found. Ask your manager or admin to copy a fresh invite link.';
    }
    if (normalized.contains('firebase_auth/') ||
        normalized.contains('auth/') ||
        normalized.contains('invalid-credential') ||
        normalized.contains('wrong-password') ||
        normalized.contains('user-not-found')) {
      return 'We couldn\'t sign you in. Check your email and password and try again.';
    }
    if (normalized.contains('already registered')) {
      return 'This email already has an account. Use the same password to continue, or sign in directly if the invite was already used for this email.';
    }
    if (normalized.contains('already linked to a venue account')) {
      return 'This email is already linked to a venue account. Sign in instead, or use a different email for this invite.';
    }
    if (normalized.contains('already linked to a different venue')) {
      return 'This email is already linked to a different venue account. Sign in instead, or use a different email for this invite.';
    }
    if (normalized.contains('too-many-requests')) {
      return 'There have been a few sign-in attempts in a row. Wait a moment and try again.';
    }
    if (normalized.contains('network-request-failed') ||
        normalized.contains('network error')) {
      return 'We couldn\'t reach the sign-in service. Check your connection and try again.';
    }
    if (normalized.contains('missing a venue assignment')) {
      return 'You\'re signed in, but this account does not have access to a venue yet.';
    }
    if (normalized.contains('unknown role')) {
      return 'Your account is set up, but your team access could not be loaded.';
    }
    if (normalized.contains('team access could not be loaded')) {
      return 'The invite may have been accepted, but the account profile could not be loaded afterwards. Copy the join diagnostics from this screen so we can inspect the exact venue and invite ids.';
    }
    if (normalized.contains('invite') && normalized.contains('disabled')) {
      return 'That invite is no longer active. Ask your manager or admin for a fresh invite link.';
    }
    if (normalized.contains('invite') && normalized.contains('expired')) {
      return 'That invite has expired. Ask your manager or admin for a fresh invite link.';
    }
    if (normalized.contains('permission-denied') &&
        (normalized.contains('invite') || normalized.contains('venue'))) {
      return '$raw Copy the join diagnostics from this screen so we can inspect the exact invite and venue ids.';
    }
    if (normalized.contains('permission-denied')) {
      return 'Your account is signed in, but this action is not available for your current access level.';
    }
    return raw;
  }

  String _friendlyStartupMessage(Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    final normalized = raw.toLowerCase();
    if (normalized.contains('missing a venue assignment')) {
      return 'You’re signed in, but this account does not have access to a venue yet.';
    }
    if (normalized.contains('unknown role')) {
      return 'Your account is set up, but your team access could not be loaded.';
    }
    if (normalized.contains('paused')) {
      return 'This account is currently paused. Ask your manager or admin to restore access when you are ready.';
    }
    return 'We couldn’t start your saved session cleanly. Please sign in again.';
  }

  String _friendlyTrainingDataMessage(Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    final normalized = raw.toLowerCase();
    if (normalized.contains('cocktail list could not be loaded')) {
      return 'Cocktail list could not be loaded. Please refresh or contact admin.';
    }
    return 'We couldn’t connect to the training data. Please try again.';
  }

  void recordNonBlockingStartupIssue(Object error) {
    _errorMessage ??= _friendlyUserMessage(error);
    notifyListeners();
  }

  Future<void> _loadRoleScopedTrainingData() async {
    final user = currentUser;
    if (user == null) {
      return;
    }
    try {
      await _trainingRepository.loadBartenderData(userId: user.id);
    } catch (error, stackTrace) {
      _logStartup(
        'Personal progress load failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _refreshVenueUsersIfNeeded({bool force = false}) async {
    if (!canAccessManagerWorkflows ||
        currentUser == null ||
        currentUser!.venueId.trim().isEmpty) {
      _venueUsers = const [];
      return;
    }
    if (!force && _venueUsers.isNotEmpty) {
      return;
    }
    _venueUsers = await _authRepository.listVenueUsers(
      venueId: currentUser!.venueId,
    );
  }

  Future<void> _refreshVenueInvitesIfNeeded({bool force = false}) async {
    if (!canManageVenueInvites ||
        currentUser == null ||
        currentUser!.venueId.trim().isEmpty) {
      _venueInvites = const [];
      return;
    }
    if (!force && _venueInvites.isNotEmpty) {
      return;
    }
    _venueInvites = await _authRepository.listVenueInvites(
      venueId: currentUser!.venueId,
    );
  }

  void _requireOwnerAccess(String message) {
    if (!canAccessAdminSetup) {
      throw Exception(message);
    }
  }

  void _requireOperationalAccess(String message) {
    if (!canAccessManagerWorkflows) {
      throw Exception(message);
    }
  }

  void _requireInviteManagementAccess(String message) {
    if (!canManageVenueInvites) {
      throw Exception(message);
    }
  }
}

(String?, int) _strongestImprovement(
  Map<String, List<QuizAttempt>> attemptsByBartender,
) {
  String? bestBartender;
  var bestDelta = 0;
  attemptsByBartender.forEach((bartender, attempts) {
    if (attempts.length < 2) {
      return;
    }
    final ordered = [...attempts]
      ..sort((a, b) => a.submittedAt.compareTo(b.submittedAt));
    final delta =
        ordered.last.scorePercent - ordered[ordered.length - 2].scorePercent;
    if (delta > bestDelta) {
      bestDelta = delta;
      bestBartender = bartender;
    }
  });
  return (bestBartender, bestDelta);
}

class DashboardViewData {
  const DashboardViewData({
    required this.latestSessions,
    required this.latestPerBartender,
    required this.potentialVarianceByIngredient,
    required this.potentialVarianceByBatch,
    required this.potentialVarianceByBartender,
    required this.misunderstoodCocktails,
    required this.trainingFocusAreas,
    required this.weakAreaSuggestions,
    required this.underpourOpportunities,
    required this.quizCompletionStatus,
    required this.weeklyConfidence,
    required this.ingredientConfidenceByWeek,
    required this.bartenderAverageScores,
    required this.ingredientMisses,
    required this.venueAverageScore,
    required this.quizCompletionRate,
    required this.activeQuizSessions,
    required this.closedQuizSessions,
    required this.unresolvedStockSessions,
    required this.strongestImprovementLabel,
    required this.strongestImprovementDelta,
  });

  final List<WeeklyConcernSession> latestSessions;
  final Map<String, QuizAttempt> latestPerBartender;
  final Map<String, double> potentialVarianceByIngredient;
  final Map<String, double> potentialVarianceByBatch;
  final Map<String, double> potentialVarianceByBartender;
  final Map<String, int> misunderstoodCocktails;
  final Map<String, int> trainingFocusAreas;
  final List<CocktailRecipe> weakAreaSuggestions;
  final Map<String, double> underpourOpportunities;
  final Map<String, String> quizCompletionStatus;
  final Map<String, int> weeklyConfidence;
  final Map<String, Map<String, int>> ingredientConfidenceByWeek;
  final Map<String, int> bartenderAverageScores;
  final Map<String, int> ingredientMisses;
  final int venueAverageScore;
  final int quizCompletionRate;
  final int activeQuizSessions;
  final int closedQuizSessions;
  final int unresolvedStockSessions;
  final String? strongestImprovementLabel;
  final int strongestImprovementDelta;
}

class SetupChecklistData {
  const SetupChecklistData({required this.items});

  final List<SetupChecklistItem> items;

  int get completedCount => items.where((item) => item.isComplete).length;
  bool get isComplete => completedCount == items.length;
}

class SetupChecklistItem {
  const SetupChecklistItem({
    required this.title,
    required this.description,
    required this.isComplete,
  });

  final String title;
  final String description;
  final bool isComplete;
}
