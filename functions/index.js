const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { evaluateRider } = require('./dropoff');

initializeApp();

// Ride-configured settings come straight from a client-writable Firestore
// doc, so clamp them to sane bounds here too (not just in firestore.rules)
// before they can ever collapse the drop-off detection window.
const MIN_THRESHOLD_METERS = 50;
const MAX_THRESHOLD_METERS = 1000;
const MIN_DWELL_SECONDS = 10;
const MAX_DWELL_SECONDS = 300;

// Ignore tiny GPS noise / floating-point drift. Only write distance (and
// re-trigger downstream) when the change is meaningful. This cuts the
// majority of write-backs that previously happened on every 10s update.
const DISTANCE_EPSILON_METERS = 10;

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

function distanceChangedMeaningfully(prev, next) {
  if (prev == null && next == null) return false;
  if (prev == null || next == null) return true;
  return Math.abs(prev - next) >= DISTANCE_EPSILON_METERS;
}

async function handleRiderPositionWritten(db, messaging, rideId, userId) {
    const rideRef = db.collection('rides').doc(rideId);
    const [rideSnap, ridersSnap] = await Promise.all([
      rideRef.get(),
      rideRef.collection('riders').get(),
    ]);
    const rawThresholdMeters = rideSnap.data()?.dropoffThresholdMeters;
    const rawDwellSeconds = rideSnap.data()?.dropoffDwellSeconds;
    const thresholdMeters =
      typeof rawThresholdMeters === 'number'
        ? clamp(rawThresholdMeters, MIN_THRESHOLD_METERS, MAX_THRESHOLD_METERS)
        : undefined;
    const dwellSeconds =
      typeof rawDwellSeconds === 'number'
        ? clamp(rawDwellSeconds, MIN_DWELL_SECONDS, MAX_DWELL_SECONDS)
        : undefined;

    const riders = ridersSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
    const rider = riders.find((r) => r.id === userId);
    if (!rider || rider.lat == null || rider.lng == null) return;

    const others = riders.filter(
      (r) => r.id !== userId && r.lat != null && r.lng != null
    );
    const previousState = rider.state || 'in_group';
    const args = [rider, others, Date.now()];
    if (thresholdMeters != null) args.push(thresholdMeters);
    if (dwellSeconds != null) {
      if (args.length === 3) args.push(undefined);
      args.push(dwellSeconds * 1000);
    }
    const result = evaluateRider(...args);

    const stateChanged = result.state !== previousState;
    const thresholdSinceChanged =
      result.thresholdExceededSince !== (rider.thresholdExceededSince ?? null);
    const distanceMeaningfullyChanged = distanceChangedMeaningfully(
      rider.distanceFromGroupMeters,
      result.distanceFromGroupMeters
    );

    // Only write when something the UI or future evaluations care about
    // actually changed. Avoids the previous almost-always-write behaviour
    // caused by floating-point distance noise on every position update.
    if (stateChanged || thresholdSinceChanged || distanceMeaningfullyChanged) {
      await db
          .collection('rides')
          .doc(rideId)
          .collection('riders')
          .doc(userId)
          .set(
            {
              distanceFromGroupMeters: result.distanceFromGroupMeters,
              thresholdExceededSince: result.thresholdExceededSince,
              state: result.state,
            },
            { merge: true }
          );
    }

    if (stateChanged) {
      const tokens = others.map((r) => r.fcmToken).filter(Boolean);
      if (tokens.length > 0) {
        const title =
          result.state === 'dropped_off'
            ? `${rider.displayName} si è staccato`
            : `${rider.displayName} è rientrato nel gruppo`;
        const body =
          result.state === 'dropped_off'
            ? `~${Math.round(result.distanceFromGroupMeters)}m dal gruppo`
            : '';
        await messaging.sendEachForMulticast({
          tokens,
          notification: { title, body },
          data: {
            riderId: userId,
            state: result.state,
            dropoffAudioUrl:
              result.state === 'dropped_off' ? rider.dropoffAudioUrl || '' : '',
          },
        });
      }
    }
}

exports.handleRiderPositionWritten = handleRiderPositionWritten;
exports.DISTANCE_EPSILON_METERS = DISTANCE_EPSILON_METERS;

exports.onRiderPositionWritten = onDocumentWritten(
  'rides/{rideId}/riders/{userId}',
  async (event) => {
    const { rideId, userId } = event.params;
    await handleRiderPositionWritten(getFirestore(), getMessaging(), rideId, userId);
  }
);
