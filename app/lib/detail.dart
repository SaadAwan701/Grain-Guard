import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import 'dashboard.dart';
import 'reports.dart';
import 'source.dart';
import 'telemetry.dart';
import 'visuals.dart';

export 'reports.dart' show showReports;

class HistoryChart extends StatelessWidget {
  const HistoryChart({
    super.key,
    required this.readings,
    required this.channel,
    required this.cadence,
    this.compact = false,
  });
  final List<Reading> readings;
  final Channel channel;
  final Duration cadence;
  final bool compact;

  List<FlSpot> points() {
    final origin = readings.first.measured;
    final groups = <List<FlSpot>>[];
    var group = <FlSpot>[];
    DateTime? previous;
    for (final reading in readings) {
      final value = reading.values[channel];
      final gap =
          previous != null &&
          reading.measured.difference(previous) > cadence * 2;
      if (value == null || gap) {
        if (group.isNotEmpty) groups.add(group);
        group = [];
      }
      if (value != null) {
        group.add(
          FlSpot(reading.measured.difference(origin).inSeconds / 3600, value),
        );
      }
      previous = reading.measured;
    }
    if (group.isNotEmpty) groups.add(group);
    final stride = math.max(1, (readings.length / 140).ceil());
    final output = <FlSpot>[];
    for (final segment in groups) {
      if (output.isNotEmpty) output.add(FlSpot.nullSpot);
      for (var i = 0; i < segment.length; i += stride) {
        final bucket = segment.sublist(i, math.min(i + stride, segment.length));
        final low = bucket.reduce((a, b) => a.y < b.y ? a : b);
        final high = bucket.reduce((a, b) => a.y >= b.y ? a : b);
        final retained = {bucket.first, low, high, bucket.last}.toList()
          ..sort((a, b) => a.x.compareTo(b.x));
        output.addAll(retained);
      }
    }
    return output;
  }

  @override
  Widget build(BuildContext context) {
    final color = channelColor(channel);
    final spots = readings.isEmpty ? <FlSpot>[] : points();
    if (spots.isEmpty) return const Text('No readings in this range.');
    final values = spots.where((spot) => !spot.isNull()).map((spot) => spot.y);
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    final padding = math.max((high - low) * .12, high.abs() * .01 + .05);
    return ExcludeSemantics(
      child: SizedBox(
        height: compact ? 105 : 205,
        child: LineChart(
          LineChartData(
            minY: low - padding,
            maxY: high + padding,
            minX: 0,
            maxX: math.max(
              1 / 60,
              readings.last.measured
                      .difference(readings.first.measured)
                      .inSeconds /
                  3600,
            ),
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: (high - low + padding * 2) / 4,
              getDrawingHorizontalLine: (_) => const FlLine(
                color: Color(0xff36435b),
                strokeWidth: 1,
                dashArray: [4, 5],
              ),
            ),
            titlesData: const FlTitlesData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                color: color,
                barWidth: 2.4,
                dotData: FlDotData(show: values.length <= 2),
                belowBarData: BarAreaData(
                  show: true,
                  color: color.withValues(alpha: .10),
                ),
              ),
            ],
          ),
          duration: Duration.zero,
        ),
      ),
    );
  }
}

class Trends extends StatefulWidget {
  const Trends({
    super.key,
    required this.feed,
    required this.bin,
    required this.initial,
  });
  final Feed feed;
  final Bin bin;
  final Channel initial;
  @override
  State<Trends> createState() => _TrendsState();
}

class _TrendsState extends State<Trends> {
  late Channel metric = widget.initial;
  int days = 1;
  DateTimeRange? custom;
  late DateTime to;
  late DateTime from;
  late Future<List<Reading>> data;

  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    to = custom == null
        ? DateTime.now().toUtc()
        : custom!.end.add(const Duration(days: 1)).toUtc();
    from = custom?.start.toUtc() ?? to.subtract(Duration(days: days));
    data = widget.feed.history(from, to);
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Text('Trends', style: display(43)),
      const SizedBox(height: 8),
      Text(
        '${widget.bin.label} · ${widget.bin.lot}',
        style: const TextStyle(color: muted),
      ),
      const SizedBox(height: 17),
      DropdownButtonFormField<Channel>(
        initialValue: metric,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Sensor'),
        items: [
          for (final channel in Channel.values)
            DropdownMenuItem(value: channel, child: Text(channel.label)),
        ],
        onChanged: (value) {
          if (value != null) setState(() => metric = value);
        },
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: [
          for (final range in [1, 7, 30])
            ChoiceChip(
              label: Text(range == 1 ? '24 hours' : '$range days'),
              selected: custom == null && range == days,
              onSelected: (_) => setState(() {
                days = range;
                custom = null;
                load();
              }),
            ),
          ActionChip(
            label: const Text('Custom'),
            onPressed: () async {
              final selected = await selectReportRange(context);
              if (mounted && selected != null) {
                setState(() {
                  custom = selected;
                  load();
                });
              }
            },
          ),
        ],
      ),
      const SizedBox(height: 16),
      FutureBuilder<List<Reading>>(
        future: data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Tile(child: Text('Loading history…'));
          }
          if (snapshot.hasError) {
            return Tile(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'History unavailable. Check your connection or bin access.',
                  ),
                  TextButton(
                    onPressed: () => setState(load),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          final history = snapshot.data ?? const [];
          final valid = history
              .where((r) => r.values.containsKey(metric))
              .toList();
          if (valid.isEmpty) {
            return const Tile(child: Text('No measurements in this range.'));
          }
          final latest = valid.last;
          final expected = math.max(
            1,
            (to.difference(from).inSeconds / widget.bin.cadence.inSeconds)
                .floor(),
          );
          final rate = metric == Channel.carbon
              ? carbonRate(valid, widget.bin.cadence)
              : null;
          return Tile(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${valueLabel(metric, latest.values[metric])} ${metric.unit}',
                  style: display(35, color: channelColor(metric)),
                ),
                const SizedBox(height: 6),
                Text(
                  'Latest in range · ${timeLabel(latest.measured)}',
                  style: const TextStyle(color: muted),
                ),
                if (metric == Channel.acoustic)
                  Text('Latest observation window: ${latest.acousticWindow} s'),
                if (rate != null)
                  Text('Recent change: ${rate.toStringAsFixed(1)} ppm/hour'),
                const SizedBox(height: 16),
                HistoryChart(
                  readings: history,
                  channel: metric,
                  cadence: widget.bin.cadence,
                ),
                const SizedBox(height: 12),
                Text(
                  '${timeLabel(from)} to ${timeLabel(to)}',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 8),
                Text(
                  '${valid.length} readings · ~$expected expected',
                  style: TextStyle(
                    color: valid.length < expected * .9 ? wheat : muted,
                  ),
                ),
                if (history.length >= 4321)
                  const Text('Range capped at the latest 4,321 readings.'),
                if (valid.length < expected * .9)
                  const Text('Coverage is incomplete.'),
              ],
            ),
          );
        },
      ),
    ],
  );
}

double? carbonRate(List<Reading> valid, Duration cadence) {
  if (valid.length < 2) return null;
  final last = valid.last;
  final before = valid[valid.length - 2];
  final minutes = last.measured.difference(before.measured).inSeconds / 60;
  if (minutes <= 0 || minutes > cadence.inSeconds / 30) return null;
  return (last.values[Channel.carbon]! - before.values[Channel.carbon]!) *
      60 /
      minutes;
}

Future<void> showDevice(
  BuildContext context,
  Bin bin,
  FeedStatus status,
  Reading? latest,
  Reading? battery,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Device details', style: display(32)),
          const SizedBox(height: 12),
          Text('${bin.label} · ${bin.id}'),
          Text('${bin.lot} · ${status.label}'),
          const Divider(height: 26),
          Text('Expected cadence: ${bin.cadence.inSeconds} s'),
          Text('Firmware: ${bin.firmware ?? 'Unavailable'}'),
          Text(
            'Last measured: ${latest == null ? 'Unavailable' : timeLabel(latest.measured)}',
          ),
          Text(
            'Last received: ${latest == null ? 'Unavailable' : timeLabel(latest.received)}',
          ),
          const Divider(height: 26),
          Text(
            'Battery percentage: ${battery?.values[Channel.battery]?.round() ?? 'Unavailable'}${battery?.values[Channel.battery] != null ? '%' : ''}',
          ),
          Text(
            'Battery voltage: ${battery?.voltage == null ? 'Unavailable' : '${battery!.voltage!.toStringAsFixed(2)} V'}',
          ),
          Text('Charge state: ${battery?.chargeState ?? 'Unavailable'}'),
          Text(
            'Battery measured: ${battery == null ? 'Unavailable' : timeLabel(battery.measured)}',
          ),
          const Divider(height: 26),
          for (final channel in Channel.values.where(
            (channel) => channel != Channel.battery,
          ))
            Text(
              '${channel.label}: ${latest?.invalid.contains(channel) == true
                  ? 'Invalid'
                  : latest?.values.containsKey(channel) == true
                  ? 'Reported'
                  : 'Unavailable'}',
            ),
        ],
      ),
    ),
  ),
);
