const test = require('node:test');
const assert = require('node:assert');
const { handleRiderPositionWritten } = require('./index');

function fakeDb({ ride, riders, writes }) {
  const riderDocs = new Map(Object.entries(riders));

  function riderDocRef(userId) {
    return {
      set(data) {
        writes.push({ userId, data });
      },
    };
  }

  return {
    collection(name) {
      assert.strictEqual(name, 'rides');
      return {
        doc(rideId) {
          return {
            get: async () => ({ data: () => ride }),
            collection(sub) {
              assert.strictEqual(sub, 'riders');
              return {
                get: async () => ({
                  docs: Array.from(riderDocs.entries()).map(([id, data]) => ({
                    id,
                    data: () => data,
                  })),
                }),
                doc: (userId) => riderDocRef(userId),
              };
            },
          };
        },
      };
    },
  };
}

function fakeMessaging(sent) {
  return {
    sendEachForMulticast: async (payload) => {
      sent.push(payload);
    },
  };
}

test('uses the ride-configured dropoffThresholdMeters instead of the default', async () => {
  // ~100m north of the other rider: under the 300m default, over a 50m
  // custom threshold.
  const now = Date.now();
  const writes = [];
  const sent = [];
  const db = fakeDb({
    ride: { dropoffThresholdMeters: 50 },
    riders: {
      me: {
        lat: 0.0009,
        lng: 0,
        state: 'in_group',
        thresholdExceededSince: now - 61000,
        displayName: 'Mario',
      },
      other1: { lat: 0, lng: 0, state: 'in_group', fcmToken: 'tok1' },
    },
    writes,
  });

  await handleRiderPositionWritten(db, fakeMessaging(sent), 'ride1', 'me');

  assert.strictEqual(writes.length, 1);
  assert.strictEqual(writes[0].userId, 'me');
  assert.strictEqual(writes[0].data.state, 'dropped_off');
  assert.strictEqual(sent.length, 1);
});

test('stays in_group when distance is under the custom threshold', async () => {
  const now = Date.now();
  const writes = [];
  const sent = [];
  const db = fakeDb({
    // Same ~100m distance as above, but the ride's custom threshold (300m)
    // is wider than the library default would need to matter here — this
    // confirms the threshold is actually read from the ride doc, not just
    // always honored by coincidence.
    ride: { dropoffThresholdMeters: 500 },
    riders: {
      me: {
        lat: 0.0009,
        lng: 0,
        state: 'in_group',
        thresholdExceededSince: now - 61000,
        displayName: 'Mario',
      },
      other1: { lat: 0, lng: 0, state: 'in_group', fcmToken: 'tok1' },
    },
    writes,
  });

  await handleRiderPositionWritten(db, fakeMessaging(sent), 'ride1', 'me');

  assert.strictEqual(writes.length, 1);
  assert.strictEqual(writes[0].data.state, 'in_group');
  assert.strictEqual(sent.length, 0);
});

test('includes the dropped-off rider\'s custom audio URL in the push payload',
  async () => {
    const now = Date.now();
    const writes = [];
    const sent = [];
    const db = fakeDb({
      ride: { dropoffThresholdMeters: 50 },
      riders: {
        me: {
          lat: 0.0009,
          lng: 0,
          state: 'in_group',
          thresholdExceededSince: now - 61000,
          displayName: 'Mario',
          dropoffAudioUrl: 'https://example.com/mario.m4a',
        },
        other1: { lat: 0, lng: 0, state: 'in_group', fcmToken: 'tok1' },
      },
      writes,
    });

    await handleRiderPositionWritten(db, fakeMessaging(sent), 'ride1', 'me');

    assert.strictEqual(sent.length, 1);
    assert.strictEqual(sent[0].data.dropoffAudioUrl, 'https://example.com/mario.m4a');
  });

test('clamps a dropoffDwellSeconds of 0 instead of collapsing the dwell window',
  async () => {
    const now = Date.now();
    const writes = [];
    const sent = [];
    const db = fakeDb({
      ride: { dropoffThresholdMeters: 50, dropoffDwellSeconds: 0 },
      riders: {
        me: {
          lat: 0.0009,
          lng: 0,
          state: 'in_group',
          thresholdExceededSince: now - 1000,
          displayName: 'Mario',
        },
        other1: { lat: 0, lng: 0, state: 'in_group', fcmToken: 'tok1' },
      },
      writes,
    });

    await handleRiderPositionWritten(db, fakeMessaging(sent), 'ride1', 'me');

    assert.strictEqual(writes[0].data.state, 'in_group');
  });

test('clamps an oversized dropoffThresholdMeters instead of trusting it unbounded',
  async () => {
    const now = Date.now();
    const writes = [];
    const sent = [];
    const db = fakeDb({
      ride: { dropoffThresholdMeters: 999999, dropoffDwellSeconds: 5 },
      riders: {
        me: {
          lat: 10,
          lng: 10,
          state: 'in_group',
          thresholdExceededSince: now - 6000,
          displayName: 'Mario',
        },
        other1: { lat: 0, lng: 0, state: 'in_group', fcmToken: 'tok1' },
      },
      writes,
    });

    await handleRiderPositionWritten(db, fakeMessaging(sent), 'ride1', 'me');

    assert.strictEqual(writes[0].data.state, 'in_group');
  });

test('respects a custom dropoffDwellSeconds from the ride settings', async () => {
  const now = Date.now();
  const writes = [];
  const sent = [];
  const db = fakeDb({
    ride: { dropoffThresholdMeters: 50, dropoffDwellSeconds: 15 },
    riders: {
      me: {
        lat: 0.0009,
        lng: 0,
        state: 'in_group',
        thresholdExceededSince: now - 16000,
        displayName: 'Mario',
      },
      other1: { lat: 0, lng: 0, state: 'in_group', fcmToken: 'tok1' },
    },
    writes,
  });

  await handleRiderPositionWritten(db, fakeMessaging(sent), 'ride1', 'me');

  assert.strictEqual(writes[0].data.state, 'dropped_off');
});

test('sends an empty dropoffAudioUrl when the dropped-off rider has none set',
  async () => {
    const now = Date.now();
    const writes = [];
    const sent = [];
    const db = fakeDb({
      ride: { dropoffThresholdMeters: 50 },
      riders: {
        me: {
          lat: 0.0009,
          lng: 0,
          state: 'in_group',
          thresholdExceededSince: now - 61000,
          displayName: 'Mario',
        },
        other1: { lat: 0, lng: 0, state: 'in_group', fcmToken: 'tok1' },
      },
      writes,
    });

    await handleRiderPositionWritten(db, fakeMessaging(sent), 'ride1', 'me');

    assert.strictEqual(sent[0].data.dropoffAudioUrl, '');
  });

test('skips write-back when distance drifts by less than epsilon and state is stable',
  async () => {
    // ~50m away (under 300m default). Previous distance was 48m → drift of 2m
    // is below DISTANCE_EPSILON_METERS (10). State and thresholdSince unchanged.
    const now = Date.now();
    const writes = [];
    const sent = [];
    const db = fakeDb({
      ride: {},
      riders: {
        me: {
          lat: 0.00045,
          lng: 0,
          state: 'in_group',
          distanceFromGroupMeters: 48,
          thresholdExceededSince: null,
          displayName: 'Mario',
        },
        other1: { lat: 0, lng: 0, state: 'in_group', fcmToken: 'tok1' },
      },
      writes,
    });

    await handleRiderPositionWritten(db, fakeMessaging(sent), 'ride1', 'me');

    assert.strictEqual(writes.length, 0);
    assert.strictEqual(sent.length, 0);
  });

test('writes when distance changes by more than epsilon even if state is stable',
  async () => {
    // Previous distance 50m, new ~150m (still under 300m default) → should write
    // the updated distance so the UI can show it, but no push.
    const now = Date.now();
    const writes = [];
    const sent = [];
    const db = fakeDb({
      ride: {},
      riders: {
        me: {
          lat: 0.00135,
          lng: 0,
          state: 'in_group',
          distanceFromGroupMeters: 50,
          thresholdExceededSince: null,
          displayName: 'Mario',
        },
        other1: { lat: 0, lng: 0, state: 'in_group', fcmToken: 'tok1' },
      },
      writes,
    });

    await handleRiderPositionWritten(db, fakeMessaging(sent), 'ride1', 'me');

    assert.strictEqual(writes.length, 1);
    assert.strictEqual(writes[0].data.state, 'in_group');
    assert.ok(writes[0].data.distanceFromGroupMeters > 100);
    assert.strictEqual(sent.length, 0);
  });
