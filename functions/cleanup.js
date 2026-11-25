/**
 * Ride TTL cleanup helpers.
 *
 * Rides stay available for a short history window after they end, then
 * subcollections (riders, track) and the ride doc itself are deleted.
 * Storage audio under rides/{rideId}/ is best-effort deleted as well.
 */

const DEFAULT_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours
const BATCH_SIZE = 400; // stay under Firestore 500 write limit

/**
 * Delete all documents in a collection (or query) in batches.
 * @param {FirebaseFirestore.Firestore} db
 * @param {FirebaseFirestore.Query} query
 */
async function deleteQueryInBatches(db, query) {
  let deleted = 0;
  // Loop until the query returns no more docs.
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const snap = await query.limit(BATCH_SIZE).get();
    if (snap.empty) break;
    const batch = db.batch();
    snap.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    deleted += snap.size;
    if (snap.size < BATCH_SIZE) break;
  }
  return deleted;
}

/**
 * Fully remove a single ride: riders, track, Storage prefix, then the ride doc.
 * @param {FirebaseFirestore.Firestore} db
 * @param {import('firebase-admin/storage').Storage | null} storage
 * @param {string} rideId
 * @param {string} [bucketName]
 */
async function deleteRideFully(db, storage, rideId, bucketName) {
  const rideRef = db.collection('rides').doc(rideId);

  const ridersDeleted = await deleteQueryInBatches(
    db,
    rideRef.collection('riders')
  );
  const trackDeleted = await deleteQueryInBatches(
    db,
    rideRef.collection('track')
  );

  // Best-effort Storage cleanup (dropoff audio under rides/{rideId}/).
  let storageDeleted = 0;
  if (storage) {
    try {
      const bucket = bucketName
        ? storage.bucket(bucketName)
        : storage.bucket();
      const [files] = await bucket.getFiles({ prefix: `rides/${rideId}/` });
      await Promise.all(files.map((f) => f.delete().catch(() => null)));
      storageDeleted = files.length;
    } catch (_) {
      // Storage may not be configured in tests / emulator.
    }
  }

  await rideRef.delete();

  return {
    rideId,
    ridersDeleted,
    trackDeleted,
    storageDeleted,
  };
}

/**
 * Find ended rides whose endedAt (or createdAt fallback) is older than ttlMs
 * and delete them.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {import('firebase-admin/storage').Storage | null} storage
 * @param {object} [opts]
 * @param {number} [opts.now]
 * @param {number} [opts.ttlMs]
 * @param {string} [opts.bucketName]
 * @param {number} [opts.maxRides] safety cap per run
 */
async function cleanupExpiredRides(db, storage, opts = {}) {
  const now = opts.now ?? Date.now();
  const ttlMs = opts.ttlMs ?? DEFAULT_TTL_MS;
  const maxRides = opts.maxRides ?? 50;
  const cutoff = now - ttlMs;

  // Prefer endedAt when present; fall back to createdAt for older docs.
  // Two queries keep the index simple (status + endedAt / createdAt).
  const endedByEndedAt = await db
    .collection('rides')
    .where('status', '==', 'ended')
    .where('endedAt', '<=', new Date(cutoff))
    .limit(maxRides)
    .get()
    .catch(() => ({ empty: true, docs: [] })); // index may not exist yet

  const results = [];
  const seen = new Set();

  for (const doc of endedByEndedAt.docs || []) {
    seen.add(doc.id);
    results.push(
      await deleteRideFully(db, storage, doc.id, opts.bucketName)
    );
  }

  // Fallback path: ended rides without endedAt, using createdAt.
  if (results.length < maxRides) {
    const endedByCreatedAt = await db
      .collection('rides')
      .where('status', '==', 'ended')
      .where('createdAt', '<=', new Date(cutoff))
      .limit(maxRides - results.length)
      .get()
      .catch(() => ({ empty: true, docs: [] }));

    for (const doc of endedByCreatedAt.docs || []) {
      if (seen.has(doc.id)) continue;
      // Skip if endedAt exists and is still within TTL (shouldn't match query,
      // but be safe when reading mixed docs).
      const data = doc.data() || {};
      if (data.endedAt) {
        const endedMs =
          typeof data.endedAt.toMillis === 'function'
            ? data.endedAt.toMillis()
            : new Date(data.endedAt).getTime();
        if (endedMs > cutoff) continue;
      }
      results.push(
        await deleteRideFully(db, storage, doc.id, opts.bucketName)
      );
    }
  }

  return results;
}

module.exports = {
  DEFAULT_TTL_MS,
  deleteRideFully,
  cleanupExpiredRides,
  deleteQueryInBatches,
};
