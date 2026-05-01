import 'package:eco_driving_app/models/trip_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TripRecorder eco score', () {
    test('keeps a clean short trip at 100', () {
      final recorder = TripRecorder()..start();

      recorder.addPoint(
        speedKmh: 35,
        instantLph: 4,
        altitude: 10,
        accelerationMs2: 0.4,
      );

      final summary = recorder.finish(
        realDistanceKm: 1,
        estimatedDurationMin: 2,
        estimatedDistanceKm: 1,
      );

      expect(summary, isNotNull);
      expect(summary!.ecoScore, 100);
      expect(summary.hardAccelerationCount, 0);
      expect(summary.hardBrakingCount, 0);
    });

    test('penalizes one harsh acceleration and one harsh braking', () {
      final recorder = TripRecorder()..start();

      recorder
        ..addPoint(
          speedKmh: 30,
          instantLph: 4,
          altitude: 10,
          accelerationMs2: 2.8,
        )
        ..addPoint(
          speedKmh: 15,
          instantLph: 2,
          altitude: 10,
          accelerationMs2: -3.4,
        );

      final summary = recorder.finish(
        realDistanceKm: 1,
        estimatedDurationMin: 2,
        estimatedDistanceKm: 1,
      );

      expect(summary, isNotNull);
      expect(summary!.hardAccelerationCount, 1);
      expect(summary.hardBrakingCount, 1);
      expect(summary.ecoScore, 74);
    });
  });
}
