import 'dart:math' as math;

import 'telemetry.dart';

// University of Arkansas Extension FSA1058, Table 3, wheat and rice.
// Columns are 14–24% grain moisture on a wet basis. Null means the
// publication provides no exact estimate for that cell.
const _daysByTemperatureF = <int, List<int?>>{
  41: [null, null, null, null, 120, 80, 50, 40, 30, 20, 10],
  50: [null, null, 160, 90, 80, 50, 40, 20, 15, 10, 10],
  59: [null, 160, 80, 60, 40, 20, 20, 10, 10, 10, 5],
  68: [null, 80, 40, 40, 20, 10, 10, 10, 5, 5, 5],
  77: [160, 40, 20, 20, 10, 5, 5, 5, 3, null, null],
  81: [120, 40, 10, 10, 5, 5, 3, null, null, null, null],
  88: [40, 20, 8, 5, 3, null, null, null, null, null, null],
};

({int remainingDays, int referenceDays})? estimateStorageLife(
  StorageConditions? conditions,
  DateTime now,
) {
  if (conditions == null || conditions.since.isAfter(now)) return null;
  final temperatureF = conditions.temperatureC * 9 / 5 + 32;
  final moisture = conditions.moisturePct;
  if (temperatureF < 41 ||
      temperatureF > 88 ||
      moisture < 14 ||
      moisture > 24) {
    return null;
  }
  final warmer = _daysByTemperatureF.keys.firstWhere(
    (row) => row >= temperatureF,
  );
  final days = _daysByTemperatureF[warmer]![moisture.ceil() - 14];
  if (days == null) return null;
  final elapsedDays =
      now.difference(conditions.since).inSeconds / Duration.secondsPerDay;
  return (
    remainingDays: math.max(0, (days - elapsedDays).floor()),
    referenceDays: days,
  );
}
