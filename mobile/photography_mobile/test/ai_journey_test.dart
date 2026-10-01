import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photography_mobile/models/ai_workflow.dart';
import 'package:photography_mobile/screens/ai/ai_journey_view.dart';

Map<String, dynamic> option(String stage, String id) => {
  'stage': stage,
  'eventId': id,
  'rank': 1,
  'studioId': 'studio',
  'packageId': 'package',
  'name': stage == 'StudioMatching' ? 'Snap Studio' : 'Portrait Package',
  'location': 'Colombo',
  'specialties': 'Portrait',
  'reason': 'Matches your requested coverage.',
  'price': 5000,
  'durationHours': 2,
  'services': ['Portrait photography'],
  'imageUrl': '',
  'date': '2030-01-03',
  'startTime': '10:00:00',
  'endTime': '12:00:00',
};

AiWorkflow workflow(
  String stage, {
  bool failed = false,
  bool submitted = false,
  bool validated = false,
}) {
  final index = agentSteps.indexOf(stage);
  return AiWorkflow(
    id: 'workflow',
    status: submitted
        ? 'AwaitingApproval'
        : failed
        ? 'Failed'
        : stage,
    step: stage,
    version: validated ? 1 : 0,
    expiresAt: DateTime.utc(2030),
    proposal: validated
        ? const AiProposal(
            studioId: 'studio',
            packageName: 'Portrait Package',
            date: '2030-01-03',
            start: '10:00',
            end: '12:00',
            price: 5000,
            extraHours: 0,
            additionalPhotographers: 0,
            summary: 'Portrait in Colombo',
          )
        : null,
    journey: {
      'revision': index + 1,
      'stage': stage,
      'busy': false,
      'validated': validated,
      'submitted': submitted,
      'errorCode': failed ? 'execution_unavailable' : null,
      'studioOptionId': index > 0 ? 'studio-option' : null,
      'packageOptionId': index > 1 ? 'package-option' : null,
      'scheduleOptionId': index > 2 ? 'schedule-option' : null,
      'options': [
        option('StudioMatching', 'studio-option'),
        if (index > 0) option('PackageRecommendation', 'package-option'),
        if (index > 1) option('Scheduling', 'schedule-option'),
      ],
    },
  );
}

void main() {
  Future<void> show(
    WidgetTester tester,
    AiWorkflow w, {
    bool busy = false,
    String? running,
    Future<void> Function(String, String?)? action,
    String? error,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiJourneyView(
          workflow: w,
          busy: busy,
          runningStage: running,
          error: error,
          onAction: action ?? (_, option) async {},
          onRefresh: () async {},
        ),
      ),
    );
  }

  for (var i = 0; i < 3; i++) {
    testWidgets(
      '${agentSteps[i]} shows its real choices and selects event reference',
      (tester) async {
        final actions = <String>[];
        await show(
          tester,
          workflow(agentSteps[i]),
          action: (action, id) async => actions.add('$action:$id'),
        );
        expect(find.text(agentTitles[i]), findsOneWidget);
        final label = [
          'Select Studio / Continue',
          'Select Package & Continue',
          'Use This Schedule',
        ][i];
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        expect(actions, [
          '${['studio', 'package', 'schedule'][i]}:${['studio', 'package', 'schedule'][i]}-option',
        ]);
        expect(find.text('Send for Studio Approval'), findsNothing);
      },
    );
  }

  for (final stage in agentSteps) {
    testWidgets(
      '$stage has a genuine pending state without selectable actions',
      (tester) async {
        await show(tester, workflow(stage), busy: true, running: stage);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.textContaining('is working'), findsOneWidget);
        expect(find.text('Send for Studio Approval'), findsNothing);
        expect(find.text('Use This Schedule'), findsNothing);
      },
    );

    testWidgets('$stage failure retries only the current stage', (
      tester,
    ) async {
      final actions = <String>[];
      await show(
        tester,
        workflow(stage, failed: true),
        action: (action, id) async => actions.add(action),
      );
      await tester.ensureVisible(find.text('Retry this stage'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry this stage'));
      expect(actions, ['retry']);
      expect(find.text('Send for Studio Approval'), findsNothing);
    });
  }

  testWidgets('validation shows authoritative proposal and explicit submit', (
    tester,
  ) async {
    final actions = <String>[];
    await show(
      tester,
      workflow('Validation', validated: true),
      action: (action, id) async => actions.add(action),
    );
    expect(find.text('AI Recommendation Ready'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Send for Studio Approval'), 250);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send for Studio Approval'));
    expect(actions, ['submit']);
    expect(find.text('Authoritative price: LKR 5000.0'), findsOneWidget);
  });

  testWidgets('changing earlier stage is navigation until customer selects', (
    tester,
  ) async {
    final actions = <String>[];
    await show(
      tester,
      workflow('Scheduling'),
      action: (action, id) async => actions.add(action),
    );
    await tester.tap(find.widgetWithText(ActionChip, 'Studio'));
    await tester.pump();
    expect(find.text('Studio Matching Agent'), findsOneWidget);
    expect(actions, isEmpty);
    await tester.ensureVisible(find.text('Select Studio / Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select Studio / Continue'));
    expect(actions, ['studio']);
  });

  testWidgets('submitted journey hides all selection and submit controls', (
    tester,
  ) async {
    await show(
      tester,
      workflow('Validation', submitted: true, validated: true),
    );
    expect(find.text('Awaiting Studio Approval'), findsOneWidget);
    expect(find.text('Send for Studio Approval'), findsNothing);
    expect(find.text('Change schedule'), findsNothing);
  });

  testWidgets('uncertain result requires refresh before another action', (
    tester,
  ) async {
    await show(
      tester,
      workflow('StudioMatching'),
      error: 'Refresh your saved journey.',
    );
    expect(find.text('Refresh saved journey'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Select Studio / Continue'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('staged cards remain usable on a narrow phone with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: AiJourneyView(
          workflow: workflow('PackageRecommendation'),
          busy: false,
          onAction: (_, option) async {},
          onRefresh: () async {},
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Select Package & Continue'),
      200,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
