import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photography_mobile/models/ai_workflow.dart';
import 'package:photography_mobile/screens/ai/ai_workflow_screens.dart';
import 'package:photography_mobile/services/ai_workflow_service.dart';

void main() {
  testWidgets(
    'customer can choose Studio and Package rank 2 from three JourneyV1 options',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'customer_jwt': 'customer-jwt',
      });
      const workflowId = '11111111-1111-4111-8111-111111111111';
      const selectedStudioId = '66666666-6666-4666-8666-666666666666';
      const selectedStudioOption = '88888888-8888-4888-8888-888888888888';
      const studioIds = [
        '22222222-2222-4222-8222-222222222222',
        '66666666-6666-4666-8666-666666666666',
        '77777777-7777-4777-8777-777777777777',
      ];
      const studioOptionIds = [
        '33333333-3333-4333-8333-333333333333',
        '88888888-8888-4888-8888-888888888888',
        '99999999-9999-4999-8999-999999999999',
      ];
      const packageIds = [
        '44444444-4444-4444-8444-444444444444',
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      ];
      const packageOptionIds = [
        '55555555-5555-4555-8555-555555555555',
        'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      ];

      final studios = List.generate(
        3,
        (i) => {
          'eventId': studioOptionIds[i],
          'studioId': studioIds[i],
          'stage': 'StudioMatching',
          'rank': i + 1,
          'name': 'Studio ${i + 1}',
          'location': 'Colombo',
          'specialties': 'Portrait photography',
          'reason': 'Matches your portrait requirements.',
        },
      );
      final packages = List.generate(
        3,
        (i) => {
          'eventId': packageOptionIds[i],
          'studioId': selectedStudioId,
          'packageId': packageIds[i],
          'stage': 'PackageRecommendation',
          'rank': i + 1,
          'name': 'Package ${i + 1}',
          'price': 12500 + i * 2500,
          'durationHours': 3 + i,
          'extraHours': 0,
          'services': ['Portrait photography'],
          'reason': 'Includes the requested portrait service.',
        },
      );

      Map<String, dynamic> response(String stage, int revision) => {
        'id': workflowId,
        'status': stage,
        'currentStep': stage,
        'proposalVersion': 0,
        'expiresAt': '2030-01-01T12:00:00Z',
        'journey': {
          'revision': revision,
          'stage': stage,
          'busy': false,
          'validated': false,
          'submitted': false,
          'errorCode': null,
          'studioOptionId': stage == 'StudioMatching'
              ? null
              : selectedStudioOption,
          'packageOptionId': stage == 'Scheduling'
              ? packageOptionIds[1]
              : null,
          'scheduleOptionId': null,
          'options': [
            ...studios,
            if (stage != 'StudioMatching') ...packages,
          ],
        },
      };

      var studioSelectionCount = 0;
      var packageSelectionCount = 0;
      final service = AiWorkflowService(
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer customer-jwt');
          if (request.method == 'GET') {
            expect(request.url.path, '/api/ai-workflows/$workflowId');
            return http.Response(
              jsonEncode(response('StudioMatching', 1)),
              200,
            );
          }

          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body.keys.toSet(), {
            'operationId',
            'revision',
            'optionEventId',
          });
          expect(
            workflowIdPattern.hasMatch(body['operationId'] as String),
            isTrue,
          );
          if (request.url.path.endsWith('/journey/studio')) {
            studioSelectionCount++;
            expect(body['revision'], 1);
            expect(body['optionEventId'], studioOptionIds[1]);
            expect(body['optionEventId'], isNot(studioIds[1]));
            return http.Response(
              jsonEncode(response('PackageRecommendation', 2)),
              200,
            );
          }
          expect(request.url.path, '/api/ai-workflows/$workflowId/journey/package');
          packageSelectionCount++;
          expect(body['revision'], 2);
          expect(body['optionEventId'], packageOptionIds[1]);
          expect(body['optionEventId'], isNot(packageIds[1]));
          return http.Response(jsonEncode(response('Scheduling', 3)), 200);
        }),
      );
      addTearDown(service.close);

      await tester.pumpWidget(
        MaterialApp(
          home: AiWorkflowStatusScreen(
            workflowId: workflowId,
            service: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final label in ['Package', 'Schedule', 'Validate']) {
        final chip = tester.widget<ActionChip>(
          find.widgetWithText(ActionChip, label),
        );
        expect(chip.onPressed, isNull, reason: '$label stays locked');
      }
      for (var i = 1; i <= 3; i++) {
        await tester.scrollUntilVisible(find.text('Studio $i'), 250);
        await tester.pumpAndSettle();
        expect(find.text('Studio $i'), findsOneWidget);
      }
      await tester.scrollUntilVisible(find.text('Studio 1'), -250);
      await tester.pumpAndSettle();
      expect(find.text('AI recommended'), findsOneWidget);

      final secondStudioCard = find.ancestor(
        of: find.text('Studio 2'),
        matching: find.byType(Card),
      );
      await tester.ensureVisible(
        find.descendant(
          of: secondStudioCard,
          matching: find.text('Select Studio / Continue'),
        ),
      );
      await tester.tap(
        find.descendant(
          of: secondStudioCard,
          matching: find.text('Select Studio / Continue'),
        ),
      );
      await tester.pumpAndSettle();

      expect(studioSelectionCount, 1);
      await tester.drag(find.byType(ListView), const Offset(0, 1000));
      await tester.pumpAndSettle();
      expect(find.text('Package Recommendation Agent'), findsOneWidget);
      expect(find.text('Studio: Studio 2'), findsOneWidget);
      for (final label in ['Schedule', 'Validate']) {
        final chip = tester.widget<ActionChip>(
          find.widgetWithText(ActionChip, label),
        );
        expect(chip.onPressed, isNull, reason: '$label stays locked');
      }
      for (var i = 1; i <= 3; i++) {
        await tester.scrollUntilVisible(find.text('Package $i'), 250);
        await tester.pumpAndSettle();
        expect(find.text('Package $i'), findsOneWidget);
        expect(
          find.text('Price: LKR ${12500 + (i - 1) * 2500}'),
          findsOneWidget,
        );
      }
      await tester.scrollUntilVisible(find.text('Package 1'), -250);
      await tester.pumpAndSettle();
      expect(find.text('AI recommended'), findsOneWidget);

      final secondPackageCard = find.ancestor(
        of: find.text('Package 2'),
        matching: find.byType(Card),
      );
      await tester.ensureVisible(
        find.descendant(
          of: secondPackageCard,
          matching: find.text('Select Package & Continue'),
        ),
      );
      await tester.tap(
        find.descendant(
          of: secondPackageCard,
          matching: find.text('Select Package & Continue'),
        ),
      );
      await tester.pumpAndSettle();

      expect(packageSelectionCount, 1);
      expect(find.text('Scheduling Agent'), findsOneWidget);
      expect(find.text('Studio: Studio 2'), findsOneWidget);
      expect(find.text('Package: Package 2'), findsOneWidget);
      expect(find.text('Quoted price: LKR 15000'), findsOneWidget);
      expect(find.text('Studio: Studio 1'), findsNothing);
      expect(find.text('Package: Package 1'), findsNothing);
    },
  );

  testWidgets(
    'displayed Studio selection preserves workflow and option IDs through HTTP',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'customer_jwt': 'customer-jwt',
      });
      const workflowId = '11111111-1111-4111-8111-111111111111';
      const studioId = '22222222-2222-4222-8222-222222222222';
      const optionId = '33333333-3333-4333-8333-333333333333';
      const packageOptionId = '44444444-4444-4444-8444-444444444444';
      const packageId = '55555555-5555-4555-8555-555555555555';
      Map<String, dynamic> response(bool selected) => {
        'id': workflowId,
        'status': selected ? 'PackageRecommendation' : 'StudioMatching',
        'currentStep': selected ? 'PackageRecommendation' : 'StudioMatching',
        'proposalVersion': 0,
        'expiresAt': '2030-01-01T12:00:00Z',
        'journey': {
          'revision': selected ? 2 : 1,
          'stage': selected ? 'PackageRecommendation' : 'StudioMatching',
          'busy': false,
          'validated': false,
          'submitted': false,
          'errorCode': null,
          'studioOptionId': selected ? optionId : null,
          'packageOptionId': null,
          'scheduleOptionId': null,
          'options': [
            {
              'eventId': optionId,
              'studioId': studioId,
              'stage': 'StudioMatching',
              'rank': 1,
              'name': 'jega studio',
              'location': 'Colombo',
            },
            if (selected)
              {
                'eventId': packageOptionId,
                'studioId': studioId,
                'packageId': packageId,
                'stage': 'PackageRecommendation',
                'rank': 1,
                'name': 'Portrait package',
                'price': 5000,
                'durationHours': 2,
              },
          ],
        },
      };
      var selections = 0;
      final service = AiWorkflowService(
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer customer-jwt');
          if (request.method == 'GET') {
            expect(request.url.path, '/api/ai-workflows/$workflowId');
            return http.Response(jsonEncode(response(false)), 200);
          }
          selections++;
          expect(request.method, 'POST');
          expect(
            request.url.path,
            '/api/ai-workflows/$workflowId/journey/studio',
          );
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body.keys.toSet(), {
            'operationId',
            'revision',
            'optionEventId',
          });
          expect(body['optionEventId'], optionId);
          expect(body['optionEventId'], isNot(studioId));
          expect(body['revision'], 1);
          expect(
            workflowIdPattern.hasMatch(body['operationId'] as String),
            isTrue,
          );
          return http.Response(jsonEncode(response(true)), 200);
        }),
      );
      addTearDown(service.close);
      await tester.pumpWidget(
        MaterialApp(
          home: AiWorkflowStatusScreen(
            workflowId: workflowId,
            service: service,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('jega studio'), findsOneWidget);
      expect(find.text('Select Package & Continue'), findsNothing);
      final select = find.text('Select Studio / Continue');
      await tester.ensureVisible(select);
      await tester.tap(select);
      await tester.pumpAndSettle();
      expect(selections, 1);
      expect(find.text('Portrait package'), findsOneWidget);
      expect(find.text('Select Package & Continue'), findsOneWidget);
      expect(
        find.text(
          'This recommendation was not found or is not available to your account.',
        ),
        findsNothing,
      );
    },
  );
}
