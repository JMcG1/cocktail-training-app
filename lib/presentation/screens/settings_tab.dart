import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/utils/browser_app_recovery.dart';
import '../../core/utils/commodity_csv_ingredient_importer.dart';
import '../../domain/models/models.dart';
import '../controllers/app_controller.dart';
import 'shell_route_helpers.dart';
import 'shell_support_widgets.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({
    super.key,
    required this.controller,
    required this.isOnline,
  });

  final AppController controller;
  final bool isOnline;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  bool _isImporting = false;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final approvedIngredients = _approvedIngredients(controller);
    final missingIngredients =
        approvedIngredients
            .where((ingredient) => !ingredient.hasCompletePricing)
            .toList()
          ..sort((left, right) {
            final leftMissing = _missingPricingParts(left).length;
            final rightMissing = _missingPricingParts(right).length;
            if (leftMissing != rightMissing) {
              return rightMissing.compareTo(leftMissing);
            }
            return left.name.compareTo(right.name);
          });
    final pricedCount = approvedIngredients
        .where((ingredient) => ingredient.hasCompletePricing)
        .length;
    final missingBottleSizeCount = missingIngredients
        .where(
          (ingredient) => ingredient.bottleSizeMl <= 0 && !ingredient.isGarnish,
        )
        .length;
    final missingBottlePriceCount = missingIngredients
        .where(
          (ingredient) => ingredient.bottleCost <= 0 && !ingredient.isGarnish,
        )
        .length;
    final garnishCount = approvedIngredients
        .where((ingredient) => ingredient.isGarnish)
        .length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const HeaderCard(
          title: 'Settings',
          subtitle:
              'Check app status, refresh the workspace if something looks stale, and keep ingredient cost details up to date.',
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'App status',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                DataLine(label: 'Build', value: controller.buildMarker),
                DataLine(label: 'Version', value: controller.appVersionLabel),
                DataLine(label: 'Runtime', value: controller.runtimeModeLabel),
                DataLine(
                  label: 'Backend',
                  value: controller.backendProfileLabel,
                ),
                DataLine(
                  label: 'Venue ID',
                  value:
                      controller.currentUser?.venueId ??
                      controller.catalogPathLabel,
                ),
                DataLine(
                  label: 'Live cocktails',
                  value: '${controller.recipes.length}',
                ),
                DataLine(
                  label: 'Live batches',
                  value: '${controller.batches.length}',
                ),
                DataLine(
                  label: 'Online',
                  value: widget.isOnline ? 'Yes' : 'No',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton(
                      onPressed: () async {
                        await BrowserAppRecovery.refreshApp();
                      },
                      child: const Text('Refresh app'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        await BrowserAppRecovery.clearSavedAppData();
                      },
                      child: const Text('Clear saved app data'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text: weeklyResultsExportJson(
                              controller.quizAttempts,
                            ),
                          ),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Quiz data copied.')),
                          );
                        }
                      },
                      child: const Text('Copy diagnostics'),
                    ),
                  ],
                ),
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
                Text(
                  'Ingredient costs',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use the commodity CSV as a starting point for bottle size and bottle price, then keep the saved venue values up to date manually here when needed.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    InfoMetric(
                      label: 'Approved ingredients',
                      value: '${approvedIngredients.length}',
                    ),
                    InfoMetric(label: 'Priced', value: '$pricedCount'),
                    InfoMetric(
                      label: 'Missing',
                      value: '${approvedIngredients.length - pricedCount}',
                    ),
                    InfoMetric(
                      label: 'Missing bottle size',
                      value: '$missingBottleSizeCount',
                    ),
                    InfoMetric(
                      label: 'Missing bottle price',
                      value: '$missingBottlePriceCount',
                    ),
                    InfoMetric(label: 'Garnish', value: '$garnishCount'),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: controller.canAccessAdminSetup && !_isImporting
                          ? _importCommodityCsv
                          : null,
                      icon: _isImporting
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file_outlined),
                      label: const Text('Import prices from commodity CSV'),
                    ),
                    if (!controller.canAccessAdminSetup)
                      const Text(
                        'Owner/admin access is required to change ingredient costs.',
                      ),
                  ],
                ),
                if (controller.latestCommodityIngredientImportResult !=
                    null) ...[
                  const SizedBox(height: 16),
                  CommodityImportSummaryCard(
                    result: controller.latestCommodityIngredientImportResult!,
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Needs pricing',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  missingIngredients.isEmpty
                      ? 'Every approved ingredient has a bottle size and bottle price saved.'
                      : 'These approved ingredients still need bottle size, bottle price, or both.',
                ),
                if (missingIngredients.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...missingIngredients.map(
                    (ingredient) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: MissingIngredientCostRow(
                        ingredient: ingredient,
                        canEdit: controller.canAccessAdminSetup,
                        onEdit: () => _editIngredient(ingredient),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Manual adjustments',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Manual edits save straight into this venue so your ingredient prices stay in place after refreshes and future logins.',
                ),
                const SizedBox(height: 12),
                ...approvedIngredients.map(
                  (ingredient) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: IngredientCostRow(
                      ingredient: ingredient,
                      canEdit: controller.canAccessAdminSetup,
                      onEdit: () => _editIngredient(ingredient),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Ingredient> _approvedIngredients(AppController controller) {
    final usedNames = <String>{
      for (final recipe in controller.recipes)
        ...recipe.ingredients
            .map((item) => item.ingredientName.trim())
            .where((name) => name.isNotEmpty),
      for (final batch in controller.batches)
        ...batch.ingredients
            .map((item) => item.ingredientName.trim())
            .where((name) => name.isNotEmpty),
    };
    final byKey = {
      for (final ingredient in controller.ingredients)
        normalizeIngredientName(ingredient.name): ingredient,
    };
    final approved = [
      for (final name in usedNames)
        byKey[normalizeIngredientName(name)] ??
            Ingredient(
              id: 'pending-${normalizeIngredientName(name)}',
              name: name,
              bottleSizeMl: 0,
              bottleCost: 0,
            ),
    ]..sort((left, right) => left.name.compareTo(right.name));
    return approved;
  }

  List<String> _missingPricingParts(Ingredient ingredient) {
    return [
      if (ingredient.bottleSizeMl <= 0 && !ingredient.isGarnish) 'bottle size',
      if (ingredient.bottleCost <= 0 && !ingredient.isGarnish) 'bottle price',
    ];
  }

  Future<void> _importCommodityCsv() async {
    setState(() => _isImporting = true);
    try {
      final pick = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true,
        dialogTitle: 'Select commodity CSV',
      );
      if (!mounted || pick == null || pick.files.isEmpty) {
        return;
      }
      final file = pick.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw Exception('The selected CSV could not be read.');
      }
      final csvText = utf8.decode(bytes, allowMalformed: true);
      final result = await widget.controller
          .importIngredientCostsFromCommodityCsv(csvText);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${result.matchedIngredients.length} ingredient prices. ${result.unmatchedIngredientNames.length} still need manual entry.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _editIngredient(Ingredient ingredient) async {
    final sizeController = TextEditingController(
      text: ingredient.bottleSizeMl == 0
          ? ''
          : ingredient.bottleSizeMl.toStringAsFixed(
              ingredient.bottleSizeMl.truncateToDouble() ==
                      ingredient.bottleSizeMl
                  ? 0
                  : 2,
            ),
    );
    final priceController = TextEditingController(
      text: ingredient.bottleCost == 0
          ? ''
          : ingredient.bottleCost.toStringAsFixed(2),
    );
    var isGarnish = ingredient.isGarnish;
    String? validationMessage;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Edit ${ingredient.name}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: sizeController,
                    decoration: const InputDecoration(
                      labelText: 'Bottle size (ml)',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceController,
                    decoration: const InputDecoration(
                      labelText: 'Bottle price',
                      prefixText: '£',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: isGarnish,
                    title: const Text('Mark as garnish'),
                    subtitle: const Text(
                      'Garnish items can be kept at zero bottle size and zero price.',
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        isGarnish = value;
                        validationMessage = null;
                      });
                    },
                  ),
                  if (validationMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      validationMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final rawBottleSize = sizeController.text.trim();
                    final rawBottleCost = priceController.text.trim();
                    final bottleSizeMl = rawBottleSize.isEmpty
                        ? 0
                        : double.tryParse(rawBottleSize);
                    final bottleCost = rawBottleCost.isEmpty
                        ? 0
                        : double.tryParse(rawBottleCost);
                    final invalidStandardIngredient =
                        !isGarnish &&
                        (bottleSizeMl == null ||
                            bottleSizeMl <= 0 ||
                            bottleCost == null ||
                            bottleCost < 0);
                    final invalidGarnish =
                        isGarnish &&
                        (bottleSizeMl == null ||
                            bottleSizeMl < 0 ||
                            bottleCost == null ||
                            bottleCost < 0);
                    if (invalidStandardIngredient || invalidGarnish) {
                      setDialogState(() {
                        validationMessage = isGarnish
                            ? 'Enter zero or a positive value for garnish bottle size and bottle price.'
                            : 'Enter a valid bottle size in ml and use zero or a positive bottle price.';
                      });
                      return;
                    }
                    try {
                      await widget.controller.saveIngredient(
                        name: ingredient.name,
                        bottleSizeMl: bottleSizeMl!.toDouble(),
                        bottleCost: bottleCost!.toDouble(),
                        isGarnish: isGarnish,
                      );
                      if (!context.mounted) {
                        return;
                      }
                      Navigator.of(context).pop(true);
                    } catch (error) {
                      setDialogState(() {
                        validationMessage =
                            widget.controller.errorMessage ??
                            error.toString().replaceFirst('Exception: ', '');
                      });
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    sizeController.dispose();
    priceController.dispose();

    if (saved == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${ingredient.name} updated.')));
    }
  }
}

class CommodityImportSummaryCard extends StatelessWidget {
  const CommodityImportSummaryCard({super.key, required this.result});

  final CommodityIngredientImportResult result;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '£', decimalDigits: 2);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101417),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF293037)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Latest import summary',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Text(
            'Matched ${result.matchedIngredients.length} ingredients. ${result.unmatchedIngredientNames.length} still need manual entry.',
          ),
          if (result.matchedIngredients.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Matched ingredients',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            ...result.matchedIngredients.map(
              (match) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${match.ingredient.name} · ${formatMl(match.bottleSizeMl)} · ${currency.format(match.bottlePrice)} · ${match.sourceProductName}',
                ),
              ),
            ),
          ],
          if (result.unmatchedIngredientNames.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Unmatched ingredients needing manual entry',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: result.unmatchedIngredientNames
                  .map((name) => Chip(label: Text(name)))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class DataLine extends StatelessWidget {
  const DataLine({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class IngredientCostRow extends StatelessWidget {
  const IngredientCostRow({
    super.key,
    required this.ingredient,
    required this.canEdit,
    required this.onEdit,
  });

  final Ingredient ingredient;
  final bool canEdit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final price = ingredient.isGarnish && ingredient.bottleCost == 0
        ? 'Garnish'
        : ingredient.bottleCost > 0
        ? NumberFormat.currency(
            symbol: '£',
            decimalDigits: 2,
          ).format(ingredient.bottleCost)
        : 'Missing';
    final size = ingredient.isGarnish && ingredient.bottleSizeMl == 0
        ? 'Garnish'
        : ingredient.bottleSizeMl > 0
        ? formatMl(ingredient.bottleSizeMl)
        : 'Missing';
    final costPerMl = ingredient.isGarnish
        ? 'Intentionally zero'
        : ingredient.bottleSizeMl > 0 && ingredient.bottleCost > 0
        ? '${(ingredient.costPerMl).toStringAsFixed(4)}/ml'
        : 'Waiting for pricing';

    Widget details() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ingredient.name,
            style: Theme.of(context).textTheme.titleMedium,
            softWrap: true,
          ),
          const SizedBox(height: 6),
          if (ingredient.isGarnish)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Chip(
                label: const Text('Garnish'),
                visualDensity: VisualDensity.compact,
              ),
            ),
          Text('Bottle size: $size'),
          Text('Bottle price: $price'),
          Text('Ingredient cost: $costPerMl'),
        ],
      );
    }

    Widget editButton({bool fullWidth = false}) {
      return SizedBox(
        width: fullWidth ? double.infinity : null,
        child: OutlinedButton(
          onPressed: canEdit ? onEdit : null,
          child: const Text('Edit'),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF293037)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useStackedLayout = constraints.maxWidth < 520;
          if (useStackedLayout) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                details(),
                const SizedBox(height: 12),
                editButton(fullWidth: true),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: details()),
              const SizedBox(width: 12),
              editButton(),
            ],
          );
        },
      ),
    );
  }
}

class MissingIngredientCostRow extends StatelessWidget {
  const MissingIngredientCostRow({
    super.key,
    required this.ingredient,
    required this.canEdit,
    required this.onEdit,
  });

  final Ingredient ingredient;
  final bool canEdit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final missingParts = <String>[
      if (ingredient.bottleSizeMl <= 0 && !ingredient.isGarnish) 'bottle size',
      if (ingredient.bottleCost <= 0 && !ingredient.isGarnish) 'bottle price',
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF5B4630)),
        color: const Color(0x14F2B56B),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useStackedLayout = constraints.maxWidth < 520;

          Widget content() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ingredient.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Missing ${missingParts.join(' and ')}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ],
            );
          }

          Widget button({bool fullWidth = false}) {
            return SizedBox(
              width: fullWidth ? double.infinity : null,
              child: OutlinedButton(
                onPressed: canEdit ? onEdit : null,
                child: const Text('Edit'),
              ),
            );
          }

          if (useStackedLayout) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                content(),
                const SizedBox(height: 12),
                button(fullWidth: true),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: content()),
              const SizedBox(width: 12),
              button(),
            ],
          );
        },
      ),
    );
  }
}

String formatMl(double value) {
  if (value.truncateToDouble() == value) {
    return '${value.toStringAsFixed(0)}ml';
  }
  return '${value.toStringAsFixed(2)}ml';
}

String normalizeIngredientName(String value) {
  return value
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r"[^a-z0-9']+"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
