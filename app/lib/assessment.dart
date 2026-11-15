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
const liveRuleVersion = 'screening-v1';
const inspectCo2Ppm = 600;
const urgentCo2Ppm = 1500;
const inspectHumidityPct = 65;

typedef RiskAssessment = ({Risk level, String evidence});

RiskAssessment assessLive(List<Reading> window, Bin bin, DateTime now) {
  if (window.isEmpty ||
      now.difference(window.last.measured) >= bin.staleAfter ||
      window.last.measured.difference(now) > const Duration(minutes: 2)) {
    return (
      level: Risk.insufficient,
      evidence: 'Waiting for fresh sensor readings.',
    );
  }
  final latest = window.last;
  final co2 = latest.values[Channel.carbon];
  final humidity = latest.values[Channel.humidity];
  if (co2 != null && co2 >= urgentCo2Ppm) {
    return (
      level: Risk.critical,
      evidence:
          'CO₂ at ${co2.round()} ppm reached the urgent inspection threshold.',
    );
  }
  final co2High = sustainedLive(window, bin, Channel.carbon, inspectCo2Ppm);
  final humid = sustainedLive(
    window,
    bin,
    Channel.humidity,
    inspectHumidityPct,
    strictlyAbove: true,
  );
  if (co2High || humid) {
    final signals = [
      if (co2High) 'CO₂ at or above $inspectCo2Ppm ppm',
      if (humid) 'relative humidity above $inspectHumidityPct%',
    ].join(' and ');
    return (
      level: co2High && humid ? Risk.high : Risk.watch,
      evidence: '$signals in three consecutive readings.',
    );
  }
  final pending =
      (co2 != null && co2 >= inspectCo2Ppm) ||
      (humidity != null && humidity > inspectHumidityPct);
  if (pending || (co2 == null && humidity == null)) {
    return (
      level: Risk.insufficient,
      evidence: pending
          ? 'Checking whether the elevated reading persists.'
          : 'CO₂ and relative humidity are unavailable.',
    );
  }
  return (
    level: Risk.normal,
    evidence: co2 == null || humidity == null
        ? 'Available screening readings are below their thresholds. One screening signal is missing.'
        : 'CO₂ and relative humidity are below their inspection thresholds.',
  );
}

bool sustainedLive(
  List<Reading> window,
  Bin bin,
  Channel channel,
  int threshold, {
  bool strictlyAbove = false,
}) {
  if (window.length < 3) return false;
  final samples = window.skip(window.length - 3).toList();
  for (var index = 0; index < samples.length; index++) {
    final reading = samples[index];
    final value = reading.values[channel];
    if (value == null ||
        (strictlyAbove ? value <= threshold : value < threshold)) {
      return false;
    }
    if (index == 0) continue;
    final interval = reading.measured.difference(samples[index - 1].measured);
    if (interval <= Duration.zero ||
        interval >= bin.staleAfter ||
        interval > bin.cadence * 2) {
      return false;
    }
  }
  return true;
}

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
    final level = assessDemo(window, reading.measured, cadence).level;
    if (level.index > levels[day].index) levels[day] = level;
  }
  return levels;
}

RiskAssessment assessDemo(
  List<Reading> history,
  DateTime now,
  Duration cadence,
) {
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
  final liveStarts = <Channel, DateTime>{};
  final liveSeverity = <Channel, bool>{};
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
      liveStarts.clear();
      liveSeverity.clear();
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
    if (!demo) {
      for (final channel in [Channel.carbon, Channel.humidity]) {
        final value = reading.values[channel];
        if (value == null) continue;
        final isCarbon = channel == Channel.carbon;
        final threshold = isCarbon ? inspectCo2Ppm : inspectHumidityPct;
        // Rearm after three readings in the recovery band.
        final recovery = isCarbon ? 550 : 63;
        if (recent.length == 3 &&
            recent.every(
              (item) => (item.values[channel] ?? double.infinity) <= recovery,
            )) {
          liveStarts.remove(channel);
          liveSeverity.remove(channel);
        }
        final urgent = isCarbon && value >= urgentCo2Ppm;
        if (!urgent &&
            !sustainedLive(
              recent,
              bin,
              channel,
              threshold,
              strictlyAbove: !isCarbon,
            )) {
          continue;
        }
        final previousSeverity = liveSeverity[channel];
        if (previousSeverity != null && (previousSeverity || !urgent)) continue;
        final start = liveStarts.putIfAbsent(channel, () => reading.measured);
        liveSeverity[channel] = urgent;
        result.add(
          AlertEpisode(
            'quality_${channel.name}_${bin.lot}_${start.millisecondsSinceEpoch}_${urgent ? 'urgent' : 'inspect'}',
            urgent
                ? 'Urgent CO₂ inspection'
                : isCarbon
                ? 'Inspect elevated CO₂'
                : 'Inspect elevated humidity',
            '${channel.label} at ${value.round()} ${channel.unit} · ${urgent ? 'urgent threshold of $urgentCo2Ppm ppm' : 'three consecutive elevated readings'}',
            urgent ? 'Contact the storage operator for immediate inspection.' : 'Check the sensor and inspect the lot for moisture or heating.',
            reading.measured,
            channel,
            critical: urgent,
          ),
        );
      }
      continue;
    }
    final risk = assessDemo(recent, reading.measured, bin.cadence);
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
