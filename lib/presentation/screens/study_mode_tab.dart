import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/models/models.dart';
import '../controllers/app_controller.dart';

enum _StudyPresentationMode { guided, blindRecall, rapidFire }

enum _StudyDeckMode {
  fullLibrary,
  weakSpots,
  batchBuilds,
  sessionFocus,
  ingredientFocus,
}

class StudyModeTab extends StatefulWidget {
  const StudyModeTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<StudyModeTab> createState() => _StudyModeTabState();
}

class _StudyModeTabState extends State<StudyModeTab> {
  final TextEditingController _searchController = TextEditingController();
  int _index = 0;
  bool _showSpec = false;
  bool _showService = false;
  bool _showMethod = false;
  bool _showBatches = false;
  _StudyPresentationMode _presentationMode = _StudyPresentationMode.guided;
  _StudyDeckMode _deckMode = _StudyDeckMode.fullLibrary;
  final Set<String> _sessionFocusRecipeIds = <String>{};
  final Set<String> _sessionConfidentRecipeIds = <String>{};
  String? _selectedIngredientFocus;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recipes = _studyRecipes();
    final feedback = widget.controller.buildStudyFeedbackSummary();
    if (recipes.isEmpty) {
      final emptyMessage = switch (_deckMode) {
        _StudyDeckMode.weakSpots =>
          'Your weak-spot deck will appear after a few quizzes. Switch back to the full library any time.',
        _StudyDeckMode.batchBuilds =>
          'Batch-build study appears here when approved cocktails link to prep batches.',
        _StudyDeckMode.sessionFocus =>
          'Mark cocktails as needs work during study and they will gather here for another pass.',
        _StudyDeckMode.ingredientFocus =>
          _selectedIngredientFocus == null
              ? 'Choose an ingredient focus and every approved cocktail that uses it will appear here.'
              : 'No approved cocktails matched $_selectedIngredientFocus in this deck yet.',
        _StudyDeckMode.fullLibrary =>
          'Approved cocktails will appear here once the library loads.',
      };
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final recipe = recipes[_index % recipes.length];
    final weakSpotRecipes = widget.controller.weakAreaRecipeSuggestions();
    final ingredientSuggestions = widget.controller.ingredientMissSuggestions();
    final ingredientOptions = _ingredientFocusOptions();
    final compactLayout = MediaQuery.sizeOf(context).height < 760;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _StudyHeaderCard(
          title: 'Study mode',
          subtitle:
              'Use guided cards, blind recall, batch-build revision, and session focus decks to learn specs in more than one way.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _StudyMetricCard(
              label: 'Deck size',
              value: '${recipes.length}',
              caption: _deckMode == _StudyDeckMode.weakSpots
                  ? 'Cocktails from recent misses'
                  : 'Approved cocktails ready to revise',
            ),
            _StudyMetricCard(
              label: 'Mode',
              value: _presentationMode == _StudyPresentationMode.guided
                  ? 'Guided'
                  : _presentationMode == _StudyPresentationMode.blindRecall
                  ? 'Blind recall'
                  : 'Rapid fire',
              caption: _presentationMode == _StudyPresentationMode.guided
                  ? 'Hints stay visible while you revise'
                  : _presentationMode == _StudyPresentationMode.blindRecall
                  ? 'Reveal answers section by section'
                  : 'Fast reps with instant self-checks',
            ),
            _StudyMetricCard(
              label: 'Weak spots',
              value: '${weakSpotRecipes.length}',
              caption: weakSpotRecipes.isEmpty
                  ? 'Unlock after a few quiz rounds'
                  : 'Ready for focused revision',
            ),
            _StudyMetricCard(
              label: 'Session focus',
              value: '${_sessionFocusRecipeIds.length}',
              caption: _sessionFocusRecipeIds.isEmpty
                  ? 'Mark cocktails that need another pass'
                  : 'Cocktails queued for extra revision',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _StudyFeedbackCard(feedback: feedback),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {
                    _index = 0;
                  }),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Search cocktails or ingredients',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Choose your study deck',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final deck in _StudyDeckMode.values)
                      ChoiceChip(
                        label: Text(_deckModeLabel(deck)),
                        selected: _deckMode == deck,
                        onSelected: (_) {
                          setState(() {
                            _deckMode = deck;
                            _index = 0;
                            _resetRevealState();
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Choose how to learn',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                SegmentedButton<_StudyPresentationMode>(
                  segments: const [
                    ButtonSegment<_StudyPresentationMode>(
                      value: _StudyPresentationMode.guided,
                      label: Text('Guided'),
                    ),
                    ButtonSegment<_StudyPresentationMode>(
                      value: _StudyPresentationMode.blindRecall,
                      label: Text('Blind recall'),
                    ),
                    ButtonSegment<_StudyPresentationMode>(
                      value: _StudyPresentationMode.rapidFire,
                      label: Text('Rapid fire'),
                    ),
                  ],
                  selected: {_presentationMode},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _presentationMode = selection.first;
                      _resetRevealState();
                    });
                  },
                ),
                if (_deckMode == _StudyDeckMode.weakSpots &&
                    weakSpotRecipes.isEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Weak-spot study unlocks after quiz misses are saved, so bartenders can revise the drinks that need attention most.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (_deckMode == _StudyDeckMode.sessionFocus) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Use "Mark needs work" while studying and this deck becomes your quick second-pass revision list.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (_deckMode == _StudyDeckMode.ingredientFocus) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue:
                        ingredientOptions.contains(_selectedIngredientFocus)
                        ? _selectedIngredientFocus
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Ingredient focus',
                    ),
                    items: ingredientOptions
                        .map(
                          (ingredient) => DropdownMenuItem<String>(
                            value: ingredient,
                            child: Text(ingredient),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedIngredientFocus = value;
                        _index = 0;
                        _resetRevealState();
                      });
                    },
                  ),
                  if (ingredientSuggestions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Suggested from recent misses',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final ingredient in ingredientSuggestions)
                          ActionChip(
                            label: Text(ingredient),
                            onPressed: () {
                              setState(() {
                                _selectedIngredientFocus = ingredient;
                                _index = 0;
                                _resetRevealState();
                              });
                            },
                          ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StudyCocktailHero(
                  recipe: recipe,
                  imageHeight: compactLayout ? 140 : 220,
                ),
                SizedBox(height: compactLayout ? 12 : 18),
                if (_presentationMode == _StudyPresentationMode.guided) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (recipe.category.trim().isNotEmpty)
                        Chip(label: Text(recipe.category)),
                      Chip(
                        label: Text(
                          recipe.ingredients.length == 1
                              ? '1 ingredient line'
                              : '${recipe.ingredients.length} ingredient lines',
                        ),
                      ),
                      if (widget.controller.canAccessManagerWorkflows &&
                          recipe.priceGbp != null)
                        Chip(label: Text(_formatPriceGbp(recipe.priceGbp!))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    recipe.notes.isEmpty
                        ? 'Use the reveal buttons below when you want the exact build details.'
                        : recipe.notes,
                    maxLines: compactLayout ? 3 : null,
                    overflow: compactLayout ? TextOverflow.ellipsis : null,
                  ),
                ] else if (_presentationMode ==
                    _StudyPresentationMode.blindRecall) ...[
                  Text(
                    'Blind recall prompt',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Before you reveal anything, say the spec out loud: every measure, the glass, the garnish, and the method.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      Chip(label: Text('How much of each ingredient?')),
                      Chip(label: Text('Which glass?')),
                      Chip(label: Text('What garnish?')),
                      Chip(label: Text('How is it made?')),
                    ],
                  ),
                ] else ...[
                  Text(
                    'Rapid fire prompt',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  Text(_rapidFirePrompt(recipe)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        label: Text(
                          recipe.ingredients.length == 1
                              ? '1 ingredient line'
                              : '${recipe.ingredients.length} ingredient lines',
                        ),
                      ),
                      if (_hasLinkedBatch(recipe))
                        const Chip(label: Text('Includes linked batch')),
                      if (recipe.glassware.trim().isNotEmpty ||
                          recipe.garnish.trim().isNotEmpty)
                        const Chip(label: Text('Service detail included')),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                if (_sessionFocusRecipeIds.contains(recipe.id) ||
                    _sessionConfidentRecipeIds.contains(recipe.id)) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: _sessionFocusRecipeIds.contains(recipe.id)
                          ? const Color(0xFF2B1E16)
                          : const Color(0xFF14251F),
                      border: Border.all(
                        color: _sessionFocusRecipeIds.contains(recipe.id)
                            ? const Color(0xFFD4894A)
                            : const Color(0xFF5ED0C7),
                      ),
                    ),
                    child: Text(
                      _sessionFocusRecipeIds.contains(recipe.id)
                          ? 'Marked for another pass in this study session.'
                          : 'Marked as confident in this study session.',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton(
                      onPressed: () => setState(() => _showSpec = !_showSpec),
                      child: Text(_showSpec ? 'Hide spec' : 'Reveal spec'),
                    ),
                    OutlinedButton(
                      onPressed: () =>
                          setState(() => _showService = !_showService),
                      child: Text(
                        _showService ? 'Hide service' : 'Reveal garnish & glass',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => setState(() => _showMethod = !_showMethod),
                      child: Text(
                        _showMethod ? 'Hide method' : 'Reveal method',
                      ),
                    ),
                    if (_hasLinkedBatch(recipe))
                      OutlinedButton(
                        onPressed: () =>
                            setState(() => _showBatches = !_showBatches),
                        child: Text(
                          _showBatches ? 'Hide batch' : 'Reveal batch',
                        ),
                      ),
                    ElevatedButton(
                      onPressed: () => setState(_revealEverything),
                      child: const Text('Reveal full build'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => setState(() {
                        _markNeedsWork(recipe.id);
                      }),
                      child: const Text('Mark needs work'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => setState(() {
                        _markNailedIt(recipe.id);
                      }),
                      child: const Text('Mark nailed it'),
                    ),
                    if (_presentationMode == _StudyPresentationMode.rapidFire)
                      ElevatedButton.icon(
                        onPressed: () => setState(() {
                          _markNailedIt(recipe.id);
                          _advanceStudyCard(recipes.length, randomize: true);
                        }),
                        icon: const Icon(Icons.flash_on),
                        label: const Text('Got it, next'),
                      ),
                    if (_presentationMode == _StudyPresentationMode.rapidFire)
                      OutlinedButton.icon(
                        onPressed: () => setState(() {
                          _markNeedsWork(recipe.id);
                          _advanceStudyCard(recipes.length, randomize: true);
                        }),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Again, next'),
                      ),
                  ],
                ),
                if (_showSpec || _showService || _showMethod || _showBatches) ...[
                  const SizedBox(height: 20),
                  if (_showSpec)
                    _StudySectionCard(
                      title: 'Spec',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: recipe.ingredients
                            .map(
                              (ingredient) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _StudyIngredientLine(
                                  ingredient: ingredient,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  if (_showService) ...[
                    const SizedBox(height: 12),
                    _StudySectionCard(
                      title: 'Garnish and glass',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _StudySpecLine(
                            label: 'Glassware',
                            value: recipe.glassware,
                          ),
                          _StudySpecLine(
                            label: 'Garnish',
                            value: recipe.garnish,
                          ),
                          if (widget.controller.canAccessManagerWorkflows)
                            _StudySpecLine(
                              label: 'Price',
                              value: recipe.priceGbp == null
                                  ? 'Missing from price list'
                                  : _formatPriceGbp(recipe.priceGbp!),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (_showMethod) ...[
                    const SizedBox(height: 12),
                    _StudySectionCard(
                      title: 'Method',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _StudySpecLine(label: 'Method', value: recipe.method),
                          if (recipe.notes.trim().isNotEmpty)
                            _StudySpecLine(label: 'Notes', value: recipe.notes),
                        ],
                      ),
                    ),
                  ],
                  if (_showBatches && _hasLinkedBatch(recipe)) ...[
                    const SizedBox(height: 12),
                    _StudySectionCard(
                      title: 'Linked batches',
                      child: Column(
                        children: _linkedBatches(recipe)
                            .map(
                              (batch) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _StudyBatchCard(batch: batch),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 180,
              child: OutlinedButton(
                onPressed: () => setState(() {
                  _index = (_index - 1) % recipes.length;
                  _resetRevealState();
                }),
                child: const Text('Previous'),
              ),
            ),
            SizedBox(
              width: 180,
              child: ElevatedButton(
                onPressed: () => setState(() {
                  _index = (_index + 1) % recipes.length;
                  _resetRevealState();
                }),
                child: const Text('Next cocktail'),
              ),
            ),
            SizedBox(
              width: 180,
              child: OutlinedButton(
                onPressed: () => setState(() {
                  _index = math.Random().nextInt(recipes.length);
                  _resetRevealState();
                }),
                child: const Text('Random cocktail'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<CocktailRecipe> _studyRecipes() {
    final searchResults = _searchController.text.trim().isEmpty
        ? widget.controller.recipes
        : widget.controller.searchRecipes(_searchController.text.trim());
    final weakIds = widget.controller.weakAreaRecipeSuggestions()
        .map((recipe) => recipe.id)
        .toSet();
    return switch (_deckMode) {
      _StudyDeckMode.fullLibrary => searchResults,
      _StudyDeckMode.weakSpots => searchResults
          .where((recipe) => weakIds.contains(recipe.id))
          .toList(),
      _StudyDeckMode.batchBuilds => searchResults
          .where((recipe) => _hasLinkedBatch(recipe))
          .toList(),
      _StudyDeckMode.sessionFocus => searchResults
          .where((recipe) => _sessionFocusRecipeIds.contains(recipe.id))
          .toList(),
      _StudyDeckMode.ingredientFocus => _selectedIngredientFocus == null
          ? const []
          : searchResults
                .where(
                  (recipe) => recipe.ingredients.any(
                    (ingredient) => ingredient.ingredientName
                        .toLowerCase()
                        .contains(_selectedIngredientFocus!.toLowerCase()),
                  ),
                )
                .toList(),
    };
  }

  List<String> _ingredientFocusOptions() {
    final names = <String>{
      for (final recipe in widget.controller.recipes)
        ...recipe.ingredients
            .where((ingredient) => !ingredient.isBatchReference)
            .map((ingredient) => ingredient.ingredientName.trim())
            .where((name) => name.isNotEmpty),
    }.toList()
      ..sort();
    return names;
  }

  bool _hasLinkedBatch(CocktailRecipe recipe) {
    return recipe.ingredients.any((ingredient) => ingredient.isBatchReference);
  }

  List<BatchRecipe> _linkedBatches(CocktailRecipe recipe) {
    return recipe.ingredients
        .where((ingredient) => ingredient.isBatchReference)
        .map(
          (ingredient) => widget.controller.batches.cast<BatchRecipe?>()
              .firstWhere(
                (batch) => batch != null && batch.id == ingredient.linkedBatchId,
                orElse: () => null,
              ),
        )
        .whereType<BatchRecipe>()
        .toList();
  }

  void _revealEverything() {
    _showSpec = true;
    _showService = true;
    _showMethod = true;
    _showBatches = true;
  }

  void _resetRevealState() {
    _showSpec = false;
    _showService = false;
    _showMethod = false;
    _showBatches = false;
  }

  void _markNeedsWork(String recipeId) {
    _sessionFocusRecipeIds.add(recipeId);
    _sessionConfidentRecipeIds.remove(recipeId);
  }

  void _markNailedIt(String recipeId) {
    _sessionConfidentRecipeIds.add(recipeId);
    _sessionFocusRecipeIds.remove(recipeId);
    if (_deckMode == _StudyDeckMode.sessionFocus) {
      _index = 0;
    }
  }

  void _advanceStudyCard(int recipeCount, {bool randomize = false}) {
    if (recipeCount <= 1) {
      _resetRevealState();
      return;
    }
    _index = randomize ? math.Random().nextInt(recipeCount) : (_index + 1);
    _resetRevealState();
  }

  String _rapidFirePrompt(CocktailRecipe recipe) {
    if (_deckMode == _StudyDeckMode.ingredientFocus &&
        _selectedIngredientFocus != null) {
      return 'Call the full spec for ${recipe.name}, then say exactly how much $_selectedIngredientFocus goes into the drink.';
    }
    if (_hasLinkedBatch(recipe)) {
      return 'Call the spec for ${recipe.name}, including the batch amount, then check yourself fast.';
    }
    return 'Call the full spec for ${recipe.name} out loud, then mark whether it felt clean or needs another pass.';
  }
}

String _deckModeLabel(_StudyDeckMode mode) {
  return switch (mode) {
    _StudyDeckMode.fullLibrary => 'Full library',
    _StudyDeckMode.weakSpots => 'Weak spots',
    _StudyDeckMode.batchBuilds => 'Batch builds',
    _StudyDeckMode.sessionFocus => 'Session focus',
    _StudyDeckMode.ingredientFocus => 'Ingredient focus',
  };
}

class _StudyHeaderCard extends StatelessWidget {
  const _StudyHeaderCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

class _StudyMetricCard extends StatelessWidget {
  const _StudyMetricCard({
    required this.label,
    required this.value,
    required this.caption,
  });

  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 10),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(caption, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudyFeedbackCard extends StatelessWidget {
  const _StudyFeedbackCard({required this.feedback});

  final StudyFeedbackSummary feedback;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Study feedback',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(feedback.headline),
            const SizedBox(height: 12),
            Text(
              feedback.recentScoreLabel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Text('Next step: ${feedback.nextStep}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Best next deck: ${feedback.recommendedDeckLabel}')),
                if (feedback.batchPracticeRecommended)
                  const Chip(label: Text('Batch revision recommended')),
                if (!feedback.hasRecentAttempt)
                  const Chip(label: Text('Take a quiz to personalise this')),
              ],
            ),
            if (feedback.focusCocktails.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Cocktails to revisit',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final cocktail in feedback.focusCocktails)
                    Chip(label: Text(cocktail)),
                ],
              ),
            ],
            if (feedback.focusIngredients.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Ingredients to tighten',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final ingredient in feedback.focusIngredients)
                    Chip(label: Text(ingredient)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StudyCocktailHero extends StatelessWidget {
  const _StudyCocktailHero({required this.recipe, required this.imageHeight});

  final CocktailRecipe recipe;
  final double imageHeight;

  @override
  Widget build(BuildContext context) {
    final imagePath = recipe.imageAssetPath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          height: imageHeight,
          child: imagePath == null || imagePath.isEmpty
              ? const _StudyImagePlaceholder()
              : ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(
                    imagePath,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _StudyImagePlaceholder(),
                  ),
                ),
        ),
        const SizedBox(height: 14),
        Text(recipe.name, style: Theme.of(context).textTheme.headlineSmall),
      ],
    );
  }
}

class _StudyImagePlaceholder extends StatelessWidget {
  const _StudyImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F2428),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Center(child: Icon(Icons.local_bar, size: 36)),
    );
  }
}

class _StudySectionCard extends StatelessWidget {
  const _StudySectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151A1E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF293037)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _StudyIngredientLine extends StatelessWidget {
  const _StudyIngredientLine({required this.ingredient});

  final RecipeIngredient ingredient;

  @override
  Widget build(BuildContext context) {
    final amount = ingredient.measureMl == null
        ? ''
        : '${ingredient.measureMl!.toStringAsFixed(0)}ml';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 7),
          child: Icon(Icons.circle, size: 8),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            amount.isEmpty
                ? ingredient.ingredientName
                : '$amount ${ingredient.ingredientName}',
          ),
        ),
      ],
    );
  }
}

class _StudySpecLine extends StatelessWidget {
  const _StudySpecLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value.isEmpty ? 'Not listed' : value),
          ],
        ),
      ),
    );
  }
}

class _StudyBatchCard extends StatelessWidget {
  const _StudyBatchCard({required this.batch});

  final BatchRecipe batch;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(batch.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              batch.totalBatchVolumeMl == null
                  ? 'Batch total not listed'
                  : 'Batch total: ${batch.totalBatchVolumeMl!.toStringAsFixed(0)}ml',
            ),
            const SizedBox(height: 10),
            ...batch.ingredients.map(
              (ingredient) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _StudyIngredientLine(ingredient: ingredient),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatPriceGbp(double priceGbp) {
  return NumberFormat.currency(
    locale: 'en_GB',
    symbol: '£',
    decimalDigits: 2,
  ).format(priceGbp);
}
