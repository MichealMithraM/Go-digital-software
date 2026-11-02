const db = require('../config/db');
const policy = require('../lib/attendancePolicy');
const { computeRows, payrollPolicy } = require('./hrmsPayrollController');
const { ensureCalendarOverrideTables, effectiveOverrides } = require('../lib/calendarOverrides');

function ok(res, data, message) {
  return res.json({ success: true, message: message || 'OK', data: data });
}

function fail(res, status, message) {
  return res.status(status).json({ success: false, message: message });
}

function requireAdmin(req, res, next) {
  const userType = String((req.user && req.user.userType) || '').toLowerCase();
  if (userType !== 'admin') {
    return fail(res, 403, 'Admin access required');
  }
  return next();
}

function formatSalary(value) {
  if (value === null || value === undefined || value === '') return 'Not Set';
  const amount = Number(value);
  if (!Number.isFinite(amount)) return 'Not Set';
  return '₹' + amount.toLocaleString('en-IN', {
    minimumFractionDigits: Number.isInteger(amount) ? 0 : 2,
    maximumFractionDigits: 2,
  });
}

function pad(value) {
  return String(value).padStart(2, '0');
}

function ymd(year, month, day) {
  return year + '-' + pad(month) + '-' + pad(day);
}

function utcWeekday(year, month, day) {
  return new Date(Date.UTC(year, month - 1, day)).getUTCDay();
}

function jsWeeklyOff(weeklyOff) {
  const value = Number(weeklyOff);
  if (value === 7) return 0;
  if (value >= 1 && value <= 6) return value;
  return 0;
}

function daysInMonth(year, month) {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

function nextDate(date) {
  const parts = String(date).split('-').map(Number);
  const value = new Date(Date.UTC(parts[0], parts[1] - 1, parts[2] + 1));
  return ymd(value.getUTCFullYear(), value.getUTCMonth() + 1, value.getUTCDate());
}

async function ensureCalendarOverridesTable() {
  await db.query(`CREATE TABLE IF NOT EXISTS hrms_calendar_overrides (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    work_date DATE NOT NULL,
    status ENUM('Working Day', 'Weekly Off', 'Holiday') NOT NULL,
    scope VARCHAR(64) NOT NULL DEFAULT 'All Employees',
    reason VARCHAR(500) NULL,
    notify_employees TINYINT(1) NOT NULL DEFAULT 1,
    updated_by INT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY unique_work_date (work_date)
  )`);
  await ensureCalendarOverrideTables();
}

async function getCalendarOverrides(start, end) {
  await ensureCalendarOverridesTable();
  const [rows] = await db.query(
    `SELECT DATE_FORMAT(work_date, '%Y-%m-%d') AS date, status, scope, reason,
            notify_employees AS notifyEmployees, updated_at AS savedAt
       FROM hrms_calendar_overrides
      WHERE work_date BETWEEN ? AND ? ORDER BY work_date`,
    [start, end]
  );
  return rows;
}

async function calendar(req, res) {
  try {
    const policy = await payrollPolicy();
    await ensureCalendarOverridesTable();
    const [overrides] = await db.query(
      `SELECT o.id, DATE_FORMAT(o.work_date, '%Y-%m-%d') AS date, o.status, o.scope,
              o.scope_type AS scopeType, o.department, o.reason,
              o.notify_employees AS notifyEmployees, o.updated_at AS savedAt,
              GROUP_CONCAT(t.employee_id ORDER BY t.employee_id) AS employeeIds,
              GROUP_CONCAT(COALESCE(u.full_name, '') ORDER BY t.employee_id SEPARATOR '||') AS employeeNames
         FROM hrms_calendar_overrides o
         LEFT JOIN hrms_calendar_override_targets t ON t.override_id = o.id
         LEFT JOIN employee_users u ON u.id = t.employee_id
        GROUP BY o.id ORDER BY o.work_date, o.id`
    );
    const normalized = overrides.map((row) => {
      const employeeIds = row.employeeIds ? String(row.employeeIds).split(',').map(Number) : [];
      const employeeNames = row.employeeNames ? String(row.employeeNames).split('||') : [];
      return {
        ...row,
        employeeIds,
        targetEmployees: employeeIds.map((id, index) => ({ id, name: employeeNames[index] || `Employee ${id}` })),
      };
    });
    const weeklyOff = policy.weeklyOffDays[0] ?? 0;
    return ok(res, {
      weeklyOffDay: weeklyOff === 0 ? 7 : weeklyOff,
      weeklyOffDays: policy.weeklyOffDays,
      overrides: normalized,
    });
  } catch (error) {
    return fail(res, 500, error.message);
  }
}

async function updateCalendar(req, res) {
  try {
    const body = req.body || {};
    if (body.weeklyOffDay !== undefined) {
      const day = jsWeeklyOff(body.weeklyOffDay);
      await payrollPolicy();
      await db.query('UPDATE hrms_payroll_policy SET weekly_off_days = ? WHERE id = 1', [JSON.stringify([day])]);
    }
    if (body.override) {
      const item = body.override;
      if (!/^\d{4}-\d{2}-\d{2}$/.test(String(item.date || ''))) return fail(res, 400, 'A valid date is required');
      if (!['Working Day', 'Weekly Off', 'Holiday'].includes(item.status)) return fail(res, 400, 'Invalid calendar status');
      if (!String(item.reason || '').trim()) return fail(res, 400, 'A reason is required');
      const scopeType = item.scope === 'Department' ? 'department' : item.scope === 'Selected Employees' ? 'employees' : 'all';
      const department = String(item.department || '').trim();
      const employeeIds = [...new Set((item.employeeIds || []).map(Number).filter(Number.isInteger))];
      if (scopeType === 'department' && !department) return fail(res, 400, 'Choose a department');
      if (scopeType === 'employees' && !employeeIds.length) return fail(res, 400, 'Choose at least one employee');
      await ensureCalendarOverridesTable();
      const saveOne = async (type, targetEmployeeId) => {
        let existing;
        if (type === 'all') {
          [existing] = await db.query("SELECT id FROM hrms_calendar_overrides WHERE work_date=? AND scope_type='all' LIMIT 1", [item.date]);
        } else if (type === 'department') {
          [existing] = await db.query("SELECT id FROM hrms_calendar_overrides WHERE work_date=? AND scope_type='department' AND department=? LIMIT 1", [item.date, department]);
        } else {
          [existing] = await db.query(`SELECT o.id FROM hrms_calendar_overrides o JOIN hrms_calendar_override_targets t ON t.override_id=o.id
            WHERE o.work_date=? AND o.scope_type='employees' AND t.employee_id=? LIMIT 1`, [item.date, targetEmployeeId]);
        }
        let overrideId;
        if (existing[0]) {
          overrideId = Number(existing[0].id);
          await db.query(`UPDATE hrms_calendar_overrides SET status=?, scope=?, department=?, reason=?, notify_employees=?, updated_by=? WHERE id=?`,
            [item.status, item.scope || 'All Employees', type === 'department' ? department : null, item.reason.trim(), item.notifyEmployees ? 1 : 0, req.user && req.user.id, overrideId]);
        } else {
          const [created] = await db.query(`INSERT INTO hrms_calendar_overrides
            (work_date,status,scope,scope_type,department,reason,notify_employees,updated_by)
            VALUES (?,?,?,?,?,?,?,?)`,
            [item.date, item.status, item.scope || 'All Employees', type, type === 'department' ? department : null, item.reason.trim(), item.notifyEmployees ? 1 : 0, req.user && req.user.id]);
          overrideId = Number(created.insertId);
          if (type === 'employees') await db.query('INSERT INTO hrms_calendar_override_targets (override_id, employee_id) VALUES (?,?)', [overrideId, targetEmployeeId]);
        }
        return overrideId;
      };
      const overrideIds = scopeType === 'employees'
        ? await Promise.all(employeeIds.map((employeeId) => saveOne('employees', employeeId)))
        : [await saveOne(scopeType)];
      if (item.notifyEmployees) {
        const affectedIds = scopeType === 'employees' ? employeeIds : null;
        const filter = scopeType === 'department' ? 'AND p.department = ?' : affectedIds ? 'AND u.id IN (?)' : '';
        const params = scopeType === 'department' ? [department] : affectedIds ? [affectedIds] : [];
        const [affected] = await db.query(`SELECT u.id FROM employee_users u LEFT JOIN hrms_employee_profiles p ON p.employee_user_id=u.id
          WHERE u.user_type='employee' AND u.is_active=1 ${filter}`, params);
        for (const employee of affected) {
          const overrideId = scopeType === 'employees' ? overrideIds[employeeIds.indexOf(Number(employee.id))] : overrideIds[0];
          await db.query(`INSERT INTO hrms_employee_calendar_notifications (employee_id, override_id, title, message)
            VALUES (?, ?, 'Work calendar updated', ?)
            ON DUPLICATE KEY UPDATE title=VALUES(title), message=VALUES(message), is_read=0, read_at=NULL, created_at=CURRENT_TIMESTAMP`,
            [employee.id, overrideId, `${item.date} is marked ${item.status}. ${item.reason.trim()}`]);
        }
      }
    }
    return calendar(req, res);
  } catch (error) {
    return fail(res, 400, error.message);
  }
}

async function timeSettings(req, res) {
  try {
    return ok(res, await policy.getTimeSettings(db));
  } catch (error) {
    console.error('GET /hrms/dashboard/time-settings', error);
    return fail(res, 500, error.message);
  }
}

async function updateTimeSettings(req, res) {
  try {
    return ok(res, await policy.updateTimeSettings(db, req.body || {}), 'Attendance time settings updated');
  } catch (error) {
    return fail(res, 400, error.message);
  }
}
async function monthView(req, res) {
  try {
    const year = Number(req.query.year);
    const month = Number(req.query.month);
    if (!year || month < 1 || month > 12) {
      return fail(res, 400, 'year and month (1-12) are required');
    }

    await require('../lib/employeeLifecycle').ensureLifecycle();
    const [employmentPeriods] = await db.query('SELECT * FROM employee_employment_periods');
    const payrollRules = await payrollPolicy();
    const weeklyOff = new Set(payrollRules.weeklyOffDays);
    const totalDays = daysInMonth(year, month);
    const start = ymd(year, month, 1);
    const end = ymd(year, month, totalDays);
    const today = policy.todayIstDate();
    const calendarOverrides = await getCalendarOverrides(start, end);

    // employee_users is the source of truth for who is an active employee.
    // HRMS profile data enriches the row, but a stale profile status must not
    // hide a valid employee account from the attendance dashboard.
    const [profiles] = await db.query(`
      SELECT
        profile.id, employee.is_active, profile.employment_status,
        employee.id AS employee_user_id,
        employee.full_name,
        COALESCE(NULLIF(profile.department, ''), employee.role, 'Not Set') AS department,
        COALESCE(profile.monthly_salary, 0) AS monthly_salary
      FROM employee_users AS employee
      LEFT JOIN hrms_employee_profiles AS profile
        ON profile.employee_user_id = employee.id
      WHERE employee.user_type = 'employee'
        AND (employee.is_active = 1 OR EXISTS (SELECT 1 FROM employee_employment_periods p WHERE p.employee_user_id=employee.id AND p.started_on<='${end}' AND p.ended_on>='${start}'))
      ORDER BY employee.full_name ASC
    `);

    const userIds = profiles
      .map(function (row) { return row.employee_user_id; })
      .filter(Boolean);
    const overridesByEmployee = await effectiveOverrides(start, end, profiles);

    // This is the same live calculation used by the Payroll and Employee
    // Salary screens.  The dashboard only renders calendar marks itself;
    // every salary number comes from this one shared source of truth.
    const payrollRows = await computeRows(year, month, today);
    const payrollByEmployee = new Map(
      payrollRows.map((row) => [Number(row.employeeUserId), row])
    );

    const [records] = userIds.length
      ? await db.query(
          `SELECT * FROM attendance_records
           WHERE attendance_date BETWEEN ? AND ?
             AND employee_id IN (?)`,
          [start, end, userIds]
        )
      : [[]];

    const [leaves] = userIds.length
      ? await db.query(
          `SELECT el.employee_id, el.duration_type, el.leave_type, lt.is_lop,
                  COALESCE(lt.abbreviation, '') AS abbreviation,
                  DATE_FORMAT(el.from_date, '%Y-%m-%d') AS from_date,
                  DATE_FORMAT(el.to_date, '%Y-%m-%d') AS to_date
           FROM employee_leaves el
           LEFT JOIN hrms_leave_types lt ON lt.id = el.leave_type_id
           WHERE el.status = 'APPROVED'
             AND el.from_date <= ? AND el.to_date >= ?
             AND el.employee_id IN (?)`,
          [end, start, userIds]
        )
      : [[]];

    const recordMap = new Map();
    records.forEach(function (row) {
      const attendanceDate = row.attendance_date instanceof Date
        ? ymd(row.attendance_date.getFullYear(), row.attendance_date.getMonth() + 1, row.attendance_date.getDate())
        : String(row.attendance_date).slice(0, 10);
      const key = row.employee_id + '|' + attendanceDate;
      recordMap.set(key, row);
    });

    const leaveMap = new Map();
    leaves.forEach(function (row) {
      let date = row.from_date;
      // Use admin-configured abbreviation; fall back to first 2 chars of leave name.
      const abbr = (row.abbreviation || row.leave_type.replace(/\s+/g, '').slice(0, 2)).toUpperCase() || 'L';
      const code = row.duration_type === 'Half Day' ? 'HL' : abbr;
      while (date <= row.to_date) {
        const key = row.employee_id + '|' + date;
        leaveMap.set(key, { code, leaveType: row.leave_type, abbreviation: abbr, isLop: Number(row.is_lop) === 1 });
        date = nextDate(date);
      }
    });

    let presentDays = 0;
    let absentDays = 0;
    let lateDays = 0;

    const employees = profiles.map(function (profile) {
      const payroll = payrollByEmployee.get(Number(profile.employee_user_id));
      const days = [];
      let present = 0;
      let late = 0;
      let halfLeave = 0;
      let earnedLeave = 0;
      let approvedLeave = 0;
      let unexcused = 0;
      let workingDays = 0;

      for (let day = 1; day <= totalDays; day += 1) {
        const date = ymd(year, month, day);
        const employed = require('../lib/employmentDates').employedOn(employmentPeriods.filter(p => Number(p.employee_user_id) === Number(profile.employee_user_id)), date);
        if (!employed) { days.push(''); continue; }
        const weekday = utcWeekday(year, month, day);
        const calendarOverride = overridesByEmployee.get(Number(profile.employee_user_id))?.get(date);
        const isWeeklyOff = calendarOverride
          ? calendarOverride.status === 'Weekly Off'
          : weeklyOff.has(weekday);
        if (calendarOverride && calendarOverride.status === 'Holiday') {
          days.push('H');
          continue;
        }
        if (isWeeklyOff) {
          days.push('OFF');
          continue;
        }
        const userId = profile.employee_user_id;
        const key = userId ? userId + '|' + date : '';
        const record = key ? recordMap.get(key) : null;
        const leaveInfo = key ? leaveMap.get(key) : null;
        const leaveType = leaveInfo ? leaveInfo.code : null;

        // Future dates stay blank, except for leave that is already approved.
        if (date > today && !leaveType) {
          days.push('');
          continue;
        }

        workingDays += 1;

        // An automatic absence deliberately has no check-in time.  Check its
        // persisted status first so it is shown as A instead of an empty dash.
        if (record && String(record.attendance_status) === 'absent') {
          days.push('A');
          if (payrollRules.deductExplicitAbsence) {
            unexcused += 1;
            absentDays += 1;
          }
        // A recorded clock-in is the final decision for that date. Leave is
        // shown only when the employee has no attendance record.
        } else if (record && (record.check_in_at || String(record.attendance_status) === 'present')) {
          if (Number(record.is_late) && !record.admin_status_override) {
            days.push('LT');
            late += 1;
            lateDays += 1;
          } else {
            days.push('P');
            present += 1;
            presentDays += 1;
          }
        } else if (leaveType) {
          days.push(leaveType);
          approvedLeave += 1;
          if (leaveType === 'HL') halfLeave += 1;
          if (leaveInfo.leaveType === 'Earned Leave' || leaveInfo.abbreviation === 'EL') earnedLeave += 1;
          if (date <= today && leaveInfo.isLop) unexcused += leaveType === 'HL' ? 0.5 : 1;
        } else {
          // A missing record is unrecorded during development, not absent.
          days.push('–');
          if (date <= today && payrollRules.missingAttendanceIsAbsent) { unexcused += 1; absentDays += 1; }
        }
      }

      const salaryNumber = payroll ? Number(payroll.monthlySalary || 0) : Number(profile.monthly_salary || 0);
      const lopDays = payroll ? Number(payroll.lopDays || 0) : Math.min(workingDays, unexcused);
      const paidDays = payroll ? Number(payroll.paidDays || 0) : Math.max(0, workingDays - lopDays);
      const deduction = payroll ? Number(payroll.deductions || 0) : Math.min(salaryNumber, Math.ceil(lopDays * (salaryNumber && workingDays > 0 ? salaryNumber / workingDays : 0)));
      const dailyRate = salaryNumber && workingDays > 0 ? salaryNumber / workingDays : 0;
      const earnedToDate = Math.max(0, Math.min(salaryNumber, paidDays * dailyRate));
      const afterLeaves = payroll ? Number(payroll.netPay || 0) : earnedToDate;

      return {
        id: profile.id,
        employeeUserId: profile.employee_user_id,
        name: profile.full_name + (Number(profile.is_active) ? '' : ' (Inactive)'),
        employmentStatus: Number(profile.is_active) ? 'Active' : 'Inactive',
        designation: profile.department,
        department: profile.department,
        days: days,
        present: payroll ? Number(payroll.presentDays || 0) : present,
        late: payroll ? Number(payroll.lateDays || 0) : late,
        excused: halfLeave,
        unexcused: payroll ? Number(payroll.absentDays || 0) : unexcused,
        halfLeave: halfLeave,
        earnedLeave: earnedLeave,
        approvedLeave: payroll ? Number(payroll.leaveDays || 0) : approvedLeave,
        salary: payroll ? payroll.salary : formatSalary(profile.monthly_salary),
        daysPaid: String(lopDays),
        deductedDays: lopDays,
        afterLeaves: payroll ? payroll.deductionsLabel : (salaryNumber ? formatSalary(deduction) : '–'),
        updatedSalary: payroll ? payroll.netPayLabel : (salaryNumber ? formatSalary(afterLeaves) : '–'),
        earnedToDate: payroll ? payroll.earnedToDateLabel : (salaryNumber ? formatSalary(earnedToDate) : '–'),
        creditedDays: payroll
          ? (String(payroll.status).toLowerCase() === 'paid' ? payroll.paidDays : payroll.paidDaysToDate) ?? null
          : paidDays,
        workingDays: payroll ? Number(payroll.workingDays || 0) : workingDays,
        dailySalary: payroll ? Number(payroll.dailyRate || 0) : dailyRate,
        paidDays: paidDays,
        paidLeaveDays: payroll ? Number(payroll.paidLeaveDays || 0) : 0,
        lopLeaveDays: payroll ? Number(payroll.lopLeaveDays || 0) : 0,
        absentDays: payroll ? Number(payroll.absentDays || 0) : absentDays,
        deductions: deduction,
      };
    });

    // Day-wise KPIs reflect *today* specifically (a live snapshot) rather
    // than a month-to-date total, independent of whichever month/year is
    // being browsed in the calendar below.
    const [todayYear, todayMonth, todayDay] = today.split('-').map(Number);
    const todayWeekday = utcWeekday(todayYear, todayMonth, todayDay);
    let todayPresent = 0;
    let todayAbsent = 0;
    let todayLate = 0;

    if (userIds.length) {
      const [todayRecords] = await db.query(
        `SELECT * FROM attendance_records WHERE attendance_date = ? AND employee_id IN (?)`,
        [today, userIds]
      );
      const [todayLeaves] = await db.query(
        `SELECT employee_id FROM employee_leaves
         WHERE status = 'APPROVED' AND from_date <= ? AND to_date >= ? AND employee_id IN (?)`,
        [today, today, userIds]
      );
      const todayRecordMap = new Map();
      todayRecords.forEach(function (row) { todayRecordMap.set(row.employee_id, row); });
      const todayLeaveSet = new Set(todayLeaves.map(function (row) { return row.employee_id; }));

      profiles.forEach(function (profile) {
        const todayOverride = overridesByEmployee.get(Number(profile.employee_user_id))?.get(today);
        const todayIsOff = todayOverride ? todayOverride.status !== 'Working Day' : weeklyOff.has(todayWeekday);
        if (todayIsOff) return;
        const userId = profile.employee_user_id;
        const record = userId ? todayRecordMap.get(userId) : null;
        if (record && String(record.attendance_status) === 'absent') {
          if (payrollRules.deductExplicitAbsence) todayAbsent += 1;
        } else if (record && (record.check_in_at || String(record.attendance_status) === 'present')) {
          if (Number(record.is_late) && !record.admin_status_override) {
            todayLate += 1;
          } else {
            todayPresent += 1;
          }
        } else if (!todayLeaveSet.has(userId) && payrollRules.missingAttendanceIsAbsent) {
          todayAbsent += 1;
        }
      });
    }

    // Compute company-wide working days (only all-employees scope overrides)
    const allOverrideMap = new Map();
    calendarOverrides.forEach(function (o) {
      if (!o.scope || o.scope === 'All Employees') allOverrideMap.set(o.date, o.status);
    });
    let monthWorkingDays = 0;
    for (let day = 1; day <= totalDays; day += 1) {
      const date = ymd(year, month, day);
      const weekday = utcWeekday(year, month, day);
      const overrideStatus = allOverrideMap.get(date);
      const isOff = overrideStatus
        ? overrideStatus !== 'Working Day'
        : weeklyOff.has(weekday);
      if (!isOff) monthWorkingDays += 1;
    }

    return ok(res, {
      year: year,
      month: month,
      daysInMonth: totalDays,
      timezone: policy.TIME_ZONE,
      payrollPolicy: { weeklyOffDays: [...payrollRules.weeklyOffDays], deductExplicitAbsence: payrollRules.deductExplicitAbsence, missingAttendanceIsAbsent: payrollRules.missingAttendanceIsAbsent },
      calendarOverrides: calendarOverrides,
      kpis: {
        totalEmployees: profiles.length,
        present: todayPresent,
        absent: todayAbsent,
        late: todayLate,
        workingDays: monthWorkingDays,
      },
      employees: employees,
    });
  } catch (error) {
    console.error('GET /hrms/dashboard', error);
    return fail(res, 500, error.message);
  }
}

module.exports = {
  requireAdmin,
  monthView,
  calendar,
  updateCalendar,
  timeSettings,
  updateTimeSettings,
};
