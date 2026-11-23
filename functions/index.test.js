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
