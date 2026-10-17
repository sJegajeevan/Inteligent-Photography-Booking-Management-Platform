import 'package:flutter/material.dart';

import '../models/photography_package.dart';
import '../screens/package/package_detail_screen.dart';
import '../services/package_service.dart';
import 'package_card.dart';
import 'package_error.dart';

class StudioPackagesSection extends StatefulWidget {
  const StudioPackagesSection({
    super.key,
    required this.studioId,
    this.studioName,
    this.service,
  });
  final String studioId;
  final String? studioName;
  final PackageService? service;
  @override
  State<StudioPackagesSection> createState() => _StudioPackagesSectionState();
}

class _StudioPackagesSectionState extends State<StudioPackagesSection> {
  late final PackageService _service = widget.service ?? PackageService();
  late Future<List<PhotographyPackage>> _packages;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _packages = _service.getPackages(widget.studioId);
  }

  @override
  void didUpdateWidget(covariant StudioPackagesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studioId != widget.studioId) _load();
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Packages',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          IconButton(
            tooltip: 'Refresh packages',
            onPressed: () => setState(_load),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      const SizedBox(height: 12),
      FutureBuilder<List<PhotographyPackage>>(
        future: _packages,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            );
          }
          if (snapshot.hasError) {
            return PackageError(
              error: snapshot.error!,
              onRetry: () => setState(_load),
            );
          }
          final packages = snapshot.data!;
          if (packages.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No packages available for this studio.'),
            );
          }
          return Column(
            children: packages
                .map(
                  (package) => PackageCard(
                    package: package,
                    onView: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PackageDetailScreen(
                          studioName: widget.studioName,
                          studioId: widget.studioId,
                          packageId: package.id,
                          allowCustomization: false,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
    ],
  );
}
