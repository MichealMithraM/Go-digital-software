const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function setup() {
  const calls = [];
  const state = {
    settings: { home_radius_meters: 345, office_radius_meters: 678, home_no_gps_timeout_minutes: 7 },
    breaks: [],
    record: { id: 70, employee_id: 7, date_key: '2026-11-02', work_mode_snapshot: 'Home',
      check_in_iso: '2026-11-02T09:00:00+05:30', check_out_iso: null, is_late: 1,
      attendance_status: 'present', session_status: 'active', check_in_method: 'gps', working_minutes: 61 },
    home: { employee_user_id: 7, approval_status: 'approved', latitude: '13.1', longitude: '80.2', address: 'Registered home' },
  };
  class Clock extends Date { static now() { return Date.parse('2026-11-02T10:01:00+05:30'); } }
  const query = async (sql, params) => {
    calls.push({ sql, params });
    if (sql.includes('FROM hrms_employee_profiles p')) return [[{ id: 1, employee_user_id: 7, full_name: 'Ravi', employee_code: 'E7', work_mode: 'Home' }]];
    if (sql.includes('FROM hrms_tracking_settings')) return [[state.settings]];
    if (sql.includes('FROM attendance_records r')) return [[state.record]];
    if (sql.includes('FROM attendance_breaks b')) {
      if (state.breakError) throw state.breakError;
      return [state.breaks];
    }
    if (sql.includes('FROM hrms_employee_home_locations')) return [[state.home]];
    if (sql.includes('FROM hrms_employee_location_status')) return [[{ employee_user_id: 7, status: 'office' }]];
    if (sql.includes('FROM hrms_location_pings p')) return [[{ employee_user_id: 7, latitude: 13.1, longitude: 80.2,
      accuracy_meters: '18.5', recorded_iso: '2026-11-02T09:56:00+05:30', address: 'Current GPS address' }]];
    throw Error('Unexpected SQL: ' + sql);
  };
  const moduleState = { exports: {} };
  vm.runInNewContext(fs.readFileSync(require.resolve('./hrmsTrackingController'), 'utf8'), {
    module: moduleState, console, Date: Clock, Map, Set,
    require: p => p === '../config/db' ? { query } : p === '../lib/attendancePolicy'
      ? { todayIstDate: () => '2026-11-02' } : p === '../lib/employeeLifecycle' ? { ensureLifecycle: async () => {} } : {},
  });
  async function run(date = '2026-11-02') {
    let body, status = 200;
    await moduleState.exports.liveOverview({ query: { date } }, { status(v) { status = v; return this; }, json(v) { body = v; } });
    return { body, status };
  }
  return { state, calls, run };
}

test('live Home tracking returns selected attendance, actual GPS and saved admin settings', async () => {
  const { run, calls } = setup();
  const { body, status } = await run();
  assert.equal(status, 200);
  const row = body.data.items[0];
  assert.equal(row.status, 'home');
  assert.equal(row.checkInAt, '2026-11-02T09:00:00+05:30');
  assert.equal(row.checkOutAt, null);
  assert.equal(row.isLate, true);
  assert.equal(row.accuracyMeters, 18.5);
  assert.equal(row.homeLatitude, 13.1);
  assert.equal(row.homeRadiusMeters, 345);
  assert.equal(row.officeRadiusMeters, 678);
  assert.equal(row.active, true);
  assert.equal(body.data.counts.home, 1);
  assert.equal(body.data.counts.office, 0);
  const ping = calls.find(c => c.sql.includes('FROM hrms_location_pings p'));
  assert.equal(ping.params[1], '2026-11-02');
  assert.equal(ping.params[2], '2026-11-02');
});
test('check-out is dynamic and stops the active badge', async () => {
  const { state, run } = setup();
  state.record.check_out_iso = '2026-11-02T10:00:00+05:30';
  const row = (await run()).body.data.items[0];
  assert.equal(row.checkOutAt, state.record.check_out_iso);
  assert.equal(row.active, false);
});

test('Office map header receives actual check-in and check-out, using Office admin timeout', async () => {
  const { state, run } = setup();
  state.record.work_mode_snapshot = 'Office';
  state.settings.office_no_gps_timeout_minutes = 11;
  let row = (await run()).body.data.items[0];
  assert.equal(row.status, 'office');
  assert.equal(row.checkInAt, state.record.check_in_iso);
  assert.equal(row.checkOutAt, null);
  assert.equal(row.active, true);
  state.record.check_out_iso = '2026-11-02T10:00:00+05:30';
  row = (await run()).body.data.items[0];
  assert.equal(row.checkOutAt, state.record.check_out_iso);
  assert.equal(row.active, false);
});
test('freshness follows admin timeout and missing configuration is not invented', async () => {
  const { state, run } = setup();
  state.settings.home_no_gps_timeout_minutes = 4;
  assert.equal((await run()).body.data.items[0].active, false);
  state.settings.home_radius_meters = null;
  delete state.settings.home_no_gps_timeout_minutes;
  const row = (await run()).body.data.items[0];
  assert.equal(row.homeRadiusMeters, null);
  assert.equal(row.active, false);
  assert.equal(row.checkInAt, state.record.check_in_iso);
});
test('another selected day never borrows today check-in and is not live', async () => {
  const { run } = setup();
  const row = (await run('2026-11-01')).body.data.items[0];
  assert.equal(row.attendanceDate, '2026-11-01');
  assert.equal(row.checkInAt, null);
  assert.equal(row.active, false);
});
test('unapproved Home coordinates are not represented as an approved Home', async () => {
  const { state, run } = setup();
  state.home.approval_status = 'pending';
  const row = (await run()).body.data.items[0];
  assert.equal(row.homeApprovalStatus, 'pending');
  assert.equal(row.homeLatitude, null);
  assert.equal(row.homeLongitude, null);
});
test('invalid calendar dates fail before reading data', async () => {
  const { run, calls } = setup();
  for (const date of ['bad', '2026-13-02', '2026-02-30']) assert.equal((await run(date)).status, 400);
  assert.equal(calls.length, 0);
});

test('break start/end follows the active break record, not the attendance session label', async () => {
  const { state, run, calls } = setup();
  state.breaks = [{ attendance_id: 70 }];
  assert.equal((await run()).body.data.items[0].onBreak, true);
  assert.equal(state.record.session_status, 'active');
  const query = calls.find(c => c.sql.includes('FROM attendance_breaks b'));
  assert.match(query.sql, /b.status = 'active'.*b.ended_at IS NULL/);
  assert.equal(query.params[1], '2026-11-02');
  state.breaks = [];
  assert.equal((await run()).body.data.items[0].onBreak, false);
  state.breaks = [{ attendance_id: 999 }];
  assert.equal((await run()).body.data.items[0].onBreak, false);
  state.breaks = [{ attendance_id: 70 }];
  state.record.check_out_iso = '2026-11-02T10:00:00+05:30';
  assert.equal((await run()).body.data.items[0].onBreak, false);
});

test('a fresh installation with no recorded breaks still shows attendance', async () => {
  const { state, run } = setup();
  state.breakError = { code: 'ER_NO_SUCH_TABLE', sqlMessage: 'Table test.attendance_breaks does not exist' };
  const { body, status } = await run();
  assert.equal(status, 200);
  assert.equal(body.data.items[0].onBreak, false);
  assert.equal(body.data.items[0].checkInAt, state.record.check_in_iso);
});
