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
  DateTime? _selectedStart;
  Duration get _duration => Duration(
    microseconds: ((widget.package.durationHours + widget.customization.extraHours) *
        Duration.microsecondsPerHour).round(),
  );
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _load();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {
          if (_selected != null && !_isSelectable(_selected!)) _selected = null;
          if (_selectedStart != null && !_selectedStart!.isAfter(DateTime.now())) {
            _selectedStart = null;
          }
        });
      }
    });
  }

  void _load() {
    _selected = null;
    _selectedStart = null;
    _availability = _service.getAvailability(widget.package.studioId);
  }

  DateTime? _time(StudioAvailability slot, String? time) {
    if (time == null) return null;
    final date = slot.date.toIso8601String().split('T').first;
    return DateTime.tryParse('${date}T$time');
  }

  bool _isSelectable(StudioAvailability slot) {
    return _startTimes(slot).isNotEmpty;
  }

  List<DateTime> _startTimes(StudioAvailability slot) {
    final start = _time(slot, slot.startTime);
    final end = _time(slot, slot.endTime);
    if (!slot.isAvailable || start == null || end == null ||
        widget.package.durationHours <= 0 ||
        widget.customization.validate(widget.package) != null ||
        _duration <= Duration.zero) {
      return [];
    }
    final now = DateTime.now();
    // Offer minute-precision starts only when the whole session fits.
    var candidate = DateTime(start.year, start.month, start.day, start.hour, start.minute);
    if (candidate.isBefore(start)) candidate = candidate.add(const Duration(minutes: 1));
    final result = <DateTime>[];
    for (; !candidate.add(_duration).isAfter(end);
        candidate = candidate.add(const Duration(minutes: 1))) {
      if (candidate.isAfter(now)) result.add(candidate);
    }
    return result;
  }

  String _displayTime(DateTime time) => MaterialLocalizations.of(context)
      .formatTimeOfDay(TimeOfDay.fromDateTime(time), alwaysUse24HourFormat: false);

  String _apiTime(DateTime time) => time.toIso8601String().split('T').last;

  void _continue() {
    final slot = _selected;
    final start = _selectedStart;
    if (slot == null || start == null || !_startTimes(slot).contains(start)) {
      setState(() => _selectedStart = null);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BookingSummaryScreen(
        studioName: widget.studioName,
        package: widget.package,
        customization: widget.customization,
        estimate: widget.estimate,
        slot: StudioAvailability(
          date: slot.date,
          isAvailable: true,
          startTime: _apiTime(start),
          endTime: _apiTime(start.add(_duration)),
        ),
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
                          const Text('Choose an availability date, then select your booking start time.'),
                          Text('Package duration: ${widget.package.durationHours.toStringAsFixed(widget.package.durationHours % 1 == 0 ? 0 : 2)} hours'),
                          Text('Extra hours: ${widget.customization.extraHours}'),
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
                                      onTap: () => setState(() {
                                        _selected = slot;
                                        _selectedStart = null;
                                      }),
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
                                              Text('Available: ${_displayTime(_time(slot, slot.startTime)!)} – ${_displayTime(_time(slot, slot.endTime)!)}'),
                                              if (selected) ...[
                                                DropdownButton<DateTime>(
                                                  isExpanded: true,
                                                  hint: const Text('Select start time'),
                                                  value: _selectedStart,
                                                  items: _startTimes(slot).map((start) => DropdownMenuItem(
                                                    value: start,
                                                    child: Text(_displayTime(start)),
                                                  )).toList(),
                                                  onChanged: (start) => setState(() => _selectedStart = start),
                                                ),
                                                if (_selectedStart != null)
                                                  Text('Selected booking: ${_displayTime(_selectedStart!)} – ${_displayTime(_selectedStart!.add(_duration))}'),
                                              ],
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
                        onPressed: _selected != null && _selectedStart != null &&
                            _startTimes(_selected!).contains(_selectedStart) ? _continue : null,
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
