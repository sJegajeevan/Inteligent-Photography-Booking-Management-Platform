import 'package:flutter/material.dart';

import '../../models/photography_package.dart';
import '../../models/studio_availability.dart';
import '../../services/booking_service.dart';
import 'my_bookings_screen.dart';

class BookingSummaryScreen extends StatefulWidget {
  const BookingSummaryScreen({
    super.key,
    required this.package,
    required this.customization,
    required this.slot,
    this.studioName,
    this.estimate,
  });

  final PhotographyPackage package;
  final PackageCustomization customization;
  final StudioAvailability slot;
  final String? studioName;
  final PackagePriceSummary? estimate;

  @override
  State<BookingSummaryScreen> createState() => _BookingSummaryScreenState();
}

class _BookingSummaryScreenState extends State<BookingSummaryScreen> {
  final _location = TextEditingController();
  final _notes = TextEditingController();
  final _service = BookingService();
  bool _submitting = false;
  bool _outcomeUnknown = false;
  String? _error;
  CreatedBooking? _created;

  PhotographyPackage get package => widget.package;
  PackageCustomization get customization => widget.customization;
  StudioAvailability get slot => widget.slot;
  String? get studioName => widget.studioName;
  PackagePriceSummary? get estimate => widget.estimate;

  String? get _selectionError {
    if (!isPackageGuid(package.studioId) || !isPackageGuid(package.id)) {
      return 'Return to the studio and select a valid package.';
    }
    final customizationError = customization.validate(package);
    if (customizationError != null) return customizationError;
    final date = slot.date.toIso8601String().split('T').first;
    final start = DateTime.tryParse('${date}T${slot.startTime ?? ''}');
    final end = DateTime.tryParse('${date}T${slot.endTime ?? ''}');
    if (!slot.isAvailable || start == null || end == null ||
        !start.isAfter(DateTime.now()) || !end.isAfter(start)) {
      return 'Go back and select an upcoming date and time.';
    }
    if (package.durationHours <= 0 ||
        end.difference(start).inSeconds / 3600 > package.durationHours + customization.extraHours) {
      return 'The selected time range exceeds the package duration plus extra hours. Go back to adjust your selection.';
    }
    return null;
  }

  bool get _valid => _location.text.trim().isNotEmpty &&
      _location.text.length <= 500 && _notes.text.length <= 1000 &&
      _selectionError == null;

  Future<void> _confirm() async {
    if (_submitting || _created != null || _outcomeUnknown) return;
    if (!_valid) {
      setState(() => _error = _selectionError ?? 'Enter a booking location and check the field lengths.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() { _submitting = true; _error = null; });
    try {
      final booking = await _service.create(package: package,
        customization: customization, slot: slot,
        location: _location.text, notes: _notes.text);
      if (mounted) setState(() => _created = booking);
    } on BookingApiException catch (error) {
      if (mounted) setState(() {
        _error = error.message;
        _outcomeUnknown = error.outcomeUnknown;
      });
    } catch (_) {
      if (mounted) setState(() {
        _error = 'Booking creation could not be verified. Open My Bookings before submitting again.';
        _outcomeUnknown = true;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _location.dispose();
    _notes.dispose();
    _service.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final price = estimate;
    final isBasePackage = customization.selectedAddonIds.isEmpty &&
        customization.extraHours == 0 && customization.additionalPhotographers == 0;
    // Customized estimates come from the pricing API. Never fabricate a quote
    // if a caller arrives without one; the normal customization flow supplies it.
    final total = price?.finalPrice ?? (isBasePackage ? package.basePrice : null);
    final selectedAddons = package.addons.where(
      (addon) => customization.selectedAddonIds.contains(addon.id),
    );

    Widget line(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 20,
        runSpacing: 6,
        children: [
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
          Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );

    Widget section(String title, IconData icon, List<Widget> children) => Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(icon, color: colors.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );

    final created = _created;
    if (created != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Booking Confirmed')),
        body: SafeArea(child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.all(24), children: [
            Icon(Icons.check_circle_outline, size: 72, color: colors.primary),
            const SizedBox(height: 20),
            Text('Booking created successfully', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 12),
            const Text('Your booking has been saved. The status below reflects the studio approval process.'),
            const SizedBox(height: 24),
            section('Booking confirmation', Icons.receipt_long_outlined, [
              if (created.id != null) line('Booking reference', '#${created.id}'),
              if (created.status != null) line('Status', created.status!),
              if (created.totalPrice != null) line('Final price', formatLkr(created.totalPrice!)),
              if (created.id == null || created.status == null || created.totalPrice == null)
                const Text('Some booking details were not returned by the server.'),
            ]),
            FilledButton(onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('Done')),
          ]),
        ))),
      );
    }

    return PopScope(
      canPop: !_submitting,
      child: Scaffold(
      appBar: AppBar(title: const Text('Booking Summary')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('SnapSync', style: theme.textTheme.labelLarge?.copyWith(color: colors.primary, letterSpacing: 1.5)),
                const SizedBox(height: 10),
                Text('Your session, at a glance', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('Review your selected package and date before the next step.'),
                const SizedBox(height: 24),
                section('Studio & package', Icons.camera_alt_outlined, [
                  line('Studio', studioName?.trim().isNotEmpty == true ? studioName! : 'Studio name unavailable'),
                  line('Package', package.name),
                ]),
                section('Selected date & time', Icons.event_outlined, [
                  line('Date', MaterialLocalizations.of(context).formatFullDate(slot.date)),
                  line('Start time', slot.startTime ?? 'Not specified'),
                  line('End time', slot.endTime ?? 'Not specified'),
                ]),
                section('Package & customization', Icons.tune, [
                  line('Base package price', formatLkr(price?.basePrice ?? package.basePrice)),
                  const Divider(),
                  Text('Selected add-ons', style: theme.textTheme.titleSmall),
                  if (customization.selectedAddonIds.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No add-ons selected.'))
                  else if (price != null)
                    ...price.selectedAddons.map((addon) => line(addon.name, formatLkr(addon.price)))
                  else
                    ...selectedAddons.map((addon) => line(addon.name, formatLkr(addon.price))),
                  const Divider(),
                  line('Extra hours', '${customization.extraHours}'),
                  if (price != null) line('Extra hours cost', formatLkr(price.extraHoursCost)),
                  line('Additional photographers', '${customization.additionalPhotographers}'),
                  if (price != null) line('Additional photographers cost', formatLkr(price.additionalPhotographersCost)),
                ]),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(colors: [colors.primaryContainer, colors.surfaceContainerLow]),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Estimated total'),
                    const SizedBox(height: 8),
                    Text(total == null ? 'Estimate unavailable' : formatLkr(total),
                      style: theme.textTheme.headlineMedium?.copyWith(color: colors.primary, fontWeight: FontWeight.w800)),
                  ]),
                ),
                const SizedBox(height: 24),
                section('Location & notes', Icons.location_on_outlined, [
                  TextFormField(
                    controller: _location,
                    enabled: !_submitting && !_outcomeUnknown,
                    maxLength: 500,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Booking location *', hintText: 'Enter the session address or venue'),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Booking location is required.'
                        : value.length > 500 ? 'Use at most 500 characters.' : null,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _notes,
                    enabled: !_submitting && !_outcomeUnknown,
                    maxLength: 1000,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: 'Notes (optional)'),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (value) => (value?.length ?? 0) > 1000 ? 'Use at most 1000 characters.' : null,
                    onChanged: (_) => setState(() {}),
                  ),
                ]),
                if (_selectionError != null)
                  Padding(padding: const EdgeInsets.only(bottom: 16),
                    child: Text(_selectionError!, style: TextStyle(color: colors.error))),
                if (_error != null)
                  Semantics(liveRegion: true, child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(_error!, style: TextStyle(color: colors.error)),
                  )),
                FilledButton(
                  onPressed: _valid && !_submitting && !_outcomeUnknown ? _confirm : null,
                  child: Padding(padding: const EdgeInsets.all(16),
                    child: _submitting
                        ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 12), Text('Confirming...'),
                          ])
                        : const Text('Confirm Booking')),
                ),
                if (_outcomeUnknown)
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const MyBookingsScreen(),
                    )),
                    child: const Text('My Bookings'),
                  ),
                OutlinedButton(onPressed: _submitting ? null : () => Navigator.of(context).pop(), child: const Text('Back')),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
