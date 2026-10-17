import 'package:flutter/material.dart';

import '../models/studio_service_item.dart';
import '../services/studio_service.dart';
import 'studio_error.dart';

class StudioServicesTab extends StatefulWidget {
  const StudioServicesTab({
    super.key,
    required this.studioId,
    required this.service,
  });

  final String studioId;
  final StudioService service;

  @override
  State<StudioServicesTab> createState() => _StudioServicesTabState();
}

class _StudioServicesTabState extends State<StudioServicesTab> {
  late Future<List<StudioServiceItem>> _services;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant StudioServicesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studioId != widget.studioId ||
        oldWidget.service != widget.service) {
      _load();
    }
  }

  void _load() {
    _services = widget.service.getServices(widget.studioId);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<StudioServiceItem>>(
    future: _services,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return StudioError(
          error: snapshot.error!,
          onRetry: () => setState(_load),
        );
      }
      final services = snapshot.data ?? const <StudioServiceItem>[];
      if (services.isEmpty) {
        return const Center(child: Text('No services available.'));
      }
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: services.length,
            separatorBuilder: (_, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _ServiceCard(
              service: services[index],
            ),
          ),
        ),
      );
    },
  );
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service});
  final StudioServiceItem service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              service.serviceName,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              service.priceLabel,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (service.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(service.description, style: theme.textTheme.bodyMedium),
            ],
            if (service.packageDetails.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(),
              ),
              Text('Service details', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final detail in service.packageDetails)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(detail)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
