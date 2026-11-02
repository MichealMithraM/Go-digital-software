const policy = require('./attendanceLocationPolicy');

function validateHomeRegistration(body, radius, now) {
  const source = body.captureSource ?? 'gps';
  if (source === 'gps') return { ...policy.validateFix(body, radius, now), captureSource: 'gps' };
  if (source !== 'map_pin') throw new policy.LocationPolicyError(400, 'Choose GPS capture or a Home map pin.');
  if (typeof body.address !== 'string' || !body.address.trim() || body.address.trim().length > 500) {
    throw new policy.LocationPolicyError(400, 'Enter the Home address for admin verification.');
  }
  // A manually chosen pin is never described or stored as a GPS measurement.
  return { ...policy.coordinates(body.latitude, body.longitude), accuracy: null, captureSource: 'map_pin' };
}
module.exports = { validateHomeRegistration };
