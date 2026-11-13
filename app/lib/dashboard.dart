import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'assessment.dart';
import 'detail.dart';
import 'source.dart';
import 'telemetry.dart';
import 'visuals.dart';

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: wheat,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.grass_rounded, color: ink, size: 24),
      ),
      const SizedBox(width: 9),
      Flexible(child: Text('GrainGuard', style: display(23))),
    ],
  );
}

String timeLabel(DateTime time) =>
    DateFormat('MMM d, HH:mm').format(time.toLocal());

String ageLabel(DateTime time, DateTime now) {
  final age = now.difference(time);
  if (age.isNegative || age.inMinutes == 0) return 'just now';
  if (age.inHours == 0) return '${age.inMinutes} min ago';
  if (age.inDays == 0) return '${age.inHours} hr ago';
  return '${age.inDays} d ago';
}

Color channelColor(Channel channel) => switch (channel) {
  Channel.temperature => coral,
  Channel.humidity => sky,
  Channel.carbon => lime,
  Channel.gas => lilac,
  Channel.acoustic => wheat,
  Channel.battery => lime,
};

IconData channelIcon(Channel channel) => switch (channel) {
  Channel.temperature => Icons.thermostat_rounded,
  Channel.humidity => Icons.water_drop_outlined,
  Channel.carbon => Icons.air_rounded,
  Channel.gas => Icons.sensors_rounded,
  Channel.acoustic => Icons.graphic_eq_rounded,
  Channel.battery => Icons.battery_std_rounded,
};

String valueLabel(Channel channel, double? value) {
  if (value == null) return '—';
  return NumberFormat.decimalPatternDigits(
    decimalDigits: channel == Channel.temperature || channel == Channel.gas
        ? 1
        : 0,
  ).format(value);
}

class DemoDashboard extends StatelessWidget {
  const DemoDashboard({super.key, required this.scenario});
  final Scenario scenario;

  @override
  Widget build(BuildContext context) =>
      DemoSession(key: ValueKey(scenario), scenario: scenario);
}

class DemoSession extends StatefulWidget {
  const DemoSession({super.key, required this.scenario});
  final Scenario scenario;
  @override
  State<DemoSession> createState() => _DemoSessionState();
}

class _DemoSessionState extends State<DemoSession> {
  late final feed = DemoFeed(
    DemoHistory(widget.scenario, DateTime.now().toUtc()),
  );

  @override
  Widget build(BuildContext context) =>
      Dashboard(bin: DemoHistory.bin, feed: feed, scenario: widget.scenario);
}

class LiveBin extends StatefulWidget {
  const LiveBin({
    super.key,
    required this.cloud,
    required this.uid,
    required this.id,
    required this.label,
    this.onSelect,
  });
  final Cloud cloud;
  final String uid;
  final String id;
  final String label;
  final VoidCallback? onSelect;

  @override
  State<LiveBin> createState() => _LiveBinState();
}

class _LiveBinState extends State<LiveBin> {
  late var metadata = widget.cloud.bin(widget.id, widget.label);
  CloudFeed? feed;

  @override
  Widget build(BuildContext context) => StreamBuilder<Bin?>(
    stream: metadata,
    builder: (context, snapshot) {
      final bin = snapshot.data;
      if (snapshot.hasError || bin == null) {
        return Scaffold(
          appBar: AppBar(title: const Brand()),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    snapshot.hasError
                        ? 'Bin access unavailable'
                        : snapshot.connectionState == ConnectionState.waiting
                        ? 'Loading bin…'
                        : 'Waiting for bin setup',
                    style: display(29),
                    textAlign: TextAlign.center,
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      metadata = widget.cloud.bin(widget.id, widget.label);
                    }),
                    child: const Text('Retry'),
                  ),
                  if (widget.onSelect != null)
                    TextButton(
                      onPressed: widget.onSelect,
                      child: const Text('Choose another bin'),
                    ),
                  TextButton(
                    onPressed: widget.cloud.auth.signOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      if (feed?.bin.lot != bin.lot) {
        feed = CloudFeed(widget.cloud.database, widget.uid, bin);
      }
      return Dashboard(
        key: ValueKey(bin.lot),
        bin: bin,
        feed: feed!,
        onSelect: widget.onSelect,
        onSignOut: widget.cloud.auth.signOut,
      );
    },
  );
}

class Dashboard extends ConsumerStatefulWidget {
  const Dashboard({
    super.key,
    required this.bin,
    required this.feed,
    this.scenario,
    this.onSelect,
    this.onSignOut,
  });
  final Bin bin;
  final Feed feed;
  final Scenario? scenario;
  final VoidCallback? onSelect;
  final Future<void> Function()? onSignOut;

  @override
  ConsumerState<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends ConsumerState<Dashboard>
    with WidgetsBindingObserver {
  StreamSubscription<bool>? connection;
  StreamSubscription<({Reading? reading, bool malformed})>? samples;
  StreamSubscription<Set<String>>? acknowledgments;
  Timer? clock;
  Reading? latest;
  Reading? lastBattery;
  bool? connected;
  bool malformed = false;
  bool denied = false;
  bool staticModel = false;
  int tab = 0;
  Channel channel = Channel.carbon;
  List<Reading> recent = const [];
  Set<String> acked = {};
  final pending = <String>{};
  final failed = <String>{};
  bool ackError = false;
  bool foreground = true;
  String? lastBanner;
  DateTime now = DateTime.now().toUtc();

  bool get demo => widget.scenario != null;
  Bin get bin => widget.bin;
  FeedStatus get status => denied
      ? FeedStatus.denied
      : malformed && connected == true
      ? FeedStatus.invalid
      : feedStatus(bin, latest, now, connected);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    subscribe();
    clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (foreground) setState(() => now = DateTime.now().toUtc());
    });
    if (demo) loadOverview();
  }

  Future<void> loadOverview() async {
    final end = DateTime.now().toUtc();
    try {
      final history = await widget.feed.history(
        end.subtract(const Duration(days: 7)),
        end,
      );
      if (!mounted) return;
      final readings = {
        for (final reading in [...history, ...recent]) reading.id: reading,
      }.values.toList()..sort((a, b) => a.measured.compareTo(b.measured));
      setState(() {
        recent = readings;
        if (lastBattery == null) {
          for (final reading in readings.reversed) {
            if (reading.values.containsKey(Channel.battery)) {
              lastBattery = reading;
              break;
            }
          }
        }
      });
    } catch (_) {
      // The latest stream still works independently of history.
    }
  }

  void subscribe() {
    connection = widget.feed.connection.listen((value) {
      if (!mounted || !foreground) return;
      final reconnected = value && connected != true;
      setState(() {
        connected = value;
        now = DateTime.now().toUtc();
      });
      if (reconnected && !demo) loadOverview();
    });
    samples = widget.feed.latest.listen(
      (event) {
        if (!mounted || !foreground) return;
        final reading = event.reading;
        setState(() {
          denied = false;
          malformed = event.malformed;
          now = DateTime.now().toUtc();
          if (reading != null) {
            latest = reading;
            if (reading.values.containsKey(Channel.battery) &&
                reading.measured.difference(now) <=
                    const Duration(minutes: 2)) {
              lastBattery = reading;
            }
            recent = [
              ...recent.where(
                (item) =>
                    item.id != reading.id &&
                    now.difference(item.measured) < const Duration(days: 7),
              ),
              reading,
            ]..sort((a, b) => a.measured.compareTo(b.measured));
          }
        });
        if (!demo && status == FeedStatus.live) {
          final events = episodes(recent, bin, status, demo: false);
          if (events.isNotEmpty) {
            final event = events.first;
            if (event.id != lastBanner &&
                now.difference(event.time) <= bin.cadence * 2 &&
                !acked.contains(event.id)) {
              lastBanner = event.id;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(event.title),
                  action: SnackBarAction(
                    label: 'View',
                    onPressed: () => setState(() => tab = 2),
                  ),
                ),
              );
            }
          }
        }
      },
      onError: (Object error) {
        if (!mounted || !foreground) return;
        setState(() {
          latest = null;
          lastBattery = null;
          recent = [];
          denied = true;
        });
      },
    );
    acknowledgments = widget.feed.acknowledgments.listen(
      (value) {
        if (mounted && foreground) {
          setState(() {
            acked = value;
            ackError = false;
          });
        }
      },
      onError: (Object error) {
        if (mounted && foreground) setState(() => ackError = true);
      },
    );
  }

  void stop() {
    connection?.cancel();
    samples?.cancel();
    acknowledgments?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    if (foreground == visible || state == AppLifecycleState.inactive) return;
    foreground = visible;
    if (visible) {
      setState(() {
        now = DateTime.now().toUtc();
        connected = null;
      });
      subscribe();
    } else {
      stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    clock?.cancel();
    stop();
    super.dispose();
  }

  void trends(Channel value) => setState(() {
    channel = value;
    tab = 1;
  });

  Future<void> acknowledge(String id) async {
    setState(() {
      pending.add(id);
      failed.remove(id);
    });
    try {
      await widget.feed.acknowledge(id);
      if (mounted) {
        setState(() {
          acked = {...acked, id};
        });
      }
    } catch (_) {
      if (mounted) setState(() => failed.add(id));
    } finally {
      if (mounted) setState(() => pending.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final assessment = assess(recent, now, bin.cadence, demo: demo);
    final currentBattery = status == FeedStatus.clock ? null : latest;
    final power = currentBattery?.values[Channel.battery];
    final cached =
        (status == FeedStatus.disconnected || status == FeedStatus.stale) &&
        lastBattery != null &&
        !lastBattery!.measured.isAfter(now);
    final shownPower = cached ? lastBattery!.values[Channel.battery] : power;
    final battery = cached ? lastBattery : currentBattery;
    final powerColor = shownPower == null || cached
        ? muted
        : shownPower <= 20
        ? coral
        : lime;
    final screens = [
      () => overview(assessment, battery, cached, shownPower, powerColor),
      () => Trends(
        key: ValueKey(channel),
        feed: widget.feed,
        bin: bin,
        initial: channel,
      ),
      () => alerts(),
      () => settings(),
    ];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: ink,
        surfaceTintColor: Colors.transparent,
        title: const Brand(),
        actions: [
          if (demo)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Chip(
                  label: const Text(
                    'DEMO',
                    style: TextStyle(color: ink, fontWeight: FontWeight.w800),
                  ),
                  backgroundColor: lime,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            )
          else
            IconButton(
              onPressed: () => setState(() => tab = 3),
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: KeyedSubtree(key: ValueKey(tab), child: screens[tab]()),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_rounded),
            label: 'Trends',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none_rounded),
            selectedIcon: Icon(Icons.notifications_rounded),
            label: 'Alerts',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz_rounded),
            label: 'More',
          ),
        ],
      ),
    );
  }

  Widget overview(
    ({Risk level, String evidence}) risk,
    Reading? battery,
    bool cached,
    double? power,
    Color powerColor,
  ) {
    final connectedStatus = demo && widget.scenario != Scenario.interrupted
        ? 'Simulated readings'
        : status.label;
    final powerText = power == null
        ? battery?.voltage == null
              ? 'Battery unavailable'
              : 'Battery percentage unavailable'
        : cached
        ? 'Last reported · ${ageLabel(battery!.measured, now)}'
        : power <= 10
        ? 'Critical battery'
        : power <= 20
        ? 'Low battery'
        : battery?.chargeState == 'charging'
        ? 'Charging'
        : 'Device battery';
    final chart = recent
        .where((r) => r.values[Channel.carbon] != null)
        .toList();
    final weeklyRisk = demo ? dailyDemoRisk(recent, now, bin.cadence) : null;
    final safeLatest = status == FeedStatus.denied || status == FeedStatus.clock
        ? null
        : latest;
    final scenario = widget.scenario;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 9, 18, 25),
      children: [
        Row(
          children: [
            Expanded(child: Text(bin.label, style: display(46))),
            if (widget.onSelect != null)
              IconButton.filledTonal(
                onPressed: widget.onSelect,
                tooltip: 'Change bin',
                icon: const Icon(Icons.unfold_more_rounded),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 7,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              bin.lot,
              style: const TextStyle(
                color: muted,
                fontWeight: FontWeight.w600,
                letterSpacing: .7,
              ),
            ),
            Semantics(
              liveRegion: true,
              child: Text(
                connectedStatus,
                style: TextStyle(
                  color: status == FeedStatus.live ? lime : coral,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (safeLatest != null)
              Text(
                ageLabel(safeLatest.measured, now),
                style: const TextStyle(color: muted),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xff362c49), Color(0xff24253e)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: const Color(0xff5f526c)),
          ),
          child: Column(
            children: [
              ListTile(
                minTileHeight: 62,
                tileColor: const Color(0xff272b43),
                leading: Icon(
                  battery?.chargeState == 'charging' && !cached
                      ? Icons.battery_charging_full_rounded
                      : Icons.battery_std_rounded,
                  color: powerColor,
                ),
                title: Text(
                  powerText,
                  style: TextStyle(
                    color: powerColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle:
                    battery?.chargeState == 'charging' &&
                        !cached &&
                        powerText != 'Charging'
                    ? const Text('Charging')
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (power != null)
                      Text(
                        '${power.round()}%',
                        style: display(27, color: powerColor),
                      ),
                    const Icon(Icons.chevron_right_rounded, color: muted),
                  ],
                ),
                onTap: () => showDevice(context, bin, status, latest, battery),
              ),
              const Divider(height: 1, color: Color(0xff5f526c)),
              Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  KernelStage(interactive: !staticModel),
                  Positioned(
                    left: 15,
                    right: 15,
                    bottom: 12,
                    child: IgnorePointer(
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Wheat kernel',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (!staticModel &&
                              !MediaQuery.disableAnimationsOf(context))
                            const Flexible(
                              child: Text(
                                'Drag to rotate',
                                textAlign: TextAlign.end,
                                style: TextStyle(color: muted, fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 15),
        Tile(
          fill: switch (risk.level) {
            Risk.normal => lime,
            Risk.watch => wheat,
            Risk.high || Risk.critical => coral,
            _ => lilac,
          },
          dark: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Storage risk',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(risk.level.label, style: display(36, color: ink)),
              const SizedBox(height: 7),
              Text(risk.evidence),
              if (demo)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Illustrative rules · demo-v1',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Tile(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                demo ? 'Illustrative estimates' : 'Storage estimates',
                style: display(23),
              ),
              const SizedBox(height: 9),
              Text(
                scenario != null && scenario != Scenario.interrupted
                    ? 'Remaining life: ${scenario == Scenario.rising ? '12 days (9–16)' : '34 days (26–43)'}.'
                    : 'Remaining life: Estimate unavailable.',
              ),
              if (scenario != null && scenario != Scenario.interrupted) ...[
                Text('Forecast: ${timeLabel(latest?.measured ?? now)}'),
                Text(
                  'Illustrative threshold: ${DateFormat.yMMMd().format((latest?.measured ?? now).add(Duration(days: scenario == Scenario.rising ? 12 : 34)).toLocal())}',
                ),
                const SizedBox(height: 5),
                const Text(
                  'Dry matter loss: 0.14% from 2 kg CO₂ per 1,000 kg initial dry matter.',
                ),
              ] else
                const Text('Dry matter loss: Estimate unavailable.'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Tile(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      demo ? 'Seven-day risk trend' : 'Seven-day CO₂ trend',
                      style: display(24),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Open carbon dioxide history',
                    onPressed: () => trends(Channel.carbon),
                    icon: const Icon(Icons.arrow_outward_rounded),
                  ),
                ],
              ),
              if (weeklyRisk != null && chart.length >= 2) ...[
                Text(
                  'Reconstructed daily peak · $demoRuleVersion',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 12),
                Semantics(
                  label:
                      'Daily peak risk, oldest to newest: ${weeklyRisk.map((r) => r.label).join(', ')}',
                  child: ExcludeSemantics(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var day = 0; day < weeklyRisk.length; day++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    height: 8 + weeklyRisk[day].index * 13,
                                    decoration: BoxDecoration(
                                      color: switch (weeklyRisk[day]) {
                                        Risk.normal => lime,
                                        Risk.watch => wheat,
                                        Risk.high || Risk.critical => coral,
                                        Risk.insufficient => muted,
                                      },
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(7),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    DateFormat('EEEEE').format(
                                      now.toLocal().subtract(
                                        Duration(days: 6 - day),
                                      ),
                                    ),
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ] else if (chart.length < 2)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Waiting for more readings.'),
                )
              else ...[
                Text(
                  '${valueLabel(Channel.carbon, chart.last.values[Channel.carbon])} ppm latest · ${chart.length} readings',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 12),
                HistoryChart(
                  readings: recent,
                  channel: Channel.carbon,
                  cadence: bin.cadence,
                  compact: true,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text('Sensor readings', style: display(29)),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns =
                constraints.maxWidth >= 315 &&
                    MediaQuery.textScalerOf(context).scale(14) <= 21
                ? 2
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final metric in Channel.values.where(
                  (m) => m != Channel.battery,
                ))
                  SizedBox(width: width, child: sensor(metric, safeLatest)),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget sensor(Channel metric, Reading? reading) {
    final color = channelColor(metric);
    final value = reading?.values[metric];
    final acoustic =
        metric == Channel.acoustic && reading?.acousticWindow != null;
    final health = reading?.invalid.contains(metric) == true
        ? 'Invalid reading'
        : value == null
        ? 'Unavailable'
        : status == FeedStatus.live
        ? timeLabel(reading!.measured)
        : 'Last reported · ${timeLabel(reading!.measured)}';
    return Tile(
      onTap: () => trends(metric),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(channelIcon(metric), color: color, size: 22),
          const SizedBox(height: 9),
          Text(
            metric.label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: valueLabel(metric, value),
                  style: display(29, color: color),
                ),
                if (value != null)
                  TextSpan(
                    text: ' ${metric.unit}',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (acoustic)
            Text(
              'Per ${reading!.acousticWindow} s',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          if (metric == Channel.gas)
            const Text(
              'VOC-related indicator',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          const SizedBox(height: 4),
          Text(health, style: const TextStyle(color: muted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget alerts() {
    final items = episodes(recent, bin, status, demo: demo);
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text('Alerts', style: display(43)),
        const SizedBox(height: 8),
        Text(
          '${bin.label} · ${bin.lot} · Last 7 days',
          style: const TextStyle(color: muted),
        ),
        if (ackError)
          const Text(
            'Acknowledgments could not be loaded.',
            style: TextStyle(color: coral),
          ),
        const SizedBox(height: 18),
        if (items.isEmpty)
          const Tile(child: Text('No alerts in the available readings.')),
        for (final event in items) ...[
          Tile(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  event.critical
                      ? Icons.error_outline_rounded
                      : Icons.warning_amber_rounded,
                  color: event.critical ? coral : wheat,
                ),
                const SizedBox(height: 8),
                Text(event.title, style: display(25)),
                const SizedBox(height: 4),
                Text(
                  timeLabel(event.time),
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 9),
                Text(event.evidence),
                Text(event.action),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => trends(event.channel),
                      child: const Text('View sensor history'),
                    ),
                    if (pending.contains(event.id))
                      const Text('Saving acknowledgment…')
                    else if (acked.contains(event.id) &&
                        !failed.contains(event.id))
                      const Text('Acknowledged')
                    else if (demo || connected == true)
                      TextButton(
                        onPressed: () => acknowledge(event.id),
                        child: Text(
                          failed.contains(event.id)
                              ? 'Retry acknowledgment'
                              : 'Acknowledge',
                        ),
                      ),
                  ],
                ),
                if (failed.contains(event.id))
                  const Text(
                    'Acknowledgment could not be confirmed.',
                    style: TextStyle(color: coral),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget settings() => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Text('More', style: display(43)),
      const SizedBox(height: 14),
      Tile(
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('Export report'),
              subtitle: const Text('CSV or PDF'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showReports(context, widget.feed, bin, demo),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.memory_rounded),
              title: const Text('Device details'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () =>
                  showDevice(context, bin, status, latest, lastBattery),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Static wheat model'),
              value: staticModel,
              onChanged: (value) => setState(() => staticModel = value),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Tile(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(demo ? 'Demo mode' : 'Live mode', style: display(25)),
            if (demo) ...[
              const SizedBox(height: 8),
              for (final option in Scenario.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(option.label),
                  trailing: option == widget.scenario
                      ? const Icon(Icons.check_rounded, color: lime)
                      : null,
                  onTap: () => ref.read(demoProvider.notifier).select(option),
                ),
              OutlinedButton(
                onPressed: () => ref.read(demoProvider.notifier).select(null),
                child: const Text('Exit demo'),
              ),
            ] else ...[
              TextButton(
                onPressed: () =>
                    ref.read(demoProvider.notifier).select(Scenario.stable),
                child: const Text('Open demo mode'),
              ),
              TextButton(
                onPressed: widget.onSignOut,
                child: const Text('Sign out'),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 14),
      Tile(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('GrainGuard 1.0.0', style: display(23)),
            const SizedBox(height: 8),
            const Text(
              'Live readings are kept in session memory. Reports are prepared on this phone and shared only when you choose to export.',
            ),
            const SizedBox(height: 8),
            Text(
              supportContact.isEmpty
                  ? 'Support: GrainGuard project administrator'
                  : supportContact,
            ),
            TextButton(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'GrainGuard',
              ),
              child: const Text('Open source licenses'),
            ),
          ],
        ),
      ),
    ],
  );
}

class Tile extends StatelessWidget {
  const Tile({
    super.key,
    required this.child,
    this.fill = panel,
    this.dark = false,
    this.onTap,
  });
  final Widget child;
  final Color fill;
  final bool dark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: fill,
    clipBehavior: Clip.antiAlias,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: dark ? ink : paper),
          child: child,
        ),
      ),
    ),
  );
}
