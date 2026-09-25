import 'package:flutter/material.dart';

import '../../models/photography_package.dart';
import '../../services/booking_service.dart';
import 'write_review_screen.dart';

class BookingDetailsScreen extends StatefulWidget {
  const BookingDetailsScreen({super.key, required this.bookingId});
  final int bookingId;

  @override
  State<BookingDetailsScreen> createState() => _BookingDetailsScreenState();
}

class _BookingDetailsScreenState extends State<BookingDetailsScreen> {
  final _service = BookingService();
  late Future<CustomerBookingDetails> _booking;
  bool _reviewRecorded = false;

  Future<void> _writeReview() async {
    final recorded = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => WriteReviewScreen(bookingId: widget.bookingId),
    ));
    if (mounted && recorded == true) setState(() => _reviewRecorded = true);
  }

  @override
  void initState() {
    super.initState();
    _booking = _service.getBooking(widget.bookingId);
  }

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }

  void _retry() => setState(() => _booking = _service.getBooking(widget.bookingId));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    Widget line(String label, String? value) {
      if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
      return Padding(padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: theme.textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: 4),
          SelectableText(value, style: theme.textTheme.bodyLarge),
        ]));
    }
    Widget card(String title, List<Widget> children) => Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
        gradient: LinearGradient(colors: [colors.surfaceContainerHigh, colors.surface]),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: theme.textTheme.titleMedium?.copyWith(color: colors.primary, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        ...children,
      ]),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Booking Details')),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(children: [
          Expanded(child: FutureBuilder<CustomerBookingDetails>(
            future: _booking,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                final error = snapshot.error;
                final code = error is BookingApiException ? error.statusCode : null;
                final title = code == 404 ? 'Booking not found'
                    : code == 401 || code == 403 ? 'Access unavailable' : 'Unable to load booking';
                return Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(code == 404 ? Icons.search_off : Icons.lock_outline, size: 48, color: colors.primary),
                    const SizedBox(height: 16),
                    Text(title, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 12),
                    Text(error is BookingApiException ? error.message : 'Please try again later.', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(onPressed: _retry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                  ]),
                ));
              }
              final booking = snapshot.data!;
              final summary = booking.summary;
              final customization = booking.customization;
              return ListView(padding: const EdgeInsets.all(20), children: [
                Text('Booking #${summary.id}', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                if (summary.status != null) Align(alignment: Alignment.centerLeft,
                  child: Chip(label: Text(summary.status!), backgroundColor: colors.primaryContainer,
                    labelStyle: TextStyle(color: colors.onPrimaryContainer))),
                const SizedBox(height: 16),
                card('Session', [
                  line('Booking date', MaterialLocalizations.of(context).formatFullDate(booking.date!)),
                  line('Start time', booking.startTime),
                  line('End time', booking.endTime),
                  line('Studio reference', booking.studioId),
                  line('Package', booking.packageName),
                  line('Package reference', booking.packageId),
                  line('Location', booking.location),
                  line('Notes', booking.notes),
                ]),
                if (customization != null) card('Saved customization', [
                  line('Base package price', formatLkr(customization.basePrice)),
                  const Divider(),
                  Text('Selected add-ons', style: theme.textTheme.titleSmall),
                  if (customization.selectedAddons.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No add-ons selected.')),
                  ...customization.selectedAddons.map((addon) => line(
                    addon.name.isEmpty ? addon.id : addon.name, formatLkr(addon.price))),
                  const Divider(),
                  line('Extra hours', '${customization.extraHours}'),
                  line('Extra hours cost', formatLkr(customization.extraHoursCost)),
                  line('Additional photographers', '${customization.additionalPhotographers}'),
                  line('Additional photographers cost', formatLkr(customization.additionalPhotographersCost)),
                  line('Saved pricing total', formatLkr(customization.finalPrice)),
                ]),
                if (summary.totalPrice != null) card('Final total', [
                  Text(formatLkr(summary.totalPrice!), style: theme.textTheme.headlineMedium?.copyWith(color: colors.primary, fontWeight: FontWeight.w700)),
                ]),
                if (summary.status == 'Completed')
                  _reviewRecorded
                      ? const Text('This booking has a review.')
                      : FilledButton.icon(onPressed: _writeReview,
                          icon: const Icon(Icons.rate_review_outlined), label: const Text('Write a Review')),
              ]);
            },
          )),
          Padding(padding: const EdgeInsets.all(16), child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back), label: const Text('Back to My Bookings'))),
        ]),
      ))),
    );
  }
}
