import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grainguard/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

const host = String.fromEnvironment(
  'GG_EMULATOR_HOST',
  defaultValue: '10.0.2.2',
);
const localPassword = 'GrainGuardLocal2026';

Future<Map<String, dynamic>> send(Uri url, String method, Object body) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, url);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    final output = await response.transform(utf8.decoder).join();
    expect(response.statusCode, 200, reason: output);
    return jsonDecode(output) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 60 && finder.evaluate().isEmpty; attempt++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(finder, findsOneWidget);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'assigned viewer goes from waiting to live after an authenticated publish',
    (tester) async {
      app.main();
      await waitFor(tester, find.text('Sign in'));
      final inputs = find.byType(TextField);
      await tester.enterText(inputs.at(0), 'viewer@example.test');
      await tester.enterText(inputs.at(1), localPassword);
      await tester.ensureVisible(find.text('Sign in'));
      await tester.tap(find.text('Sign in'));
      await waitFor(tester, find.text('Choose your grain'));
      await tester.tap(find.text('Wheat'));
      await waitFor(tester, find.text('Waiting for first reading'));

      final credentials = await send(
        Uri.http(
          '$host:9099',
          '/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword',
          {'key': 'fake-api-key'},
        ),
        'POST',
        {
          'email': 'publisher@example.test',
          'password': localPassword,
          'returnSecureToken': true,
        },
      );
      final time = DateTime.now().millisecondsSinceEpoch;
      final id = 'integration-$time';
      final sample = {
        'schemaVersion': 1,
        'deviceId': 'GG001',
        'lotId': 'WHEAT-001',
        'sampleId': id,
        'measuredAtMs': time,
        'receivedAtMs': {'.sv': 'timestamp'},
        'battery': {'percent': 67, 'chargeState': 'charging'},
        'sensors': {'co2Ppm': 800},
      };
      await send(
        Uri.http('$host:9000', '/.json', {
          'ns': 'demo-grainguard-default-rtdb',
          'auth': credentials['idToken'] as String,
        }),
        'PATCH',
        {
          'devices/GG001/latest': sample,
          'devices/GG001/lots/WHEAT-001/samples/$id': sample,
        },
      );
      await waitFor(tester, find.text('Live readings'));
      expect(find.text('67%'), findsOneWidget);
      expect(find.text('Charging'), findsOneWidget);
    },
  );
}
