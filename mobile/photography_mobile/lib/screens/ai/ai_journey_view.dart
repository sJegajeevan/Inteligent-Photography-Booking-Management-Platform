import 'package:flutter/material.dart';

import '../../models/ai_workflow.dart';
import '../../services/api_config.dart';
import '../studio/studio_detail_screen.dart';
import '../booking/my_bookings_screen.dart';

/// Renders only persisted stage options. Navigation never executes an agent.
class AiJourneyView extends StatefulWidget {
  const AiJourneyView({
    super.key,
    required this.workflow,
    required this.busy,
    required this.onAction,
    required this.onRefresh,
    this.error,
    this.runningStage,
    this.loadingMessage,
  });
  final AiWorkflow workflow;
  final bool busy;
  final String? error, runningStage, loadingMessage;
  final Future<void> Function(String action, String? option) onAction;
  final Future<void> Function() onRefresh;
  @override
  State<AiJourneyView> createState() => _AiJourneyViewState();
}

class _AiJourneyViewState extends State<AiJourneyView> {
  String? _viewing;
  @override
  void didUpdateWidget(covariant AiJourneyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workflow.journey?['revision'] !=
            widget.workflow.journey?['revision'] ||
        oldWidget.runningStage != widget.runningStage) {
      _viewing = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final j = widget.workflow.journey!;
    final theme = Theme.of(context);
    final options = (j['options'] as List).cast<Map<String, dynamic>>();
    final submitted = j['submitted'] == true;
    final busy = widget.busy || j['busy'] == true;
    final stage = widget.runningStage ?? _viewing ?? j['stage'] as String;
    final index = agentSteps.indexOf(stage);
    final visible = options.where((o) => o['stage'] == stage).toList();
    Map<String, dynamic>? selected(String key) {
      for (final o in options) {
        if (o['eventId'] == j[key]) return o;
      }
      return null;
    }

    final studio = selected('studioOptionId'),
        package = selected('packageOptionId');
    final schedule = selected('scheduleOptionId');
    final p = widget.workflow.proposal;
    final validated = j['validated'] == true && p != null;
    final failed = j['errorCode'] != null && stage == j['stage'];
    final blocked = busy || submitted || widget.error != null;
    Widget fact(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text('$label: $value')),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your photography journey'),
        actions: [
          IconButton(
            tooltip: 'Refresh journey',
            onPressed: widget.busy ? null : widget.onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  const Chip(
                    avatar: Icon(Icons.check, size: 16),
                    label: Text('Requirements'),
                  ),
                  for (var i = 0; i < agentSteps.length; i++)
                    ActionChip(
                      avatar: Icon(
                        i < index || validated || submitted
                            ? Icons.check_circle
                            : i == index
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 17,
                        color: theme.colorScheme.primary,
                      ),
                      label: Text(
                        const ['Studio', 'Package', 'Schedule', 'Validate'][i],
                      ),
                      onPressed:
                          blocked ||
                              !(options.any(
                                    (o) => o['stage'] == agentSteps[i],
                                  ) ||
                                  i == agentSteps.indexOf(j['stage']))
                          ? null
                          : () => setState(() => _viewing = agentSteps[i]),
                    ),
                ],
              ),
              const SizedBox(height: 28),
              Text(
                submitted
                    ? (widget.workflow.status == 'AwaitingApproval'
                          ? 'Awaiting Studio Approval'
                          : widget.workflow.label)
                    : validated && stage == 'Validation'
                    ? 'AI Recommendation Ready'
                    : agentTitles[index],
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.workflow.status == 'Approved'
                    ? 'Your studio approved the recommendation and your booking was created after fresh checks.'
                    : widget.workflow.status == 'Rejected'
                    ? 'The studio did not approve this recommendation.'
                    : submitted
                    ? 'Your studio reviews the final recommendation. Availability and pricing are checked again before a booking is created.'
                    : const [
                        'Discover the right creative team for your moment.',
                        'Choose a package from your selected studio.',
                        'Choose an available session in Sri Lanka time.',
                        'We check your selection against current studio, pricing and availability data.',
                      ][index],
              ),
              if (studio != null && index > 0) ...[
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        fact(
                          Icons.photo_camera_outlined,
                          'Studio',
                          studio['name'],
                        ),
                        if (package != null && index > 1) ...[
                          fact(
                            Icons.inventory_2_outlined,
                            'Package',
                            package['name'],
                          ),
                          fact(
                            Icons.schedule,
                            'Package duration',
                            '${package['durationHours']} hours + ${package['extraHours'] ?? 0} extra hours',
                          ),
                          fact(
                            Icons.payments_outlined,
                            'Quoted price',
                            'LKR ${package['price']}',
                          ),
                        ],
                        if (schedule != null && index > 2)
                          fact(
                            Icons.event,
                            'Schedule',
                            '${schedule['date']} · ${schedule['startTime'].toString().substring(0, 5)}–${schedule['endTime'].toString().substring(0, 5)}',
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              if (busy)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Semantics(
                    liveRegion: true,
                    child: Column(
                      children: [
                        const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(
                          widget.loadingMessage ??
                              '${agentTitles[index]} is working… Your progress is saved.',
                        ),
                      ],
                    ),
                  ),
                ),
              if (widget.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      Text(
                        widget.error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      TextButton(
                        onPressed: widget.busy ? null : widget.onRefresh,
                        child: const Text('Refresh saved journey'),
                      ),
                    ],
                  ),
                ),
              if (failed && !busy && !submitted)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'This stage could not finish. Your earlier selections are saved.',
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: blocked
                              ? null
                              : () => widget.onAction('retry', null),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry this stage'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!busy && !submitted && stage != 'Validation') ...[
                const SizedBox(height: 20),
                for (final o in visible)
                  Card(
                    clipBehavior: Clip.antiAlias,
                    margin: const EdgeInsets.only(bottom: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (stage != 'Scheduling' &&
                            ApiConfig.imageUrl(o['imageUrl'] as String?) !=
                                null)
                          Image.network(
                            ApiConfig.imageUrl(o['imageUrl'])!,
                            height: 180,
                            fit: BoxFit.cover,
                            errorBuilder: (_, error, stack) => const SizedBox(
                              height: 100,
                              child: Icon(
                                Icons.photo_camera_outlined,
                                size: 48,
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (o['rank'] == 1)
                                const Chip(
                                  avatar: Icon(Icons.auto_awesome, size: 16),
                                  label: Text('AI recommended'),
                                ),
                              Text(
                                stage == 'Scheduling'
                                    ? '${o['startTime'].toString().substring(0, 5)} – ${o['endTime'].toString().substring(0, 5)}'
                                    : o['name'],
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (stage == 'StudioMatching') ...[
                                fact(
                                  Icons.place_outlined,
                                  'Location',
                                  o['location'] ?? '',
                                ),
                                Text(o['specialties'] ?? ''),
                                TextButton(
                                  onPressed: blocked
                                      ? null
                                      : () => Navigator.of(context).push<void>(
                                          MaterialPageRoute(
                                            builder: (_) => StudioDetailScreen(
                                              studioId: o['studioId'],
                                            ),
                                          ),
                                        ),
                                  child: const Text('View Studio'),
                                ),
                              ],
                              if (stage == 'PackageRecommendation') ...[
                                fact(
                                  Icons.payments_outlined,
                                  'Price',
                                  'LKR ${o['price']}',
                                ),
                                fact(
                                  Icons.schedule,
                                  'Package duration',
                                  '${o['durationHours']} hours + ${o['extraHours'] ?? 0} extra hours',
                                ),
                                if (o['services'] is List)
                                  Text((o['services'] as List).join(' · ')),
                              ],
                              if (stage == 'Scheduling')
                                fact(Icons.event, 'Event date', o['date']),
                              if (o['reason'] != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Text(o['reason']),
                                ),
                              FilledButton.icon(
                                onPressed: blocked
                                    ? null
                                    : () => widget.onAction(
                                        const [
                                          'studio',
                                          'package',
                                          'schedule',
                                        ][index],
                                        o['eventId'],
                                      ),
                                icon: const Icon(Icons.arrow_forward),
                                label: Text(
                                  const [
                                    'Select Studio / Continue',
                                    'Select Package & Continue',
                                    'Use This Schedule',
                                  ][index],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              if (stage == 'Validation' && !busy && !submitted) ...[
                if (validated) ...[
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          fact(
                            Icons.payments,
                            'Authoritative price',
                            'LKR ${p.price}',
                          ),
                          for (final check in [
                            'Studio valid',
                            'Package belongs to studio',
                            'Price verified',
                            'Schedule available',
                            'No booking conflict',
                          ])
                            fact(Icons.verified_outlined, 'Verified', check),
                          const SizedBox(height: 12),
                          const Text(
                            'Point-in-time checks. Your session is reserved only through the existing approval and booking process.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: blocked
                        ? null
                        : () => widget.onAction('submit', null),
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Send for Studio Approval'),
                  ),
                ] else if (!failed) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Validation has expired. Check current availability and pricing again.',
                  ),
                  FilledButton(
                    onPressed: blocked
                        ? null
                        : () => widget.onAction('retry', null),
                    child: const Text('Validate again'),
                  ),
                ],
              ],
              if (widget.workflow.status == 'Approved')
                FilledButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const MyBookingsScreen()),
                  ),
                  child: const Text('View My Bookings'),
                ),
              if (!submitted && index > 0 && !busy)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: TextButton.icon(
                    onPressed: blocked
                        ? null
                        : () =>
                              setState(() => _viewing = agentSteps[index - 1]),
                    icon: const Icon(Icons.arrow_back),
                    label: Text(
                      'Change ${const ['studio', 'package', 'schedule'][index - 1]}',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
