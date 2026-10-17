import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photography_mobile/models/studio.dart';
import 'package:photography_mobile/screens/studio/studio_list_screen.dart';
import 'package:photography_mobile/services/api_config.dart';
import 'package:photography_mobile/services/studio_service.dart';
import 'package:photography_mobile/theme/app_theme.dart';
import 'package:photography_mobile/widgets/studio_image.dart';

void main() {
  test('relative images resolve; filesystem paths are rejected', () {
    expect(
      ApiConfig.imageUrl('/uploads/studios/photo.jpg'),
      'http://localhost:5284/uploads/studios/photo.jpg',
    );
    expect(ApiConfig.imageUrl(null), isNull);
    expect(ApiConfig.imageUrl(r'C:\photos\image.jpg'), isNull);
    expect(ApiConfig.imageUrl('file:///photo.jpg'), isNull);
  });

  test('search matches normalized multi-word text across studio fields', () {
    const studio = Studio(
      id: 'studio-1',
      studioName: 'Luna Photo',
      location: 'Colombo  Fort',
      description: 'Wedding and portrait photography',
      photographyTypes: ['Wedding'],
    );

    expect(studio.matches('  WEDDING   colombo '), isTrue);
    expect(studio.matches('Luna portrait'), isTrue);
    expect(studio.matches('Kandy wedding'), isFalse);
    expect(studio.matches('   '), isTrue);
  });

  for (final status in [401, 403, 404, 408, 429, 500]) {
    test('HTTP $status has a controlled error', () async {
      final service = StudioService(
        client: MockClient((_) async => http.Response('', status)),
      );
      addTearDown(service.close);
      await expectLater(
        service.getStudios(),
        throwsA(isA<StudioApiException>()),
      );
    });
  }
  for (final body in ['not json', '{}', '[{}]']) {
    test('invalid response $body has a controlled error', () async {
      final service = StudioService(
        client: MockClient((_) async => http.Response(body, 200)),
      );
      addTearDown(service.close);
      await expectLater(
        service.getStudios(),
        throwsA(isA<StudioApiException>()),
      );
    });
  }
  test('connection failure has a controlled error', () async {
    final service = StudioService(
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    addTearDown(service.close);
    await expectLater(service.getStudios(), throwsA(isA<StudioApiException>()));
  });

  test('rate limit response suggests a safe next step', () async {
    final service = StudioService(
      client: MockClient((_) async => http.Response('', 429)),
    );
    addTearDown(service.close);
    await expectLater(
      service.getStudios(),
      throwsA(
        isA<StudioApiException>().having(
          (error) => error.message,
          'message',
          contains('Wait a moment'),
        ),
      ),
    );
  });

  testWidgets('missing studio image displays an accessible fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(width: 300, height: 160, child: StudioImage()),
      ),
    );

    expect(find.text('No photo yet'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Studio cover photo, not provided',
      ),
      findsOneWidget,
    );
  });

  testWidgets('search and photography type chips refine studio results', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = StudioService(
      client: MockClient(
        (_) async => http.Response('''
          [
            {
              "id": "luna",
              "studioName": "Luna Photo",
              "location": "Colombo",
              "photographyTypes": ["Wedding", "Portrait"]
            },
            {
              "id": "island",
              "studioName": "Island Frames",
              "location": "Kandy",
              "photographyTypes": ["Wedding"]
            }
          ]
          ''', 200),
      ),
    );
    addTearDown(service.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: StudioListScreen(service: service),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 studios found'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'portrait colombo');
    await tester.pumpAndSettle();
    expect(find.text('1 studio found'), findsOneWidget);
    expect(find.text('Luna Photo'), findsOneWidget);
    expect(find.text('Island Frames'), findsNothing);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('2 studios found'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Portrait'));
    await tester.pumpAndSettle();
    expect(find.text('1 studio found'), findsOneWidget);
    expect(find.text('Luna Photo'), findsOneWidget);
    expect(find.text('Island Frames'), findsNothing);
  });

  testWidgets('390 x 844: loading, error, retry and empty state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    final service = StudioService(
      client: MockClient((_) async {
        calls++;
        return http.Response(calls == 1 ? '' : '[]', calls == 1 ? 500 : 200);
      }),
    );
    addTearDown(service.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: StudioListScreen(service: service),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Unable to load studios.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No studios available yet.'), findsOneWidget);
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });
}
