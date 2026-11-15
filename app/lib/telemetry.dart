enum Channel {
  temperature('temperatureC', 'Temperature', '°C'),
  humidity('relativeHumidityPct', 'Relative humidity', '%'),
  carbon('co2Ppm', 'Carbon dioxide', 'ppm'),
  gas('gasResistanceOhm', 'Gas resistance', 'kΩ'),
  acoustic('acousticEvents', 'Acoustic activity', 'events'),
  battery('percent', 'Device battery', '%');

  const Channel(this.field, this.label, this.unit);
  final String field;
  final String label;
  final String unit;
}

Map<Object?, Object?> fields(Object? data) =>
    data is Map ? Map<Object?, Object?>.from(data) : const {};

double? number(Object? raw, num minimum, num maximum) =>
    raw is num && raw.isFinite && raw >= minimum && raw <= maximum
    ? raw.toDouble()
    : null;

DateTime? timestamp(Object? raw) =>
    raw is int && raw > 0 && raw <= 8640000000000000
    ? DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true)
    : null;

class Bin {
  const Bin(
    this.id,
    this.label,
    this.lot, {
    this.cadence = const Duration(minutes: 10),
    this.offlineTimeout,
    this.firmware,
  });
  final String id;
  final String label;
  final String lot;
  final Duration cadence;
  final Duration? offlineTimeout;
  Duration get staleAfter => offlineTimeout ?? cadence * 3;
  final String? firmware;
}

class Reading {
  const Reading({
    required this.id,
    required this.device,
    required this.lot,
    required this.measured,
    required this.received,
    required this.values,
    this.voltage,
    this.chargeState,
    this.acousticWindow,
    this.invalid = const {},
  });

  final String id;
  final String device;
  final String lot;
  final DateTime measured;
  final DateTime received;
  final Map<Channel, double> values;
  final Set<Channel> invalid;
  final double? voltage;
  final String? chargeState;
  final int? acousticWindow;

  static Reading? decode(Object? raw, Bin bin, {String? sampleKey}) {
    final data = fields(raw);
    final id = data['sampleId'];
    final measured = timestamp(data['measuredAtMs']);
    final received = timestamp(data['receivedAtMs']);
    if (data['schemaVersion'] != 1 ||
        data['deviceId'] != bin.id ||
        data['lotId'] != bin.lot ||
        id is! String ||
        id.isEmpty ||
        (sampleKey != null && id != sampleKey) ||
        measured == null ||
        received == null) {
      return null;
    }
    final sensors = fields(data['sensors']);
    final battery = fields(data['battery']);
    final values = <Channel, double>{};
    final invalid = <Channel>{};
    final window = number(sensors['acousticWindowSec'], 1, 86400);
    final validWindow = window != null && window == window.roundToDouble();
    for (final channel in Channel.values) {
      final source = channel == Channel.battery ? battery : sensors;
      final rawValue = source[channel.field];
      if (rawValue == null) continue;
      final value = switch (channel) {
        Channel.temperature => number(rawValue, -60, 100),
        Channel.humidity || Channel.battery => number(rawValue, 0, 100),
        Channel.carbon => number(rawValue, 0, 100000),
        Channel.gas => number(rawValue, 0, 1000000000),
        Channel.acoustic =>
          validWindow && rawValue is int ? number(rawValue, 0, 1000000) : null,
      };
      if (value == null) {
        invalid.add(channel);
      } else {
        values[channel] = channel == Channel.gas ? value / 1000 : value;
      }
    }
    final charge = battery['chargeState'];
    final millivolts = number(battery['voltageMv'], 1, 60000);
    return Reading(
      id: id,
      device: bin.id,
      lot: bin.lot,
      measured: measured,
      received: received,
      values: Map.unmodifiable(values),
      invalid: Set.unmodifiable(invalid),
      voltage: millivolts == null ? null : millivolts / 1000,
      chargeState:
          const ['charging', 'discharging', 'full', 'unknown'].contains(charge)
          ? charge as String
          : null,
      acousticWindow: validWindow ? window.toInt() : null,
    );
  }
}

enum FeedStatus {
  connecting('Connecting'),
  waiting('Waiting for first reading'),
  live('Live readings'),
  stale('System offline · No new data'),
  disconnected('Connection lost'),
  clock('Device clock needs checking'),
  invalid('Reading could not be verified'),
  denied('Bin access unavailable');

  const FeedStatus(this.label);
  final String label;
}

FeedStatus feedStatus(Bin bin, Reading? latest, DateTime now, bool? connected) {
  if (connected == null) return FeedStatus.connecting;
  if (!connected) return FeedStatus.disconnected;
  if (latest == null) return FeedStatus.waiting;
  if (latest.measured.difference(now) > const Duration(minutes: 2)) {
    return FeedStatus.clock;
  }
  if (now.difference(latest.measured) >= bin.staleAfter) {
    return FeedStatus.stale;
  }
  return FeedStatus.live;
}

enum Scenario {
  stable('Stable storage'),
  rising('Rising risk'),
  lowBattery('Low battery'),
  interrupted('Interrupted feed');

  const Scenario(this.label);
  final String label;
}

class DemoHistory {
  DemoHistory(this.scenario, this.anchor, {this.bin = wheatBin});
  final Scenario scenario;
  final DateTime anchor;
  final Bin bin;
  static const wheatBin = Bin(
    'GG-DEMO',
    'East Silo',
    'WHEAT-DEMO',
    firmware: 'Demo node',
  );
  static const riceBin = Bin(
    'GG-DEMO-RICE',
    'East Silo',
    'RICE-DEMO',
    firmware: 'Demo node',
  );

  Reading sample(int intervalsAgo) {
    final time = anchor.subtract(bin.cadence * intervalsAgo);
    final ramp = (1 - intervalsAgo / 144).clamp(0.0, 1.0);
    final swing = (intervalsAgo % 17) / 17;
    final rising = scenario == Scenario.rising;
    return Reading(
      id: 'demo-${time.millisecondsSinceEpoch}',
      device: bin.id,
      lot: bin.lot,
      measured: time,
      received: time.add(const Duration(seconds: 2)),
      values: {
        Channel.temperature: 22.4 + swing + (rising ? ramp * 9 : 0),
        Channel.humidity: 57 + swing * 2 + (rising ? ramp * 23 : 0),
        Channel.carbon: 480 + swing * 40 + (rising ? ramp * 1500 : 0),
        Channel.gas: 43 + swing * 8,
        Channel.acoustic:
            (intervalsAgo % 4 + (rising ? (ramp * 11).round() : 0)).toDouble(),
        Channel.battery: scenario == Scenario.lowBattery
            ? 12 + (intervalsAgo / 12).clamp(0, 68).toDouble()
            : 78,
      },
      voltage: scenario == Scenario.lowBattery ? 3.52 : 3.94,
      chargeState: 'discharging',
      acousticWindow: 600,
    );
  }

  int get offset => scenario == Scenario.interrupted ? 7 : 0;
  Reading get latest => sample(offset);
  List<Reading> history(DateTime from, DateTime to) => [
    for (var i = 4319; i >= offset; i--)
      if (!anchor.subtract(bin.cadence * i).isBefore(from) &&
          !anchor.subtract(bin.cadence * i).isAfter(to))
        sample(i),
  ];
}
