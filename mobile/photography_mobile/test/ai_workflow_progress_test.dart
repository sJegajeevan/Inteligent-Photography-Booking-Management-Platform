import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photography_mobile/models/ai_workflow.dart';
import 'package:photography_mobile/screens/ai/ai_workflow_progress.dart';

import 'ai_workflow_test.dart' as fixtures;

void main() {
  for (final status in ['AwaitingApproval', 'Approved']) {
    testWidgets('four canonical stages for $status', (tester) async {
      final data = fixtures.fixture(status);
      data['proposal']['validation'] = {'outcome': 'Pass', 'raw': 'SECRET'};
      final workflow = AiWorkflow.fromJson(data);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AiWorkflowProgress(
                workflow: workflow,
                studioName: 'Snap Studio',
              ),
            ),
          ),
        ),
      );
      for (final title in agentTitles) {
        expect(find.textContaining(title), findsOneWidget);
      }
      expect(find.text('Completed'), findsNWidgets(4));
      expect(find.text('Snap Studio'), findsOneWidget);
      expect(find.text('Portrait session'), findsOneWidget);
      expect(find.textContaining('5,000'), findsOneWidget);
      expect(find.text('2030-01-01'), findsOneWidget);
      expect(find.textContaining('validation passed'), findsOneWidget);
      expect(
        find.textContaining(
          status == 'AwaitingApproval'
              ? 'Awaiting Studio Approval'
              : 'Approved',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('SECRET'), findsNothing);
      expect(find.textContaining(fixtures.studio), findsNothing);
    });
  }
  for (var stage = 0; stage < 4; stage++) {
    testWidgets('failure at stage $stage stops later agents', (tester) async {
      final data = fixtures.fixture('Failed')..['proposal'] = null;
      data['failure'] = {
        'stage': agentSteps[stage],
        'code': 'gemini_unavailable',
        'message': 'SECRET stack',
      };
      final workflow = AiWorkflow.fromJson(data);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AiWorkflowProgress(workflow: workflow),
            ),
          ),
        ),
      );
      expect(find.text('Completed'), findsNWidgets(stage));
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Not executed'), findsNWidgets(3 - stage));
      expect(find.textContaining('temporarily unavailable'), findsOneWidget);
      expect(find.textContaining('SECRET'), findsNothing);
    });
  }
  test('unknown failures and coarse running state never invent completion', () {
    for (final status in [
      'Failed',
      'StudioMatching',
      'Submitted',
      'NeedsInput',
    ]) {
      final data = fixtures.fixture(status)..['proposal'] = null;
      final workflow = AiWorkflow.fromJson(data);
      expect(
        List.generate(4, workflow.stageState),
        everyElement(isNot('Completed')),
      );
    }
  });
}
