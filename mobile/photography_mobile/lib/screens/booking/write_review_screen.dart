import 'package:flutter/material.dart';
import '../../services/review_service.dart';

class WriteReviewScreen extends StatefulWidget {
  const WriteReviewScreen({super.key, required this.bookingId});
  final int bookingId;

  @override
  State<WriteReviewScreen> createState() => _WriteReviewScreenState();
}

class _WriteReviewScreenState extends State<WriteReviewScreen> {
  final _service = ReviewService();
  final _comment = TextEditingController();
  int _rating = 0;
  bool _submitting = false;
  bool _saved = false;
  bool _duplicate = false;
  String? _error;

  Future<void> _submit() async {
    if (_submitting || _saved || _duplicate || _rating < 1 || _rating > 5 || _comment.text.length > 2000) return;
    FocusScope.of(context).unfocus();
    setState(() { _submitting = true; _error = null; });
    try {
      await _service.submit(bookingId: widget.bookingId, rating: _rating, comment: _comment.text);
      if (mounted) setState(() => _saved = true);
    } on ReviewApiException catch (error) {
      if (mounted) setState(() {
        _error = error.message;
        _duplicate = error.statusCode == 409;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to submit your review. Check your connection and sign-in session.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _comment.dispose();
    _service.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    void back() => Navigator.of(context).pop(_saved || _duplicate);
    return PopScope(
      canPop: !_submitting,
      child: Scaffold(
        appBar: AppBar(title: const Text('Write a Review'),
          leading: IconButton(onPressed: _submitting ? null : back, icon: const Icon(Icons.arrow_back))),
        body: SafeArea(child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.all(24), children: [
            Text('Booking #${widget.bookingId}', style: theme.textTheme.titleLarge),
            const SizedBox(height: 24),
            if (_saved || _duplicate) ...[
              Icon(_saved ? Icons.check_circle_outline : Icons.rate_review_outlined, color: colors.primary, size: 64),
              const SizedBox(height: 16),
              Text(_saved ? 'Thank you! Your review has been submitted.' : 'This booking already has a review.',
                style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            ] else Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24), border: Border.all(color: colors.outlineVariant)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('How was your experience?', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(alignment: WrapAlignment.center, children: List.generate(5, (index) => IconButton(
                  tooltip: '${index + 1} ${index == 0 ? 'star' : 'stars'}',
                  isSelected: _rating >= index + 1,
                  onPressed: _submitting ? null : () => setState(() => _rating = index + 1),
                  icon: Icon(_rating >= index + 1 ? Icons.star_rounded : Icons.star_border_rounded,
                    color: colors.primary, size: 32),
                ))),
                Text(_rating == 0 ? 'Select a rating from 1 to 5 stars.' : '$_rating out of 5 stars', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                TextFormField(controller: _comment, enabled: !_submitting,
                  minLines: 4, maxLines: 8, maxLength: 2000,
                  decoration: const InputDecoration(labelText: 'Comment (optional)'),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (value) => (value?.length ?? 0) > 2000 ? 'Use at most 2000 characters.' : null,
                  onChanged: (_) => setState(() {})),
                if (_error != null) Semantics(liveRegion: true, child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(_error!, style: TextStyle(color: colors.error)))),
                FilledButton(onPressed: !_submitting && _rating >= 1 && _rating <= 5 && _comment.text.length <= 2000 ? _submit : null,
                  child: Padding(padding: const EdgeInsets.all(12), child: _submitting
                    ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 12), Text('Submitting...')])
                    : const Text('Submit Review'))),
              ]),
            ),
            const SizedBox(height: 24),
            OutlinedButton(onPressed: _submitting ? null : back, child: const Text('Back to Booking')),
          ]),
        ))),
      ),
    );
  }
}
