import 'package:flutter/material.dart';
import '../../models/customer_notification.dart';
import '../../services/notification_service.dart';
import '../booking/booking_details_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = NotificationService();
  List<CustomerNotification> _items = [];
  bool _loading = true;
  String? _error;
  String? _openingId;
  int _loadRequest = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (_openingId != null) return;
    final request = ++_loadRequest;
    setState(() { _loading = true; _error = null; });
    try {
      final items = await _service.getNotifications();
      if (mounted && request == _loadRequest) setState(() => _items = items);
    } catch (error) {
      if (mounted && request == _loadRequest) setState(() => _error = error.toString());
    } finally {
      if (mounted && request == _loadRequest) setState(() => _loading = false);
    }
  }

  Future<void> _open(CustomerNotification notification) async {
    if (!mounted || _loading || _openingId != null) return;
    setState(() => _openingId = notification.id);
    try {
      if (!notification.isRead) {
        await _service.markRead(notification.id);
        if (!mounted) return;
        setState(() => _items = _items.map((item) => item.id == notification.id ? item.asRead() : item).toList());
      }
      if (!mounted) return;
      if (notification.bookingId != null) {
        await Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => BookingDetailsScreen(bookingId: notification.bookingId!),
        ));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString()),
        action: SnackBarAction(label: 'Retry', onPressed: () => _open(notification)),
      ));
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  IconData _icon(String type) => switch (type) {
    'BookingCreated' => Icons.event_available_outlined,
    'BookingConfirmed' => Icons.check_circle_outline,
    'BookingCancelled' => Icons.event_busy_outlined,
    _ => Icons.update_rounded,
  };

  String _dateTime(DateTime timestamp) {
    final local = timestamp.toLocal();
    final localization = MaterialLocalizations.of(context);
    return '${localization.formatMediumDate(local)} · ${localization.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620),
        child: RefreshIndicator(onRefresh: _load,
          child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(20), children: [
            if (_loading) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Column(children: [
              const Icon(Icons.cloud_off_outlined, size: 40),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
            ])),
            if (!_loading && _error == null && _items.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 64), child: Column(children: [
                Icon(Icons.notifications_none_rounded, size: 56, color: colors.primary),
                const SizedBox(height: 16),
                Text('No notifications yet', style: theme.textTheme.titleMedium),
              ])),
            ..._items.map((item) => Padding(padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: item.isRead ? colors.surface : colors.primaryContainer.withValues(alpha: 0.55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: item.isRead ? colors.outlineVariant : colors.primary.withValues(alpha: 0.35))),
                clipBehavior: Clip.antiAlias,
                child: InkWell(onTap: _loading || _openingId != null ? null : () => _open(item),
                  child: Padding(padding: const EdgeInsets.all(18), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(_icon(item.type), color: colors.primary, size: 28),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: item.isRead ? FontWeight.w500 : FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(item.message),
                      const SizedBox(height: 10),
                      Text(_dateTime(item.createdAt), style: theme.textTheme.bodySmall),
                      const SizedBox(height: 4),
                      Text(item.isRead ? 'Read' : 'Unread', style: theme.textTheme.labelSmall?.copyWith(color: colors.primary)),
                      if (item.bookingId != null) Padding(padding: const EdgeInsets.only(top: 8),
                        child: Text('View booking', style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600))),
                    ])),
                    if (_openingId == item.id) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    else if (!item.isRead) Icon(Icons.circle, size: 10, color: colors.primary),
                  ])),
                ),
              ),
            )),
          ]),
        ),
      )),
    );
  }
}
