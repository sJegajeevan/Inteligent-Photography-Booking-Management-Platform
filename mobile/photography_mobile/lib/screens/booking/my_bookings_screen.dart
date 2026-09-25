import 'package:flutter/material.dart';

import '../../models/photography_package.dart';
import '../../services/booking_service.dart';
import 'booking_details_screen.dart';

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  final _service = BookingService();
  late Future<List<CustomerBooking>> _bookings;

  @override
  void initState() {
    super.initState();
    _bookings = _service.getMyBookings();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    final request = _service.getMyBookings();
    setState(() {
      _bookings = request;
    });
    try {
      await request;
    } catch (_) {
      // FutureBuilder renders the error and retry action.
    }
  }

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('My Bookings')),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: FutureBuilder<List<CustomerBooking>>(
          future: _bookings,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              final error = snapshot.error;
              return Center(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.cloud_off_outlined, size: 48, color: colors.primary),
                  const SizedBox(height: 16),
                  Text(error is BookingApiException ? error.message : 'Unable to load bookings. Please try again.', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                ]),
              ));
            }
            final bookings = snapshot.data ?? const <CustomerBooking>[];
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                itemCount: bookings.isEmpty ? 1 : bookings.length,
                itemBuilder: (context, index) {
                  if (bookings.isEmpty) {
                    return Padding(padding: const EdgeInsets.symmetric(vertical: 64),
                      child: Column(children: [
                        Icon(Icons.event_note_outlined, size: 64, color: colors.primary),
                        const SizedBox(height: 20),
                        Text('No bookings yet', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 8),
                        const Text('Your bookings will appear here once created.'),
                      ]));
                  }
                  final booking = bookings[index];
                  final summary = booking.summary;
                  final packageName = booking.packageName;
                  return Semantics(
                    button: true,
                    label: 'View booking ${summary.id}',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => BookingDetailsScreen(bookingId: summary.id!),
                        ));
                        await _reload();
                      },
                      child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: colors.outlineVariant),
                      gradient: LinearGradient(colors: [colors.surfaceContainerHigh, colors.surface]),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text('Booking #${summary.id}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        Chip(label: Text(summary.status ?? 'Status unavailable'),
                          backgroundColor: colors.primaryContainer,
                          labelStyle: TextStyle(color: colors.onPrimaryContainer)),
                      ]),
                      const SizedBox(height: 14),
                      if (packageName != null && packageName.trim().isNotEmpty)
                        Text(packageName, style: theme.textTheme.titleMedium)
                      else if (booking.packageId != null)
                        Text('Package reference: ${booking.packageId}'),
                      if (booking.studioId != null) ...[
                        const SizedBox(height: 8),
                        Text('Studio reference: ${booking.studioId}', style: theme.textTheme.bodySmall),
                      ],
                      const SizedBox(height: 16),
                      Text(MaterialLocalizations.of(context).formatFullDate(booking.date!)),
                      const SizedBox(height: 6),
                      Text('${booking.startTime ?? 'Time unavailable'} - ${booking.endTime ?? 'Time unavailable'}'),
                      const Divider(height: 28),
                      Text(summary.totalPrice == null ? 'Total price unavailable' : formatLkr(summary.totalPrice!),
                        style: theme.textTheme.titleLarge?.copyWith(color: colors.primary, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      Row(children: [Text('View Details', style: TextStyle(color: colors.primary)),
                        const SizedBox(width: 8), Icon(Icons.chevron_right, color: colors.primary)]),
                    ]),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ))),
    );
  }
}
