import 'package:flutter/material.dart';

import '../../models/photography_package.dart';
import '../../services/package_service.dart';
import '../../widgets/package_card.dart';
import '../../widgets/package_error.dart';

class PackageDetailScreen extends StatefulWidget {
  const PackageDetailScreen({
    super.key,
    required this.studioId,
    required this.packageId,
    this.service,
  });
  final String studioId, packageId;
  final PackageService? service;
  @override
  State<PackageDetailScreen> createState() => _PackageDetailScreenState();
}

class _PackageDetailScreenState extends State<PackageDetailScreen> {
  late final PackageService _service = widget.service ?? PackageService();
  late Future<PhotographyPackage> _package;
  final Set<String> _selected = {};
  int _extraHours = 0, _photographers = 0, _generation = 0;
  bool _calculating = false;
  PackagePriceSummary? _summary;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _generation++;
    _selected.clear();
    _extraHours = 0;
    _photographers = 0;
    _summary = null;
    _error = null;
    _calculating = false;
    _package = _service.getPackage(widget.studioId, widget.packageId);
  }

  @override
  void didUpdateWidget(covariant PackageDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packageId != widget.packageId ||
        oldWidget.studioId != widget.studioId) {
      _load();
    }
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  void _change(VoidCallback change) => setState(() {
    change();
    _summary = null;
    _error = null;
  });

  Future<void> _calculate(PhotographyPackage package) async {
    if (_calculating) return;
    final generation = _generation;
    setState(() {
      _calculating = true;
      _summary = null;
      _error = null;
    });
    try {
      final result = await _service.calculatePrice(
        package,
        PackageCustomization(
          selectedAddonIds: _selected,
          extraHours: _extraHours,
          additionalPhotographers: _photographers,
        ),
      );
      if (mounted && generation == _generation) {
        setState(() => _summary = result);
      }
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _calculating = false);
      }
    }
  }

  Widget _counter(String label, int value, int max, ValueChanged<int> change) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Decrease $label',
                  onPressed: _calculating || value == 0
                      ? null
                      : () => _change(() => change(value - 1)),
                  icon: const Icon(Icons.remove),
                ),
                Text('$value', style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  tooltip: 'Increase $label',
                  onPressed: _calculating || value >= max
                      ? null
                      : () => _change(() => change(value + 1)),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Package details')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: FutureBuilder<PhotographyPackage>(
            future: _package,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return SingleChildScrollView(
                  child: PackageError(
                    error: snapshot.error!,
                    onRetry: () => setState(_load),
                  ),
                );
              }
              final package = snapshot.data!;
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  PackageCard(package: package, detail: true),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Customize Package',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Available Add-ons',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (package.addons.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'No add-ons available for this package.',
                              ),
                            ),
                          ...package.addons.map(
                            (addon) => CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(
                                addon.name.isEmpty
                                    ? 'Package add-on'
                                    : addon.name,
                              ),
                              subtitle: Text(
                                '${formatLkr(addon.price)}${addon.description.isEmpty ? '' : '\n${addon.description}'}',
                              ),
                              value: _selected.contains(addon.id),
                              onChanged: _calculating
                                  ? null
                                  : (checked) => _change(() {
                                      if (checked == true) {
                                        _selected.add(addon.id);
                                      } else {
                                        _selected.remove(addon.id);
                                      }
                                    }),
                            ),
                          ),
                          const Divider(height: 24),
                          Text(
                            'Extra hour rate: ${formatLkr(package.extraHourRate)}',
                          ),
                          _counter(
                            'Extra Hours',
                            _extraHours,
                            1000,
                            (value) => _extraHours = value,
                          ),
                          Text(
                            'Additional photographer rate: ${formatLkr(package.additionalPhotographerRate)}',
                          ),
                          _counter(
                            'Additional Photographers',
                            _photographers,
                            100,
                            (value) => _photographers = value,
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _calculating
                                ? null
                                : () => _calculate(package),
                            child: Text(
                              _calculating ? 'Calculating…' : 'Calculate Price',
                            ),
                          ),
                          if (_calculating)
                            const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: LinearProgressIndicator(),
                            ),
                          if (_error != null)
                            PackageError(
                              error: _error!,
                              onRetry:
                                  _error is PackageApiException &&
                                      (_error as PackageApiException)
                                              .statusCode ==
                                          404
                                  ? () => setState(_load)
                                  : () => _calculate(package),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (_summary != null) _PriceSummary(summary: _summary!),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _PriceSummary extends StatelessWidget {
  const _PriceSummary({required this.summary});
  final PackagePriceSummary summary;
  @override
  Widget build(BuildContext context) {
    Widget line(String label, double amount) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 16,
        runSpacing: 4,
        children: [Text(label), Text(formatLkr(amount))],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Price Summary',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            line('Base Package', summary.basePrice),
            Text(
              'Selected Add-ons',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (summary.selectedAddons.isEmpty)
              const Text('No add-ons selected.'),
            ...summary.selectedAddons.map(
              (addon) => line(addon.name, addon.price),
            ),
            line('Extra Hours (${summary.extraHours})', summary.extraHoursCost),
            line(
              'Additional Photographers (${summary.additionalPhotographers})',
              summary.additionalPhotographersCost,
            ),
            const Divider(),
            Text('Total', style: Theme.of(context).textTheme.titleMedium),
            Text(
              formatLkr(summary.finalPrice),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
