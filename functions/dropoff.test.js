const test = require('node:test');
const assert = require('node:assert');
const { evaluateRider } = require('./dropoff');

test('stays in_group under threshold', () => {
  const rider = { lat: 0, lng: 0, thresholdExceededSince: null };
  const others = [{ lat: 0.0001, lng: 0.0001 }];
  const result = evaluateRider(rider, others, Date.now());
  assert.strictEqual(result.state, 'in_group');
});

test('marks dropped_off after dwell time over threshold', () => {
  const now = Date.now();
  const rider = { lat: 10, lng: 10, thresholdExceededSince: now - 61000 };
  const others = [{ lat: 0, lng: 0 }];
  const result = evaluateRider(rider, others, now, 300);
  assert.strictEqual(result.state, 'dropped_off');
});

test('does not mark dropped_off before dwell time elapses', () => {
  const now = Date.now();
  const rider = { lat: 10, lng: 10, thresholdExceededSince: now - 5000 };
  const others = [{ lat: 0, lng: 0 }];
  const result = evaluateRider(rider, others, now, 300);
  assert.strictEqual(result.state, 'in_group');
});

test('resets exceededSince when back under threshold', () => {
  const rider = { lat: 0, lng: 0.0001, thresholdExceededSince: Date.now() - 70000 };
  const others = [{ lat: 0, lng: 0 }];
  const result = evaluateRider(rider, others, Date.now(), 300);
  assert.strictEqual(result.thresholdExceededSince, null);
});

test('stays in_group with no other riders to compare against', () => {
  const rider = { lat: 10, lng: 10, thresholdExceededSince: null };
  const result = evaluateRider(rider, [], Date.now());
  assert.strictEqual(result.state, 'in_group');
});
