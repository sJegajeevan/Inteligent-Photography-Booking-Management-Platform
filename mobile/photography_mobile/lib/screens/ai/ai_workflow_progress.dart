import 'package:flutter/material.dart';

import '../../models/ai_workflow.dart';
import '../../models/photography_package.dart';

class AiWorkflowProgress extends StatelessWidget {
  const AiWorkflowProgress({
    super.key,
    required this.workflow,
    this.studioName,
  });
  final AiWorkflow workflow;
  final String? studioName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = workflow.proposal;
    final localizations = MaterialLocalizations.of(context);
    String time(String value) => localizations.formatTimeOfDay(
      TimeOfDay(
        hour: int.parse(value.split(':')[0]),
        minute: int.parse(value.split(':')[1]),
      ),
      alwaysUse24HourFormat: false,
    );
    final details = [
      p == null
          ? 'Find a studio for your requirements.'
          : studioName ?? 'Selected studio • Name unavailable',
      p == null
          ? 'Recommend a suitable package within your budget.'
          : p.packageName,
      p == null ? 'Find a suitable date and time.' : p.date,
      p?.validationOutcome == 'Pass'
          ? 'Proposal validation passed at recommendation time. This is not a reservation.'
          : p?.validationOutcome == 'Fail'
          ? 'Proposal validation failed.'
          : p?.validationOutcome == 'NeedsInput'
          ? 'Validation needs more information.'
          : 'Validation result not available.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('AI Workflow Progress', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('One integrated workflow • Four agents'),
        if (workflow.status == 'StudioMatching')
          const Text(
            'Workflow running. Individual agent progress is not available yet.',
          ),
        const SizedBox(height: 16),
        for (var i = 0; i < agentTitles.length; i++) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      workflow.stageState(i) == 'Completed'
                          ? Icons.check_circle_outline
                          : workflow.stageState(i) == 'Failed'
                          ? Icons.error_outline
                          : workflow.stageState(i) == 'Running'
                          ? Icons.sync
                          : Icons.radio_button_unchecked,
                      color: workflow.stageState(i) == 'Failed'
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${i + 1}. ${agentTitles[i]}',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(workflow.stageState(i), style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                Text(
                  workflow.failureStage == agentSteps[i] && p == null
                      ? workflow.safeFailureMessage
                      : details[i],
                ),
                if (i == 1 && p != null) ...[
                  Text('Authoritative price: ${formatLkr(p.price)}'),
                  Text(
                    '${p.extraHours} extra hours • ${p.additionalPhotographers} additional photographers',
                  ),
                  if (p.addonNames.isNotEmpty)
                    Text('Add-ons: ${p.addonNames.join(', ')}'),
                ],
                if (i == 2 && p != null) ...[
                  Text('${time(p.start)} – ${time(p.end)}'),
                  const Text(
                    'Sri Lanka time • Availability is checked again on approval.',
                  ),
                ],
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 16),
            child: Icon(Icons.arrow_downward, size: 20),
          ),
        ],
        Text(
          'Overall status: ${workflow.status == 'AwaitingApproval' ? 'Awaiting Studio Approval' : workflow.label}',
          style: theme.textTheme.titleMedium,
        ),
        if (workflow.status == 'Failed' && workflow.failureStage == null)
          Text(
            '${workflow.safeFailureMessage} The failed agent was not confirmed.',
          ),
        const SizedBox(height: 20),
      ],
    );
  }
}
