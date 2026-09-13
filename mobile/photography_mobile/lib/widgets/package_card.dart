import 'package:flutter/material.dart';

import '../models/photography_package.dart';

class PackageCard extends StatelessWidget {
  const PackageCard({
    super.key,
    required this.package,
    this.onView,
    this.detail = false,
  });
  final PhotographyPackage package;
  final VoidCallback? onView;
  final bool detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hours = package.durationHours;
    final duration = hours.toStringAsFixed(
      hours == hours.roundToDouble() ? 0 : 2,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              package.name.isEmpty ? 'Photography package' : package.name,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              package.description.isEmpty
                  ? 'No description provided.'
                  : package.description,
              maxLines: detail ? null : 3,
              overflow: detail ? null : TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            Text(
              formatLkr(package.basePrice),
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                Text('$duration hours'),
                Text('${package.numberOfPhotographers} photographers'),
                Text('${package.editedPhotoCount} edited photos'),
                Text('Album included: ${package.albumIncluded ? 'Yes' : 'No'}'),
                Text('Video included: ${package.videoIncluded ? 'Yes' : 'No'}'),
              ],
            ),
            const SizedBox(height: 16),
            Text('Included Services', style: theme.textTheme.titleSmall),
            if (package.services.isEmpty)
              const Text('No included services listed.'),
            ...package.services.map(
              (service) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '• ${service.serviceName.isEmpty ? 'Photography service' : service.serviceName}${detail && service.description.isNotEmpty ? '\n${service.description}' : ''}',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('${package.addons.length} available add-ons'),
            if (onView != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onView,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('View Details'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
