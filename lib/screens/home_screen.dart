import 'package:cocktail_training/models/cocktail.dart';
import 'package:cocktail_training/widgets/cocktail_card.dart';
import 'package:cocktail_training/widgets/metric_chip.dart';
import 'package:cocktail_training/widgets/premium_backdrop.dart';
import 'package:cocktail_training/widgets/surface_section.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.cocktails,
    required this.onSelectCocktail,
  });

  final List<Cocktail> cocktails;
  final ValueChanged<Cocktail> onSelectCocktail;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  static const _allSectionsLabel = 'All sections';
  static const _allBuildsLabel = 'All builds';

  String _query = '';
  String _selectedCategory = _allSectionsLabel;
  String _selectedBuildStyle = _allBuildsLabel;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearch);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearch)
      ..dispose();
    super.dispose();
  }

  void _handleSearch() {
    setState(() {
      _query = _searchController.text;
    });
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.cocktails.map((cocktail) => cocktail.category).toSet().toList()..sort();
    final buildStyles = widget.cocktails.map((cocktail) => cocktail.buildStyleLabel).toSet().toList()
      ..sort();

    final filtered = widget.cocktails.where((cocktail) {
      final matchesQuery = cocktail.matchesQuery(_query);
      final matchesCategory =
          _selectedCategory == _allSectionsLabel || cocktail.category == _selectedCategory;
      final matchesBuild =
          _selectedBuildStyle == _allBuildsLabel || cocktail.buildStyleLabel == _selectedBuildStyle;
      return matchesQuery && matchesCategory && matchesBuild;
    }).toList();

    final filteredSections = filtered.map((cocktail) => cocktail.category).toSet().length;
    final filteredBuilds = filtered.map((cocktail) => cocktail.buildStyleLabel).toSet().length;
    final hasActiveFilters = _query.isNotEmpty ||
        _selectedCategory != _allSectionsLabel ||
        _selectedBuildStyle != _allBuildsLabel;

    return PremiumBackdrop(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Library',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Search live serve specs, review builds quickly, and drill the details that matter during service.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search by drink, ingredient, build style, or tag',
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: _searchController.clear,
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  SurfaceSection(
                    eyebrow: 'Service filters',
                    title: 'Find specs fast',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Jump straight to the right section or build style when you need an answer quickly on the floor.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            MetricChip(
                              label: 'Results',
                              value: filtered.length.toString(),
                            ),
                            MetricChip(
                              label: 'Sections',
                              value: filteredSections.toString(),
                            ),
                            MetricChip(
                              label: 'Builds',
                              value: filteredBuilds.toString(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Sections',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _LibraryFilterChip(
                              label: _allSectionsLabel,
                              selected: _selectedCategory == _allSectionsLabel,
                              onSelected: () {
                                setState(() {
                                  _selectedCategory = _allSectionsLabel;
                                });
                              },
                            ),
                            for (final category in categories)
                              _LibraryFilterChip(
                                label: category,
                                selected: _selectedCategory == category,
                                onSelected: () {
                                  setState(() {
                                    _selectedCategory = category;
                                  });
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Build style',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _LibraryFilterChip(
                              label: _allBuildsLabel,
                              selected: _selectedBuildStyle == _allBuildsLabel,
                              onSelected: () {
                                setState(() {
                                  _selectedBuildStyle = _allBuildsLabel;
                                });
                              },
                            ),
                            for (final buildStyle in buildStyles)
                              _LibraryFilterChip(
                                label: buildStyle,
                                selected: _selectedBuildStyle == buildStyle,
                                onSelected: () {
                                  setState(() {
                                    _selectedBuildStyle = buildStyle;
                                  });
                                },
                              ),
                          ],
                        ),
                        if (hasActiveFilters) ...[
                          const SizedBox(height: 18),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _query = '';
                                  _selectedCategory = _allSectionsLabel;
                                  _selectedBuildStyle = _allBuildsLabel;
                                });
                              },
                              icon: const Icon(Icons.restart_alt),
                              label: const Text('Clear filters'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SurfaceSection(
                    eyebrow: 'Drink specs',
                    title: '${filtered.length} result${filtered.length == 1 ? '' : 's'}',
                    child: filtered.isEmpty
                        ? Text(
                            'No serves matched your search. Try a section filter, an ingredient like lime, or a drink by name.',
                            style: Theme.of(context).textTheme.bodyLarge,
                          )
                        : Column(
                            children: [
                              for (final cocktail in filtered) ...[
                                CocktailCard(
                                  cocktail: cocktail,
                                  onTap: () => widget.onSelectCocktail(cocktail),
                                ),
                                if (cocktail != filtered.last) const SizedBox(height: 14),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LibraryFilterChip extends StatelessWidget {
  const _LibraryFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: FilterChip(
        selected: selected,
        onSelected: (_) => onSelected(),
        showCheckmark: false,
        label: Text(label),
        selectedColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
        side: BorderSide(
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.32)
              : Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        ),
        labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected ? Theme.of(context).colorScheme.primary : const Color(0xFFE5D9C9),
            ),
        backgroundColor: const Color(0xFF171F27),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}
