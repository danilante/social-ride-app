const { distanceMeters, centroid } = require('./geo');

const DEFAULT_THRESHOLD_METERS = 300;
const DWELL_MS = 60 * 1000;

function evaluateRider(rider, otherRiders, now, thresholdMeters = DEFAULT_THRESHOLD_METERS) {
  if (otherRiders.length === 0) {
    return { state: 'in_group', distanceFromGroupMeters: 0, thresholdExceededSince: null };
  }

  const inGroupRiders = otherRiders.filter((r) => r.state !== 'dropped_off');
  if (inGroupRiders.length === 0) {
    return { state: 'in_group', distanceFromGroupMeters: 0, thresholdExceededSince: null };
  }

  const groupCenter = centroid(inGroupRiders.map((r) => ({ lat: r.lat, lng: r.lng })));
  const distance = distanceMeters(rider.lat, rider.lng, groupCenter.lat, groupCenter.lng);
  const overThreshold = distance > thresholdMeters;

  let exceededSince = rider.thresholdExceededSince;
  if (!overThreshold) {
    exceededSince = null;
  } else if (!exceededSince) {
    exceededSince = now;
  }

  const droppedOff = overThreshold && exceededSince && now - exceededSince >= DWELL_MS;

  return {
    state: droppedOff ? 'dropped_off' : 'in_group',
    distanceFromGroupMeters: distance,
    thresholdExceededSince: overThreshold ? exceededSince : null,
  };
}

module.exports = { evaluateRider, DEFAULT_THRESHOLD_METERS, DWELL_MS };
