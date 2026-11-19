const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { evaluateRider } = require('./dropoff');

initializeApp();

async function handleRiderPositionWritten(db, messaging, rideId, userId) {
    const rideRef = db.collection('rides').doc(rideId);
    const [rideSnap, ridersSnap] = await Promise.all([
      rideRef.get(),
      rideRef.collection('riders').get(),
    ]);
    const thresholdMeters = rideSnap.data()?.dropoffThresholdMeters;

    const riders = ridersSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
    const rider = riders.find((r) => r.id === userId);
    if (!rider || rider.lat == null || rider.lng == null) return;

    const others = riders.filter(
      (r) => r.id !== userId && r.lat != null && r.lng != null
    );
    const previousState = rider.state || 'in_group';
    const result = thresholdMeters != null
      ? evaluateRider(rider, others, Date.now(), thresholdMeters)
      : evaluateRider(rider, others, Date.now());

    const unchanged =
      result.state === previousState &&
      result.distanceFromGroupMeters === rider.distanceFromGroupMeters &&
      result.thresholdExceededSince === (rider.thresholdExceededSince ?? null);

    if (!unchanged) {
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

    if (result.state !== previousState) {
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
        });
      }
    }
}

exports.handleRiderPositionWritten = handleRiderPositionWritten;

exports.onRiderPositionWritten = onDocumentWritten(
  'rides/{rideId}/riders/{userId}',
  async (event) => {
    const { rideId, userId } = event.params;
    await handleRiderPositionWritten(getFirestore(), getMessaging(), rideId, userId);
  }
);
