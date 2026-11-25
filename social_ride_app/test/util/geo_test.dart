import 'package:flutter_test/flutter_test.dart';
import 'package:social_ride_app/util/geo.dart';

void main() {
  test('distanceMeters returns 0 for identical points', () {
    expect(distanceMeters(45.0, 7.0, 45.0, 7.0), 0);
  });

  test('distanceMeters is approximately 111 km for 1 degree of latitude', () {
    final d = distanceMeters(0, 0, 1, 0);
    expect(d, greaterThan(110000));
    expect(d, lessThan(112000));
  });

  test('distanceMeters is symmetric', () {
    final a = distanceMeters(45.07, 7.68, 45.08, 7.69);
    final b = distanceMeters(45.08, 7.69, 45.07, 7.68);
    expect(a, closeTo(b, 0.01));
  });
}
