import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/models/models.dart';
import '../controllers/app_controller.dart';

class ManagerLibraryTab extends StatelessWidget {
  const ManagerLibraryTab({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return CocktailLibraryTab(
      controller: controller,
      headerTitle: 'Approved cocktail library',
      headerSubtitle:
          'Managers see the same approved cocktail and batch learning data as bartenders.',
      showPrices: true,
    );
  }
}

class CocktailLibraryTab extends StatefulWidget {
  const CocktailLibraryTab({
    super.key,
    required this.controller,
    this.headerTitle = 'Approved cocktail library',
    this.headerSubtitle =
        'Browse approved cocktails only. Open a card for ingredients, garnish, glassware, method, and linked batch details.',
    this.showPrices = false,
  });

  final AppController controller;
  final String headerTitle;
  final String headerSubtitle;
  final bool showPrices;

  @override
  State<CocktailLibraryTab> createState() => _CocktailLibraryTabState();
}

class _CocktailLibraryTabState extends State<CocktailLibraryTab> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = widget.controller.searchRecipes(_searchController.text);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _LibraryHeaderCard(
          title: widget.headerTitle,
          subtitle: widget.headerSubtitle,
          trailing: _LibraryInfoMetric(
            label: 'Cocktails',
            value: '${widget.controller.recipes.length}',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Search cocktails, categories, or ingredients',
          ),
        ),
        const SizedBox(height: 16),
        if (results.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('No approved cocktails matched that search yet.'),
            ),
          ),
        ...results.map(
          (recipe) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _CocktailCard(
              recipe: recipe,
              showPrice: widget.showPrices,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CocktailDetailScreen(
                    recipe: recipe,
                    batches: widget.controller.batches,
                    showPrice: widget.showPrices,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ProgressTab extends StatelessWidget {
  const ProgressTab({
    super.key,
    required this.controller,
    required this.managerView,
  });

  final AppController controller;
  final bool managerView;

  @override
  Widget build(BuildContext context) {
    final attempts = managerView
        ? controller.personalQuizAttempts
        : controller.quizAttempts;
    final stats = _ProgressStats.fromAttempts(
      attempts: attempts,
      recipesById: controller.recipesById,
    );
    final subtitle = managerView
        ? 'Your own learning confidence stays here. Team-wide coaching detail lives in the Team tab.'
        : 'Your quiz history stays here so you can see what is feeling solid and what deserves a little more practice.';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _LibraryHeaderCard(title: 'Progress', subtitle: subtitle),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _ProgressMetricCard(
              title: 'Quizzes',
              value: '${stats.quizCount}',
              caption: 'Completed rounds',
            ),
            _ProgressMetricCard(
              title: 'Average score',
              value: '${stats.averageScore}%',
              caption: 'Across loaded quiz attempts',
            ),
            _ProgressMetricCard(
              title: 'Confidence',
              value: stats.confidenceLabel,
              caption: 'Friendly pulse check',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _InsightListCard(
          title: 'Cocktails to revisit',
          emptyLabel:
              'No weak cocktails yet. Start a quiz and your learning highlights will appear here.',
          items: stats.weakCocktails.entries
              .map((entry) => '${entry.key} · ${entry.value} misses')
              .toList(),
        ),
        const SizedBox(height: 16),
        _InsightListCard(
          title: 'Ingredient focus areas',
          emptyLabel:
              'Ingredient patterns will appear after a few quiz rounds.',
          items: stats.weakIngredients.entries
              .map((entry) => '${entry.key} · ${entry.value} misses')
              .toList(),
        ),
      ],
    );
  }
}

class CocktailDetailScreen extends StatelessWidget {
  const CocktailDetailScreen({
    super.key,
    required this.recipe,
    required this.batches,
    this.showPrice = false,
  });

  final CocktailRecipe recipe;
  final List<BatchRecipe> batches;
  final bool showPrice;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(recipe.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CocktailHero(recipe: recipe, imageHeight: 240),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (recipe.category.trim().isNotEmpty)
                        Chip(label: Text(recipe.category)),
                      if (recipe.glassware.trim().isNotEmpty)
                        Chip(label: Text(recipe.glassware)),
                      if (recipe.garnish.trim().isNotEmpty)
                        Chip(label: Text(recipe.garnish)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _RecipeSpecBlock(
                    recipe: recipe,
                    batches: batches,
                    showPrice: showPrice,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipeSpecBlock extends StatelessWidget {
  const _RecipeSpecBlock({
    required this.recipe,
    required this.batches,
    this.showPrice = false,
  });

  final CocktailRecipe recipe;
  final List<BatchRecipe> batches;
  final bool showPrice;

  @override
  Widget build(BuildContext context) {
    final linkedBatches = recipe.ingredients
        .where((ingredient) => ingredient.isBatchReference)
        .map(
          (ingredient) => batches.cast<BatchRecipe?>().firstWhere(
            (batch) => batch != null && batch.id == ingredient.linkedBatchId,
            orElse: () => null,
          ),
        )
        .whereType<BatchRecipe>()
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showPrice)
          _SpecLine(
            label: 'Price',
            value: recipe.priceGbp == null
                ? 'Missing from Signature Cocktails price list'
                : _formatPriceGbp(recipe.priceGbp!),
          ),
        _SpecLine(label: 'Method', value: recipe.method),
        _SpecLine(label: 'Glassware', value: recipe.glassware),
        _SpecLine(label: 'Garnish', value: recipe.garnish),
        if (recipe.notes.trim().isNotEmpty)
          _SpecLine(label: 'Notes', value: recipe.notes),
        const SizedBox(height: 18),
        Text('Ingredients', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        ...recipe.ingredients.map(
          (ingredient) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _IngredientLine(ingredient: ingredient),
          ),
        ),
        if (linkedBatches.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Linked batches',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          ...linkedBatches.map(
            (batch) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        batch.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
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
                          child: _IngredientLine(ingredient: ingredient),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CocktailCard extends StatelessWidget {
  const _CocktailCard({
    required this.recipe,
    required this.onTap,
    this.showPrice = false,
  });

  final CocktailRecipe recipe;
  final VoidCallback onTap;
  final bool showPrice;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CocktailImage(recipe: recipe, size: 88),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (recipe.category.trim().isNotEmpty)
                      Text(
                        recipe.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    if (showPrice) ...[
                      const SizedBox(height: 8),
                      Text(
                        recipe.priceGbp == null
                            ? 'Price missing from source list'
                            : _formatPriceGbp(recipe.priceGbp!),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      recipe.ingredients
                          .take(3)
                          .map((item) => item.ingredientName)
                          .join(' • '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
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

class _CocktailHero extends StatelessWidget {
  const _CocktailHero({required this.recipe, required this.imageHeight});

  final CocktailRecipe recipe;
  final double imageHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CocktailImage(
          recipe: recipe,
          size: double.infinity,
          height: imageHeight,
        ),
        const SizedBox(height: 14),
        Text(recipe.name, style: Theme.of(context).textTheme.headlineSmall),
      ],
    );
  }
}

class _CocktailImage extends StatelessWidget {
  const _CocktailImage({required this.recipe, required this.size, this.height});

  final CocktailRecipe recipe;
  final double size;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final imagePath = recipe.imageAssetPath;
    final image = imagePath == null || imagePath.isEmpty
        ? const _ImagePlaceholder()
        : ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              imagePath,
              width: size == double.infinity ? null : size,
              height: height ?? size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const _ImagePlaceholder(),
            ),
          );
    return SizedBox(
      width: size == double.infinity ? double.infinity : size,
      height: height ?? size,
      child: image,
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

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

class _IngredientLine extends StatelessWidget {
  const _IngredientLine({required this.ingredient});

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

class _SpecLine extends StatelessWidget {
  const _SpecLine({required this.label, required this.value});

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

class _LibraryHeaderCard extends StatelessWidget {
  const _LibraryHeaderCard({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 10),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 16), trailing!],
          ],
        ),
      ),
    );
  }
}

class _ProgressMetricCard extends StatelessWidget {
  const _ProgressMetricCard({
    required this.title,
    required this.value,
    required this.caption,
  });

  final String title;
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
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 12),
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(caption, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _InsightListCard extends StatelessWidget {
  const _InsightListCard({
    required this.title,
    required this.items,
    required this.emptyLabel,
  });

  final String title;
  final List<String> items;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Text(emptyLabel)
            else
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 7),
                        child: Icon(Icons.circle, size: 8),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(item)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LibraryInfoMetric extends StatelessWidget {
  const _LibraryInfoMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2428),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF293037)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

class _ProgressStats {
  const _ProgressStats({
    required this.quizCount,
    required this.averageScore,
    required this.confidenceLabel,
    required this.weakCocktails,
    required this.weakIngredients,
  });

  final int quizCount;
  final int averageScore;
  final String confidenceLabel;
  final Map<String, int> weakCocktails;
  final Map<String, int> weakIngredients;

  factory _ProgressStats.fromAttempts({
    required List<QuizAttempt> attempts,
    required Map<String, CocktailRecipe> recipesById,
  }) {
    if (attempts.isEmpty) {
      return const _ProgressStats(
        quizCount: 0,
        averageScore: 0,
        confidenceLabel: 'Just getting started',
        weakCocktails: {},
        weakIngredients: {},
      );
    }

    final weakCocktails = <String, int>{};
    final weakIngredients = <String, int>{};
    var totalScore = 0;

    for (final attempt in attempts) {
      totalScore += attempt.scorePercent;
      for (final response in attempt.responses.where(
        (item) => !item.isCorrect,
      )) {
        final recipeName =
            recipesById[response.question.cocktailId]?.name ??
            response.question.cocktailName;
        weakCocktails.update(
          recipeName,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
        final ingredientName = (response.question.ingredientName ?? '').trim();
        if (ingredientName.isNotEmpty) {
          weakIngredients.update(
            ingredientName,
            (value) => value + 1,
            ifAbsent: () => 1,
          );
        }
      }
    }

    final sortedCocktails = weakCocktails.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sortedIngredients = weakIngredients.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final averageScore = (totalScore / attempts.length).round();

    return _ProgressStats(
      quizCount: attempts.length,
      averageScore: averageScore,
      confidenceLabel: averageScore >= 85
          ? 'Feeling strong'
          : averageScore >= 65
          ? 'Building well'
          : 'Worth a refresher',
      weakCocktails: {
        for (final entry in sortedCocktails.take(6)) entry.key: entry.value,
      },
      weakIngredients: {
        for (final entry in sortedIngredients.take(6)) entry.key: entry.value,
      },
    );
  }
}
