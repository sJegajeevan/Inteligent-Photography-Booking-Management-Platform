import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photography_mobile/models/photography_package.dart';
import 'package:photography_mobile/models/studio_availability.dart';
import 'package:photography_mobile/screens/booking/booking_summary_screen.dart';
import 'package:photography_mobile/screens/booking/my_bookings_screen.dart';
import 'package:photography_mobile/services/booking_service.dart';

PhotographyPackage package() => PhotographyPackage.fromJson({
  'id': '22222222-2222-2222-2222-222222222222',
  'studioId': '11111111-1111-1111-1111-111111111111',
  'name': 'Portrait',
  'status': 'Active',
  'basePrice': 5000,
  'durationHours': 2,
});

StudioAvailability slot() => StudioAvailability(
  date: DateTime.now().add(const Duration(days: 2)),
  isAvailable: true,
  startTime: '10:00:00',
  endTime: '11:00:00',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'customer_jwt': 'test-token'});
  });

  test('creation requires a positive ID, known status and positive finite total', () {
    final valid = <String, dynamic>{'id': 12, 'status': 0, 'totalPrice': 5000};
    expect(CreatedBooking.fromCreationJson(valid).status, 'Pending');
    expect(CreatedBooking.fromCreationJson({...valid, 'status': 'Pending'}).id, 12);
    for (final field in valid.keys) {
      final missing = {...valid}..remove(field);
      expect(() => CreatedBooking.fromCreationJson(missing), throwsFormatException);
    }
    for (final id in [0, -1, '12', 1.5]) {
      expect(() => CreatedBooking.fromCreationJson({...valid, 'id': id}), throwsFormatException);
    }
    for (final status in ['', 'Unknown', -1, 8, 0.5]) {
      expect(() => CreatedBooking.fromCreationJson({...valid, 'status': status}), throwsFormatException);
    }
    for (final price in [0, -1, '5000', double.nan, double.infinity]) {
      expect(() => CreatedBooking.fromCreationJson({...valid, 'totalPrice': price}), throwsFormatException);
    }
  });

  test('malformed 2xx responses are uncertain and never retried automatically', () async {
    for (final body in ['', 'not json', '[]', '{}', '{"id":12,"status":0}']) {
      var posts = 0;
      await http.runWithClient(() async {
        final service = BookingService();
        try {
          await expectLater(service.create(
            package: package(), customization: PackageCustomization(),
            slot: slot(), location: 'Studio', notes: '',
          ), throwsA(isA<BookingApiException>()
              .having((error) => error.outcomeUnknown, 'uncertain outcome', true)
              .having((error) => error.message, 'verification guidance', contains('My Bookings'))));
          expect(posts, 1);
        } finally {
          service.close();
        }
      }, () => MockClient((request) async {
        posts++;
        return http.Response(body, 201);
      }));
    }
  });

  testWidgets('confirmation blocks double taps and remains disabled after uncertain success', (tester) async {
    var posts = 0;
    final response = Completer<http.Response>();
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(home: BookingSummaryScreen(
        package: package(), customization: PackageCustomization(), slot: slot(),
      )));
      final formScroll = find.descendant(
        of: find.byType(ListView), matching: find.byType(Scrollable),
      ).first;
      await tester.scrollUntilVisible(find.text('Booking location *'), 300, scrollable: formScroll);
      await tester.enterText(find.byType(TextFormField).first, 'Studio');
      await tester.pump();
      final confirm = find.widgetWithText(FilledButton, 'Confirm Booking');
      await tester.scrollUntilVisible(confirm, 300, scrollable: formScroll);
      final confirmCallback = tester.widget<FilledButton>(confirm).onPressed!;
      confirmCallback();
      confirmCallback();
      await tester.pump();
      expect(posts, 1);
      expect(find.text('Confirming...'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      response.complete(http.Response('{}', 201));
      await tester.pumpAndSettle();
      expect(find.text('Booking created successfully'), findsNothing);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      final myBookings = find.widgetWithText(OutlinedButton, 'My Bookings');
      await tester.scrollUntilVisible(myBookings, 200, scrollable: formScroll);
      expect(myBookings, findsOneWidget);
      expect(posts, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((request) {
      posts++;
      return response.future;
    }));
  });

  testWidgets('My Bookings reloads after details returns', (tester) async {
    var listReads = 0;
    Map<String, dynamic> booking(int status) => {
      'id': 12, 'status': status, 'totalPrice': 5000,
      'bookingDate': '2026-12-01', 'startTime': '10:00:00', 'endTime': '11:00:00',
    };
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: MyBookingsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Pending'), findsOneWidget);
      await tester.tap(find.text('View Details'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(listReads, 2);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.byType(RefreshIndicator), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((request) async {
      if (request.url.path.endsWith('/api/bookings')) {
        listReads++;
        return http.Response(jsonEncode([booking(listReads == 1 ? 0 : 3)]), 200);
      }
      return http.Response(jsonEncode(booking(0)), 200);
    }));
  });
}
