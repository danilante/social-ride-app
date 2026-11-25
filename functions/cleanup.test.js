const test = require('node:test');
const assert = require('node:assert');
const {
  deleteRideFully,
  cleanupExpiredRides,
  DEFAULT_TTL_MS,
} = require('./cleanup');

function fakeDb({ rides = {}, subcollections = {} }) {
  const writes = [];
  const deletes = [];

  function makeQuery(docs) {
    return {
      limit(n) {
        return {
          async get() {
            const slice = docs.slice(0, n);
            return {
              empty: slice.length === 0,
              size: slice.length,
              docs: slice,
            };
          },
        };
      },
      async get() {
        return {
          empty: docs.length === 0,
          size: docs.length,
          docs,
        };
      },
    };
  }

  return {
    writes,
    deletes,
    collection(name) {
      assert.strictEqual(name, 'rides');
      return {
        where(field, op, value) {
          // Collect matching ride docs for the query chain.
          let matched = Object.entries(rides)
            .filter(([, data]) => {
              if (field === 'status' && op === '==') {
                return data.status === value;
              }
              return true;
            })
            .map(([id, data]) => ({
              id,
              data: () => data,
              ref: { path: `rides/${id}` },
            }));

          // Second where (endedAt / createdAt) applied in a chained call.
          return {
            where(field2, op2, value2) {
              matched = matched.filter((d) => {
                const data = d.data();
                const raw = data[field2];
                if (raw == null) return field2 === 'createdAt'; // allow fallback
                const ms =
                  typeof raw.toMillis === 'function'
                    ? raw.toMillis()
                    : new Date(raw).getTime();
                if (op2 === '<=') return ms <= value2.getTime();
                return true;
              });
              return makeQuery(
                matched.map((d) => ({
                  ...d,
                  ref: {
                    path: `rides/${d.id}`,
                    // used by batch.delete
                  },
                }))
              );
            },
            limit: makeQuery(matched).limit,
            get: makeQuery(matched).get,
          };
        },
        doc(rideId) {
          return {
            collection(sub) {
              const key = `${rideId}/${sub}`;
              const docs = (subcollections[key] || []).map((id) => ({
                id,
                ref: { path: `rides/${rideId}/${sub}/${id}` },
              }));
              return makeQuery(docs);
            },
            async delete() {
              deletes.push(`rides/${rideId}`);
            },
          };
        },
      };
    },
    batch() {
      const ops = [];
      return {
        delete(ref) {
          ops.push(ref.path);
        },
        async commit() {
          deletes.push(...ops);
        },
      };
    },
  };
}

test('deleteRideFully removes riders, track and the ride doc', async () => {
  const db = fakeDb({
    rides: { r1: { status: 'ended' } },
    subcollections: {
      'r1/riders': ['u1', 'u2'],
      'r1/track': ['t1'],
    },
  });

  const result = await deleteRideFully(db, null, 'r1');

  assert.strictEqual(result.rideId, 'r1');
  assert.strictEqual(result.ridersDeleted, 2);
  assert.strictEqual(result.trackDeleted, 1);
  assert.ok(db.deletes.includes('rides/r1'));
  assert.ok(db.deletes.some((p) => p.includes('riders')));
  assert.ok(db.deletes.some((p) => p.includes('track')));
});

test('cleanupExpiredRides only targets ended rides past TTL', async () => {
  const now = Date.now();
  const old = new Date(now - DEFAULT_TTL_MS - 60_000);
  const recent = new Date(now - 60_000);

  const db = fakeDb({
    rides: {
      oldEnded: {
        status: 'ended',
        endedAt: { toMillis: () => old.getTime() },
        createdAt: { toMillis: () => old.getTime() },
      },
      recentEnded: {
        status: 'ended',
        endedAt: { toMillis: () => recent.getTime() },
        createdAt: { toMillis: () => recent.getTime() },
      },
      stillActive: {
        status: 'active',
        createdAt: { toMillis: () => old.getTime() },
      },
    },
    subcollections: {
      'oldEnded/riders': ['a'],
      'oldEnded/track': [],
    },
  });

  const results = await cleanupExpiredRides(db, null, {
    now,
    ttlMs: DEFAULT_TTL_MS,
    maxRides: 10,
  });

  assert.strictEqual(results.length, 1);
  assert.strictEqual(results[0].rideId, 'oldEnded');
  assert.ok(db.deletes.includes('rides/oldEnded'));
  assert.ok(!db.deletes.includes('rides/recentEnded'));
  assert.ok(!db.deletes.includes('rides/stillActive'));
});

test('DEFAULT_TTL_MS is 24 hours', () => {
  assert.strictEqual(DEFAULT_TTL_MS, 24 * 60 * 60 * 1000);
});
