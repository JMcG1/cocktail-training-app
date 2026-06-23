import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/browser_connectivity.dart';
import '../../core/utils/browser_history.dart';
import '../../core/utils/variance_math.dart';
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
              onTap: () async {
                final previousFragment = currentBrowserFragment();
                final detailFragment = 'cocktail-${recipe.id}';
                pushBrowserFragment(detailFragment);
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CocktailDetailScreen(
                      recipe: recipe,
                      batches: widget.controller.batches,
                      showPrice: widget.showPrices,
                      expectedFragment: detailFragment,
                    ),
                  ),
                );
                if (!context.mounted) {
                  return;
                }
                replaceBrowserFragment(previousFragment);
              },
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
    final feedback = controller.buildStudyFeedbackSummary();
    final exposureByCocktailId = controller.currentUserExposureByCocktailId;
    final latestAttempt = attempts.isEmpty ? null : attempts.first;
    final latestImpactSummary = latestAttempt == null
        ? null
        : VarianceMath.buildSalesImpactSummary(
            attempt: latestAttempt,
            recipesById: controller.recipesById,
            ingredientsByName: controller.ingredientsByName,
            batches: controller.batches,
          );
    final highVolumeWeakCocktails = controller.weakAreaRecipeSuggestions()
        .where((recipe) => (exposureByCocktailId[recipe.id] ?? 0) > 0)
        .take(3)
        .map(
          (recipe) =>
              '${recipe.name} · ${exposureByCocktailId[recipe.id] ?? 0} sold',
        )
        .toList();
    final subtitle = managerView
        ? 'Your own learning confidence stays here. Team-wide coaching detail lives in the Team tab.'
        : 'Your quiz history stays here so you can see what is feeling solid and what deserves a little more practice.';
    final isOnline = BrowserConnectivity.isOnline();
    final syncStatus = controller.trainingSyncStatus;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _LibraryHeaderCard(title: 'Progress', subtitle: subtitle),
        const SizedBox(height: 16),
        _ProgressSyncBanner(isOnline: isOnline, syncStatus: syncStatus),
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
            _ProgressMetricCard(
              title: 'Latest score',
              value: stats.latestScoreLabel,
              caption: 'Most recent saved quiz',
            ),
            _ProgressMetricCard(
              title: 'Best score',
              value: stats.bestScoreLabel,
              caption: 'Personal best',
            ),
            _ProgressMetricCard(
              title: 'Current streak',
              value: stats.currentStreakLabel,
              caption: 'Consecutive passes',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _TrendChartCard(
          title: 'Score trend',
          entries: stats.scoreTrendEntries,
          valueSuffix: '%',
        ),
        const SizedBox(height: 16),
        _ProgressPracticePlanCard(
          feedback: feedback,
          weakCocktailCount: stats.totalWeakCocktailMisses,
          weakIngredientCount: stats.totalWeakIngredientMisses,
          highVolumeWeakCocktails: highVolumeWeakCocktails,
          latestImpactSummary: latestImpactSummary,
          potentialOverpourCostLabel: stats.potentialOverpourCostLabel,
          guestRiskCountLabel: stats.guestRiskCountLabel,
          highConfidenceMissLabel: stats.highConfidenceMissLabel,
        ),
        const SizedBox(height: 16),
        _InsightListCard(
          title: 'Cocktails to revisit',
          emptyLabel:
              'No weak cocktails yet. Start a quiz and your learning highlights will appear here.',
          items: stats.weakestCocktails.entries
              .map((entry) => '${entry.key} · ${entry.value} misses')
              .toList(),
        ),
        const SizedBox(height: 16),
        _InsightListCard(
          title: 'Strongest cocktails',
          emptyLabel:
              'Strongest cocktails appear once you begin answering correctly across multiple rounds.',
          items: stats.strongestCocktails.entries
              .map((entry) => '${entry.key} · ${entry.value} correct')
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
        const SizedBox(height: 16),
        _InsightListCard(
          title: 'Guest experience risks',
          emptyLabel:
              'Underpour and service-quality risks will appear after the first saved quiz.',
          items: stats.guestExperienceRisks,
        ),
        const SizedBox(height: 16),
        _InsightListCard(
          title: 'Recommended study topics',
          emptyLabel:
              'Study topics will appear once the app sees a few answer patterns.',
          items: stats.recommendedStudyTopics,
        ),
      ],
    );
  }
}

class CocktailDetailScreen extends StatefulWidget {
  const CocktailDetailScreen({
    super.key,
    required this.recipe,
    required this.batches,
    this.showPrice = false,
    this.expectedFragment,
  });

  final CocktailRecipe recipe;
  final List<BatchRecipe> batches;
  final bool showPrice;
  final String? expectedFragment;

  @override
  State<CocktailDetailScreen> createState() => _CocktailDetailScreenState();
}

class _CocktailDetailScreenState extends State<CocktailDetailScreen> {
  @override
  void initState() {
    super.initState();
    addBrowserHistoryListener(_handleBrowserFragmentChange);
  }

  @override
  void dispose() {
    removeBrowserHistoryListener(_handleBrowserFragmentChange);
    super.dispose();
  }

  void _handleBrowserFragmentChange(String fragment) {
    final expected = widget.expectedFragment;
    if (!mounted || expected == null || fragment == expected) {
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.recipe.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CocktailHero(recipe: widget.recipe, imageHeight: 240),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (widget.recipe.category.trim().isNotEmpty)
                        Chip(label: Text(widget.recipe.category)),
                      if (widget.recipe.glassware.trim().isNotEmpty)
                        Chip(label: Text(widget.recipe.glassware)),
                      if (widget.recipe.garnish.trim().isNotEmpty)
                        Chip(label: Text(widget.recipe.garnish)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _RecipeSpecBlock(
                    recipe: widget.recipe,
                    batches: widget.batches,
                    showPrice: widget.showPrice,
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          return Padding(
            padding: const EdgeInsets.all(20),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      if (trailing != null) ...[
                        const SizedBox(height: 16),
                        trailing!,
                      ],
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              subtitle,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: 16),
                        trailing!,
                      ],
                    ],
                  ),
          );
        },
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
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 220),
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

class _ProgressPracticePlanCard extends StatelessWidget {
  const _ProgressPracticePlanCard({
    required this.feedback,
    required this.weakCocktailCount,
    required this.weakIngredientCount,
    required this.highVolumeWeakCocktails,
    required this.latestImpactSummary,
    required this.potentialOverpourCostLabel,
    required this.guestRiskCountLabel,
    required this.highConfidenceMissLabel,
  });

  final StudyFeedbackSummary feedback;
  final int weakCocktailCount;
  final int weakIngredientCount;
  final List<String> highVolumeWeakCocktails;
  final QuizSalesImpactSummary? latestImpactSummary;
  final String potentialOverpourCostLabel;
  final String guestRiskCountLabel;
  final String highConfidenceMissLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Practice plan', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Text(feedback.headline),
            const SizedBox(height: 12),
            Text(
              feedback.recentScoreLabel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Text('Best next deck: ${feedback.recommendedDeckLabel}'),
            const SizedBox(height: 8),
            Text(feedback.nextStep),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('$weakCocktailCount cocktail misses logged')),
                Chip(
                  label: Text(
                    '$weakIngredientCount ingredient misses logged',
                  ),
                ),
                Chip(label: Text('Potential overpour cost $potentialOverpourCostLabel')),
                Chip(label: Text(guestRiskCountLabel)),
                Chip(label: Text(highConfidenceMissLabel)),
                if (feedback.batchPracticeRecommended)
                  const Chip(label: Text('Batch build revision worth a pass')),
                if (!feedback.hasRecentAttempt)
                  const Chip(label: Text('Take a quiz to personalise this plan')),
              ],
            ),
            if (feedback.focusCocktails.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Start with these cocktails',
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
            if (highVolumeWeakCocktails.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Highest-volume drinks needing work',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final cocktail in highVolumeWeakCocktails)
                    Chip(label: Text(cocktail)),
                ],
              ),
            ],
            if ((latestImpactSummary?.lines.isNotEmpty ?? false)) ...[
              const SizedBox(height: 12),
              _ProgressImpactCallout(summary: latestImpactSummary!),
            ],
            if (feedback.focusIngredients.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Tighten these ingredients',
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

class _ProgressSyncBanner extends StatelessWidget {
  const _ProgressSyncBanner({
    required this.isOnline,
    required this.syncStatus,
  });

  final bool isOnline;
  final TrainingSyncStatus syncStatus;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = !isOnline || syncStatus.quizReadsFromCache
        ? colorScheme.tertiaryContainer
        : colorScheme.secondaryContainer;
    final text = !isOnline
        ? 'Offline right now. Your saved progress will update once you reconnect.'
        : syncStatus.quizReadsFromCache
        ? 'Showing saved progress. ${syncStatus.lastQuizSyncMessage}'
        : syncStatus.lastQuizSyncMessage;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text),
    );
  }
}

class _TrendChartCard extends StatelessWidget {
  const _TrendChartCard({
    required this.title,
    required this.entries,
    this.valueSuffix = '',
  });

  final String title;
  final List<({String label, int value})> entries;
  final String valueSuffix;

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
            if (entries.isEmpty)
              const Text('Trend data appears after a few saved quizzes.')
            else
              ...entries.map((entry) {
                final maxValue = entries
                    .map((item) => item.value)
                    .fold<int>(1, (max, value) => value > max ? value : max);
                final progress = maxValue == 0 ? 0.0 : entry.value / maxValue;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(entry.label)),
                          Text('${entry.value}$valueSuffix'),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: progress, minHeight: 8),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _ProgressImpactCallout extends StatelessWidget {
  const _ProgressImpactCallout({required this.summary});

  final QuizSalesImpactSummary summary;

  @override
  Widget build(BuildContext context) {
    final topLine = summary.lines.first;
    final currency = NumberFormat.currency(symbol: '£', decimalDigits: 2);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF101417),
        border: Border.all(color: const Color(0xFF293037)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Latest quiz impact to watch',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '${topLine.cocktailName} · ${topLine.ingredientName}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            '${topLine.errorMlPerServe.toStringAsFixed(0)}ml per serve across ${topLine.quantitySold} sold could hide ${topLine.recoverableCocktails.toStringAsFixed(2)} more cocktails.',
          ),
          Text(
            'Potential direct ingredient cost: ${currency.format(topLine.ingredientCostImpactGbp)} · potential sales value hidden in the error: ${currency.format(topLine.recoverableRevenueGbp)}',
          ),
        ],
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
    required this.latestScoreLabel,
    required this.bestScoreLabel,
    required this.currentStreakLabel,
    required this.weakestCocktails,
    required this.strongestCocktails,
    required this.weakIngredients,
    required this.guestExperienceRisks,
    required this.recommendedStudyTopics,
    required this.potentialOverpourCostLabel,
    required this.guestRiskCountLabel,
    required this.highConfidenceMissLabel,
    required this.scoreTrendEntries,
  });

  final int quizCount;
  final int averageScore;
  final String confidenceLabel;
  final String latestScoreLabel;
  final String bestScoreLabel;
  final String currentStreakLabel;
  final Map<String, int> weakestCocktails;
  final Map<String, int> strongestCocktails;
  final Map<String, int> weakIngredients;
  final List<String> guestExperienceRisks;
  final List<String> recommendedStudyTopics;
  final String potentialOverpourCostLabel;
  final String guestRiskCountLabel;
  final String highConfidenceMissLabel;
  final List<({String label, int value})> scoreTrendEntries;
  int get totalWeakCocktailMisses =>
      weakestCocktails.values.fold(0, (sum, value) => sum + value);
  int get totalWeakIngredientMisses =>
      weakIngredients.values.fold(0, (sum, value) => sum + value);

  factory _ProgressStats.fromAttempts({
    required List<QuizAttempt> attempts,
    required Map<String, CocktailRecipe> recipesById,
  }) {
    if (attempts.isEmpty) {
      return const _ProgressStats(
        quizCount: 0,
        averageScore: 0,
        confidenceLabel: 'Just getting started',
        latestScoreLabel: 'No score yet',
        bestScoreLabel: 'No score yet',
        currentStreakLabel: '0',
        weakestCocktails: {},
        strongestCocktails: {},
        weakIngredients: {},
        guestExperienceRisks: [],
        recommendedStudyTopics: [],
        potentialOverpourCostLabel: '£0.00',
        guestRiskCountLabel: '0 guest risks logged',
        highConfidenceMissLabel: '0 high-confidence misses',
        scoreTrendEntries: [],
      );
    }

    final weakCocktails = <String, int>{};
    final strongCocktails = <String, int>{};
    final weakIngredients = <String, int>{};
    final guestExperienceRisks = <String>[];
    final recommendedStudyTopics = <String>{};
    var totalScore = 0;
    var potentialOverpourCost = 0.0;
    var highConfidenceMisses = 0;

    for (final attempt in attempts) {
      totalScore += attempt.scorePercent;
      potentialOverpourCost += attempt.overpourLines.fold<double>(
        0,
        (sum, line) => sum + line.approximateValue,
      );
      potentialOverpourCost += attempt.batchOverpourLines.fold<double>(
        0,
        (sum, line) => sum + line.approximateValue,
      );
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
        if (response.isHighConfidenceMiss) {
          highConfidenceMisses += 1;
          recommendedStudyTopics.add(
            'High-confidence miss: ${response.question.cocktailName}',
          );
        }
        if (response.question.kind == QuestionKind.ingredientMeasure ||
            response.question.kind == QuestionKind.batchAmount) {
          recommendedStudyTopics.add(
            'Specification accuracy: ${response.question.cocktailName}',
          );
        }
      }
      for (final response in attempt.responses.where((item) => item.isCorrect)) {
        final recipeName =
            recipesById[response.question.cocktailId]?.name ??
            response.question.cocktailName;
        strongCocktails.update(
          recipeName,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
      for (final line in attempt.underpourLines) {
        guestExperienceRisks.add(
          '${line.ingredientName} underpour risk · ${line.totalMl.toStringAsFixed(0)}ml below spec across service volume',
        );
      }
    }

    final sortedCocktails = weakCocktails.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sortedStrongCocktails = strongCocktails.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sortedIngredients = weakIngredients.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final averageScore = (totalScore / attempts.length).round();
    final latestAttempt = attempts.first;
    final ordered = [...attempts]
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    var streak = 0;
    for (final attempt in ordered) {
      if (!attempt.passed) {
        break;
      }
      streak += 1;
    }
    final currency = NumberFormat.currency(symbol: '£', decimalDigits: 2);
    final trendEntries = ordered
        .take(6)
        .toList()
        .reversed
        .map(
          (attempt) => (
            label: DateFormat('d MMM').format(attempt.submittedAt),
            value: attempt.scorePercent,
          ),
        )
        .toList();

    return _ProgressStats(
      quizCount: attempts.length,
      averageScore: averageScore,
      confidenceLabel: averageScore >= 85
          ? 'Feeling strong'
          : averageScore >= 65
          ? 'Building well'
          : 'Worth a refresher',
      latestScoreLabel: '${latestAttempt.scorePercent}%',
      bestScoreLabel:
          '${attempts.map((attempt) => attempt.scorePercent).reduce((a, b) => a > b ? a : b)}%',
      currentStreakLabel: '$streak',
      weakestCocktails: {
        for (final entry in sortedCocktails.take(6)) entry.key: entry.value,
      },
      strongestCocktails: {
        for (final entry in sortedStrongCocktails.take(6)) entry.key: entry.value,
      },
      weakIngredients: {
        for (final entry in sortedIngredients.take(6)) entry.key: entry.value,
      },
      guestExperienceRisks: guestExperienceRisks.take(6).toList(),
      recommendedStudyTopics: recommendedStudyTopics.take(6).toList(),
      potentialOverpourCostLabel: currency.format(potentialOverpourCost),
      guestRiskCountLabel:
          '${guestExperienceRisks.length} guest risk${guestExperienceRisks.length == 1 ? '' : 's'} logged',
      highConfidenceMissLabel:
          '$highConfidenceMisses high-confidence miss${highConfidenceMisses == 1 ? '' : 'es'}',
      scoreTrendEntries: trendEntries,
    );
  }
}
