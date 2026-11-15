import 'dart:io';
import 'dart:math' as math;

import 'package:csv/csv.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'assessment.dart';
import 'dashboard.dart';
import 'source.dart';
import 'telemetry.dart';
import 'visuals.dart';

Future<DateTimeRange?> selectReportRange(BuildContext context) async {
  final today = DateUtils.dateOnly(DateTime.now());
  final range = await showDateRangePicker(
    context: context,
    firstDate: DateTime(2020),
    lastDate: today,
    initialDateRange: DateTimeRange(
      start: today.subtract(const Duration(days: 6)),
      end: today,
    ),
  );
  if (range != null &&
      range.end.difference(range.start) >= const Duration(days: 30)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select up to 30 calendar days.')),
      );
    }
    return null;
  }
  return range;
}

Future<void> showReports(BuildContext context, Feed feed, Bin bin, bool demo) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ReportSheet(feed: feed, bin: bin, demo: demo),
    );

class ReportSheet extends StatefulWidget {
  const ReportSheet({
    super.key,
    required this.feed,
    required this.bin,
    required this.demo,
  });
  final Feed feed;
  final Bin bin;
  final bool demo;

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  int days = 7;
  DateTimeRange? custom;
  bool busy = false;
  String? message;

  Future<void> generate({required bool pdf}) async {
    final now = DateTime.now().toUtc();
    final from = custom?.start.toUtc() ?? now.subtract(Duration(days: days));
    final selectedEnd = custom == null
        ? now
        : DateTime(
            custom!.end.year,
            custom!.end.month,
            custom!.end.day + 1,
          ).toUtc();
    final to = selectedEnd.isAfter(now) ? now : selectedEnd;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final readings = await widget.feed.history(from, to);
      if (!mounted) return;
      if (readings.isEmpty) {
        setState(
          () => message = 'No readings are available for that date range.',
        );
        return;
      }
      final report = Report(widget.bin, widget.demo, from, to, now, readings);
      final folder = await (await getTemporaryDirectory()).createTemp(
        'grainguard-',
      );
      final file = File(
        '${folder.path}/GrainGuard-${widget.demo ? 'DEMO-' : ''}${now.millisecondsSinceEpoch}.${pdf ? 'pdf' : 'csv'}',
      );
      if (pdf) {
        await file.writeAsBytes(await report.document());
      } else {
        await file.writeAsString('\uFEFF${report.spreadsheet()}');
      }
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(file.path, mimeType: pdf ? 'application/pdf' : 'text/csv'),
          ],
          subject: 'GrainGuard report',
          sharePositionOrigin: box != null && box.hasSize
              ? box.localToGlobal(Offset.zero) & box.size
              : null,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Export unavailable. Check the connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Export report', style: display(34)),
          const SizedBox(height: 9),
          Text(
            '${widget.bin.label} · ${widget.bin.lot}${widget.demo ? ' · Demo data' : ''}',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final range in [1, 7, 30])
                ChoiceChip(
                  label: Text(range == 1 ? '24 hours' : '$range days'),
                  selected: custom == null && days == range,
                  onSelected: busy
                      ? null
                      : (_) => setState(() {
                          days = range;
                          custom = null;
                        }),
                ),
              ActionChip(
                label: const Text('Custom'),
                onPressed: busy
                    ? null
                    : () async {
                        final range = await selectReportRange(context);
                        if (range != null && mounted) {
                          setState(() => custom = range);
                        }
                      },
              ),
            ],
          ),
          if (custom != null)
            Text(
              '${timeLabel(custom!.start)} through ${timeLabel(custom!.end)}',
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            children: [
              FilledButton.icon(
                onPressed: busy ? null : () => generate(pdf: true),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Share PDF'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => generate(pdf: false),
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('Share CSV'),
              ),
            ],
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('Preparing report…'),
            ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(message!),
            ),
        ],
      ),
    ),
  );
}

class Report {
  const Report(
    this.bin,
    this.demo,
    this.from,
    this.to,
    this.created,
    this.readings,
  );
  final Bin bin;
  final bool demo;
  final DateTime from;
  final DateTime to;
  final DateTime created;
  final List<Reading> readings;

  String localTimestamp(DateTime time) {
    final local = time.toLocal();
    final minutes = local.timeZoneOffset.inMinutes;
    final hours = (minutes.abs() ~/ 60).toString().padLeft(2, '0');
    final remainder = (minutes.abs() % 60).toString().padLeft(2, '0');
    return '${local.toIso8601String()}${minutes < 0 ? '-' : '+'}$hours:$remainder';
  }

  List<List<Object?>> get metadata {
    final expected = math.max(
      1,
      to.difference(from).inSeconds ~/ bin.cadence.inSeconds,
    );
    return [
      ['Mode', demo ? 'DEMO - SIMULATED DATA' : 'Live'],
      ['Bin', bin.label],
      ['Device', bin.id],
      ['Lot', bin.lot],
      ['Timezone', created.toLocal().timeZoneName],
      ['Generated', localTimestamp(created)],
      ['From', localTimestamp(from)],
      ['To', localTimestamp(to)],
      [
        'Data coverage',
        '${readings.length} readings of approximately $expected expected'
            '${readings.length >= 4321 ? ' (query cap reached)' : ''}',
      ],
      ['Risk rule version', demo ? demoRuleVersion : liveRuleVersion],
      [
        'Remaining storage life',
        demo ? 'Illustrative only' : 'See live dashboard',
      ],
      ['Dry matter loss', demo ? 'Illustrative only' : 'Unavailable'],
    ];
  }

  Object? safeCell(Object? value) {
    if (value is String &&
        RegExp(r'^[\s\u0000-\u001f]*[=+\-@]|^[\t\r\n]').hasMatch(value)) {
      return "'$value";
    }
    return value;
  }

  String spreadsheet() => csv.encode(
    [
      ...metadata,
      [],
      [
        'Sample ID',
        'Measured (local)',
        'Received (local)',
        ...Channel.values.map((c) => '${c.label} (${c.unit})'),
        'Acoustic window (s)',
        'Battery voltage (V)',
        'Charge state',
        'Invalid channels',
      ],
      for (final reading in readings)
        [
          reading.id,
          localTimestamp(reading.measured),
          localTimestamp(reading.received),
          for (final c in Channel.values) reading.values[c],
          reading.acousticWindow,
          reading.voltage,
          reading.chargeState,
          reading.invalid.map((c) => c.label).join(', '),
        ],
    ].map((row) => row.map(safeCell).toList()).toList(),
  );

  Future<Uint8List> document() async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/WorkSans.ttf'),
    );
    final file = pw.Document(
      title: 'GrainGuard storage report',
      author: 'GrainGuard',
    );
    const navy = PdfColor.fromInt(0xff11192c);
    const gold = PdfColor.fromInt(0xffffce79);
    file.addPage(
      pw.MultiPage(
        maxPages: 220,
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font),
        header: (_) => pw.Container(
          color: navy,
          padding: const pw.EdgeInsets.all(14),
          margin: const pw.EdgeInsets.only(bottom: 10),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'GrainGuard',
                style: const pw.TextStyle(color: gold, fontSize: 19),
              ),
              if (demo)
                pw.Text(
                  'DEMO / SIMULATED DATA',
                  style: const pw.TextStyle(color: gold, fontSize: 10),
                ),
            ],
          ),
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
        build: (_) => [
          pw.Text(
            'Storage report',
            style: const pw.TextStyle(fontSize: 23, color: navy),
          ),
          pw.SizedBox(height: 10),
          for (final row in metadata)
            pw.Text(
              '${row[0]}: ${row[1]}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Measurements in report timezone. A dash indicates an unavailable value.',
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.SizedBox(height: 5),
          pw.TableHelper.fromTextArray(
            headers: [
              'Measured (local)',
              'Temp °C',
              'RH %',
              'CO2 ppm',
              'Gas kOhm',
              'Events / s window',
              'Battery %',
            ],
            data: [
              for (final reading in readings)
                [
                  localTimestamp(reading.measured)
                      .replaceFirst(RegExp(r'\.\d+'), ''),
                  for (final channel in Channel.values)
                    channel == Channel.acoustic &&
                            reading.values[channel] != null
                        ? '${reading.values[channel]!.round()} / ${reading.acousticWindow}'
                        : reading.values[channel]?.toStringAsFixed(
                                channel == Channel.temperature ||
                                        channel == Channel.gas
                                    ? 1
                                    : 0,
                              ) ??
                              '-',
                ],
            ],
            headerDecoration: const pw.BoxDecoration(color: gold),
            headerStyle: const pw.TextStyle(color: navy, fontSize: 7),
            cellStyle: const pw.TextStyle(fontSize: 7),
            cellPadding: const pw.EdgeInsets.all(4),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            border: null,
            columnWidths: {0: const pw.FlexColumnWidth(2.8)},
          ),
        ],
      ),
    );
    return file.save();
  }
}
