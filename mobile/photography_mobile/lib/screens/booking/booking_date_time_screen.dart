import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/photography_package.dart';
import '../../models/studio_availability.dart';
import '../../services/studio_service.dart';
import '../../widgets/studio_error.dart';
import 'booking_summary_screen.dart';

class BookingDateTimeScreen extends StatefulWidget {
  const BookingDateTimeScreen({
    super.key,
    required this.package,
    required this.customization,
    this.estimate,
    this.studioName,
  });

  final PhotographyPackage package;
  final PackageCustomization customization;
  final PackagePriceSummary? estimate;
  final String? studioName;

  @override
  State<BookingDateTimeScreen> createState() => _BookingDateTimeScreenState();
}

class _BookingDateTimeScreenState extends State<BookingDateTimeScreen> {
  final _service = StudioService();
  late Future<List<StudioAvailability>> _availability;
  StudioAvailability? _selected;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _load();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {
        if (_selected != null && !_isSelectable(_selected!)) _selected = null;
      });
    });
  }

  void _load() {
    _selected = null;
    _availability = _service.getAvailability(widget.package.studioId);
  }

  DateTime? _time(StudioAvailability slot, String? time) {
    if (time == null) return null;
    final date = slot.date.toIso8601String().split('T').first;
    return DateTime.tryParse('${date}T$time');
  }

  bool _isSelectable(StudioAvailability slot) {
    final start = _time(slot, slot.startTime);
    final end = _time(slot, slot.endTime);
    return slot.isAvailable && start != null && end != null &&
        start.isAfter(DateTime.now()) && end.isAfter(start);
  }

  void _continue() {
    final slot = _selected;
    if (slot == null || !_isSelectable(slot)) {
      setState(() => _selected = null);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BookingSummaryScreen(
        studioName: widget.studioName,
        package: widget.package,
        customization: widget.customization,
        estimate: widget.estimate,
        slot: slot,
      ),
    ));
  }

  @override
  void dispose() {
    _clock?.cancel();
    _service.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Select date & time')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: FutureBuilder<List<StudioAvailability>>(
              future: _availability,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return StudioError(error: snapshot.error!, onRetry: () => setState(_load));
                }
                final slots = (snapshot.data ?? const <StudioAvailability>[])
                    .where(_isSelectable).toList()
                  ..sort((a, b) => _time(a, a.startTime)!.compareTo(_time(b, b.startTime)!));
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.package.name, style: theme.textTheme.titleLarge),
                          const SizedBox(height: 8),
                          const Text('Choose one available date and time range.'),
                          if (widget.estimate != null) ...[
                            const SizedBox(height: 8),
                            Text('Package estimate: ${formatLkr(widget.estimate!.finalPrice)}'),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      child: slots.isEmpty
                          ? const Center(child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('No upcoming bookable time slots available.', textAlign: TextAlign.center),
                            ))
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: slots.length,
                              itemBuilder: (context, index) {
                                final slot = slots[index];
                                final selected = identical(_selected, slot);
                                return Semantics(
                                  selected: selected,
                                  button: true,
                                  child: Card(
                                    color: selected ? theme.colorScheme.primaryContainer : null,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                      side: BorderSide(color: selected
                                          ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                                        width: selected ? 2 : 1),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(18),
                                      onTap: () => setState(() => _selected = slot),
                                      child: Padding(
                                        padding: const EdgeInsets.all(18),
                                        child: Row(children: [
                                          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                            color: theme.colorScheme.primary),
                                          const SizedBox(width: 14),
                                          Expanded(child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(MaterialLocalizations.of(context).formatFullDate(slot.date),
                                                style: theme.textTheme.titleMedium),
                                              const SizedBox(height: 6),
                                              Text('${slot.startTime} – ${slot.endTime}'),
                                              if (selected) const Text('Selected'),
                                            ],
                                          )),
                                        ]),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: FilledButton(
                        onPressed: _selected != null && _isSelectable(_selected!) ? _continue : null,
                        child: const Padding(padding: EdgeInsets.all(16), child: Text('Continue')),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
