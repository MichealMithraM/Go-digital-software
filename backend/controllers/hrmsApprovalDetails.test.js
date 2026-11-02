const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const moduleState = { exports: {} };
vm.runInNewContext(fs.readFileSync(require.resolve('./hrmsApprovalsController'), 'utf8') + '\nmodule.exports = { toUi };', {
  module: moduleState, require: () => ({}), console, Date,
});
const { toUi } = moduleState.exports;
const leave = { id: 11, employee_id: 3, full_name: 'Arun babu', staff_id: '173540696',
  request_type: 'earned_leave', status: 'approved', request_date: '2026-10-07',
  from_date: '2026-10-07', to_date: '2026-10-07', el_leave_type: 'Earned Leave', duration_type: 'Full Day',
  reason: 'Earned Leave · Full Day · 2026-10-07 to 2026-10-07\ndsf', leave_reason: 'dsf' };

test('linked leave shows the employee reason without generated metadata', () => {
  const row = toUi(leave);
  assert.equal(row.reason, 'dsf');
  assert.equal(row.dates, '7 Oct 2026');
  assert.equal(row.duration, '1 Day');
  assert.equal(row.type, 'Earned Leave');
  assert.equal(row.name, 'Arun babu');
  assert.equal(row.employeeCode, '173540696');
  assert.equal(row.status, 'Approved');
  assert.equal(row.id, 11);
});
test('multi-day leave uses full original range and duration', () => {
  const row = toUi({ ...leave, request_date: '2026-10-09', to_date: '2026-10-10' });
  assert.equal(row.dates, '7 Oct 2026 – 10 Oct 2026');
  assert.equal(row.startDate, '2026-10-07');
  assert.equal(row.endDate, '2026-10-10');
  assert.equal(row.duration, '4 Days');
});
test('half-day and blank original reason are preserved without metadata fallback', () => {
  const row = toUi({ ...leave, duration_type: 'Half Day', leave_reason: '' });
  assert.equal(row.duration, 'Half Day');
  assert.equal(row.reason, '');
});
test('stored leave days remain authoritative for duration', () => {
  assert.equal(toUi({ ...leave, to_date: '2026-10-10', leave_days: '2.00' }).duration, '2 Days');
});
test('permission duration comes from stored start and end times', () => {
  const row = toUi({ request_type: 'permission', reason: 'Doctor visit', request_date: '2026-11-02',
    permission_start_time: '09:30:00', permission_end_time: '11:00:00' });
  assert.equal(row.reason, 'Doctor visit');
  assert.equal(row.duration, '1h 30m');
  assert.equal(row.type, 'Permission');
  assert.equal(row.dates, '2 Nov 2026');
});
test('missing permission times are not reported as a full day', () => {
  assert.equal(toUi({ request_type: 'permission' }).duration, '—');
});
test('WFH preserves its own reason and inclusive dates', () => {
  const row = toUi({ request_type: 'wfh', request_date: '2026-11-02', wfh_end_date: '2026-11-04', reason: 'At home' });
  assert.equal(row.dates, '2 Nov 2026 – 4 Nov 2026');
  assert.equal(row.duration, '3 Days');
  assert.equal(row.reason, 'At home');
});
