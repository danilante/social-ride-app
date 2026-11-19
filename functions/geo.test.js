const test = require('node:test');
const assert = require('node:assert');
const { distanceMeters, centroid } = require('./geo');

test('distanceMeters returns 0 for identical points', () => {
  assert.strictEqual(distanceMeters(45.07, 7.68, 45.07, 7.68), 0);
});

test('distanceMeters returns ~111km for 1 degree latitude difference', () => {
  const d = distanceMeters(0, 0, 1, 0);
  assert.ok(Math.abs(d - 111195) < 100);
});

test('centroid averages positions', () => {
  const c = centroid([{ lat: 0, lng: 0 }, { lat: 2, lng: 2 }]);
  assert.strictEqual(c.lat, 1);
  assert.strictEqual(c.lng, 1);
});
