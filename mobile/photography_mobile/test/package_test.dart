import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photography_mobile/models/photography_package.dart';
import 'package:photography_mobile/screens/package/package_detail_screen.dart';
import 'package:photography_mobile/services/package_service.dart';
import 'package:photography_mobile/theme/app_theme.dart';
import 'package:photography_mobile/widgets/studio_packages_section.dart';

// Test fixtures only; production identifiers always come from the API.
const studioId = '11111111-1111-1111-1111-111111111111';
const packageId = '22222222-2222-2222-2222-222222222222';
const addonId = '33333333-3333-3333-3333-333333333333';
const otherId = '44444444-4444-4444-4444-444444444444';

Map<String, dynamic> addonJson() => {
  'id': addonId,
  'packageId': packageId,
  'name': 'Outdoor',
  'description': null,
  'price': 18000,
  'createdAt': '2026-09-09T10:00:00Z',
  'updatedAt': null,
};
Map<String, dynamic> packageJson() => {
  'id': packageId,
  'studioId': studioId,
  'name': 'Wedding Premium',
  'description': null,
  'basePrice': 150000,
  'durationHours': 8.5,
  'numberOfPhotographers': 2,
  'editedPhotoCount': 200,
  'albumIncluded': true,
  'videoIncluded': false,
  'extraHourRate': 5000,
  'additionalPhotographerRate': 10000,
  'coverImageUrl': null,
  'status': 'Active',
  'createdAt': null,
  'updatedAt': null,
  'services': [
    {'id': otherId, 'serviceName': 'Wedding Photography', 'description': null},
  ],
  'addons': [addonJson()],
};
Map<String, dynamic> summaryJson() => {
  'packageId': packageId,
  'packageName': 'Wedding Premium',
  'basePrice': 150000,
  'selectedAddons': [
    {'id': addonId, 'name': 'Outdoor', 'price': 18000},
  ],
  'extraHours': 1,
  'extraHoursCost': 5000,
  'additionalPhotographers': 0,
  'additionalPhotographersCost': 0,
  'finalPrice': 173000,
};
http.Response ok(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  test(
    'package and add-on parse actual DTO fields and nullable display data',
    () {
      final package = PhotographyPackage.fromJson(packageJson());
      expect(package.id, packageId);
      expect(package.studioId, studioId);
      expect(package.description, '');
      expect(package.basePrice, 150000);
      expect(package.durationHours, 8.5);
      expect(package.numberOfPhotographers, 2);
      expect(package.editedPhotoCount, 200);
      expect(package.albumIncluded, isTrue);
      expect(package.videoIncluded, isFalse);
      expect(package.extraHourRate, 5000);
      expect(package.additionalPhotographerRate, 10000);
      expect(package.services.single.serviceName, 'Wedding Photography');
      expect(package.addons.single.packageId, packageId);
      expect(package.addons.single.description, '');
      expect(package.addons.single.createdAt, isNotNull);
      expect(package.isActive, isTrue);
      expect(
        PhotographyPackage.fromJson({
          ...packageJson(),
          'services': null,
          'addons': null,
        }).addons,
        isEmpty,
      );
      expect(formatLkr(18000), 'LKR 18,000.00');
    },
  );

  test('invalid IDs, prices and cross-package add-ons are rejected', () {
    expect(
      () => PhotographyPackage.fromJson({...packageJson(), 'id': 'invalid'}),
      throwsFormatException,
    );
    expect(
      () => PackageAddon.fromJson({...addonJson(), 'price': null}),
      throwsFormatException,
    );
    expect(
      () => PhotographyPackage.fromJson({
        ...packageJson(),
        'addons': [
          {...addonJson(), 'packageId': otherId},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () =>
          PackagePriceSummary.fromJson({...summaryJson(), 'finalPrice': null}),
      throwsFormatException,
    );
  });

  test('price summary uses returned totals and selected add-on prices', () {
    final result = PackagePriceSummary.fromJson(summaryJson());
    expect(result.packageId, packageId);
    expect(result.selectedAddons.single.price, 18000);
    expect(result.extraHoursCost, 5000);
    expect(result.additionalPhotographersCost, 0);
    expect(result.finalPrice, 173000);
  });

  test('customization validates package scope and quantity bounds', () {
    final package = PhotographyPackage.fromJson(packageJson());
    expect(PackageCustomization().validate(package), isNull);
    for (final request in [
      PackageCustomization(extraHours: -1),
      PackageCustomization(extraHours: 1001),
      PackageCustomization(additionalPhotographers: -1),
      PackageCustomization(additionalPhotographers: 101),
      PackageCustomization(selectedAddonIds: [otherId]),
    ]) {
      expect(request.validate(package), isNotNull);
    }
    expect(
      PackageCustomization().validate(
        PhotographyPackage.fromJson({...packageJson(), 'status': 'Inactive'}),
      ),
      isNotNull,
    );
  });

  test('public routes and calculation payload contain only identifiers and quantities', () async {
    final requests = <http.Request>[];
    final service = PackageService(
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST') return ok(summaryJson());
        return ok(
          request.url.path.endsWith('/packages')
              ? [
                  packageJson(),
                  {...packageJson(), 'status': 'Inactive'},
                ]
              : packageJson(),
        );
      }),
    );
    addTearDown(service.close);
    expect(await service.getPackages(studioId), hasLength(1));
    final package = await service.getPackage(studioId, packageId);
    final summary = await service.calculatePrice(
      package,
      PackageCustomization(selectedAddonIds: [addonId], extraHours: 1),
    );
    expect(requests[0].url.path, '/api/public/studios/$studioId/packages');
    expect(
      requests[1].url.path,
      '/api/public/studios/$studioId/packages/$packageId',
    );
    expect(
      requests[2].url.path,
      '/api/public/studios/$studioId/packages/$packageId/calculate-price',
    );
    expect(jsonDecode(requests[2].body), {
      'selectedAddonIds': [addonId],
      'extraHours': 1,
      'additionalPhotographers': 0,
    });
    expect(summary.finalPrice, 173000);
    await expectLater(
      service.calculatePrice(
        package,
        PackageCustomization(selectedAddonIds: [otherId]),
      ),
      throwsA(isA<PackageApiException>()),
    );
    expect(requests, hasLength(3));
  });

  for (final code in [400, 401, 403, 404, 500]) {
    test('HTTP $code is a controlled package error', () async {
      final service = PackageService(
        client: MockClient((_) async => http.Response('', code)),
      );
      addTearDown(service.close);
      await expectLater(
        service.getPackages(studioId),
        throwsA(
          isA<PackageApiException>().having(
            (e) => e.statusCode,
            'status',
            code,
          ),
        ),
      );
    });
  }
  for (final body in [
    'not json',
    '{}',
    '[{}]',
    jsonEncode([
      {...packageJson(), 'studioId': otherId},
    ]),
  ]) {
    test(
      'malformed or wrong-studio package response is rejected: $body',
      () async {
        final service = PackageService(
          client: MockClient((_) async => http.Response(body, 200)),
        );
        addTearDown(service.close);
        await expectLater(
          service.getPackages(studioId),
          throwsA(isA<PackageApiException>()),
        );
      },
    );
  }
  test('connection errors and invalid links are controlled', () async {
    final service = PackageService(
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    addTearDown(service.close);
    await expectLater(
      service.getPackages(studioId),
      throwsA(isA<PackageApiException>()),
    );
    await expectLater(
      service.getPackages('bad-id'),
      throwsA(isA<PackageApiException>()),
    );
  });

  testWidgets('invalid package link shows an error without sending a request', (
    tester,
  ) async {
    var calls = 0;
    final service = PackageService(
      client: MockClient((_) async {
        calls++;
        return ok(packageJson());
      }),
    );
    addTearDown(service.close);
    await tester.pumpWidget(
      MaterialApp(
        home: PackageDetailScreen(
          studioId: studioId,
          packageId: 'invalid',
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('This studio or package link is invalid.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('package section loading, error, retry and empty state', (
    tester,
  ) async {
    var calls = 0;
    final service = PackageService(
      client: MockClient(
        (_) async => ++calls == 1 ? http.Response('', 500) : ok([]),
      ),
    );
    addTearDown(service.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: StudioPackagesSection(studioId: studioId, service: service),
          ),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.textContaining('server is unavailable'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No packages available for this studio.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '320px package navigation, customization, pending request and backend summary',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<http.Response>();
      var postCount = 0;
      final service = PackageService(
        client: MockClient((request) async {
          if (request.method == 'POST') {
            postCount++;
            expect(jsonDecode(request.body), {
              'selectedAddonIds': [addonId],
              'extraHours': 1,
              'additionalPhotographers': 0,
            });
            return pending.future;
          }
          return ok(
            request.url.path.endsWith('/packages')
                ? [packageJson()]
                : packageJson(),
          );
        }),
      );
      addTearDown(service.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: StudioPackagesSection(
                studioId: studioId,
                service: service,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('View Details'));
      await tester.tap(find.text('View Details'));
      await tester.pumpAndSettle();
      expect(find.byType(PackageDetailScreen), findsOneWidget);
      Future<void> reveal(Finder finder) async {
        await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
        await tester.pumpAndSettle();
      }

      await tester.scrollUntilVisible(
        find.byType(CheckboxListTile),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await reveal(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byTooltip('Increase Extra Hours'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Decrease Extra Hours',
              ),
            )
            .onPressed,
        isNull,
      );
      await reveal(find.byTooltip('Increase Extra Hours'));
      await tester.tap(find.byTooltip('Increase Extra Hours'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Calculate Price'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await reveal(find.text('Calculate Price'));
      await tester.tap(find.text('Calculate Price'));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Calculating…'),
            )
            .onPressed,
        isNull,
      );
      expect(postCount, 1);
      pending.complete(ok(summaryJson()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('LKR 173,000.00'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Price Summary'), findsOneWidget);
      expect(find.text('LKR 173,000.00'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byTooltip('Increase Extra Hours'),
        -200,
        scrollable: find.byType(Scrollable).last,
      );
      await reveal(find.byTooltip('Increase Extra Hours'));
      await tester.tap(find.byTooltip('Increase Extra Hours'));
      await tester.pump();
      expect(find.text('Price Summary'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
