import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photography_mobile/models/photography_package.dart';
import 'package:photography_mobile/screens/booking/booking_date_time_screen.dart';
import 'package:photography_mobile/screens/booking/booking_summary_screen.dart';

import 'package_test.dart' show packageJson, summaryJson, addonId;

void main() {
  for (final scenario in [
    (extra: 0, start: 9, end: 13),
    (extra: 0, start: 11, end: 15),
    (extra: 2, start: 9, end: 15),
    (extra: 0, start: 14, end: 18),
  ]) {
    testWidgets('${scenario.extra} extra hours: ${scenario.start}:00 to ${scenario.end}:00; preserves pricing customization', (tester) async {
      FlutterSecureStorage.setMockInitialValues({'customer_jwt': 'test-token'});
      final date = DateTime.now().add(const Duration(days: 30));
      final day = DateTime(date.year, date.month, date.day);
      final customization = PackageCustomization(
        selectedAddonIds: [addonId], extraHours: scenario.extra,
        additionalPhotographers: 1,
      );
      final price = PackagePriceSummary.fromJson({
        ...summaryJson(), 'extraHours': scenario.extra,
        'extraHoursCost': scenario.extra * 5000,
        'additionalPhotographers': 1, 'additionalPhotographersCost': 10000,
        'finalPrice': 178000 + scenario.extra * 5000,
      });
      Map<String, dynamic>? submitted;
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(home: BookingDateTimeScreen(
          package: PhotographyPackage.fromJson({...packageJson(), 'durationHours': 4}),
          customization: customization, estimate: price,
        )));
        await tester.pumpAndSettle();
        expect(find.text('Package duration: 4 hours'), findsOneWidget);
        await tester.tap(find.textContaining('Available:'));
        await tester.pumpAndSettle();
        final continueButton = find.widgetWithText(FilledButton, 'Continue');
        expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);
        final dropdown = tester.widget<DropdownButton<DateTime>>(find.byType(DropdownButton<DateTime>));
        final starts = dropdown.items!.map((item) => item.value!).toList();
        expect(starts.first, day.add(const Duration(hours: 9)));
        expect(starts.last, day.add(Duration(hours: 14 - scenario.extra)));
        expect(starts, isNot(contains(day.add(Duration(hours: 14 - scenario.extra, minutes: 1)))));
        expect(starts.every((start) => !start.add(Duration(hours: 4 + scenario.extra)).isAfter(day.add(const Duration(hours: 18)))), isTrue);
        // Pick the same value a dropdown selection supplies.
        dropdown.onChanged!(day.add(Duration(hours: scenario.start)));
        await tester.pumpAndSettle();
        expect(find.textContaining('Selected booking:'), findsOneWidget);
        await tester.tap(continueButton);
        await tester.pumpAndSettle();
        final summary = tester.widget<BookingSummaryScreen>(find.byType(BookingSummaryScreen));
        expect(summary.slot.startTime, '${scenario.start.toString().padLeft(2, '0')}:00:00.000');
        expect(summary.slot.endTime, '${scenario.end}:00:00.000');
        expect(summary.customization, same(customization));
        expect(summary.estimate, same(price));
        final scroll = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
        await tester.scrollUntilVisible(find.text('Booking location *'), 300, scrollable: scroll);
        await tester.enterText(find.byType(TextFormField).first, 'Studio');
        await tester.pump();
        final confirm = find.widgetWithText(FilledButton, 'Confirm Booking');
        await tester.scrollUntilVisible(confirm, 300, scrollable: scroll);
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(submitted?['startTime'], summary.slot.startTime);
        expect(submitted?['endTime'], summary.slot.endTime);
        expect(submitted?['extraHours'], scenario.extra);
        expect(submitted?['selectedAddonIds'], [addonId]);
        expect(submitted?['additionalPhotographers'], 1);
        expect(submitted!.containsKey('totalPrice'), isFalse);
        expect(find.text(formatLkr(price.finalPrice)), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => MockClient((request) async {
        if (request.method == 'POST') {
          submitted = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'id': 12, 'status': 0, 'totalPrice': price.finalPrice}), 201);
        }
        return http.Response(jsonEncode([{
          'date': day.toIso8601String().split('T').first,
          'isAvailable': true, 'startTime': '09:00:00', 'endTime': '18:00:00',
        }]), 200);
      }));
    });
  }

  testWidgets('hides availability windows too short for the required duration', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(home: BookingDateTimeScreen(
        package: PhotographyPackage.fromJson({...packageJson(), 'durationHours': 4}),
        customization: PackageCustomization(extraHours: 2),
      )));
      await tester.pumpAndSettle();
      expect(find.text('No upcoming bookable time slots available.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue')).onPressed, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((_) async => http.Response(jsonEncode([{
      'date': DateTime.now().add(const Duration(days: 30)).toIso8601String().split('T').first,
      'isAvailable': true, 'startTime': '09:00:00', 'endTime': '14:59:00',
    }]), 200)));
  });
}
