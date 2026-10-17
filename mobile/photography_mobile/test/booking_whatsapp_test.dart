import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photography_mobile/services/booking_service.dart';
import 'package:photography_mobile/services/booking_whatsapp.dart';
import 'package:photography_mobile/screens/booking/booking_details_screen.dart';
import 'package:photography_mobile/screens/booking/booking_conversation_screen.dart';

Map<String, dynamic> booking({String? contact = '0771234567'}) => {
  'id': 12, 'status': 0, 'totalPrice': 5000, 'studioName': 'Lens & Light',
  'studioContactNumber': contact, 'bookingDate': '2026-12-01',
  'startTime': '10:00:00', 'endTime': '11:30:00',
  'customerId': 9876, 'studioId': 'private-studio-guid', 'notes': 'PRIVATE NOTES',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({'customer_jwt': 'secret-test-token'}));

  for (final number in ['0771234567', '+94771234567', '94771234567', '(077) 123-4567', '+94 (77) 123-4567']) {
    test('normalizes $number', () => expect(normalizeWhatsAppNumber(number), '94771234567'));
  }
  test('missing and invalid numbers are unavailable', () {
    for (final number in [null, '', ' ', '123', '0000000000', '940771234567', '+0771234567',
      '07712345678', '0771234567 ext 1', '0771234567&text=bad', '++94771234567', 'abc']) {
      expect(normalizeWhatsAppNumber(number), isNull, reason: '$number');
      expect(bookingWhatsAppUrl(CustomerBookingDetails.fromJson(booking(contact: number))), isNull);
    }
  });
  test('URL encodes only booking context, including punctuation and newlines', () {
    final url = bookingWhatsAppUrl(CustomerBookingDetails.fromJson(booking()))!;
    expect(url.scheme, 'https');
    expect(url.host, 'wa.me');
    expect(url.path, '/94771234567');
    expect(url.queryParameters.keys, ['text']);
    expect(url.queryParameters['text'], 'Hi, I have a booking with Lens & Light.\n'
      'Booking #12\nDate: 2026-12-01\nTime: 10:00 - 11:30\n\nI would like to discuss my booking.');
    expect(url.toString(), contains('%26'));
    expect(url.toString(), contains('%0A'));
    expect(url.toString(), contains('%23'));
    for (final private in ['9876', 'private-studio-guid', 'PRIVATE', 'secret-test-token']) {
      expect(url.toString(), isNot(contains(private)));
    }
  });

  testWidgets('internal messaging still opens the existing booked studio conversation', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: BookingDetailsScreen(bookingId: 12)));
      await tester.pumpAndSettle();
      expect(find.text('Contact Studio'), findsOneWidget);
      expect(find.text('Chat on WhatsApp'), findsOneWidget);
      await tester.tap(find.text('Message in SnapSync'));
      await tester.pumpAndSettle();
      final screen = tester.widget<BookingConversationScreen>(find.byType(BookingConversationScreen));
      expect(screen.bookingId, 12);
      expect(screen.studioName, 'Lens & Light');
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((request) async => http.Response(
      request.url.path.endsWith('/messages') ? '[]' : jsonEncode(booking()), 200)));
  });

  testWidgets('missing contact shows friendly feedback and keeps internal messaging available', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: BookingDetailsScreen(bookingId: 12)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chat on WhatsApp'));
      await tester.pump();
      expect(find.text('WhatsApp contact is not available for this studio.'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Message in SnapSync')).onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((_) async => http.Response(jsonEncode(booking(contact: null)), 200)));
  });

  testWidgets('launcher failure offers SnapSync fallback without crashing', (tester) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    var launches = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'launch');
      expect(Uri.parse(call.arguments['url'] as String).host, 'wa.me');
      expect(call.arguments['useWebView'], isFalse);
      launches++;
      return false;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: BookingDetailsScreen(bookingId: 12)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chat on WhatsApp'));
      await tester.pumpAndSettle();
      expect(launches, 1);
      expect(find.text('Unable to open WhatsApp. Please use Message in SnapSync.'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Message in SnapSync')).onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((_) async => http.Response(jsonEncode(booking()), 200)));
  });
}
