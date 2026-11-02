const db = require('../config/db');
const policy = require('../lib/attendancePolicy');
const staff = require('../lib/staffDirectory');

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

const LEAVE_TYPES = ['leave', 'risk_leave', 'annual_leave', 'sick_leave', 'personal_leave', 'casual_leave', 'earned_leave', 'optional_holiday'];
const EXTRA_TYPES = ['extra_hours', 'late_entry', 'early_exit'];
const leaveSystem = require('../lib/leaveSystem');

function displayType(requestType) {
  const value = String(requestType || '').toLowerCase();
  if (value === 'casual_leave') return 'Casual Leave';
  if (value === 'earned_leave') return 'Earned Leave';
  if (value === 'optional_holiday') return 'Optional Holiday';
  if (value === 'annual_leave' || value === 'leave') return 'Annual Leave';
  if (value === 'sick_leave') return 'Sick Leave';
  if (value === 'personal_leave' || value === 'risk_leave') return 'Personal Leave';
  if (value === 'extra_hours') return 'Extra Hours';
  if (value === 'late_entry') return 'Late Entry';
  if (value === 'early_exit') return 'Early Exit';
  if (value === 'wfh') return 'Work From Home';
  if (value === 'permission') return 'Permission';
  return String(requestType || '').replace(/_/g, ' ');
}

function iconMeta(typeLabel) {
  if (typeLabel === 'Sick Leave') return { icon: 'medical', color: 0xFFFF4F62 };
  if (typeLabel === 'Personal Leave') return { icon: 'event_busy', color: 0xFFFF6D3A };
  if (typeLabel === 'Extra Hours' || typeLabel === 'Late Entry' || typeLabel === 'Early Exit') {
    return { icon: 'more_time', color: 0xFFFF6500 };
  }
  if (typeLabel === 'Work From Home') return { icon: 'home', color: 0xFF0B72F5 };
  return { icon: 'beach', color: 0xFF7137E8 };
}

function toIsoDate(value) {
  if (!value) return '';
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    const year = value.getUTCFullYear();
    const month = String(value.getUTCMonth() + 1).padStart(2, '0');
    const day = String(value.getUTCDate()).padStart(2, '0');
    return year + '-' + month + '-' + day;
  }
  const match = String(value).match(/(\d{4}-\d{2}-\d{2})/);
  return match ? match[1] : '';
}

function formatDay(value) {
  const date = toIsoDate(value);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    return { pretty: '—', weekday: '—', iso: '' };
  }
  const [year, month, day] = date.split('-').map(Number);
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const weekday = weekdays[new Date(Date.UTC(year, month - 1, day)).getUTCDay()];
  return {
    pretty: day + ' ' + months[month - 1] + ' ' + year,
    weekday: weekday,
    iso: date,
  };
}

function leaveDuration(row) {
  if (String(row.duration_type || '').toLowerCase() === 'half day') return 'Half Day';
  const savedDays = Number(row.leave_days);
  if (Number.isFinite(savedDays) && savedDays > 0) return `${savedDays} ${savedDays === 1 ? 'Day' : 'Days'}`;
  const from = toIsoDate(row.from_date || row.request_date);
  const to = toIsoDate(row.to_date || row.request_date);
  if (!from || !to) return '1 Day';
  const days = Math.max(1, Math.round((Date.parse(to + 'T00:00:00Z') - Date.parse(from + 'T00:00:00Z')) / 86400000) + 1);
  return days + (days === 1 ? ' Day' : ' Days');
}

function toUi(row) {
  // Prefer the actual leave type name from employee_leaves when available
  const actualType = row.el_leave_type || null;
  const type = actualType || displayType(row.request_type);
  const abbreviation = row.lt_abbreviation || null;
  const start = formatDay(row.from_date || row.el_from_date || row.request_date);
  const requestType = String(row.request_type).toLowerCase();
  const extra = EXTRA_TYPES.indexOf(requestType) !== -1;
  const leave = LEAVE_TYPES.indexOf(requestType) !== -1;
  const meta = iconMeta(type);
  const wfhEnd = toIsoDate(row.wfh_end_date);
  const wfhDays = requestType === 'wfh' && wfhEnd
    ? Math.max(1, Math.round((Date.parse(wfhEnd + 'T00:00:00Z') - Date.parse(start.iso + 'T00:00:00Z')) / 86400000) + 1)
    : 0;
  const endDate = toIsoDate(row.wfh_end_date || row.to_date) || start.iso;
  const reason = row.leave_reason != null ? String(row.leave_reason) : String(row.reason || '');
  let duration = extra ? '—' : requestType === 'wfh' && wfhDays ? `${wfhDays} ${wfhDays === 1 ? 'Day' : 'Days'}` : leaveDuration(row);
  if (requestType === 'permission') {
    const minutes = value => { const match = /^(\d{2}):(\d{2})/.exec(String(value || '')); return match ? Number(match[1]) * 60 + Number(match[2]) : null; };
    const from = minutes(row.permission_start_time), to = minutes(row.permission_end_time);
    const total = from != null && to != null ? to - from : 0;
    duration = total > 0 ? [Math.floor(total / 60) ? `${Math.floor(total / 60)}h` : '', total % 60 ? `${total % 60}m` : ''].filter(Boolean).join(' ') : '—';
  }
  return {
    id: row.id,
    name: String(row.full_name || 'Unknown employee').trim(),
    employeeCode: row.staff_id || ('EMP' + row.employee_id),
    type: type,
    abbreviation: abbreviation,
    requestType: row.request_type,
    dates: endDate && endDate !== start.iso ? `${start.pretty} – ${formatDay(endDate).pretty}` : (start.pretty || '—'),
    dayRange: start.weekday && start.weekday !== '—' ? '(' + start.weekday + ')' : '',
    duration,
    reason: reason.trim(),
    status: String(row.status || 'pending').replace(/^./, function (c) { return c.toUpperCase(); }),
    icon: meta.icon,
    color: meta.color,
    tab: extra ? 'extra' : leave ? 'leave' : 'permission',
    startDate: start.iso || null,
    endDate: endDate || null,
    homeLocation: row.home_latitude == null ? null : {
      latitude: Number(row.home_latitude),
      longitude: Number(row.home_longitude),
      accuracyMeters: Number(row.home_accuracy_meters),
      address: row.home_address || null,
    },
  };
}

async function ensureAdminNotifications() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS hrms_admin_notifications (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      approval_request_id BIGINT UNSIGNED NOT NULL,
      title VARCHAR(160) NOT NULL,
      message VARCHAR(500) NOT NULL,
      is_read TINYINT(1) NOT NULL DEFAULT 0,
      read_at DATETIME NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      UNIQUE KEY uniq_approval_notification (approval_request_id)
    )
  `);
}

async function syncPendingNotifications() {
  await ensureAdminNotifications();
  await db.query(`
    INSERT IGNORE INTO hrms_admin_notifications (approval_request_id, title, message)
    SELECT p.id,
           CONCAT('New ', REPLACE(p.request_type, '_', ' '), ' request'),
           CONCAT(COALESCE(u.full_name, CONCAT('Employee #', p.employee_id)), ' submitted a request for approval.')
    FROM attendance_permission_requests p
    LEFT JOIN employee_users u ON u.id = p.employee_id
    WHERE p.status = 'pending'
  `);
}

async function ensureWfhRequestColumns() {
  const columns = [
    ['wfh_end_date', 'DATE NULL AFTER request_date'],
    ['permission_start_time', 'TIME NULL AFTER request_date'],
    ['permission_end_time', 'TIME NULL AFTER permission_start_time'],
    ['home_latitude', 'DECIMAL(10,7) NULL AFTER wfh_end_date'],
    ['home_longitude', 'DECIMAL(10,7) NULL AFTER home_latitude'],
    ['home_accuracy_meters', 'DECIMAL(10,2) NULL AFTER home_longitude'],
    ['home_captured_at', 'DATETIME NULL AFTER home_accuracy_meters'],
    ['home_address', 'VARCHAR(500) NULL AFTER home_captured_at'],
  ];
  for (const [name, definition] of columns) {
    const [found] = await db.query(`SHOW COLUMNS FROM attendance_permission_requests LIKE '${name}'`);
    if (!found.length) await db.query(`ALTER TABLE attendance_permission_requests ADD COLUMN ${name} ${definition}`);
  }
}

async function notifications(req, res) {
  try {
    await syncPendingNotifications();
    const [rows] = await db.query(`
      SELECT id, approval_request_id, title, message, is_read, created_at
      FROM hrms_admin_notifications
      ORDER BY created_at DESC
      LIMIT 12
    `);
    const [counts] = await db.query(
      'SELECT COUNT(*) AS total FROM hrms_admin_notifications WHERE is_read = 0'
    );
    return ok(res, {
      unreadCount: Number(counts[0] && counts[0].total || 0),
      items: rows.map(function (row) {
        return {
          id: row.id,
          approvalRequestId: row.approval_request_id,
          title: row.title,
          message: row.message,
          isRead: Boolean(row.is_read),
          createdAt: row.created_at,
        };
      }),
    });
  } catch (error) {
    console.error('GET /hrms/approvals/notifications', error);
    return fail(res, 500, error.message);
  }
}

async function markAllNotificationsRead(req, res) {
  try {
    await ensureAdminNotifications();
    await db.query(
      'UPDATE hrms_admin_notifications SET is_read = 1, read_at = ? WHERE is_read = 0',
      [policy.nowIstDateTime()]
    );
    return ok(res, { unreadCount: 0 }, 'All notifications marked as read');
  } catch (error) {
    console.error('PATCH /hrms/approvals/notifications/read-all', error);
    return fail(res, 500, error.message);
  }
}
async function list(req, res) {
  try {
    await ensureWfhRequestColumns();
    const tab = String(req.query.tab || 'leave').toLowerCase();
    const status = String(req.query.status || '').trim();
    const employee = String(req.query.employee || '').trim();
    const extraPlaceholders = EXTRA_TYPES.map(function () { return '?'; }).join(', ');
    const where = [];
    const params = [];
    const startDate = String(req.query.startDate || '').trim();
    const endDate = String(req.query.endDate || '').trim();
    if (startDate || endDate) {
      const validDate = value => {
        const parsed = new Date(value + 'T00:00:00Z');
        return /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
      };
      if (!validDate(startDate) || !validDate(endDate) || startDate > endDate) return fail(res, 400, 'Valid startDate and endDate are required');
      // Match the requested day/month against the entire saved request range.
      where.push('COALESCE(el.from_date, p.request_date) <= ? AND COALESCE(el.to_date, p.wfh_end_date, p.request_date) >= ?');
      params.push(endDate, startDate);
    }

    if (tab === 'extra') {
      where.push('p.request_type IN (' + extraPlaceholders + ')');
      params.push.apply(params, EXTRA_TYPES);
    } else if (tab === 'permission') {
      const leavePlaceholders = LEAVE_TYPES.map(function () { return '?'; }).join(', ');
      where.push('p.request_type NOT IN (' + extraPlaceholders + ') AND p.request_type NOT IN (' + leavePlaceholders + ')');
      params.push.apply(params, EXTRA_TYPES.concat(LEAVE_TYPES));
    } else {
      where.push('p.request_type IN (' + LEAVE_TYPES.map(function () { return '?'; }).join(', ') + ')');
      params.push.apply(params, LEAVE_TYPES);
    }

    if (status && status !== 'All Status') {
      where.push('p.status = ?');
      params.push(status.toLowerCase());
    }
    if (employee && employee !== 'All Employees') {
      where.push('s.' + staff.quote(staff.STAFF.name) + ' = ?');
      params.push(employee);
    }

    const [rows] = await db.query(
      `SELECT p.id, p.employee_id, p.request_type, p.reason, p.status, p.wfh_end_date,
              p.permission_start_time, p.permission_end_time, el.reason AS leave_reason, el.days_count AS leave_days,
              p.home_latitude, p.home_longitude, p.home_accuracy_meters, p.home_address,
              DATE_FORMAT(p.request_date, '%Y-%m-%d') AS request_date,
              DATE_FORMAT(el.from_date, '%Y-%m-%d') AS from_date,
              DATE_FORMAT(el.to_date, '%Y-%m-%d') AS to_date,
              el.duration_type,
              el.leave_type AS el_leave_type,
              DATE_FORMAT(el.from_date, '%Y-%m-%d') AS el_from_date,
              lt.abbreviation AS lt_abbreviation,
              s.${staff.quote(staff.STAFF.name)} AS full_name,
              s.${staff.quote(staff.STAFF.staffCode)} AS staff_id
       FROM attendance_permission_requests p
       LEFT JOIN ${staff.staffFrom()} s ON s.${staff.quote(staff.STAFF.id)} = p.employee_id
       LEFT JOIN hrms_leave_approval_links link ON link.approval_request_id = p.id
       LEFT JOIN employee_leaves el ON el.id = link.leave_id
       LEFT JOIN hrms_leave_types lt ON lt.id = el.leave_type_id
       WHERE ${where.join(' AND ')}
       ORDER BY p.created_at DESC, p.id DESC`,
      params
    );

    const [allRows] = await db.query(
      `SELECT status FROM attendance_permission_requests`
    );
    const items = rows.map(toUi);
    const names = [...new Set(items.map(function (item) { return item.name; }))];

    return ok(res, {
      items: items,
      employees: names,
      kpis: {
        pending: allRows.filter(function (r) { return r.status === 'pending'; }).length,
        approved: allRows.filter(function (r) { return r.status === 'approved'; }).length,
        rejected: allRows.filter(function (r) { return r.status === 'rejected'; }).length,
      },
    });
  } catch (error) {
    console.error('GET /hrms/approvals', error);
    return fail(res, 500, error.message);
  }
}

async function review(req, res) {
  try {
    const id = Number(req.params.id);
    const status = String((req.body && req.body.status) || '').toLowerCase();
    if (status !== 'approved' && status !== 'rejected') {
      return fail(res, 400, 'status must be approved or rejected');
    }
    await ensureWfhRequestColumns();
    const [[request]] = await db.query(
      `SELECT p.*, h.approval_status AS current_home_status
       FROM attendance_permission_requests p
       LEFT JOIN hrms_employee_home_locations h ON h.employee_user_id = p.employee_id
       WHERE p.id = ? AND p.status = 'pending'`, [id]
    );
    if (!request) return fail(res, 404, 'Pending request not found');
    if (status === 'approved' && request.request_type === 'wfh' &&
        request.current_home_status !== 'approved' &&
        (request.home_latitude == null || request.home_longitude == null)) {
      return fail(res, 409, 'This WFH request has no approved or captured Home location. Ask the employee to submit a new request.');
    }
    const at = policy.nowIstDateTime();
    const [result] = await db.query(
      `UPDATE attendance_permission_requests
       SET status = ?, reviewed_by = ?, reviewed_at = ?
       WHERE id = ? AND status = 'pending'`,
      [status, req.user.id, at, id]
    );
    if (!result.affectedRows) {
      return fail(res, 404, 'Pending request not found');
    }
    if (status === 'approved' && request.request_type === 'wfh' && request.home_latitude != null) {
      await db.query(
        `INSERT INTO hrms_employee_home_locations
          (employee_user_id, latitude, longitude, address, approval_status, reviewed_by, reviewed_at)
         VALUES (?, ?, ?, ?, 'approved', ?, CURRENT_TIMESTAMP)
         ON DUPLICATE KEY UPDATE
           latitude = VALUES(latitude), longitude = VALUES(longitude), address = VALUES(address),
           approval_status = 'approved', reviewed_by = VALUES(reviewed_by), reviewed_at = VALUES(reviewed_at),
           rejection_reason = NULL, updated_at = CURRENT_TIMESTAMP`,
        [request.employee_id, request.home_latitude, request.home_longitude,
          request.home_address || null, req.user.id]
      );
    }
    await db.query(`
      CREATE TABLE IF NOT EXISTS hrms_leave_approval_links (
        leave_id BIGINT UNSIGNED NOT NULL,
        approval_request_id BIGINT UNSIGNED NOT NULL,
        PRIMARY KEY (leave_id),
        UNIQUE KEY uniq_leave_approval_request (approval_request_id)
      )
    `);
    await db.query(
      `UPDATE employee_leaves l
       INNER JOIN hrms_leave_approval_links link ON link.leave_id = l.id
       SET l.status = ?
       WHERE link.approval_request_id = ?`,
      [status === 'approved' ? 'APPROVED' : 'DENIED', id]
    );
    if (status === 'approved') {
      const [leaveRows] = await db.query(`SELECT l.* FROM employee_leaves l
        INNER JOIN hrms_leave_approval_links link ON link.leave_id = l.id
        WHERE link.approval_request_id = ?`, [id]);
      for (const leave of leaveRows) await leaveSystem.reconcileApprovedAbsences(db, leave);
    }
    const [rows] = await db.query(
      `SELECT p.id, p.employee_id, p.request_type, p.reason, p.status, p.wfh_end_date,
              p.permission_start_time, p.permission_end_time, el.reason AS leave_reason, el.days_count AS leave_days,
              p.home_latitude, p.home_longitude, p.home_accuracy_meters, p.home_address,
              DATE_FORMAT(p.request_date, '%Y-%m-%d') AS request_date,
              DATE_FORMAT(el.from_date, '%Y-%m-%d') AS from_date,
              DATE_FORMAT(el.to_date, '%Y-%m-%d') AS to_date,
              el.duration_type,
              el.leave_type AS el_leave_type,
              DATE_FORMAT(el.from_date, '%Y-%m-%d') AS el_from_date,
              lt.abbreviation AS lt_abbreviation,
              s.${staff.quote(staff.STAFF.name)} AS full_name,
              s.${staff.quote(staff.STAFF.staffCode)} AS staff_id
       FROM attendance_permission_requests p
       LEFT JOIN ${staff.staffFrom()} s ON s.${staff.quote(staff.STAFF.id)} = p.employee_id
       LEFT JOIN hrms_leave_approval_links link ON link.approval_request_id = p.id
       LEFT JOIN employee_leaves el ON el.id = link.leave_id
       LEFT JOIN hrms_leave_types lt ON lt.id = el.leave_type_id
       WHERE p.id = ?`,
      [id]
    );
    return ok(res, toUi(rows[0] || {}), 'Request ' + status);
  } catch (error) {
    console.error('PATCH /hrms/approvals/:id', error);
    return fail(res, 500, error.message);
  }
}

module.exports = {
  requireAdmin,
  list,
  review,
  notifications,
  markAllNotificationsRead,
  LEAVE_TYPES,
};


