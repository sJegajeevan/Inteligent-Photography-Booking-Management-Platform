import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photography_mobile/models/ai_workflow.dart';
import 'package:photography_mobile/services/ai_workflow_service.dart';
import 'package:photography_mobile/screens/ai/ai_workflow_screens.dart';
import 'package:photography_mobile/theme/app_theme.dart';

const id = '11111111-1111-4111-8111-111111111111';
const studio = '22222222-2222-4222-8222-222222222222';
const pack = '33333333-3333-4333-8333-333333333333';
Map<String, dynamic> fixture([String status = 'AwaitingApproval']) => {
  'id': id,
  'status': status,
  'currentStep': 'HumanApproval',
  'proposalVersion': 1,
  'selectedStudioId': studio,
  'selectedPackageId': pack,
  'expiresAt': '2030-01-01T12:00:00Z',
  'events': 'PRIVATE',
  'proposal': {
    'version': 1,
    'selection': {
      'studioId': studio,
      'packageId': pack,
      'date': '2030-01-01',
      'startTime': '10:00:00',
      'endTime': '12:00:00',
      'customization': {'extraHours': 0, 'additionalPhotographers': 0},
    },
    'pricing': {'packageName': 'Portrait session', 'finalPrice': 5000},
    'requirements': {'photographyType': 'Portrait', 'location': 'Colombo'},
    'finalEvidence': {'prompt': 'PRIVATE'},
  },
};
AiRequirements requirements({
  String type = 'Portrait',
  String location = 'Colombo',
  String budget = '6000',
  String first = '2030-01-01',
  String last = '2030-01-02',
  String hours = '2',
  String start = '',
  String end = '',
  String services = '',
}) => AiRequirements(
  photographyType: type,
  location: location,
  budget: budget,
  earliestDate: first,
  latestDate: last,
  coverageHours: hours,
  preferredStart: start,
  preferredEnd: end,
  services: services,
);

class FakeService extends AiWorkflowService {
  String status = 'AwaitingApproval';
  int gets = 0;
  @override
  Future<AiWorkflow> get(String id) async {
    gets++;
    return AiWorkflow.fromJson(fixture(status));
  }

  @override
  Future<String?> studioName(String id) async => 'Snap Studio';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'customer_jwt': 'customer-jwt',
    }),
  );
  test('requirements validate supported bounded fields', () {
    expect(requirements().validate(), isNull);
    expect(
      requirements(
        start: '08:00',
        end: '12:00',
        services: 'Photography, Album',
      ).validate(),
      isNull,
    );
    for (final value in [
      requirements(type: ''),
      requirements(location: ''),
      requirements(budget: '-1'),
      requirements(budget: 'NaN'),
      requirements(hours: '0'),
      requirements(hours: '25'),
      requirements(first: '2030-02-30'),
      requirements(last: '2029-12-30'),
      requirements(last: '2030-02-01'),
      requirements(start: '12:00'),
      requirements(start: '12:00', end: '08:00'),
      requirements(start: '25:00', end: '26:00'),
      requirements(services: List.filled(21, 'Photography').join(',')),
    ]) {
      expect(value.validate(), isNotNull);
    }
  });
  test('submission uses Customer JWT and only requirements; never identity or booking', () async {
    var requests = 0;
    final service = AiWorkflowService(
      client: MockClient((request) async {
        requests++;
        expect(request.url.path, '/api/ai-workflows');
        expect(request.method, 'POST');
        expect(request.headers['Authorization'], 'Bearer customer-jwt');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys, ['requirements']);
        expect(body['requirements'], requirements().toJson());
        expect(request.body, isNot(contains('customerId')));
        expect(request.body, isNot(contains('reviewer')));
        return http.Response(jsonEncode(fixture()), 201);
      }),
    );
    addTearDown(service.close);
    expect((await service.submit(requirements())).status, 'AwaitingApproval');
    expect(requests, 1);
  });
  test('missing token and invalid requirements cannot dispatch', () async {
    FlutterSecureStorage.setMockInitialValues({});
    var calls = 0;
    final service = AiWorkflowService(
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(service.close);
    await expectLater(
      service.submit(requirements()),
      throwsA(isA<AiWorkflowException>()),
    );
    await expectLater(
      service.submit(requirements(type: '')),
      throwsA(isA<AiWorkflowException>()),
    );
    expect(calls, 0);
  });
  test('history and detail authenticate and verify correlation', () async {
    final service = AiWorkflowService(
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer customer-jwt');
        if (request.url.path.endsWith(id)) {
          return http.Response(jsonEncode(fixture('Approved')), 200);
        }
        expect(request.url.queryParameters, {'page': '1', 'pageSize': '20'});
        return http.Response(
          jsonEncode({
            'items': [fixture()],
            'page': 1,
            'hasMore': false,
          }),
          200,
        );
      }),
    );
    addTearDown(service.close);
    expect((await service.list()).items.single.label, 'Awaiting Approval');
    expect((await service.get(id)).status, 'Approved');
  });
  for (final status in [400, 401, 404, 409, 500]) {
    test('HTTP $status error is sanitized', () async {
      final service = AiWorkflowService(
        client: MockClient(
          (_) async => http.Response('PRIVATE key trace', status),
        ),
      );
      addTearDown(service.close);
      await expectLater(
        service.submit(requirements()),
        throwsA(
          isA<AiWorkflowException>().having(
            (e) => e.message,
            'safe message',
            isNot(contains('PRIVATE')),
          ),
        ),
      );
    });
  }
  test('malformed creation result is uncertain and never retried', () async {
    var count = 0;
    final service = AiWorkflowService(
      client: MockClient((_) async {
        count++;
        return http.Response('{}', 201);
      }),
    );
    addTearDown(service.close);
    await expectLater(
      service.submit(requirements()),
      throwsA(
        isA<AiWorkflowException>().having(
          (e) => e.outcomeUnknown,
          'uncertain',
          true,
        ),
      ),
    );
    expect(count, 1);
  });
  test('unknown status and incomplete proposal fail closed', () {
    expect(
      () => AiWorkflow.fromJson(fixture('Unknown')),
      throwsFormatException,
    );
    expect(
      () => AiWorkflow.fromJson({...fixture(), 'proposal': null}),
      throwsFormatException,
    );
    expect(
      AiWorkflow.fromJson({...fixture('Submitted'), 'proposal': null}).label,
      'Processing',
    );
  });
  for (final status in [
    'AwaitingApproval',
    'Approved',
    'Rejected',
    'RevalidationRequired',
    'Failed',
  ]) {
    testWidgets('$status displays safe canonical status and details', (
      tester,
    ) async {
      final service = FakeService();
      addTearDown(service.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: AiWorkflowStatusScreen(
            workflowId: id,
            initial: AiWorkflow.fromJson(fixture(status)),
            service: service,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(workflowLabels[status]!), findsOneWidget);
      expect(find.text('Studio: Snap Studio'), findsOneWidget);
      expect(find.text('Package: Portrait session'), findsOneWidget);
      expect(find.textContaining('PRIVATE'), findsNothing);
      if (status == 'Approved') {
        expect(
          find.textContaining('No booking has been created'),
          findsOneWidget,
        );
      }
    });
  }
  testWidgets('manual refresh shows later Studio approval', (tester) async {
    final service = FakeService();
    addTearDown(service.close);
    await tester.pumpWidget(
      MaterialApp(
        home: AiWorkflowStatusScreen(
          workflowId: id,
          initial: AiWorkflow.fromJson(fixture()),
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    service.status = 'Approved';
    await tester.tap(find.byTooltip('Refresh status'));
    await tester.pumpAndSettle();
    expect(find.text('Approved'), findsOneWidget);
    expect(service.gets, 1);
    await tester.pump(const Duration(minutes: 5));
    expect(service.gets, 1); // No polling.
  });
  testWidgets(
    'duplicate submit blocked and uncertain result requires history check',
    (tester) async {
      var posts = 0;
      final response = Completer<http.Response>();
      final service = AiWorkflowService(
        client: MockClient((request) {
          posts++;
          return response.future;
        }),
      );
      addTearDown(service.close);
      await tester.pumpWidget(
        MaterialApp(home: AiRequirementsScreen(service: service)),
      );
      for (final entry in {
        'type': 'Portrait',
        'location': 'Colombo',
        'budget': '6000',
        'earliest': '2030-01-01',
        'latest': '2030-01-02',
        'hours': '2',
      }.entries) {
        await tester.ensureVisible(find.byKey(ValueKey(entry.key)));
        await tester.enterText(find.byKey(ValueKey(entry.key)), entry.value);
      }
      final submit = find.widgetWithText(FilledButton, 'Get recommendation');
      await tester.ensureVisible(submit);
      final submitCallback = tester.widget<FilledButton>(submit).onPressed!;
      submitCallback();
      submitCallback(); // Two queued taps before the disabled button is rebuilt.
      await tester.pump();
      expect(posts, 1);
      expect(find.text('Submitting…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Processing…'), findsOneWidget);
      response.complete(http.Response('{}', 201));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(FilledButton),
        250,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ).first,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.text('Check My AI recommendations'), findsOneWidget);
    },
  );
}
