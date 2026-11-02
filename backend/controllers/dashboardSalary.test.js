const { test } = require('node:test');
const assert = require('node:assert/strict');

let fixture;
const profile = { id: 1, employee_user_id: 7, full_name: 'Ravi', is_active: 1, department: 'Design', monthly_salary: 31000 };
const query = async sql => {
  if (/CREATE TABLE/.test(sql)) return [[]];
  if (/FROM employee_users AS employee/.test(sql)) return [[profile]];
  if (/FROM employee_employment_periods/.test(sql)) return [[{ employee_user_id: 7, started_on: '2020-01-01', ended_on: null }]];
  if (/FROM hrms_calendar_overrides/.test(sql)) return [[]];
  if (/FROM attendance_records/.test(sql)) return [[]];
  if (/FROM employee_leaves/.test(sql)) return [[]];
  throw new Error('Unexpected SQL: ' + sql);
};
require.cache[require.resolve('../config/db')] = { exports: { query } };
require.cache[require.resolve('../lib/attendancePolicy')] = { exports: { TIME_ZONE: 'Asia/Kolkata', todayIstDate: () => '2026-12-31' } };
require.cache[require.resolve('../lib/employeeLifecycle')] = { exports: { ensureLifecycle: async () => {} } };
require.cache[require.resolve('../lib/calendarOverrides')] = { exports: {
  ensureCalendarOverrideTables: async () => {},
  effectiveOverrides: async () => new Map([[7, new Map(fixture.holidays)]]),
} };
require.cache[require.resolve('./hrmsPayrollController')] = { exports: {
  payrollPolicy: async () => fixture.rules,
  computeRows: async (...args) => { fixture.calculation = args; return fixture.payroll; },
} };
const { monthView } = require('./hrmsDashboardController');

function reset() {
  fixture = {
    rules: { weeklyOffDays: [0], deductExplicitAbsence: true, missingAttendanceIsAbsent: false },
    holidays: [],
    payroll: [],
  };
}

async function month(month = 10) {
  let payload;
  const res = {
    status(code) { assert.fail('Unexpected response status ' + code); },
    json(data) { payload = data; return data; },
  };
  await monthView({ query: { year: 2026, month } }, res);
  assert.equal(payload.success, true);
  return payload.employees || payload.data.employees;
}

test('dashboard salary and deducted days come from the shared payroll result', async () => {
  reset();
  fixture.payroll = [{ employeeUserId: 7, monthlySalary: 33600, salary: '₹33,600', dailyRate: 1600,
    workingDays: 21, lopDays: 2.5, paidDays: 18.5, paidDaysToDate: 9.5, deductions: 4000,
    deductionsLabel: '₹4,000', netPayLabel: '₹29,600', earnedToDateLabel: '₹15,200' }];
  const [row] = await month();
  assert.deepEqual(fixture.calculation, [2026, 10, '2026-12-31']);
  assert.equal(row.salary, '₹33,600');
  assert.equal(row.dailySalary, 1600);
  assert.equal(row.deductedDays, 2.5);
  assert.equal(row.daysPaid, '2.5');
  assert.equal(row.afterLeaves, '₹4,000');
  assert.equal(row.updatedSalary, '₹29,600');
  assert.equal(row.earnedToDate, '₹15,200');
  assert.equal(row.creditedDays, 9.5);
});

test('different selected months use their own payroll values', async () => {
  reset();
  fixture.payroll = [{ employeeUserId: 7, monthlySalary: 31000, dailyRate: 1200, lopDays: 1, paidDaysToDate: 2 }];
  const [october] = await month(10);
  assert.equal(october.deductedDays, 1);
  assert.equal(october.creditedDays, 2);
  fixture.payroll = [{ employeeUserId: 7, monthlySalary: 35000, dailyRate: 1400, lopDays: 3.5, paidDaysToDate: 4.5 }];
  const [row] = await month(11);
  assert.deepEqual(fixture.calculation, [2026, 11, '2026-12-31']);
  assert.equal(row.dailySalary, 1400);
  assert.equal(row.deductedDays, 3.5);
  assert.equal(row.creditedDays, 4.5);
});

test('paid payroll uses the saved credited days matching its saved salary', async () => {
  reset();
  fixture.payroll = [{ employeeUserId: 7, status: 'Paid', monthlySalary: 33600,
    paidDays: 18.5, paidDaysToDate: 9.5, netPayLabel: '₹29,600', earnedToDateLabel: '₹29,600' }];
  const [row] = await month();
  assert.equal(row.updatedSalary, '₹29,600');
  assert.equal(row.creditedDays, 18.5);
});

test('zero credited days are preserved and missing counts are not invented', async () => {
  reset();
  fixture.payroll = [{ employeeUserId: 7, status: 'Draft', paidDays: 21, paidDaysToDate: 0 }];
  assert.equal((await month())[0].creditedDays, 0);
  delete fixture.payroll[0].paidDaysToDate;
  assert.equal((await month())[0].creditedDays, null);
});

test('monthly updated salary remains separate from zero earned salary', async () => {
  reset();
  fixture.payroll = [{ employeeUserId: 7, monthlySalary: 50000, deductionsLabel: '₹2,000',
    netPayLabel: '₹48,000', earnedToDateLabel: '₹0', paidDaysToDate: 0 }];
  const [row] = await month();
  assert.equal(row.updatedSalary, '₹48,000');
  assert.equal(row.earnedToDate, '₹0');
  assert.equal(row.creditedDays, 0);
});

test('daily salary fallback follows configured weekly offs and holidays', async () => {
  reset();
  fixture.rules.weeklyOffDays = [0, 6];
  fixture.holidays = [['2026-10-02', { status: 'Holiday' }]];
  const [holidayMonth] = await month(10);
  assert.equal(holidayMonth.workingDays, 21);
  assert.equal(holidayMonth.dailySalary, 31000 / 21);
  assert.equal(holidayMonth.creditedDays, 21);
  fixture.rules.weeklyOffDays = [0];
  fixture.holidays = [];
  const [sundayOnly] = await month(10);
  assert.equal(sundayOnly.workingDays, 27);
  assert.equal(sundayOnly.dailySalary, 31000 / 27);
  assert.equal(sundayOnly.creditedDays, 27);
});
