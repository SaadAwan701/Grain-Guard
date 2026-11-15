import 'telemetry.dart';

enum Risk {
  insufficient('Insufficient data'),
  normal('Normal'),
  watch('Watch'),
  high('High'),
  critical('Critical');

  const Risk(this.label);
  final String label;
}

const demoRuleVersion = 'demo-v1';

List<Risk> dailyDemoRisk(
  List<Reading> history,
  DateTime now,
  Duration cadence,
) {
  final levels = List.filled(7, Risk.insufficient);
  final window = <Reading>[];
  for (final reading in history) {
    if (reading.measured.isAfter(now)) break;
    window.add(reading);
    if (window.length > 3) window.removeAt(0);
    final day = 6 - now.difference(reading.measured).inDays;
    if (day < 0) continue;
    final level = assess(window, reading.measured, cadence, demo: true).level;
    if (level.index > levels[day].index) levels[day] = level;
  }
  return levels;
}

({Risk level, String evidence}) assess(
  List<Reading> history,
  DateTime now,
  Duration cadence, {
  required bool demo,
}) {
  if (!demo) {
    return (
      level: Risk.insufficient,
      evidence: 'Live risk thresholds are awaiting project validation.',
    );
  }
  final recent = history
      .where(
        (r) =>
            !r.measured.isAfter(now) &&
            now.difference(r.measured) <= cadence * 3,
      )
      .toList();
  final window = recent.length < 3 ? recent : recent.sublist(recent.length - 3);
  if (window.length < 3 ||
      window.any(
        (r) =>
            r.values[Channel.carbon] == null ||
            r.values[Channel.humidity] == null,
      )) {
    return (
      level: Risk.insufficient,
      evidence: 'Three recent CO₂ and humidity readings are needed.',
    );
  }
  bool sustained(double ppm, double humidity) => window.every(
    (r) =>
        r.values[Channel.carbon]! >= ppm &&
        r.values[Channel.humidity]! >= humidity,
  );
  final level = sustained(2400, 82)
      ? Risk.critical
      : sustained(1600, 75)
      ? Risk.high
      : sustained(950, 68)
      ? Risk.watch
      : Risk.normal;
  final last = window.last.values;
  return (
    level: level,
    evidence:
        'Three readings over ${window.last.measured.difference(window.first.measured).inMinutes} min. '
        'Latest CO₂ ${last[Channel.carbon]!.round()} ppm and relative humidity ${last[Channel.humidity]!.round()}%.',
  );
}

class AlertEpisode {
  const AlertEpisode(
    this.id,
    this.title,
    this.evidence,
    this.action,
    this.time,
    this.channel, {
    this.critical = false,
  });
  final String id;
  final String title;
  final String evidence;
  final String action;
  final DateTime time;
  final Channel channel;
  final bool critical;
}

List<AlertEpisode> episodes(
  List<Reading> history,
  Bin bin,
  FeedStatus status, {
  required bool demo,
}) {
  final result = <AlertEpisode>[];
  int? batteryIndex;
  Reading? lowCandidate;
  int? riskIndex;
  final faultStarts = <Channel, Reading>{};
  final faultActive = <Channel>{};
  Reading? previous;
  final recent = <Reading>[];
  for (final reading in history) {
    final contiguous =
        previous != null &&
        reading.measured.difference(previous.measured) <= bin.cadence * 2;
    if (!contiguous) {
      recent.clear();
      lowCandidate = null;
      batteryIndex = null;
      riskIndex = null;
      faultStarts.clear();
      faultActive.clear();
    }
    previous = reading;
    final power = reading.values[Channel.battery];
    if (power != null && power >= 24) batteryIndex = null;
    if (power != null && power <= 20 && lowCandidate != null) {
      final existing = batteryIndex == null ? null : result[batteryIndex];
      final critical = power <= 10;
      final first = lowCandidate;
      if (existing == null || (critical && !existing.critical)) {
        final event = AlertEpisode(
          existing?.id ??
              'battery_${bin.lot}_${first.measured.millisecondsSinceEpoch}',
          critical ? 'Critical device battery' : 'Low device battery',
          'Device battery reported ${power.round()}% across consecutive low observations.',
          'Plan a recharge and verify the node remains connected.',
          existing?.time ?? first.measured,
          Channel.battery,
          critical: critical,
        );
        if (batteryIndex == null) {
          batteryIndex = result.length;
          result.add(event);
        } else {
          result[batteryIndex] = event;
        }
      }
    }
    lowCandidate = power != null && power <= 20
        ? lowCandidate ?? reading
        : null;
    for (final channel in Channel.values.where((c) => c != Channel.battery)) {
      if (reading.invalid.contains(channel)) {
        final start = faultStarts[channel];
        if (start != null && faultActive.add(channel)) {
          result.add(
            AlertEpisode(
              'fault_${channel.name}_${bin.lot}_${start.measured.millisecondsSinceEpoch}',
              '${channel.label} readings invalid',
              'Two consecutive measurements could not be decoded.',
              'Check sensor calibration and the node payload.',
              start.measured,
              channel,
            ),
          );
        }
        faultStarts[channel] ??= reading;
      } else {
        faultStarts.remove(channel);
        if (reading.values.containsKey(channel)) faultActive.remove(channel);
      }
    }
    recent.add(reading);
    if (recent.length > 3) recent.removeAt(0);
    if (!demo) continue;
    final risk = assess(recent, reading.measured, bin.cadence, demo: true);
    if (risk.level == Risk.normal) riskIndex = null;
    if (risk.level.index >= Risk.watch.index) {
      final existing = riskIndex == null ? null : result[riskIndex];
      final critical = risk.level.index >= Risk.high.index;
      if (existing == null || (critical && !existing.critical)) {
        final event = AlertEpisode(
          existing?.id ??
              'risk_${bin.lot}_${reading.measured.millisecondsSinceEpoch}',
          '${risk.level.label} storage risk',
          risk.evidence,
          'Inspect the bin and review aeration with the operator.',
          existing?.time ?? reading.measured,
          Channel.carbon,
          critical: critical,
        );
        if (riskIndex == null) {
          riskIndex = result.length;
          result.add(event);
        } else {
          result[riskIndex] = event;
        }
      }
    }
  }
  if (history.isNotEmpty &&
      (status == FeedStatus.stale || status == FeedStatus.disconnected)) {
    final time = history.last.measured.add(bin.staleAfter);
    result.add(
      AlertEpisode(
        'stale_${bin.lot}_${history.last.measured.millisecondsSinceEpoch}',
        status.label,
        'New telemetry is currently unavailable.',
        'Check node power and network connectivity.',
        time,
        Channel.carbon,
      ),
    );
  }
  return result.reversed.toList();
}
