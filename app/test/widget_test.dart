import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grainguard/main.dart';
import 'package:grainguard/source.dart';

void main() {
  testWidgets(
    'offline demo places battery above the kernel and exposes scenarios',
    (tester) async {
      tester.view.physicalSize = const Size(420, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [cloudProvider.overrideWith((_) async => null)],
          child: const GrainGuard(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open demo mode'));
      await tester.pumpAndSettle();
      expect(find.text('DEMO'), findsOneWidget);
      expect(find.text('78%'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('78%')).dy,
        lessThan(tester.getTopLeft(find.text('Wheat kernel')).dy),
      );
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Low battery'));
      await tester.tap(find.text('Low battery'));
      await tester.pumpAndSettle();
      expect(find.text('12%'), findsOneWidget);
      await tester.tap(find.text('Alerts'));
      await tester.pumpAndSettle();
      expect(find.text('Low device battery'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('overview fits a narrow phone at enlarged text', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [cloudProvider.overrideWith((_) async => null)],
        child: const GrainGuard(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Open demo mode'));
    await tester.tap(find.text('Open demo mode'));
    await tester.pumpAndSettle();
    expect(find.text('Device battery'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
