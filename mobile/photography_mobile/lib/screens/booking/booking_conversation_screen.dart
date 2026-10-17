import 'package:flutter/material.dart';

import '../../models/booking_message.dart';
import '../../services/booking_service.dart';

class BookingConversationScreen extends StatefulWidget {
  const BookingConversationScreen({super.key, required this.bookingId, this.studioName});
  final int bookingId;
  final String? studioName;

  @override
  State<BookingConversationScreen> createState() => _BookingConversationScreenState();
}

class _BookingConversationScreenState extends State<BookingConversationScreen> {
  final _service = BookingService();
  final _draft = TextEditingController();
  final _scroll = ScrollController();
  List<BookingMessage> _messages = [];
  bool _loading = true, _sending = false, _uncertain = false;
  String? _error;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _service.close();
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  });

  Future<void> _load() async {
    final version = ++_loadVersion;
    setState(() { _loading = true; _error = null; });
    try {
      final messages = await _service.getMessages(widget.bookingId);
      if (!mounted || version != _loadVersion) return;
      setState(() { _messages = messages; _uncertain = false; });
      _scrollToEnd();
    } catch (error) {
      if (mounted && version == _loadVersion) {
        setState(() => _error = error is BookingApiException ? error.message : 'Unable to load conversation. Please retry.');
      }
    } finally {
      if (mounted && version == _loadVersion) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    if (_sending || _loading || _uncertain || _draft.text.trim().isEmpty || _draft.text.length > 1000) return;
    setState(() { _sending = true; _error = null; });
    try {
      final message = await _service.sendMessage(widget.bookingId, _draft.text);
      if (!mounted) return;
      _draft.clear();
      setState(() => _messages = [..._messages, message]);
      _scrollToEnd();
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() {
          _uncertain = error is BookingApiException && error.outcomeUnknown;
          _error = error is BookingApiException ? error.message : 'Unable to send. Refresh before trying again.';
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final localizations = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.studioName?.trim().isNotEmpty == true ? widget.studioName! : 'Studio Conversation'),
        actions: [IconButton(onPressed: _loading || _sending ? null : _load,
          tooltip: 'Refresh conversation', icon: const Icon(Icons.refresh))]),
      body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720),
        child: Column(children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Column(children: [
            Text(_error!, style: TextStyle(color: colors.error)),
            TextButton(onPressed: _loading || _sending ? null : _load, child: const Text('Retry refresh')),
          ])),
          Expanded(child: !_loading && _error == null && _messages.isEmpty
            ? const Center(child: Text('No messages yet. Ask your studio about this booking.'))
            : ListView.builder(controller: _scroll, padding: const EdgeInsets.all(16),
              itemCount: _messages.length, itemBuilder: (context, index) {
                final message = _messages[index];
                final own = message.senderRole == 'Customer';
                final time = message.sentAt.toLocal();
                return Align(alignment: own ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .8),
                    margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: own ? colors.primaryContainer : colors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(18)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${message.senderName.isEmpty ? message.senderRole : message.senderName} · ${message.senderRole}',
                        style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 6), SelectableText(message.message), const SizedBox(height: 6),
                      Text('${localizations.formatShortDate(time)} ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(time))}',
                        style: Theme.of(context).textTheme.labelSmall),
                    ])));
              })),
          Padding(padding: const EdgeInsets.all(16), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: TextField(controller: _draft, enabled: !_sending, maxLength: 1000,
              minLines: 1, maxLines: 4, onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Message', hintText: 'Discuss this booking…', border: OutlineInputBorder()))),
            const SizedBox(width: 12),
            FilledButton(onPressed: _sending || _loading || _uncertain || _draft.text.trim().isEmpty || _draft.text.length > 1000 ? null : _send,
              child: Text(_sending ? 'Sending…' : 'Send')),
          ])),
        ])))),
    );
  }
}
