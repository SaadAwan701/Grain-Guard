import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'telemetry.dart';

const emulatorMode = bool.fromEnvironment('GG_EMULATORS');
const supportContact = String.fromEnvironment('GG_SUPPORT_CONTACT');

class Cloud {
  const Cloud(this.auth, this.database);
  final FirebaseAuth auth;
  final FirebaseDatabase database;

  static Future<Cloud?> open() async {
    final staging = appFlavor == 'staging';
    if (emulatorMode && !staging) return null;
    final (apiKey, appId, projectId, senderId, url) = staging
        ? (
            const String.fromEnvironment('GG_STAGING_API_KEY'),
            const String.fromEnvironment('GG_STAGING_APP_ID'),
            const String.fromEnvironment('GG_STAGING_PROJECT_ID'),
            const String.fromEnvironment('GG_STAGING_SENDER_ID'),
            const String.fromEnvironment('GG_STAGING_DATABASE_URL'),
          )
        : (
            const String.fromEnvironment('GG_PRODUCTION_API_KEY'),
            const String.fromEnvironment('GG_PRODUCTION_APP_ID'),
            const String.fromEnvironment('GG_PRODUCTION_PROJECT_ID'),
            const String.fromEnvironment('GG_PRODUCTION_SENDER_ID'),
            const String.fromEnvironment('GG_PRODUCTION_DATABASE_URL'),
          );
    if (!emulatorMode &&
        [apiKey, appId, projectId, senderId, url].any((item) => item.isEmpty)) {
      return null;
    }
    const host = String.fromEnvironment(
      'GG_EMULATOR_HOST',
      defaultValue: '10.0.2.2',
    );
    final app = Firebase.apps.isEmpty
        ? await Firebase.initializeApp(
            options: emulatorMode
                ? const FirebaseOptions(
                    apiKey: 'fake-api-key',
                    appId: '1:1234567890:android:1234567890',
                    messagingSenderId: '1234567890',
                    projectId: 'demo-grainguard',
                    databaseURL:
                        'https://demo-grainguard-default-rtdb.firebaseio.com',
                  )
                : FirebaseOptions(
                    apiKey: apiKey,
                    appId: appId,
                    projectId: projectId,
                    messagingSenderId: senderId,
                    databaseURL: url,
                  ),
          )
        : Firebase.app();
    final auth = FirebaseAuth.instanceFor(app: app);
    final database = FirebaseDatabase.instanceFor(app: app);
    if (emulatorMode) {
      await auth.useAuthEmulator(host, 9099, automaticHostMapping: false);
      database.useDatabaseEmulator(host, 9000, automaticHostMapping: false);
    }
    return Cloud(auth, database);
  }

  Stream<Map<String, String>> assignments(String uid) => database
      .ref('memberships/$uid')
      .onValue
      .map(
        (event) => {
          for (final item in event.snapshot.children)
            if (item.key != null)
              item.key!: fields(item.value)['label'] as String? ?? item.key!,
        },
      );

  Stream<Bin?> bin(String id, String label) =>
      database.ref('devices/$id/meta').onValue.map((event) {
        final data = fields(event.snapshot.value);
        final lot = data['activeLotId'];
        if (lot is! String || lot.isEmpty) return null;
        final seconds =
            number(data['expectedCadenceSec'], 1, 86400)?.round() ?? 600;
        return Bin(
          id,
          data['label'] is String ? data['label'] as String : label,
          lot,
          cadence: Duration(seconds: seconds),
          firmware: data['firmwareVersion'] as String?,
        );
      });
}

abstract interface class Feed {
  Stream<bool> get connection;
  Stream<({Reading? reading, bool malformed})> get latest;
  Future<List<Reading>> history(DateTime from, DateTime to);
  Stream<Set<String>> get acknowledgments;
  Future<void> acknowledge(String id);
}

class CloudFeed implements Feed {
  CloudFeed(this.database, this.uid, this.bin);
  final FirebaseDatabase database;
  final String uid;
  final Bin bin;

  @override
  Stream<bool> get connection => database
      .ref('.info/connected')
      .onValue
      .map((event) => event.snapshot.value == true);

  @override
  Stream<({Reading? reading, bool malformed})> get latest =>
      database.ref('devices/${bin.id}/latest').onValue.map((event) {
        final raw = event.snapshot.value;
        // The publisher can still be waiting for the first reading of a newly active lot.
        if (raw == null ||
            (fields(raw)['lotId'] is String &&
                fields(raw)['lotId'] != bin.lot)) {
          return (reading: null, malformed: false);
        }
        final reading = Reading.decode(raw, bin);
        return (reading: reading, malformed: reading == null);
      });

  @override
  Future<List<Reading>> history(DateTime from, DateTime to) async {
    final snapshot = await database
        .ref('devices/${bin.id}/lots/${bin.lot}/samples')
        .orderByChild('measuredAtMs')
        .startAt(from.millisecondsSinceEpoch)
        .endAt(to.millisecondsSinceEpoch)
        .limitToLast(4321)
        .get()
        .timeout(const Duration(seconds: 12));
    final readings = <String, Reading>{};
    for (final sample in snapshot.children) {
      final reading = Reading.decode(sample.value, bin, sampleKey: sample.key);
      if (reading != null) readings[reading.id] = reading;
    }
    return readings.values.toList()
      ..sort((a, b) => a.measured.compareTo(b.measured));
  }

  DatabaseReference get _acks =>
      database.ref('userState/$uid/devices/${bin.id}/alertAcks');

  @override
  Stream<Set<String>> get acknowledgments => _acks.onValue.map(
    (event) => fields(event.snapshot.value).keys.whereType<String>().toSet(),
  );

  @override
  Future<void> acknowledge(String id) async {
    final target = _acks.child(id);
    if ((await target.get().timeout(const Duration(seconds: 8))).exists) return;
    await target
        .set({'acknowledgedAtMs': ServerValue.timestamp})
        .timeout(const Duration(seconds: 8));
  }
}

class DemoFeed implements Feed {
  DemoFeed(this.data);
  final DemoHistory data;

  @override
  Stream<bool> get connection =>
      Stream.value(data.scenario != Scenario.interrupted);

  @override
  Stream<({Reading? reading, bool malformed})> get latest =>
      Stream.value((reading: data.latest, malformed: false));

  @override
  Future<List<Reading>> history(DateTime from, DateTime to) async =>
      data.history(from, to);

  @override
  Stream<Set<String>> get acknowledgments => Stream.value(const {});

  @override
  Future<void> acknowledge(String id) async {}
}

final cloudProvider = FutureProvider<Cloud?>((ref) => Cloud.open());
final demoProvider = NotifierProvider<DemoSelection, Scenario?>(
  DemoSelection.new,
);

class DemoSelection extends Notifier<Scenario?> {
  @override
  Scenario? build() => null;
  void select(Scenario? scenario) => state = scenario;
}
