import 'package:flutter/material.dart';

import '../models/studio_availability.dart';
import '../services/studio_service.dart';
import 'studio_error.dart';

class StudioAvailabilityTab extends StatefulWidget {
  const StudioAvailabilityTab({
    super.key,
    required this.studioId,
    required this.service,
  });

  final String studioId;
  final StudioService service;

  @override
  State<StudioAvailabilityTab> createState() => _StudioAvailabilityTabState();
}

class _StudioAvailabilityTabState extends State<StudioAvailabilityTab> {
  late Future<List<StudioAvailability>> _availability;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant StudioAvailabilityTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studioId != widget.studioId ||
        oldWidget.service != widget.service) {
      _load();
    }
  }

  void _load() {
    _availability = widget.service.getAvailability(widget.studioId);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<StudioAvailability>>(
    future: _availability,
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
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final slots = (snapshot.data ?? const <StudioAvailability>[])
          .where((slot) => !slot.date.isBefore(today))
          .toList()
        ..sort((a, b) {
          final dateOrder = a.date.compareTo(b.date);
          if (dateOrder != 0) return dateOrder;
          // Missing times follow timed slots on the same date.
          final startOrder = (a.startTime ?? '99').compareTo(b.startTime ?? '99');
          if (startOrder != 0) return startOrder;
          return (a.endTime ?? '99').compareTo(b.endTime ?? '99');
        });
      if (slots.isEmpty) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No upcoming availability available.',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: slots.length,
            separatorBuilder: (_, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _AvailabilityCard(slot: slots[index]),
          ),
        ),
      );
    },
  );
}

class _AvailabilityCard extends StatelessWidget {
  const _AvailabilityCard({required this.slot});
  final StudioAvailability slot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statusColor = slot.isAvailable ? colors.primary : colors.onSurfaceVariant;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              MaterialLocalizations.of(context).formatFullDate(slot.date),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: slot.isAvailable
                    ? colors.primaryContainer
                    : colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    slot.isAvailable
                        ? Icons.check_circle_outline
                        : Icons.block,
                    size: 18,
                    color: statusColor,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      slot.isAvailable ? 'Available' : 'Unavailable',
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Start time: ${slot.startTime ?? 'Not specified'}'),
            const SizedBox(height: 6),
            Text('End time: ${slot.endTime ?? 'Not specified'}'),
          ],
        ),
      ),
    );
  }
}
