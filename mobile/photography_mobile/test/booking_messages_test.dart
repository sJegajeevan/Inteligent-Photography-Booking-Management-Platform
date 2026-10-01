import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photography_mobile/screens/booking/booking_conversation_screen.dart';
import 'package:photography_mobile/services/booking_service.dart';

Map<String, dynamic> message({int id = 1, String role = 'Customer', String text = 'Hello'}) => {
  'id': id, 'bookingId': 12, 'senderUserId': role == 'Customer' ? 1 : 2,
  'senderName': role == 'Customer' ? 'Alice' : 'Studio Owner', 'senderRole': role,
  'message': text, 'sentAt': '2026-09-28T10:00:00Z',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({'customer_jwt': 'test-token'}));

  test('authenticated message service sends only trimmed text and parses UTC', () async {
    await http.runWithClient(() async {
      final service = BookingService();
      final messages = await service.getMessages(12);
      expect(messages.single.sentAt.isUtc, isTrue);
      final sent = await service.sendMessage(12, '  Hello  ');
      expect(sent.message, 'Hello');
      service.close();
    }, () => MockClient((request) async {
      expect(request.url.path, '/api/bookings/12/messages');
      expect(request.headers['Authorization'], 'Bearer test-token');
      if (request.method == 'POST') {
        expect(jsonDecode(request.body), {'message': 'Hello'});
        return http.Response(jsonEncode(message()), 201);
      }
      return http.Response(jsonEncode([message()]), 200);
    }));
  });

  test('empty and oversized messages are rejected before network access', () async {
    var calls = 0;
    await http.runWithClient(() async {
      final service = BookingService();
      for (final text in ['', ' \n ', 'x' * 1001]) {
        await expectLater(service.sendMessage(12, text), throwsA(isA<BookingApiException>()));
      }
      expect(calls, 0);
      await service.sendMessage(12, 'x' * 1000);
      expect(calls, 1);
      service.close();
    }, () => MockClient((request) async { calls++; return http.Response(jsonEncode(message()), 201); }));
  });

  test('unauthorized and unavailable conversations surface safe errors', () async {
    for (final code in [401, 403, 404]) {
      await http.runWithClient(() async {
        final service = BookingService();
        await expectLater(service.getMessages(12), throwsA(isA<BookingApiException>()
          .having((error) => error.statusCode, 'status', code)));
        service.close();
      }, () => MockClient((_) async => http.Response('{}', code)));
    }
  });

  testWidgets('conversation displays messages and prevents duplicate sends then refreshes', (tester) async {
    final pending = Completer<http.Response>();
    var posts = 0, reads = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: BookingConversationScreen(bookingId: 12, studioName: 'Portrait Studio')));
      await tester.pumpAndSettle();
      expect(find.text('Portrait Studio'), findsOneWidget);
      expect(find.text('Studio Owner · Studio'), findsOneWidget);
      expect(find.text('Welcome'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();
      final send = tester.widget<FilledButton>(find.byType(FilledButton)).onPressed!;
      send(); send();
      await tester.pump();
      expect(posts, 1);
      expect(find.text('Sending…'), findsOneWidget);
      pending.complete(http.Response(jsonEncode(message()), 201));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('Hello'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((request) async {
      if (request.method == 'POST') { posts++; return pending.future; }
      reads++;
      return http.Response(jsonEncode([message(id: 2, role: 'Studio', text: 'Welcome'), if (reads > 1) message()]), 200);
    }));
  });

  testWidgets('failed load offers retry and recovers to empty state', (tester) async {
    var reads = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: BookingConversationScreen(bookingId: 12)));
      await tester.pumpAndSettle();
      expect(find.text('Retry refresh'), findsOneWidget);
      await tester.tap(find.text('Retry refresh'));
      await tester.pumpAndSettle();
      expect(find.text('No messages yet. Ask your studio about this booking.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((_) async { reads++; return http.Response(reads == 1 ? '{}' : '[]', reads == 1 ? 500 : 200); }));
  });

  testWidgets('failed send preserves draft and uncertain delivery requires refresh', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: BookingConversationScreen(bookingId: 12)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Keep my draft');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Keep my draft');
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      await tester.tap(find.text('Retry refresh'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((request) async => request.method == 'POST'
      ? http.Response('{}', 201) : http.Response('[]', 200)));
  });
}
