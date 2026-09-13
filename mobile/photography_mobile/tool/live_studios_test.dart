// Opt-in live API test: uses only owner-created data from the running backend.
import 'dart:io';

import 'package:http/io_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photography_mobile/screens/studio/studio_list_screen.dart';
import 'package:photography_mobile/services/studio_service.dart';
import 'package:photography_mobile/theme/app_theme.dart';

void main() {
  final liveClient = IOClient(HttpClient());
  testWidgets('real studio list, search and ID-based details at phone size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = StudioService(client: liveClient);
    addTearDown(service.close);
    final studios = await tester.runAsync(service.getStudios);
    expect(
      studios,
      isNotEmpty,
      reason:
          'Create a studio with the owner app before running this live test.',
    );
    final selected = studios!.first;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: StudioListScreen(service: service),
        ),
      );
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pumpAndSettle();
    expect(find.text(selected.studioName), findsWidgets);
    await tester.enterText(
      find.byType(TextField),
      selected.location.toUpperCase(),
    );
    await tester.pumpAndSettle();
    expect(find.text(selected.studioName), findsWidgets);
    await tester.enterText(
      find.byType(TextField),
      'no-match-${DateTime.now().microsecondsSinceEpoch}',
    );
    await tester.pumpAndSettle();
    expect(find.text('No studios match your search.'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField),
      selected.studioName.toUpperCase(),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('View Studio').first);
    await tester.runAsync(() async {
      await tester.tap(find.text('View Studio').first);
      await tester.pump();
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pumpAndSettle();
    expect(find.text('Studio details'), findsOneWidget);
    expect(find.text(selected.studioName), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
