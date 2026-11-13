import 'package:flutter_test/flutter_test.dart';
import 'package:grainguard/assessment.dart';
import 'package:grainguard/reports.dart';
import 'package:grainguard/telemetry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bin = Bin('GG001', 'East Silo', 'WHEAT-001');
  final now = DateTime.utc(2026, 11, 11, 12);
  Map<String, Object> payload({
    int version = 1,
    String lot = 'WHEAT-001',
    DateTime? measured,
    Map<String, Object> sensors = const {'co2Ppm': 0},
    Map<String, Object>? battery,
  }) => {
    'schemaVersion': version,
    'deviceId': bin.id,
    'lotId': lot,
    'sampleId': 'fixture',
    'measuredAtMs': (measured ?? now).millisecondsSinceEpoch,
    'receivedAtMs': now.millisecondsSinceEpoch,
    'sensors': sensors,
    'battery': ?battery,
  };

  test('battery bounds, zero, charging and voltage-only measurements', () {
    for (final value in [0, 10, 11, 20, 21, 100]) {
      final reading = Reading.decode(
        payload(battery: {'percent': value, 'chargeState': 'charging'}),
        bin,
      )!;
      expect(reading.values[Channel.battery], value);
      expect(reading.chargeState, 'charging');
    }
    final bad = Reading.decode(
      payload(battery: {'percent': 101, 'voltageMv': 3820}),
      bin,
    )!;
    expect(bad.values[Channel.battery], isNull);
    expect(bad.invalid, contains(Channel.battery));
    expect(bad.voltage, 3.82);
    expect(
      Reading.decode(
        payload(battery: {'voltageMv': 3820}),
        bin,
      )!.values[Channel.battery],
      isNull,
    );
    expect(Reading.decode(payload(), bin)!.values[Channel.carbon], 0);
  });

  test(
    'unsupported schema, wrong lot and unstable history identity are rejected',
    () {
      expect(Reading.decode(payload(version: 2), bin), isNull);
      expect(Reading.decode(payload(lot: 'OLD'), bin), isNull);
      expect(Reading.decode(payload(), bin, sampleKey: 'other'), isNull);
      final invalid = Reading.decode(
        payload(sensors: {'acousticEvents': 8, 'acousticWindowSec': 0}),
        bin,
      )!;
      expect(invalid.invalid, contains(Channel.acoustic));
    },
  );

  test('freshness uses measurement time, waits for first sample and detects clock drift', () {
    expect(feedStatus(bin, null, now, true), FeedStatus.waiting);
    final delayed = Reading.decode(
      payload(measured: now.subtract(const Duration(minutes: 30))),
      bin,
    )!;
    expect(feedStatus(bin, delayed, now, true), FeedStatus.stale);
    expect(feedStatus(bin, delayed, now, false), FeedStatus.disconnected);
    final future = Reading.decode(
      payload(measured: now.add(const Duration(minutes: 3))),
      bin,
    )!;
    expect(feedStatus(bin, future, now, true), FeedStatus.clock);
  });

  test('illustrative risk requires a sustained window and remains unavailable in live mode', () {
    final fixture = DemoHistory(Scenario.rising, now);
    final history = [fixture.sample(2), fixture.sample(1), fixture.sample(0)];
    expect(assess(history, now, bin.cadence, demo: true).level, Risk.high);
    expect(
      assess(history, now, bin.cadence, demo: false).level,
      Risk.insufficient,
    );
    expect(
      assess(history.take(2).toList(), now, bin.cadence, demo: true).level,
      Risk.insufficient,
    );
  });

  test(
    'report carries mode, coverage, units and spreadsheet-safe identifiers',
    () {
      const unsafe = Bin('GG001', '=FORMULA()', 'WHEAT-001');
      final reading = Reading.decode(payload(), bin)!;
      final report = Report(
        unsafe,
        true,
        now.subtract(const Duration(days: 1)),
        now,
        now,
        [reading],
      );
      final csv = report.spreadsheet();
      expect(csv, contains('DEMO - SIMULATED DATA'));
      expect(csv, contains("'=FORMULA()"));
      expect(csv, contains('Carbon dioxide (ppm)'));
      expect(csv, contains('approximately 144 expected'));
    },
  );

  test('report generates a PDF with the bundled font', () async {
    final reading = Reading.decode(payload(), bin)!;
    final report = Report(
      bin,
      true,
      now.subtract(const Duration(days: 1)),
      now,
      now,
      [reading],
    );
    final document = await report.document();
    expect(document.length, greaterThan(1000));
    expect(String.fromCharCodes(document.take(5)), '%PDF-');
  });
}
