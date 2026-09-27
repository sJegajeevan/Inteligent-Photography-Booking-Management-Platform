import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photography_mobile/models/ai_workflow.dart';
import 'package:photography_mobile/screens/ai/ai_workflow_screens.dart';
import 'package:photography_mobile/screens/booking/my_bookings_screen.dart';
import 'package:photography_mobile/theme/app_theme.dart';

import 'ai_workflow_test.dart' as fixtures;

class SubmissionService extends fixtures.FakeService {
  int submits = 0;
  AiRequirements? submitted;
  final result = Completer<AiWorkflow>();
  @override
  Future<AiWorkflow> submit(AiRequirements value) {
    submits++;
    submitted = value;
    return result.future;
  }
}

class LongNameService extends fixtures.FakeService {
  @override
  Future<String?> studioName(String id) async =>
      List.filled(12, 'Photography Studio').join(' ');
}

Future<void> fill(WidgetTester tester, Map<String, String> fields) async {
  for (final entry in fields.entries) {
    final field = find.byKey(ValueKey(entry.key));
    await tester.ensureVisible(field);
    await tester.enterText(field, entry.value);
  }
}

const valid = {
  'type': ' Portrait ',
  'location': ' Colombo ',
  'budget': '6000',
  'earliest': '2030-01-01',
  'latest': '2030-01-02',
  'hours': '2',
};

Future<void> submit(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Get recommendation');
  await tester.scrollUntilVisible(
    button,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  tester.widget<FilledButton>(button).onPressed!();
  await tester.pump();
}

void main() {
  testWidgets(
    'long names and add-ons wrap with larger text on a narrow phone',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = LongNameService();
      addTearDown(service.close);
      final data = fixtures.fixture();
      final name = List.filled(12, 'Wedding Photography').join(' ');
      data['proposal']['pricing']['packageName'] = name;
      data['proposal']['pricing']['selectedAddons'] = [
        {'id': fixtures.pack, 'name': 'Photo album'},
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: AiWorkflowStatusScreen(
            workflowId: fixtures.id,
            initial: AiWorkflow.fromJson(data),
            service: service,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(name), findsOneWidget);
      await tester.ensureVisible(find.textContaining('Add-ons: Photo album'));
      await tester.pumpAndSettle();
      expect(find.textContaining(fixtures.pack), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'customer_jwt': 'test-token',
    }),
  );
  testWidgets('empty required fields have inline errors without dispatch', (
    tester,
  ) async {
    final service = SubmissionService();
    addTearDown(service.close);
    await tester.pumpWidget(
      MaterialApp(home: AiRequirementsScreen(service: service)),
    );
    await submit(tester);
    for (final key in valid.keys) {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey(key)),
        key == 'type' ? -250 : 250,
        scrollable: find.byType(Scrollable).first,
      );
      final field = tester.widget<TextFormField>(find.byKey(ValueKey(key)));
      final decoration = tester
          .widget<TextField>(
            find.descendant(
              of: find.byWidget(field),
              matching: find.byType(TextField),
            ),
          )
          .decoration!;
      expect(decoration.errorText, isNotEmpty, reason: key);
    }
    expect(service.submits, 0);
  });

  for (final entry in <String, Map<String, String>>{
    'budget': {'budget': '0'},
    'non-numeric budget': {'budget': 'abc'},
    'date range': {'latest': '2029-12-31'},
    'coverage': {'hours': '0'},
    'coverage maximum': {'hours': '25'},
  }.entries) {
    testWidgets('invalid ${entry.key} is rejected locally', (tester) async {
      final service = SubmissionService();
      addTearDown(service.close);
      await tester.pumpWidget(
        MaterialApp(home: AiRequirementsScreen(service: service)),
      );
      await fill(tester, {...valid, ...entry.value});
      await submit(tester);
      expect(service.submits, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'valid form dispatches once and disables button while processing',
    (tester) async {
      final service = SubmissionService();
      addTearDown(service.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AiRequirementsScreen(service: service),
        ),
      );
      await fill(tester, valid);
      final button = find.widgetWithText(FilledButton, 'Get recommendation');
      await tester.ensureVisible(button);
      final callback = tester.widget<FilledButton>(button).onPressed!;
      callback();
      callback();
      await tester.pump();
      expect(service.submits, 1);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.text('Finding the best match for you...'), findsOneWidget);
      expect(service.submitted!.toJson()['photographyType'], 'Portrait');
      expect(service.submitted!.toJson()['location'], 'Colombo');
      service.result.complete(AiWorkflow.fromJson(fixtures.fixture()));
      await tester.pumpAndSettle();
      expect(find.byType(AiWorkflowStatusScreen), findsOneWidget);
      expect(service.submits, 1);
    },
  );

  for (final status in [
    'AwaitingApproval',
    'Approved',
    'Rejected',
    'Failed',
    'Expired',
    'RevalidationRequired',
  ]) {
    testWidgets(
      '$status is readable and contains no internal data on a small screen',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = fixtures.FakeService();
        service.status = status;
        addTearDown(service.close);
        final data = fixtures.fixture(status);
        data['errorCode'] = 'gemini_unavailable provider_error 429 503';
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: AiWorkflowStatusScreen(
              workflowId: fixtures.id,
              initial: AiWorkflow.fromJson(data),
              service: service,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Snap Studio'), findsOneWidget);
        expect(find.text('Portrait session'), findsOneWidget);
        expect(find.text('Portrait in Colombo'), findsOneWidget);
        expect(find.text('10:00 AM – 12:00 PM'), findsOneWidget);
        expect(find.textContaining('5,000'), findsOneWidget);
        for (final forbidden in [
          fixtures.id,
          fixtures.studio,
          fixtures.pack,
          'UTC',
          '2030-01-01T',
          'Proposal version',
          'PRIVATE',
          'gemini_unavailable',
          'provider_error',
          '429',
          '503',
        ]) {
          expect(find.textContaining(forbidden), findsNothing);
        }
        final expected = {
          'AwaitingApproval':
              'Your recommendation has been sent to the studio for review.',
          'Approved': 'Your booking has been created successfully.',
          'Rejected': 'Recommendation was not approved.',
          'Failed': 'AI recommendations are temporarily unavailable. Please try again later.',
          'Expired': 'This recommendation has expired. Please create a new recommendation.',
          'RevalidationRequired': 'Availability or pricing has changed. Please create a new recommendation.',
        }[status]!;
        await tester.ensureVisible(find.text(expected));
        await tester.pumpAndSettle();
        expect(find.text(expected), findsOneWidget);
        if (status == 'AwaitingApproval') {
          expect(
            find.textContaining('5:30 PM (Sri Lanka time)'),
            findsOneWidget,
          );
        }
        if (status == 'Approved') {
          await http.runWithClient(
            () async {
              final action = find.text('Go to My Bookings');
              await tester.scrollUntilVisible(
                action,
                250,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.tap(action);
              await tester.pumpAndSettle();
              expect(find.byType(MyBookingsScreen), findsOneWidget);
              await tester.pumpWidget(const SizedBox.shrink());
            },
            () => MockClient((request) async {
              expect(request.method, 'GET');
              return http.Response(jsonEncode([]), 200);
            }),
          );
        }
        if (status == 'Rejected') {
          final action = find.text('Create a new recommendation');
          await tester.scrollUntilVisible(
            action,
            250,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(action);
          await tester.pumpAndSettle();
          expect(find.byType(AiRequirementsScreen), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
