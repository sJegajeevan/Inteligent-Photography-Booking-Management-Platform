import 'package:flutter/material.dart';

import '../../models/photography_package.dart';
import '../../services/package_service.dart';
import '../../widgets/package_error.dart';
import '../../widgets/studio_image.dart';
import '../booking/booking_date_time_screen.dart';

class PackageDetailScreen extends StatefulWidget {
  const PackageDetailScreen({
    super.key,
    required this.studioId,
    required this.packageId,
    this.studioName,
    this.service,
    this.allowCustomization = false,
  });
  final String studioId, packageId;
  final String? studioName;
  final PackageService? service;
  final bool allowCustomization;
  @override
  State<PackageDetailScreen> createState() => _PackageDetailScreenState();
}

class _PackageDetailScreenState extends State<PackageDetailScreen> {
  late final PackageService _service = widget.service ?? PackageService();
  late Future<PhotographyPackage> _package;
  final Set<String> _selected = {};
  int _extraHours = 0, _photographers = 0, _generation = 0;
  bool _calculating = false;
  bool _showCustomization = false;
  PackagePriceSummary? _summary;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final generation = ++_generation;
    _showCustomization = widget.allowCustomization;
    _selected.clear();
    _extraHours = 0;
    _photographers = 0;
    _summary = null;
    _error = null;
    _calculating = false;
    _package = _service.getPackage(widget.studioId, widget.packageId).then((package) {
      if (mounted && generation == _generation && _showCustomization) {
        _calculate(package);
      }
      return package;
    });
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

  void _change(PhotographyPackage package, VoidCallback change) {
    setState(() {
      change();
      _summary = null;
      _error = null;
    });
    _calculate(package);
  }

  void _openCustomization(PhotographyPackage package) {
    setState(() => _showCustomization = true);
    _calculate(package);
  }

  void _selectBookingTime(PhotographyPackage package) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BookingDateTimeScreen(
        studioName: widget.studioName,
        package: package,
        customization: PackageCustomization(
          selectedAddonIds: _selected,
          extraHours: _extraHours,
          additionalPhotographers: _photographers,
        ),
        estimate: _summary,
      ),
    ));
  }

  Future<void> _calculate(PhotographyPackage package) async {
    // Each request supersedes earlier estimates, including errors. Customers
    // can keep adjusting selections while the server calculates the price.
    final generation = ++_generation;
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

  Widget _counter(PhotographyPackage package, String label, int value, int max, ValueChanged<int> change) =>
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
                  onPressed: value == 0
                      ? null
                      : () => _change(package, () => change(value - 1)),
                  icon: const Icon(Icons.remove),
                ),
                Text('$value', style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  tooltip: 'Increase $label',
                  onPressed: value >= max
                      ? null
                      : () => _change(package, () => change(value + 1)),
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
                  _PackageOverview(package: package),
                  if (_showCustomization)
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
                              onChanged: (checked) => _change(package, () {
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
                            package,
                            'Extra Hours',
                            _extraHours,
                            1000,
                            (value) => _extraHours = value,
                          ),
                          Text(
                            'Additional photographer rate: ${formatLkr(package.additionalPhotographerRate)}',
                          ),
                          _counter(
                            package,
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
                              child: Column(
                                children: [
                                  LinearProgressIndicator(),
                                  SizedBox(height: 8),
                                  Text('Updating estimated total…'),
                                ],
                              ),
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
                  if (_showCustomization && _summary != null)
                    Semantics(
                      liveRegion: true,
                      child: _PriceSummary(summary: _summary!),
                    ),
                  const SizedBox(height: 8),
                  if (!_showCustomization)
                    FilledButton(
                      onPressed: () => _selectBookingTime(package),
                      child: const Text('Continue to Booking'),
                    ),
                  if (!_showCustomization)
                    FilledButton(
                      onPressed: () => _openCustomization(package),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('Customize Package'),
                      ),
                    )
                  else ...[
                    FilledButton(
                      onPressed: _calculating || _summary == null || _error != null
                          ? null : () => _selectBookingTime(package),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('Continue to Booking'),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 8, bottom: 12),
                      child: Text(
                        'Next: select an available date and time.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _PackageOverview extends StatelessWidget {
  const _PackageOverview({required this.package});
  final PhotographyPackage package;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hours = package.durationHours;
    final duration = hours.toStringAsFixed(hours == hours.roundToDouble() ? 0 : 2);

    Widget section(String title, List<Widget> children) => Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );

    Widget fact(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          const SizedBox(width: 12),
          Flexible(child: Text(value, textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (package.coverImageUrl.trim().isNotEmpty) ...[
          Semantics(
            label: '${package.name} package cover',
            child: ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: StudioImage(url: package.coverImageUrl),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
        Text(package.name, style: theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800, letterSpacing: -.5,
        )),
        const SizedBox(height: 12),
        Text(
          package.description.trim().isEmpty ? 'No description provided.' : package.description,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.6, color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.primaryContainer, colors.surfaceContainerLow],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Base price', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Text(formatLkr(package.basePrice), style: theme.textTheme.headlineMedium?.copyWith(
                color: colors.primary, fontWeight: FontWeight.w800,
              )),
            ],
          ),
        ),
        section('Package at a glance', [
          fact(Icons.schedule_outlined, 'Duration', '$duration ${hours == 1 ? 'hour' : 'hours'}'),
          fact(Icons.people_outline, 'Photographers', '${package.numberOfPhotographers}'),
          fact(Icons.photo_library_outlined, 'Edited photos', '${package.editedPhotoCount}'),
          fact(Icons.photo_album_outlined, 'Album included', package.albumIncluded ? 'Yes' : 'No'),
          fact(Icons.videocam_outlined, 'Video included', package.videoIncluded ? 'Yes' : 'No'),
        ]),
        section('Included services', [
          if (package.services.isEmpty) const Text('No included services listed.'),
          for (final service in package.services)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline, size: 22, color: colors.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(service.serviceName, style: theme.textTheme.titleSmall),
                      if (service.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(service.description, style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant, height: 1.5,
                        )),
                      ],
                    ],
                  )),
                ],
              ),
            ),
        ]),
        section('Available add-ons', [
          if (package.addons.isEmpty) const Text('No add-ons available for this package.'),
          for (final addon in package.addons)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(addon.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  if (addon.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(addon.description, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                  ],
                  const SizedBox(height: 10),
                  Text(formatLkr(addon.price), style: theme.textTheme.titleSmall?.copyWith(color: colors.primary)),
                ],
              ),
            ),
        ]),
      ],
    );
  }
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
            line('Base Price', summary.basePrice),
            line('Selected Add-ons', summary.selectedAddons.fold<double>(
              0, (total, addon) => total + addon.price,
            )),
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
            Text('Estimated Total', style: Theme.of(context).textTheme.titleMedium),
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
