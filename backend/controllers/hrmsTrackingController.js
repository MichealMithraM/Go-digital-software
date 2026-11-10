const db = require('../config/db');
const { configuredNumber } = require('../lib/configuredSetting');
const nullableNumber = value => value == null || String(value).trim() === '' ? null : Number(value);
const policy = require('../lib/attendancePolicy');
const locationPolicy = require('../lib/attendanceLocationPolicy');
const { validateHomeRegistration } = require('../lib/homeLocationRegistration');

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

const LEAVE_TYPES = ['leave', 'risk_leave', 'annual_leave', 'sick_leave', 'personal_leave'];

function isoDate(value) {
  if (!value) return '';
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return value.toISOString().slice(0, 10);
  }
  const match = String(value).match(/(\d{4}-\d{2}-\d{2})/);
  return match ? match[1] : '';
}

function formatHours(minutes) {
  const total = Math.max(0, Number(minutes) || 0);
  const hours = Math.floor(total / 60);
  const mins = total % 60;
  if (!total) return '—';
  return hours + 'h ' + String(mins).padStart(2, '0') + 'm';
}

function minutesFromCheckIn(checkInAt) {
  if (!checkInAt) return 0;
  const start = new Date(String(checkInAt).replace(' ', 'T'));
  if (Number.isNaN(start.getTime())) return 0;
  return Math.max(0, Math.round((Date.now() - start.getTime()) / 60000));
}

function weekdayIndex(date) {
  const [year, month, day] = date.split('-').map(Number);
  return new Date(Date.UTC(year, month - 1, day)).getUTCDay();
}

async function list(req, res) {
  try {
    const today = policy.todayIstDate();
    const date = String(req.query.date || today).slice(0, 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      return fail(res, 400, 'date must be YYYY-MM-DD');
    }
    const employee = String(req.query.employee || '').trim();
    const statusFilter = String(req.query.status || '').trim();
    const isSunday = weekdayIndex(date) === 0;
    const isFuture = date > today;

    await require('../lib/employeeLifecycle').ensureLifecycle();
    const [profiles] = await db.query(`
      SELECT p.* FROM hrms_employee_profiles p
      WHERE EXISTS (SELECT 1 FROM employee_employment_periods e WHERE e.employee_user_id=p.employee_user_id
        AND e.started_on<=? AND (e.ended_on IS NULL OR e.ended_on>=?))
      ORDER BY full_name ASC
    `, [date,date]);

    const userIds = profiles.map(function (row) { return row.employee_user_id; }).filter(Boolean);

    const [records] = userIds.length
      ? await db.query(
          `SELECT employee_id, DATE_FORMAT(attendance_date, '%Y-%m-%d') AS attendance_date,
                  check_in_at, check_out_at, is_late, working_minutes, check_in_method,
                  attendance_status, session_status
           FROM attendance_records
           WHERE attendance_date = ?
             AND employee_id IN (?)`,
          [date, userIds]
        )
      : [[]];

    const leavePlaceholders = LEAVE_TYPES.map(function () { return '?'; }).join(', ');
    const [leaves] = userIds.length
      ? await db.query(
          `SELECT employee_id, request_type
           FROM attendance_permission_requests
           WHERE status = 'approved'
             AND request_type IN (` + leavePlaceholders + `)
             AND request_date = ?
             AND employee_id IN (?)`,
          LEAVE_TYPES.concat([date, userIds])
        )
      : [[]];

    const recordMap = new Map();
    records.forEach(function (row) {
      recordMap.set(Number(row.employee_id), row);
    });
    const leaveMap = new Map();
    leaves.forEach(function (row) {
      leaveMap.set(Number(row.employee_id), row.request_type);
    });

    let present = 0;
    let late = 0;
    let stillIn = 0;
    let absent = 0;
    let onLeave = 0;

    let items = profiles.map(function (profile) {
      const record = profile.employee_user_id
        ? recordMap.get(Number(profile.employee_user_id))
        : null;
      const leaveType = profile.employee_user_id
        ? leaveMap.get(Number(profile.employee_user_id))
        : null;
      const checkIn = record && record.check_in_at;
      const checkOut = record && record.check_out_at;
      const isLate = Boolean(record && Number(record.is_late));
      const markedAbsent = Boolean(record && record.attendance_status === 'absent');
      let status = 'Absent';
      let minutes = Number((record && record.working_minutes) || 0);

      if (isFuture) {
        status = 'Upcoming';
      } else if (isSunday) {
        status = 'Weekly off';
      } else if (markedAbsent) {
        status = 'Absent';
        absent += 1;
      } else if (checkIn) {
        if (checkOut) {
          status = isLate ? 'Late · out' : 'Checked out';
          present += 1;
          if (isLate) late += 1;
        } else {
          status = isLate ? 'Late · in' : 'In';
          minutes = minutesFromCheckIn(checkIn);
          present += 1;
          stillIn += 1;
          if (isLate) late += 1;
        }
      } else if (leaveType) {
        status = 'On leave';
        onLeave += 1;
      } else {
        absent += 1;
      }

      return {
        profileId: profile.id,
        employeeUserId: profile.employee_user_id,
        name: String(profile.full_name || '').trim(),
        employeeCode: profile.employee_code,
        department: profile.department,
        checkIn: policy.formatDisplayTime(checkIn),
        checkOut: policy.formatDisplayTime(checkOut),
        method: (record && record.check_in_method) || '—',
        hours: formatHours(minutes),
        workingMinutes: minutes,
        isLate: isLate,
        status: status,
      };
    });

    const names = [...new Set(items.map(function (item) { return item.name; }))];
    if (employee && employee !== 'All Employees') {
      items = items.filter(function (item) { return item.name === employee; });
    }
    if (statusFilter && statusFilter !== 'All Status') {
      items = items.filter(function (item) { return item.status === statusFilter; });
    }

    return ok(res, {
      date: date,
      today: today,
      timezone: policy.TIME_ZONE,
      lateAfter: policy.LATE_AFTER,
      absentAfter: policy.ABSENT_AFTER,
      shiftStart: policy.SHIFT_START,
      requiredHours: policy.REQUIRED_MINUTES / 60,
      employees: names,
      items: items,
      kpis: {
        present: present,
        late: late,
        stillIn: stillIn,
        absent: absent,
        onLeave: onLeave,
        total: profiles.length,
      },
    });
  } catch (error) {
    console.error('GET /hrms/tracking', error);
    return fail(res, 500, error.message);
  }
}

const GEOCODE_CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 24h; rounded coords repeat a lot
const geocodeCache = new Map();
const routeCache = new Map();
const ROUTE_CACHE_TTL_MS = 5 * 60 * 1000;

function roundCoord(value) {
  return Math.round(Number(value) * 10000) / 10000; // ~11m precision
}

async function reverseGeocode(latitude, longitude) {
  const key = roundCoord(latitude) + ',' + roundCoord(longitude);
  const cached = geocodeCache.get(key);
  if (cached && cached.expiresAt > Date.now()) {
    return cached.address;
  }

  const apiKey = process.env.GOOGLE_GEOCODING_API_KEY;
  if (!apiKey) return null;

  try {
    const url = 'https://maps.googleapis.com/maps/api/geocode/json'
      + '?latlng=' + encodeURIComponent(latitude + ',' + longitude)
      + '&key=' + apiKey;
    const response = await fetch(url);
    const data = await response.json();

    if (data.status !== 'OK' || !data.results || !data.results.length) {
      return null;
    }

    const localityResult = data.results.find(function (r) {
      return r.types.includes('sublocality') || r.types.includes('locality');
    });
    const address = (localityResult || data.results[0]).formatted_address;

    geocodeCache.set(key, { address: address, expiresAt: Date.now() + GEOCODE_CACHE_TTL_MS });
    return address;
  } catch (error) {
    console.error('Reverse geocode failed', error.message);
    return null;
  }
}

async function setStatus(req, res) {
  try {
    const employeeUserId = req.user && req.user.id;
    const status = String(req.body.status || '').toLowerCase();
    if (!employeeUserId) return fail(res, 401, 'Unauthorized');
    if (!['office', 'home', 'hybrid'].includes(status)) {
      return fail(res, 400, "status must be 'office', 'home', or 'hybrid'");
    }
    await db.query(
      `INSERT INTO hrms_employee_location_status (employee_user_id, status)
       VALUES (?, ?)
       ON DUPLICATE KEY UPDATE status = VALUES(status), updated_at = CURRENT_TIMESTAMP`,
      [employeeUserId, status]
    );
    return ok(res, { status: status }, 'Status updated');
  } catch (error) {
    console.error('POST /hrms/tracking/status', error);
    return fail(res, 500, error.message);
  }
}

function distanceMeters(lat1, lng1, lat2, lng2) {
  const earthRadius = 6371000;

  const toRadians = (value) => (value * Math.PI) / 180;

  const dLat = toRadians(lat2 - lat1);
  const dLng = toRadians(lng2 - lng1);

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRadians(lat1)) *
      Math.cos(toRadians(lat2)) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);

  return earthRadius * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function decodeGooglePolyline(encoded) {
  const points = [];
  let index = 0;
  let latitude = 0;
  let longitude = 0;

  while (index < encoded.length) {
    let result = 0;
    let shift = 0;
    let value;
    do {
      value = encoded.charCodeAt(index++) - 63;
      result |= (value & 0x1f) << shift;
      shift += 5;
    } while (value >= 0x20 && index < encoded.length);
    latitude += result & 1 ? ~(result >> 1) : result >> 1;

    result = 0;
    shift = 0;
    do {
      value = encoded.charCodeAt(index++) - 63;
      result |= (value & 0x1f) << shift;
      shift += 5;
    } while (value >= 0x20 && index < encoded.length);
    longitude += result & 1 ? ~(result >> 1) : result >> 1;

    points.push({ latitude: latitude / 1e5, longitude: longitude / 1e5 });
  }
  return points;
}

function routeWaypoints(points, maximum = 25) {
  if (points.length <= maximum) return points;
  const selected = [];
  for (let index = 0; index < maximum; index += 1) {
    selected.push(points[Math.round(index * (points.length - 1) / (maximum - 1))]);
  }
  return selected;
}

function durationSeconds(value) {
  const match = String(value || '').match(/([0-9.]+)s/);
  return match ? Math.round(Number(match[1])) : 0;
}

function rawRouteSummary(points) {
  if (points.length < 2) return { distanceMeters: 0, durationSeconds: 0 };
  let totalDistance = 0;
  for (let index = 1; index < points.length; index += 1) {
    totalDistance += distanceMeters(
      points[index - 1].latitude,
      points[index - 1].longitude,
      points[index].latitude,
      points[index].longitude
    );
  }
  const first = new Date(points[0].recordedAt).getTime();
  const last = new Date(points[points.length - 1].recordedAt).getTime();
  return {
    distanceMeters: Math.round(totalDistance),
    durationSeconds: Number.isFinite(first) && Number.isFinite(last)
      ? Math.max(0, Math.round((last - first) / 1000))
      : 0,
  };
}

async function roadRoute(points, cacheKey) {
  if (points.length < 2) return null;

  const cached = routeCache.get(cacheKey);
  if (cached && cached.expiresAt > Date.now()) return cached.value;

  const apiKey = process.env.GOOGLE_ROUTES_API_KEY;
  if (!apiKey) return null;

  const selected = routeWaypoints(points);
  const toWaypoint = (point) => ({
    location: { latLng: { latitude: Number(point.latitude), longitude: Number(point.longitude) } },
  });
  try {
    const response = await fetch('https://routes.googleapis.com/directions/v2:computeRoutes', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': 'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline',
      },
      body: JSON.stringify({
        origin: toWaypoint(selected[0]),
        destination: toWaypoint(selected[selected.length - 1]),
        intermediates: selected.slice(1, -1).map(toWaypoint),
        travelMode: 'DRIVE',
        routingPreference: 'TRAFFIC_UNAWARE',
        polylineQuality: 'HIGH_QUALITY',
      }),
    });
    if (!response.ok) {
      console.error('Road route request failed', response.status, await response.text());
      return null;
    }
    const data = await response.json();
    const route = data.routes && data.routes[0];
    const encoded = route && route.polyline && route.polyline.encodedPolyline;
    if (!encoded) return null;

    const value = {
      points: decodeGooglePolyline(encoded),
      distanceMeters: Number(route.distanceMeters || 0),
      durationSeconds: durationSeconds(route.duration),
    };
    routeCache.set(cacheKey, { value: value, expiresAt: Date.now() + ROUTE_CACHE_TTL_MS });
    return value;
  } catch (error) {
    console.error('Road route request failed', error.message);
    return null;
  }
}

async function detectFieldWaitingTime(employeeUserId, latitude, longitude) {
  const [sessions] = await db.query(
    `SELECT id, started_at
     FROM hrms_field_tracking_sessions
     WHERE employee_user_id = ? AND is_active = 1
     ORDER BY started_at DESC
     LIMIT 1`,
    [employeeUserId]
  );

  if (!sessions.length) return;

  const session = sessions[0];

  const [settingsRows] = await db.query(
    `SELECT field_waiting_minutes, stationary_radius_meters
     FROM hrms_tracking_settings
     WHERE id = 1`
  );

  if (!settingsRows.length) return;

  const waitingMinutes = Number(settingsRows[0].field_waiting_minutes);
  const stationaryRadius = Number(settingsRows[0].stationary_radius_meters);
  if (!Number.isFinite(waitingMinutes) || waitingMinutes < 1 ||
      !Number.isFinite(stationaryRadius) || stationaryRadius < 1) {
    throw new Error('Admin must configure valid Hybrid waiting time and stationary radius');
  }

  const [existingAlerts] = await db.query(
    `SELECT id
     FROM hrms_field_waiting_reasons
     WHERE field_session_id = ?
       AND reason IS NULL
       AND review_status = 'pending'
     LIMIT 1`,
    [session.id]
  );

  if (existingAlerts.length) return;

  const [pings] = await db.query(
    `SELECT latitude, longitude, recorded_at
     FROM hrms_location_pings
     WHERE employee_user_id = ?
       AND recorded_at >= ?
     ORDER BY recorded_at ASC`,
    [employeeUserId, session.started_at]
  );

  if (pings.length < 2) return;

  let firstStillPing = pings[pings.length - 1];

  for (let index = pings.length - 1; index >= 0; index--) {
    const ping = pings[index];

    const distance = distanceMeters(
      latitude,
      longitude,
      Number(ping.latitude),
      Number(ping.longitude)
    );

    if (distance > stationaryRadius) break;

    firstStillPing = ping;
  }

  const startedAt = new Date(firstStillPing.recorded_at);

  const elapsedMinutes = Math.floor(
    (Date.now() - startedAt.getTime()) / 60000
  );

  if (elapsedMinutes < waitingMinutes) return;

const eventKey =
  `${session.id}:${new Date(firstStillPing.recorded_at).toISOString()}`;

await db.query(
  `INSERT IGNORE INTO hrms_field_waiting_reasons (
     field_session_id,
     employee_user_id,
     latitude,
     longitude,
     waiting_started_at,
     waiting_detected_at,
     waiting_minutes,
     event_key
   )
   VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP, ?, ?)`,
  [
    session.id,
    employeeUserId,
    latitude,
    longitude,
    firstStillPing.recorded_at,
    elapsedMinutes,
    eventKey,
  ]
);
}

async function ping(req, res) {
  try {
    const employeeUserId = req.user && req.user.id;
    const latitude = Number(req.body.latitude);
    const longitude = Number(req.body.longitude);
    const accuracy = req.body.accuracy != null ? Number(req.body.accuracy) : null;
    if (!employeeUserId) return fail(res, 401, 'Unauthorized');
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
      return fail(res, 400, 'latitude and longitude are required numbers');
    }
    const [result] = await db.query(
      `INSERT INTO hrms_location_pings (employee_user_id, latitude, longitude, accuracy_meters)
       VALUES (?, ?, ?, ?)`,
      [employeeUserId, latitude, longitude, accuracy]
    );
    const pingId = result.insertId;

    const [profiles] = await db.query(
      `SELECT work_mode FROM hrms_employee_profiles WHERE employee_user_id = ?`,
      [employeeUserId]
    );
    const workMode = profiles[0] && profiles[0].work_mode;

    if (workMode === 'Office' || workMode === 'Home') {
      const rules = await locationPolicy.getCheckInPolicy(db, employeeUserId, false);
      const settings = await locationPolicy.settingsFor(db, false, workMode);
      const distance = locationPolicy.distanceMeters(rules.center, { latitude, longitude });
      const [breakRows] = await db.query(
        `SELECT b.id, TIMESTAMPDIFF(MINUTE, b.started_at, CURRENT_TIMESTAMP) AS break_minutes
         FROM attendance_breaks b
         INNER JOIN attendance_records a ON a.id = b.attendance_id
         WHERE a.employee_id = ? AND a.attendance_date = ?
           AND a.check_in_at IS NOT NULL AND a.check_out_at IS NULL
           AND b.status = 'active'
         ORDER BY b.id DESC LIMIT 1`,
        [employeeUserId, policy.todayIstDate()]
      );
      let breakProtected = false;
      if (breakRows.length) {
        const [[breakSettings]] = await db.query('SELECT break_minutes, break_grace_minutes FROM hrms_attendance_time_settings WHERE id=1');
        const allowed = configuredNumber(breakSettings?.break_minutes, 'break time', true);
        const grace = configuredNumber(breakSettings?.break_grace_minutes, 'break grace', true);
        breakProtected = Number(breakRows[0].break_minutes) < allowed + grace;
      }

      if (breakProtected) {
        await db.query(
          `UPDATE attendance_records SET outside_radius_since = NULL
           WHERE employee_id = ? AND attendance_date = ? AND check_out_at IS NULL`,
          [employeeUserId, policy.todayIstDate()]
        );
      } else if (distance > Number(workMode === 'Home' ? settings.homeRadiusMeters : settings.radiusMeters)) {
        const [activeAttendance] = await db.query(
          `SELECT id, check_in_at, outside_radius_since FROM attendance_records
           WHERE employee_id = ? AND attendance_date = ?
             AND check_in_at IS NOT NULL AND check_out_at IS NULL
           ORDER BY id DESC LIMIT 1`,
          [employeeUserId, policy.todayIstDate()]
        );

        if (activeAttendance.length) {
          const attendance = activeAttendance[0];
          if (!attendance.outside_radius_since) {
            await db.query(
              `UPDATE attendance_records SET outside_radius_since = CURRENT_TIMESTAMP
               WHERE id = ? AND check_out_at IS NULL`,
              [attendance.id]
            );
          } else {
            const [expired] = await db.query(
              `SELECT id FROM attendance_records
               WHERE id = ? AND check_out_at IS NULL
                 AND outside_radius_since <= (CURRENT_TIMESTAMP - INTERVAL ? MINUTE)`,
              [attendance.id, workMode === 'Home' ? settings.homeOutsideRadiusGraceMinutes : settings.officeOutsideRadiusGraceMinutes]
            );

            if (expired.length) {
              await db.query(
                `UPDATE attendance_records
                 SET check_out_at = CURRENT_TIMESTAMP,
                     working_minutes = GREATEST(0, TIMESTAMPDIFF(MINUTE, check_in_at, CURRENT_TIMESTAMP)),
                     outside_radius_since = NULL,
                     session_status = 'completed'
                 WHERE id = ? AND check_out_at IS NULL`,
                [attendance.id]
              );
              await db.query(
                `UPDATE attendance_breaks
                 SET ended_at = CURRENT_TIMESTAMP,
                     duration_minutes = GREATEST(0, TIMESTAMPDIFF(MINUTE, started_at, CURRENT_TIMESTAMP)),
                     status = 'auto_closed'
                 WHERE attendance_id = ? AND status = 'active'`,
                [attendance.id]
              );
            }
          }
        }
      } else {
        await db.query(
          `UPDATE attendance_records SET outside_radius_since = NULL
           WHERE employee_id = ? AND attendance_date = ? AND check_in_at IS NOT NULL AND check_out_at IS NULL`,
          [employeeUserId, policy.todayIstDate()]
        );
      }
    }

    await detectFieldWaitingTime(employeeUserId, latitude, longitude).catch(
      function (error) {
        console.error('Field waiting-time detection failed', error.message);
      }
    );

    ok(res, null, 'Location recorded'); // respond right away, don't block on geocoding

    reverseGeocode(latitude, longitude).then(function (address) {
      if (!address) return;
      db.query(`UPDATE hrms_location_pings SET address = ? WHERE id = ?`, [address, pingId])
        .catch(function (e) { console.error('Address backfill failed', e.message); });
    });
  } catch (error) {
    console.error('POST /hrms/tracking/ping', error);
    return fail(res, 500, error.message);
  }
}

async function liveOverview(req, res) {
  try {
    const today = policy.todayIstDate();
    const date = String(req.query.date || today);
    const parsedDate = new Date(date + 'T00:00:00Z');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || Number.isNaN(parsedDate.getTime()) || parsedDate.toISOString().slice(0, 10) !== date) return fail(res, 400, 'date must be YYYY-MM-DD');
    const monthStart = date.slice(0, 7) + '-01';
    await require('../lib/employeeLifecycle').ensureLifecycle();
    const [profiles] = await db.query(`
      SELECT p.id, p.employee_user_id, p.full_name, p.employee_code, p.work_mode
      FROM hrms_employee_profiles p
      WHERE EXISTS (SELECT 1 FROM employee_employment_periods e WHERE e.employee_user_id=p.employee_user_id
        AND e.started_on<=? AND (e.ended_on IS NULL OR e.ended_on>=?))
    `, [date, date]);
    const userIds = profiles.map(function (row) { return row.employee_user_id; }).filter(Boolean);
    const [[settings = {}]] = await db.query('SELECT * FROM hrms_tracking_settings WHERE id = 1 LIMIT 1');
    const [attendance] = userIds.length ? await db.query(
      `SELECT r.*, DATE_FORMAT(attendance_date, '%Y-%m-%d') AS date_key,
        CONCAT(DATE_FORMAT(check_in_at, '%Y-%m-%dT%H:%i:%s'), '+05:30') AS check_in_iso,
        CONCAT(DATE_FORMAT(check_out_at, '%Y-%m-%dT%H:%i:%s'), '+05:30') AS check_out_iso
       FROM attendance_records r WHERE employee_id IN (?) AND attendance_date BETWEEN ? AND ? ORDER BY attendance_date DESC, id DESC`,
      [userIds, monthStart, date]) : [[]];
    const [openBreaks] = userIds.length ? await db.query(
      `SELECT b.attendance_id FROM attendance_breaks b
       INNER JOIN attendance_records r ON r.id = b.attendance_id
       WHERE r.employee_id IN (?) AND r.attendance_date = ? AND b.status = 'active' AND b.ended_at IS NULL`,
      [userIds, date]).catch(error => {
        // An installation with no break table cannot have recorded breaks yet.
        if (error.code === 'ER_NO_SUCH_TABLE' && String(error.sqlMessage || error.message).includes('attendance_breaks')) return [[]];
        throw error;
      }) : [[]];
    const openBreakIds = new Set(openBreaks.map(b => Number(b.attendance_id)));
    const [homes] = userIds.length ? await db.query(
      'SELECT employee_user_id, latitude, longitude, address, approval_status FROM hrms_employee_home_locations WHERE employee_user_id IN (?)', [userIds]) : [[]];
    const homeMap = new Map(homes.map(h => [Number(h.employee_user_id), h]));

    const [statuses] = userIds.length
      ? await db.query(
          `SELECT employee_user_id, status FROM hrms_employee_location_status
           WHERE employee_user_id IN (?)`,
          [userIds]
        )
      : [[]];
    const statusMap = new Map();
    statuses.forEach(function (row) { statusMap.set(Number(row.employee_user_id), row.status); });

    const [latestPings] = userIds.length
      ? await db.query(
          `SELECT p.employee_user_id, p.latitude, p.longitude, p.address, p.recorded_at, p.accuracy_meters,
                  CONCAT(DATE_FORMAT(p.recorded_at, '%Y-%m-%dT%H:%i:%s'), '+05:30') AS recorded_iso
           FROM hrms_location_pings p
           INNER JOIN (
             SELECT employee_user_id, MAX(id) AS latest_id
             FROM hrms_location_pings
             WHERE employee_user_id IN (?) AND recorded_at >= ? AND recorded_at < DATE_ADD(?, INTERVAL 1 DAY)
             GROUP BY employee_user_id
           ) latest
           ON latest.employee_user_id = p.employee_user_id AND latest.latest_id = p.id`,
          [userIds, date, date]
        )
      : [[]];
    const pingMap = new Map();
    latestPings.forEach(function (row) { pingMap.set(Number(row.employee_user_id), row); });

    const now = Date.now();
    let activeNow = 0;
    const counts = { office: 0, home: 0, hybrid: 0 };

    const items = profiles.map(function (profile) {
      const uid = profile.employee_user_id ? Number(profile.employee_user_id) : null;
      const history = attendance.filter(r => Number(r.employee_id) === uid);
      const record = history.find(r => r.date_key === date);
      const status = String((record && record.work_mode_snapshot) || (uid && statusMap.get(uid)) || profile.work_mode || '').toLowerCase().replace('field', 'hybrid');
      const ping = uid ? pingMap.get(uid) : null;
      const home = uid ? homeMap.get(uid) : null;
      counts[status] = (counts[status] || 0) + 1;

      let isActive = false;
      if (date === today && record && record.check_in_iso && !record.check_out_iso && ping && ping.recorded_iso) {
        const ageMinutes = (now - new Date(ping.recorded_iso).getTime()) / 60000;
        const timeout = nullableNumber(settings[status === 'home' ? 'home_no_gps_timeout_minutes' : status === 'office' ? 'office_no_gps_timeout_minutes' : 'field_ping_interval_minutes']);
        isActive = Number.isFinite(timeout) && timeout > 0 && ageMinutes >= 0 && ageMinutes <= timeout && new Date(ping.recorded_iso) >= new Date(record.check_in_iso);
      }
      if (isActive) activeNow += 1;

      return {
        employeeUserId: uid,
        name: String(profile.full_name || '').trim(),
        employeeCode: profile.employee_code,
        status: status,
        latitude: ping ? Number(ping.latitude) : null,
        longitude: ping ? Number(ping.longitude) : null,
        address: ping ? ping.address : null,
        lastUpdated: ping ? ping.recorded_iso : null,
        active: isActive,
        attendanceDate: date,
        checkInAt: record ? record.check_in_iso : null,
        checkOutAt: record ? record.check_out_iso : null,
        isLate: Boolean(record && Number(record.is_late)),
        onBreak: Boolean(record && record.check_in_iso && !record.check_out_iso && openBreakIds.has(Number(record.id))),
        sessionStatus: record ? record.session_status : null,
        attendanceStatus: record ? record.attendance_status : null,
        checkInMethod: record ? record.check_in_method : null,
        workingMinutes: record ? nullableNumber(record.working_minutes) : null,
        accuracyMeters: ping ? nullableNumber(ping.accuracy_meters) : null,
        homeApprovalStatus: home ? home.approval_status : null,
        homeLatitude: home && home.approval_status === 'approved' ? nullableNumber(home.latitude) : null,
        homeLongitude: home && home.approval_status === 'approved' ? nullableNumber(home.longitude) : null,
        homeAddress: home && home.approval_status === 'approved' ? home.address : null,
        homeRadiusMeters: nullableNumber(settings.home_radius_meters),
        officeRadiusMeters: nullableNumber(settings.office_radius_meters),
        recentAttendance: history.map(r => ({ date: r.date_key, checkInAt: r.check_in_iso, checkOutAt: r.check_out_iso, status: r.attendance_status, method: r.check_in_method })),
      };
    });

    return ok(res, {
      date,
      counts: {
        office: counts.office || 0,
        home: counts.home || 0,
        hybrid: counts.hybrid || 0,
        activeNow: activeNow,
      },
      items: items,
    });
  } catch (error) {
    console.error('GET /hrms/tracking/live', error);
    return fail(res, 500, error.message);
  }
}

async function routeHistory(req, res) {
  try {
    const employeeUserId = Number(req.params.employeeUserId);
    const date = String(req.query.date || policy.todayIstDate()).slice(0, 10);
    if (!employeeUserId) return fail(res, 400, 'Valid employeeUserId is required');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return fail(res, 400, 'date must be YYYY-MM-DD');

    const [pings] = await db.query(
      `SELECT latitude, longitude, address, recorded_at
       FROM hrms_location_pings
       WHERE employee_user_id = ? AND DATE(recorded_at) = ?
       ORDER BY recorded_at ASC`,
      [employeeUserId, date]
    );

    // Waiting reasons are employee-submitted events.  Return them with the
    // route so the dashboard can place the same event on both the map and the
    // existing route progress line without making a second, unscoped request.
    const [waitingReasons] = await db.query(
      `SELECT id, latitude, longitude, reason, reason_submitted_at,
              waiting_detected_at, review_status, reviewed_at
       FROM hrms_field_waiting_reasons
       WHERE employee_user_id = ?
         AND reason IS NOT NULL
         AND DATE(reason_submitted_at) = ?
       ORDER BY reason_submitted_at ASC`,
      [employeeUserId, date]
    );

    const activities = pings.map(function (row) {
      return {
        latitude: Number(row.latitude),
        longitude: Number(row.longitude),
        placeName: row.address || null,
        address: row.address || null,
        recordedAt: row.recorded_at,
      };
    });
    const validRoutePoints = activities.filter(function (point) {
      return Number.isFinite(point.latitude) && Number.isFinite(point.longitude)
        && Math.abs(point.latitude) <= 90 && Math.abs(point.longitude) <= 180
        && point.latitude !== 0 && point.longitude !== 0;
    });
    const cacheKey = [
      employeeUserId,
      date,
      pings.length,
      pings.length ? pings[pings.length - 1].recorded_at : '',
    ].join(':');
    const mappedRoute = await roadRoute(validRoutePoints, cacheKey);
    const fallbackSummary = rawRouteSummary(validRoutePoints);
    const routePoints = mappedRoute ? mappedRoute.points : validRoutePoints;
    const totalDistance = mappedRoute ? mappedRoute.distanceMeters : fallbackSummary.distanceMeters;
    const totalDuration = mappedRoute ? mappedRoute.durationSeconds : fallbackSummary.durationSeconds;

    return ok(res, {
      employeeUserId: employeeUserId,
      date: date,
      // Keep raw pings for activity history, and provide road geometry for maps.
      points: activities,
      activities: activities,
      routePoints: routePoints,
      waitingReasons: waitingReasons.map(function (row) {
        return {
          id: Number(row.id),
          latitude: nullableNumber(row.latitude),
          longitude: nullableNumber(row.longitude),
          reason: row.reason,
          submittedAt: row.reason_submitted_at,
          detectedAt: row.waiting_detected_at,
          reviewStatus: row.review_status || 'pending',
          reviewedAt: row.reviewed_at,
        };
      }),
      distanceMeters: totalDistance,
      durationSeconds: totalDuration,
      averageSpeedKmh: totalDuration > 0
        ? Number(((totalDistance / totalDuration) * 3.6).toFixed(1))
        : 0,
    });
  } catch (error) {
    console.error('GET /hrms/tracking/route/:employeeUserId', error);
    return fail(res, 500, error.message);
  }
}

// Return the authenticated employee's own route without granting access to
// another employee's location history.
async function myRouteHistory(req, res) {
  if (!req.user || !req.user.id) {
    return fail(res, 401, 'Unauthorized');
  }
  req.params.employeeUserId = req.user.id;
  return routeHistory(req, res);
}

async function getTrackingSettings(req, res) {
  try {
    const [rows] = await db.query(
      'SELECT * FROM hrms_tracking_settings WHERE id = 1'
    );

    if (!rows.length) {
      return fail(res, 404, 'Tracking settings not found');
    }

    return ok(res, rows[0]);
  } catch (error) {
    console.error('GET /hrms/tracking/settings', error);
    return fail(res, 500, error.message);
  }
}

async function updateTrackingSettings(req, res) {
  try {
    const [rows] = await db.query(
      'SELECT * FROM hrms_tracking_settings WHERE id = 1'
    );

    if (!rows.length) {
      return fail(res, 404, 'Tracking settings not found');
    }

    const current = rows[0];

    const officeName =
        String(req.body.officeName ?? current.office_name).trim();

    const officeAddress =
        String(req.body.officeAddress ?? current.office_address).trim();

    const officeLatitude =
        nullableNumber(req.body.officeLatitude ?? current.office_latitude);

    const officeLongitude =
        nullableNumber(req.body.officeLongitude ?? current.office_longitude);

    const officeRadiusMeters =
        Number(req.body.officeRadiusMeters ?? current.office_radius_meters);

    const fieldPingIntervalMinutes =
        nullableNumber(req.body.fieldPingIntervalMinutes ?? current.field_ping_interval_minutes);

    const fieldWaitingMinutes =
        nullableNumber(req.body.fieldWaitingMinutes ?? current.field_waiting_minutes);

    const stationaryRadiusMeters =
        nullableNumber(req.body.stationaryRadiusMeters ?? current.stationary_radius_meters);

    if (
      !officeName ||
      !officeAddress ||
      officeLatitude == null ||
      officeLongitude == null ||
      !Number.isFinite(officeLatitude) ||
      !Number.isFinite(officeLongitude) ||
      officeLatitude < -90 ||
      officeLatitude > 90 ||
      officeLongitude < -180 ||
      officeLongitude > 180 ||
      !Number.isSafeInteger(officeRadiusMeters) || officeRadiusMeters < 1 ||
      [fieldPingIntervalMinutes, fieldWaitingMinutes, stationaryRadiusMeters].some(value => value != null && (!Number.isSafeInteger(value) || value < 1))
    ) {
      return fail(res, 400, 'Invalid tracking settings');
    }

    await db.query(
      `UPDATE hrms_tracking_settings
       SET office_name = ?,
           office_address = ?,
           office_latitude = ?,
           office_longitude = ?,
           office_radius_meters = ?,
           field_ping_interval_minutes = ?,
           field_waiting_minutes = ?,
           stationary_radius_meters = ?,
           updated_by = ?
       WHERE id = 1`,
      [
        officeName,
        officeAddress,
        officeLatitude,
        officeLongitude,
        officeRadiusMeters,
        fieldPingIntervalMinutes,
        fieldWaitingMinutes,
        stationaryRadiusMeters,
        req.user.id,
      ]
    );

    return getTrackingSettings(req, res);
  } catch (error) {
    console.error('PUT /hrms/tracking/settings', error);
    return fail(res, 500, error.message);
  }
}

async function getMyHomeLocation(req, res) {
  try {
    const employeeUserId = req.user && req.user.id;

    if (!employeeUserId) {
      return fail(res, 401, 'Unauthorized');
    }

    const [rows] = await db.query(
      `SELECT employee_user_id, latitude, longitude, address,
              approval_status, submitted_at, reviewed_at, rejection_reason, capture_source, accuracy_meters
       FROM hrms_employee_home_locations
       WHERE employee_user_id = ?`,
      [employeeUserId]
    );

    return ok(res, rows[0] || null);
  } catch (error) {
    console.error('GET /hrms/tracking/home-location', error);
    return fail(res, 500, error.message);
  }
}

async function submitHomeLocation(req, res) {
  let connection;
  try {
    const employeeUserId = req.user && req.user.id;
    const body = req.body || {};
    const address = typeof body.address === 'string' ? body.address.trim() : '';

    if (!employeeUserId) {
      return fail(res, 401, 'Unauthorized');
    }

    if (address.length > 500) return fail(res, 400, 'Home address must be 500 characters or fewer.');
    connection = await db.getConnection();
    await connection.beginTransaction();
    await locationPolicy.profileFor(connection, employeeUserId, true);
    const settings = await locationPolicy.settingsFor(connection, true, 'Home');
    const fix = validateHomeRegistration(body, settings.homeRadiusMeters);

    await connection.query(
      `INSERT INTO hrms_employee_home_locations
        (employee_user_id, latitude, longitude, address, capture_source, accuracy_meters, approval_status)
       VALUES (?, ?, ?, ?, ?, ?, 'pending')
       ON DUPLICATE KEY UPDATE
         latitude = VALUES(latitude),
         longitude = VALUES(longitude),
         address = VALUES(address),
         capture_source = VALUES(capture_source),
         accuracy_meters = VALUES(accuracy_meters),
         approval_status = 'pending',
         reviewed_by = NULL,
         reviewed_at = NULL,
         rejection_reason = NULL,
         submitted_at = CURRENT_TIMESTAMP,
         updated_at = CURRENT_TIMESTAMP`,
      [employeeUserId, fix.latitude, fix.longitude, address || null, fix.captureSource, fix.accuracy]
    );
    await connection.commit();
    return ok(res, null, 'Home location submitted for admin approval');
  } catch (error) {
    if (connection) await connection.rollback();
    if (error instanceof locationPolicy.LocationPolicyError) return fail(res, error.status, error.message);
    console.error('POST /hrms/tracking/home-location', error);
    return fail(res, 500, 'Unable to submit Home location. Please try again.');
  } finally {
    if (connection) connection.release();
  }
}

async function listHomeLocations(req, res) {
  try {
    if (String(req.user && req.user.userType || '').toLowerCase() !== 'admin') {
      return fail(res, 403, 'Admin access required');
    }
    const [rows] = await db.query(`
      SELECT h.employee_user_id, h.latitude, h.longitude, h.address,
             h.approval_status, h.submitted_at, h.reviewed_at,
             h.rejection_reason, h.capture_source, h.accuracy_meters, p.full_name, p.employee_code
      FROM hrms_employee_home_locations h
      LEFT JOIN hrms_employee_profiles p
        ON p.employee_user_id = h.employee_user_id
      ORDER BY
        CASE h.approval_status
          WHEN 'pending' THEN 1
          WHEN 'approved' THEN 2
          ELSE 3
        END,
        h.submitted_at DESC
    `);

    return ok(res, { items: rows });
  } catch (error) {
    console.error('GET /hrms/tracking/home-locations', error);
    return fail(res, 500, error.message);
  }
}

async function reviewHomeLocation(req, res) {
  let connection;
  try {
    if (String(req.user && req.user.userType || '').toLowerCase() !== 'admin') {
      return fail(res, 403, 'Admin access required');
    }
    const employeeUserId = Number(req.params.employeeUserId);
    const body = req.body || {};
    const approvalStatus = String(body.approvalStatus || '').toLowerCase();
    const rejectionReason = typeof body.rejectionReason === 'string' ? body.rejectionReason.trim() : '';

    if (!Number.isSafeInteger(employeeUserId) || employeeUserId < 1) {
      return fail(res, 400, 'Valid employee ID is required');
    }

    if (!['approved', 'rejected'].includes(approvalStatus)) {
      return fail(res, 400, 'approvalStatus must be approved or rejected');
    }
    if (rejectionReason.length > 500) return fail(res, 400, 'Rejection reason must be 500 characters or fewer.');
    if (approvalStatus === 'rejected' && !rejectionReason) {
      return fail(res, 400, 'Enter a reason for rejecting the Home location.');
    }
    const reviewedCoordinates = locationPolicy.coordinates(body.latitude, body.longitude);
    connection = await db.getConnection();
    await connection.beginTransaction();
    const profile = await locationPolicy.profileFor(connection, employeeUserId, true);
    const [homes] = await connection.query(
      `SELECT latitude, longitude, address, approval_status, capture_source FROM hrms_employee_home_locations
       WHERE employee_user_id = ? FOR UPDATE`, [employeeUserId]);
    if (homes.length !== 1) {
      throw new locationPolicy.LocationPolicyError(404, 'Home location request not found.');
    }
    if (homes[0].approval_status !== 'pending') {
      throw new locationPolicy.LocationPolicyError(409, 'This Home location request was already reviewed. Refresh the list.');
    }
    if (approvalStatus === 'approved' && homes[0].capture_source === 'map_pin' && body.mapPinVerified !== true) {
      throw new locationPolicy.LocationPolicyError(400, 'Verify the selected Home map pin and address before approving.');
    }
    if (approvalStatus === 'approved' && homes[0].capture_source === 'map_pin' &&
        String(body.reviewedAddress ?? '').trim() !== String(homes[0].address ?? '').trim()) {
      throw new locationPolicy.LocationPolicyError(409, 'The Home address changed. Refresh and verify the new request.');
    }
    if (Number(homes[0].latitude) !== reviewedCoordinates.latitude ||
        Number(homes[0].longitude) !== reviewedCoordinates.longitude) {
      throw new locationPolicy.LocationPolicyError(409, 'The employee submitted a different Home location. Refresh and review the new request.');
    }
    await connection.query(
      `UPDATE hrms_employee_home_locations
       SET approval_status = ?,
           reviewed_by = ?,
           reviewed_at = CURRENT_TIMESTAMP,
           rejection_reason = ?
       WHERE employee_user_id = ? AND approval_status = 'pending'`,
      [
        approvalStatus,
        req.user.id,
        approvalStatus === 'rejected' ? rejectionReason || null : null,
        employeeUserId,
      ]
    );
    await connection.commit();
    return ok(res, null, approvalStatus === 'approved'
      ? 'Home location approved. The employee’s permanent work mode is unchanged.'
      : 'Home location rejected');
  } catch (error) {
    if (connection) await connection.rollback();
    if (error instanceof locationPolicy.LocationPolicyError) return fail(res, error.status, error.message);
    console.error('PATCH /hrms/tracking/home-locations/:employeeUserId', error);
    return fail(res, 500, 'Unable to review Home location. Please try again.');
  } finally {
    if (connection) connection.release();
  }
}

async function getMyFieldSession(req, res) {
  try {
    const employeeUserId = req.user && req.user.id;

    if (!employeeUserId) {
      return fail(res, 401, 'Unauthorized');
    }

    const [profiles] = await db.query(
      `SELECT work_mode FROM hrms_employee_profiles
       WHERE employee_user_id = ?`,
      [employeeUserId]
    );
    const workMode = profiles[0] && profiles[0].work_mode;
    if (workMode !== 'Hybrid') {
      return fail(res, 403, 'Live tracking is only available for Hybrid employees');
    }

    const [rows] = await db.query(
      `SELECT *
       FROM hrms_field_tracking_sessions
       WHERE employee_user_id = ? AND is_active = 1
       ORDER BY started_at DESC
       LIMIT 1`,
      [employeeUserId]
    );

    return ok(res, {
      ...(rows[0] || { isActive: false }),
      workMode,
      isHybrid: workMode === 'Hybrid',
    });
  } catch (error) {
    console.error('GET /hrms/tracking/field-session', error);
    return fail(res, 500, error.message);
  }
}

async function startFieldTracking(req, res) {
  try {
    const employeeUserId = req.user && req.user.id;
    const latitude = Number(req.body.latitude);
    const longitude = Number(req.body.longitude);
    const accuracy =
        req.body.accuracy != null ? Number(req.body.accuracy) : null;

    if (!employeeUserId) {
      return fail(res, 401, 'Unauthorized');
    }

    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
      return fail(res, 400, 'Valid latitude and longitude are required');
    }

    const [profiles] = await db.query(
      `SELECT work_mode
       FROM hrms_employee_profiles
       WHERE employee_user_id = ?`,
      [employeeUserId]
    );

    if (!profiles.length || profiles[0].work_mode !== 'Hybrid') {
      return fail(res, 403, 'Live tracking is only available for Hybrid employees');
    }

    // Hybrid attendance begins with Clock In. Tracking is available only for
    // an active attendance session, so an employee cannot create location
    // records before starting work.
    const [attendanceRows] = await db.query(
      `SELECT id FROM attendance_records
       WHERE employee_id = ?
         AND attendance_date = ?
         AND check_in_at IS NOT NULL
         AND check_out_at IS NULL
       LIMIT 1`,
      [employeeUserId, policy.todayIstDate()]
    );
    if (!attendanceRows.length) {
      return fail(res, 409, 'Clock in before starting Hybrid live tracking.');
    }

    const [activeSessions] = await db.query(
      `SELECT id
       FROM hrms_field_tracking_sessions
       WHERE employee_user_id = ? AND is_active = 1
       LIMIT 1`,
      [employeeUserId]
    );

    if (activeSessions.length) {
      return ok(
        res,
        { sessionId: activeSessions[0].id, isActive: true },
        'Live tracking is already active'
      );
    }

    const [session] = await db.query(
      `INSERT INTO hrms_field_tracking_sessions
        (employee_user_id, start_latitude, start_longitude)
       VALUES (?, ?, ?)`,
      [employeeUserId, latitude, longitude]
    );

    await db.query(
      `INSERT INTO hrms_location_pings
        (employee_user_id, latitude, longitude, accuracy_meters)
       VALUES (?, ?, ?, ?)`,
      [employeeUserId, latitude, longitude, accuracy]
    );

    await db.query(
      `INSERT INTO hrms_employee_location_status (employee_user_id, status)
        VALUES (?, 'hybrid')
       ON DUPLICATE KEY UPDATE
          status = 'hybrid',
         updated_at = CURRENT_TIMESTAMP`,
      [employeeUserId]
    );

    return ok(
      res,
      { sessionId: session.insertId, isActive: true },
      'Hybrid live tracking started'
    );
  } catch (error) {
    console.error('POST /hrms/tracking/field-session/start', error);
    return fail(res, 500, error.message);
  }
}

async function stopFieldTracking(req, res) {
  try {
    const employeeUserId = req.user && req.user.id;
    const latitude =
        req.body.latitude != null ? Number(req.body.latitude) : null;
    const longitude =
        req.body.longitude != null ? Number(req.body.longitude) : null;
    const accuracy =
        req.body.accuracy != null ? Number(req.body.accuracy) : null;

    if (!employeeUserId) {
      return fail(res, 401, 'Unauthorized');
    }

    const [activeSessions] = await db.query(
      `SELECT id
       FROM hrms_field_tracking_sessions
       WHERE employee_user_id = ? AND is_active = 1
       ORDER BY started_at DESC
       LIMIT 1`,
      [employeeUserId]
    );

    if (!activeSessions.length) {
      return ok(res, { isActive: false }, 'No active Hybrid tracking session');
    }

    const sessionId = activeSessions[0].id;

    await db.query(
      `UPDATE hrms_field_tracking_sessions
       SET is_active = 0,
           stopped_at = CURRENT_TIMESTAMP,
           stop_latitude = ?,
           stop_longitude = ?
       WHERE id = ?`,
      [
        Number.isFinite(latitude) ? latitude : null,
        Number.isFinite(longitude) ? longitude : null,
        sessionId,
      ]
    );

    if (Number.isFinite(latitude) && Number.isFinite(longitude)) {
      await db.query(
        `INSERT INTO hrms_location_pings
          (employee_user_id, latitude, longitude, accuracy_meters)
         VALUES (?, ?, ?, ?)`,
        [employeeUserId, latitude, longitude, accuracy]
      );
    }

    return ok(
      res,
      { sessionId: sessionId, isActive: false },
      'Hybrid live tracking stopped'
    );
  } catch (error) {
    console.error('POST /hrms/tracking/field-session/stop', error);
    return fail(res, 500, error.message);
  }
}
async function getMyWaitingAlert(req, res) {
  try {
    const employeeUserId = req.user && req.user.id;

    const [rows] = await db.query(
      `SELECT id, waiting_minutes, waiting_started_at, waiting_detected_at
       FROM hrms_field_waiting_reasons
       WHERE employee_user_id = ?
         AND reason IS NULL
         AND review_status = 'pending'
       ORDER BY waiting_detected_at DESC
       LIMIT 1`,
      [employeeUserId]
    );

    return ok(res, rows[0] || null);
  } catch (error) {
    return fail(res, 500, error.message);
  }
}

async function submitWaitingReason(req, res) {
  try {
    const employeeUserId = req.user && req.user.id;
    const reasonId = Number(req.params.id);
    const reason = String(req.body.reason || '').trim();

    if (!reasonId || !reason) {
      return fail(res, 400, 'Waiting reason is required');
    }

    const [result] = await db.query(
      `UPDATE hrms_field_waiting_reasons
       SET reason = ?,
           reason_submitted_at = CURRENT_TIMESTAMP
       WHERE id = ?
         AND employee_user_id = ?
         AND reason IS NULL`,
      [reason, reasonId, employeeUserId]
    );

    if (!result.affectedRows) {
      return fail(res, 404, 'Waiting alert not found');
    }

    return ok(res, null, 'Waiting reason submitted');
  } catch (error) {
    return fail(res, 500, error.message);
  }
}

async function listFieldWaitingReasons(req, res) {
  try {
    const [rows] = await db.query(`
      SELECT w.*,
             p.full_name,
             p.employee_code
      FROM hrms_field_waiting_reasons w
      LEFT JOIN hrms_employee_profiles p
        ON p.employee_user_id = w.employee_user_id
      ORDER BY w.waiting_detected_at DESC
      LIMIT 100
    `);

    return ok(res, { items: rows });
  } catch (error) {
    return fail(res, 500, error.message);
  }
}

async function reviewFieldWaitingReason(req, res) {
  try {
    const reasonId = Number(req.params.id);

    if (!reasonId) {
      return fail(res, 400, 'Valid waiting reason ID is required');
    }

    const [result] = await db.query(
      `UPDATE hrms_field_waiting_reasons
       SET review_status = 'reviewed',
           reviewed_by = ?,
           reviewed_at = CURRENT_TIMESTAMP
       WHERE id = ?`,
      [req.user.id, reasonId]
    );

    if (!result.affectedRows) {
      return fail(res, 404, 'Waiting reason not found');
    }

    return ok(res, null, 'Waiting reason reviewed');
  } catch (error) {
    return fail(res, 500, error.message);
  }
}



async function monthlyReport(req, res) {
  try {
    const employeeUserId = Number(req.params.employeeUserId);
    if (!employeeUserId) return fail(res, 400, 'Valid employeeUserId is required');

    const monthParam = String(req.query.month || '').slice(0, 7);
    if (!/^\d{4}-\d{2}$/.test(monthParam)) {
      return fail(res, 400, 'month must be YYYY-MM');
    }

    const [year, month] = monthParam.split('-').map(Number);
    const firstDay = `${monthParam}-01`;
    const lastDay = new Date(Date.UTC(year, month, 0)).toISOString().slice(0, 10);

    const [profiles] = await db.query(
      `SELECT full_name, employee_code, work_mode FROM hrms_employee_profiles WHERE employee_user_id = ? LIMIT 1`,
      [employeeUserId]
    );
    if (!profiles.length) return fail(res, 404, 'Employee not found');
    const profile = profiles[0];

    const [attendance] = await db.query(
      `SELECT DATE_FORMAT(attendance_date, '%Y-%m-%d') AS date,
              check_in_at, check_out_at, is_late, working_minutes,
              attendance_status, check_in_method, session_status
       FROM attendance_records
       WHERE employee_id = ? AND attendance_date BETWEEN ? AND ?
       ORDER BY attendance_date ASC`,
      [employeeUserId, firstDay, lastDay]
    );

    const [pingSummary] = await db.query(
      `SELECT DATE_FORMAT(recorded_at, '%Y-%m-%d') AS date,
              COUNT(*) AS ping_count
       FROM hrms_location_pings
       WHERE employee_user_id = ? AND DATE(recorded_at) BETWEEN ? AND ?
       GROUP BY DATE_FORMAT(recorded_at, '%Y-%m-%d')`,
      [employeeUserId, firstDay, lastDay]
    );

    const [fieldSessions] = await db.query(
      `SELECT DATE_FORMAT(started_at, '%Y-%m-%d') AS date,
              COUNT(*) AS session_count,
              SUM(TIMESTAMPDIFF(MINUTE, started_at, IFNULL(stopped_at, NOW()))) AS field_minutes
       FROM hrms_field_tracking_sessions
       WHERE employee_user_id = ? AND DATE(started_at) BETWEEN ? AND ?
       GROUP BY DATE_FORMAT(started_at, '%Y-%m-%d')`,
      [employeeUserId, firstDay, lastDay]
    );

    const attendanceMap = new Map(attendance.map(function (r) { return [r.date, r]; }));
    const pingMap = new Map(pingSummary.map(function (r) { return [r.date, r]; }));
    const sessionMap = new Map(fieldSessions.map(function (r) { return [r.date, r]; }));

    const today = policy.todayIstDate();
    const days = [];
    for (let d = new Date(Date.UTC(year, month - 1, 1)); isoDate(d) <= lastDay && isoDate(d) <= today; d.setUTCDate(d.getUTCDate() + 1)) {
      const dateStr = isoDate(d);
      const att = attendanceMap.get(dateStr);
      const pings = pingMap.get(dateStr);
      const sessions = sessionMap.get(dateStr);

      let status = 'Absent';
      if (att) {
        if (att.attendance_status === 'absent') {
          status = 'Absent';
        } else if (att.check_in_at && att.check_out_at) {
          status = att.is_late ? 'Late' : 'Present';
        } else if (att.check_in_at) {
          status = att.is_late ? 'Late (in)' : 'Checked In';
        }
      }

      const weekday = new Date(Date.UTC(year, month - 1, d.getUTCDate())).getUTCDay();

      days.push({
        date: dateStr,
        weekday: ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][weekday],
        status: status,
        checkIn: att && att.check_in_at ? policy.formatDisplayTime(att.check_in_at) : null,
        checkOut: att && att.check_out_at ? policy.formatDisplayTime(att.check_out_at) : null,
        workingMinutes: att ? Number(att.working_minutes || 0) : 0,
        isLate: att ? Boolean(att.is_late) : false,
        method: att ? (att.check_in_method || null) : null,
        pingCount: pings ? Number(pings.ping_count) : 0,
        fieldSessions: sessions ? Number(sessions.session_count) : 0,
        fieldMinutes: sessions ? Math.round(Number(sessions.field_minutes || 0)) : 0,
      });
    }

    const presentDays = days.filter(function (d) { return d.status === 'Present' || d.status === 'Late' || d.status === 'Checked In' || d.status === 'Late (in)'; }).length;
    const lateDays = days.filter(function (d) { return d.isLate; }).length;
    const totalPings = days.reduce(function (sum, d) { return sum + d.pingCount; }, 0);

    return ok(res, {
      employeeUserId: employeeUserId,
      name: profile.full_name,
      employeeCode: profile.employee_code,
      workMode: profile.work_mode,
      month: monthParam,
      days: days,
      summary: {
        presentDays: presentDays,
        lateDays: lateDays,
        absentDays: days.length - presentDays,
        totalPings: totalPings,
        totalDays: days.length,
      },
    });
  } catch (error) {
    console.error('GET /hrms/tracking/employee/:id/monthly', error);
    return fail(res, 500, error.message);
  }
}

async function updateHomeSettings(req, res) {
  try {
    const [rows] = await db.query('SELECT * FROM hrms_tracking_settings WHERE id = 1');
    if (!rows.length) return fail(res, 404, 'Tracking settings not found');
    const current = rows[0];

    const homeRadiusMeters = req.body.homeRadiusMeters != null
      ? Number(req.body.homeRadiusMeters) : Number(current.home_radius_meters);
    const homeOutsideRadiusGraceMinutes = req.body.homeOutsideRadiusGraceMinutes != null
      ? Number(req.body.homeOutsideRadiusGraceMinutes) : Number(current.home_outside_radius_grace_minutes);
    const homeNoGpsTimeoutMinutes = req.body.homeNoGpsTimeoutMinutes != null
      ? Number(req.body.homeNoGpsTimeoutMinutes) : Number(current.home_no_gps_timeout_minutes);
    const homeTrackingEnabled = req.body.homeTrackingEnabled != null
      ? (req.body.homeTrackingEnabled ? 1 : 0) : Number(current.home_tracking_enabled !== 0 ? 1 : 0);

    if (![homeRadiusMeters, homeOutsideRadiusGraceMinutes, homeNoGpsTimeoutMinutes].every(value => Number.isSafeInteger(value) && value > 0)) {
      return fail(res, 400, 'Invalid home settings');
    }

    await db.query(
      `UPDATE hrms_tracking_settings
       SET home_radius_meters = ?,
           home_outside_radius_grace_minutes = ?,
           home_no_gps_timeout_minutes = ?,
           home_tracking_enabled = ?,
           updated_by = ?
       WHERE id = 1`,
      [homeRadiusMeters, homeOutsideRadiusGraceMinutes, homeNoGpsTimeoutMinutes, homeTrackingEnabled, req.user.id]
    );

    return getTrackingSettings(req, res);
  } catch (error) {
    console.error('PUT /hrms/tracking/home-settings', error);
    return fail(res, 500, error.message);
  }
}

async function updateHybridSettings(req, res) {
  try {
    const [rows] = await db.query('SELECT * FROM hrms_tracking_settings WHERE id = 1');
    if (!rows.length) return fail(res, 404, 'Tracking settings not found');
    const current = rows[0];

    const fieldWaitingMinutes = Number(req.body.fieldWaitingMinutes ?? current.field_waiting_minutes);
    const stationaryRadiusMeters = Number(req.body.stationaryRadiusMeters ?? current.stationary_radius_meters);
    const fieldPingIntervalMinutes = Number(req.body.fieldPingIntervalMinutes ?? current.field_ping_interval_minutes);
    const officeOutsideRadiusGraceMinutes = req.body.officeOutsideRadiusGraceMinutes != null
      ? Number(req.body.officeOutsideRadiusGraceMinutes) : Number(current.office_outside_radius_grace_minutes);
    const officeNoGpsTimeoutMinutes = req.body.officeNoGpsTimeoutMinutes != null
      ? Number(req.body.officeNoGpsTimeoutMinutes) : Number(current.office_no_gps_timeout_minutes);

    if (![fieldWaitingMinutes, stationaryRadiusMeters, fieldPingIntervalMinutes, officeOutsideRadiusGraceMinutes, officeNoGpsTimeoutMinutes].every(value => Number.isSafeInteger(value) && value > 0)) {
      return fail(res, 400, 'Invalid hybrid settings');
    }

    await db.query(
      `UPDATE hrms_tracking_settings
       SET field_waiting_minutes = ?,
           stationary_radius_meters = ?,
           field_ping_interval_minutes = ?,
           office_outside_radius_grace_minutes = ?,
           office_no_gps_timeout_minutes = ?,
           updated_by = ?
       WHERE id = 1`,
      [fieldWaitingMinutes, stationaryRadiusMeters, fieldPingIntervalMinutes,
       officeOutsideRadiusGraceMinutes, officeNoGpsTimeoutMinutes, req.user.id]
    );

    return getTrackingSettings(req, res);
  } catch (error) {
    console.error('PUT /hrms/tracking/hybrid-settings', error);
    return fail(res, 500, error.message);
  }
}

module.exports = {
  detectFieldWaitingTime,
  requireAdmin,
  list,
  setStatus,
  ping,
  liveOverview,
  routeHistory,
  myRouteHistory,
  getTrackingSettings,
  updateTrackingSettings,
  updateHomeSettings,
  updateHybridSettings,
  getMyHomeLocation,
  submitHomeLocation,
  listHomeLocations,
  reviewHomeLocation,
  getMyFieldSession,
startFieldTracking,
stopFieldTracking,
getMyWaitingAlert,
submitWaitingReason,
listFieldWaitingReasons,
reviewFieldWaitingReason,
  monthlyReport,
};
