const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { evaluateRider } = require('./dropoff');

initializeApp();

exports.onRiderPositionWritten = onDocumentWritten(
  'rides/{rideId}/riders/{userId}',
  async (event) => {
    const { rideId, userId } = event.params;
    const db = getFirestore();
    const ridersSnap = await db
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .get();

    const riders = ridersSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
    const rider = riders.find((r) => r.id === userId);
    if (!rider || rider.lat == null || rider.lng == null) return;

    const others = riders.filter(
      (r) => r.id !== userId && r.lat != null && r.lng != null
    );
    const previousState = rider.state || 'in_group';
    const result = evaluateRider(rider, others, Date.now());

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
        await getMessaging().sendEachForMulticast({
          tokens,
          notification: { title, body },
        });
      }
    }
  }
);
