import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photography_mobile/screens/studio/studio_list_screen.dart';
import 'package:photography_mobile/services/location_service.dart';
import 'package:photography_mobile/services/studio_service.dart';

class FakeLocationService extends LocationService {
  FakeLocationService({this.failure});
  final String? failure;
  int calls = 0;
  @override
  Future<CustomerLocation> getCurrentLocation() async {
    calls++;
    if (failure != null) throw LocationFailure(failure!);
    return const CustomerLocation(6.9271, 79.8612);
  }
}

void main() {
  testWidgets(
    'GPS is opt-in; Near Me shows distance; All studios restores browsing',
    (tester) async {
      final location = FakeLocationService();
      final service = StudioService(
        client: MockClient((request) async {
          final nearby = request.url.path.endsWith('/nearby');
          if (nearby) {
            expect(request.url.queryParameters['latitude'], '6.9271');
            expect(request.url.queryParameters['longitude'], '79.8612');
            expect(request.url.queryParameters['radiusKm'], '50.0');
          } else {
            expect(request.url.queryParameters, isEmpty);
          }
          return http.Response(
            jsonEncode([
              {
                'id': 'studio',
                'studioName': nearby ? 'Nearby studio' : 'Normal studio',
                if (nearby) 'distanceKm': 2.4,
              },
            ]),
            200,
          );
        }),
      );
      addTearDown(service.close);
      await tester.pumpWidget(
        MaterialApp(
          home: StudioListScreen(service: service, locationService: location),
        ),
      );
      await tester.pumpAndSettle();
      expect(location.calls, 0);
      await tester.tap(find.text('Near Me'));
      await tester.pumpAndSettle();
      expect(location.calls, 1);
      expect(find.text('2.4 km away'), findsOneWidget);
      await tester.tap(find.text('All studios'));
      await tester.pumpAndSettle();
      expect(find.text('Normal studio'), findsOneWidget);
      expect(find.text('2.4 km away'), findsNothing);
    },
  );

  testWidgets('Location failure leaves normal browsing usable', (tester) async {
    final service = StudioService(
      client: MockClient((request) async {
        expect(request.url.path.endsWith('/nearby'), isFalse);
        return http.Response('[]', 200);
      }),
    );
    addTearDown(service.close);
    await tester.pumpWidget(
      MaterialApp(
        home: StudioListScreen(
          service: service,
          locationService: FakeLocationService(failure: 'Permission denied'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Near Me'));
    await tester.pumpAndSettle();
    expect(find.text('Permission denied'), findsOneWidget);
    expect(find.text('No studios available yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
