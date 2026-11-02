const {test} = require('node:test');
const assert = require('node:assert/strict');
const {validateHomeRegistration} = require('./homeLocationRegistration');
const policy = require('./attendanceLocationPolicy');
test('manual Home pin has no invented GPS accuracy or timestamp', () => {
  const fix = validateHomeRegistration({captureSource:'map_pin',latitude:13,longitude:80,address:'My home',accuracy:0},100);
  assert.deepEqual(fix,{latitude:13,longitude:80,accuracy:null,captureSource:'map_pin'});
});
test('manual selection requires a valid pin, supported source and address', () => {
  for(const body of [
    {captureSource:'map_pin',latitude:13,longitude:80,address:''},
    {captureSource:'map_pin',latitude:91,longitude:80,address:'Home'},
    {captureSource:'map_pin',latitude:'',longitude:80,address:'Home'},
    {captureSource:'other',latitude:13,longitude:80,address:'Home'},
  ]) assert.throws(()=>validateHomeRegistration(body,100));
});
test('GPS registration still uses the admin radius and fresh GPS', () => {
  const body={latitude:13,longitude:80,accuracy:250,capturedAt:new Date().toISOString()};
  assert.throws(()=>validateHomeRegistration(body,100),/GPS accuracy/);
  assert.equal(validateHomeRegistration(body,300).captureSource,'gps');
  assert.throws(()=>validateHomeRegistration({...body,capturedAt:'2000-01-01T00:00:00Z'},300),/fresh GPS/);
});
test('a manual pin cannot replace GPS validation during Home check-in', () => {
  assert.throws(()=>policy.validateCheckIn({requiresLocation:true,workMode:'Home',radiusMeters:100,center:{latitude:13,longitude:80}},
    {captureSource:'map_pin',latitude:13,longitude:80,address:'Home'}),/GPS accuracy/);
});
