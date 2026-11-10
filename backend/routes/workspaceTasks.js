// routes/workspaceTasks.js — Employee Workspace data
// Mount in server.js:  app.use('/api/workspace-tasks', require('./routes/workspaceTasks'));
//
//   GET   /cards?employee=                       client + deadline cards (only the employee's own tasks)
//   GET   /my-tasks?employee=&client=&date=      rows for the My Tasks table
//   POST  /my-tasks/:id/sub-rows                 Ads Handler: add 1.1, 1.2 … under a main row
//   PATCH /my-tasks/:id                          edit a nested row (description / submit date only)
//   GET   /review?employee=&client=&date=        Task Review tab
//
// Row "state" (what the UI shows):
//   IDLE | IN PROGRESS | ON HOLD | IN REVIEW (completed, waiting) | REWORK | APPROVED | REJECTED
const express = require('express');
const router = express.Router();
const db = require('../config/db');
const { touchedOn, localDay, syncDayPlanStatus } = require('../lib/dayPlanSync');
const { ensureWorkspaceTaskSchemaOnce } = require('../lib/ensureWorkspaceTaskSchema');
const { ensureEventsTable } = require('../lib/assignmentEvents');

// Make sure the nested-row / review columns exist before any query runs.
router.use(async (req, res, next) => {
  try {
    await ensureWorkspaceTaskSchemaOnce(db);
    next();
  } catch (err) {
    console.error('Workspace schema check failed:', err.message);
    res.status(500).json({ success: false, message: `Database setup failed: ${err.message}` });
  }
});

// direct: true  → tasks go straight to the employee's My Tasks once the admin
//                 assigns them (no Content Calendar preparation).
// Otherwise the Page / Ads Handler prepares the rows in the Content Calendar
// first and they appear after "Assign All".
const ROLES = [
  { key: 'designer', label: 'Designer', emp: 'designer', tasks: 'designer_tasks' },
  { key: 'videographer', label: 'Videographer', emp: 'videographer', tasks: 'videographer_tasks' },
  { key: 'video_editor', label: 'Video Editor', emp: 'video_editor', tasks: 'video_editor_task' },
  { key: 'website_designer', label: 'Website Designer', emp: 'website_designer', tasks: 'website_designer_tasks', rich: true },
  { key: 'ui_ux_designer', label: 'UI/UX Designer', emp: 'ui_ux_designer', tasks: 'ui_ux_tasks', direct: true },
  { key: 'developer', label: 'Developer', emp: 'developer', tasks: 'developer_tasks', direct: true },
  { key: 'ads_handling', label: 'Ads Handler', emp: 'ads_handling', tasks: 'ads_platform', direct: true, nested: true },
  { key: 'page_handling', label: 'Page Handler', emp: 'page_handling', tasks: 'pages_platform', direct: true },
];

const norm = (v) => String(v ?? '').trim().replace(/\s+/g, ' ').toLowerCase();
const upper = (v) => String(v ?? '').trim().toUpperCase();
const pad = (n) => String(n).padStart(2, '0');

// "Arun .", "ARUN", "arun" all match; a cell may list several people
// ("Arun, Priya" / "Arun & Priya").
const personKey = (v) => String(v ?? '').toLowerCase().replace(/[^a-z0-9]+/g, '');
function namesEmployee(cell, employee) {
  const me = personKey(employee);
  if (!me) return false;
  return String(cell ?? '')
    .split(/,|&|\/|\band\b/i)
    .some((part) => personKey(part) === me);
}

function dateKey(value) {
  if (!value) return '';
  if (value instanceof Date) {
    if (Number.isNaN(value.getTime())) return '';
    return `${value.getFullYear()}-${pad(value.getMonth() + 1)}-${pad(value.getDate())}`;
  }
  const s = String(value).trim();
  const dmy = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})/);
  if (dmy) return `${dmy[3]}-${pad(dmy[2])}-${pad(dmy[1])}`;
  return s.slice(0, 10);
}

function parseTasks(value) {
  return String(value || '')
    .split(',')
    .map((entry, taskIndex) => {
      const match = entry.trim().match(/^(.*?)\s*\((\d+)\)\s*$/);
      return {
        name: (match ? match[1] : entry).trim(),
        count: match ? Number(match[2]) : 1,
        taskIndex,
      };
    })
    .filter((t) => t.name && Number.isSafeInteger(t.count) && t.count > 0);
}

function employeeFrom(req) {
  return String(
    req.query.employee || req.body?.employee || req.user?.fullName || req.user?.full_name || '',
  ).trim();
}

function workingDuration(row) {
  if (!row.start_time) return Number(row.duration_secs) || 0;
  let total = 0;
  let activeStart = new Date(row.start_time);
  for (let i = 1; i <= 10; i += 1) {
    const hold = row[`hold_time_${i}`];
    const restart = row[`restart_time_${i}`];
    if (hold && activeStart) {
      const h = new Date(hold);
      if (h > activeStart) total += Math.floor((h - activeStart) / 1000);
      activeStart = null;
    }
    if (restart) activeStart = new Date(restart);
    else if (hold) { activeStart = null; break; }
  }
  if (activeStart) {
    const end = row.complete_time ? new Date(row.complete_time) : new Date();
    if (end > activeStart) total += Math.floor((end - activeStart) / 1000);
  }
  return total;
}

function rowState(row) {
  const status = upper(row.status || 'IDLE');
  const review = upper(row.review_status);
  if (review === 'APPROVED') return 'APPROVED';
  // Rejected by the reviewer: shown as REJECTED until the employee restarts it
  // (RESTART continues the same timer, like rework).
  if (review === 'REJECTED' && ['REWORK', 'REJECTED', 'IDLE'].includes(status)) return 'REJECTED';
  if (status === 'REWORK') return 'REWORK';
  // Rework requested: until the employee restarts it, it is still "REWORK"
  // even if an older screen saved the status back to IDLE.
  if (review === 'REWORK' && !['IN PROGRESS', 'ON HOLD'].includes(status)) return 'REWORK';
  if (status === 'COMPLETED') return review === 'REJECTED' ? 'REJECTED' : 'IN REVIEW';
  if (status === 'REJECTED') return 'REJECTED';
  return status || 'IDLE';
}

// Active clients only: is_active = 1, and when the clients table also keeps a
// text status (status / client_status / account_status) it must not say
// Inactive / Disabled / Closed. Cached for 5 s (many calls per request).
let activeClientCache = { at: 0, set: null };
let clientStatusCols = null;
async function activeClientSet() {
  if (activeClientCache.set && Date.now() - activeClientCache.at < 5000) return activeClientCache.set;
  if (!clientStatusCols) {
    try {
      const [cols] = await db.query(
        `SELECT COLUMN_NAME AS c FROM information_schema.COLUMNS
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'clients'`,
      );
      const have = new Set(cols.map((r) => r.c));
      clientStatusCols = ['status', 'client_status', 'account_status'].filter((c) => have.has(c));
    } catch (_) {
      clientStatusCols = [];
    }
  }
  const extra = clientStatusCols.map((c) => `, \`${c}\``).join('');
  const [rows] = await db.query(`SELECT company_name${extra} FROM clients WHERE is_active = 1`);
  const inactive = /^(in-?\s*active|disabled|closed|deactivated)/i;
  const set = new Set(rows
    .filter((r) => clientStatusCols.every((c) => !inactive.test(String(r[c] ?? '').trim())))
    .map((r) => norm(r.company_name)));
  activeClientCache = { at: Date.now(), set };
  return set;
}

async function employeeIdFor(name) {
  const [rows] = await db.query(
    'SELECT id FROM employee_users WHERE LOWER(TRIM(full_name)) = LOWER(TRIM(?)) LIMIT 1',
    [name],
  );
  return rows[0]?.id ?? null;
}

// Every (assignment, role, task) where THIS employee is the person named for that role.
async function employeeAssignments(employee, clientName = null) {
  const params = [];
  let where = 'is_assigned = 1';
  if (clientName) {
    where += ' AND LOWER(TRIM(client_name)) = LOWER(TRIM(?))';
    params.push(clientName);
  }
  const [rows] = await db.query(
    `SELECT * FROM task_assignments WHERE ${where} ORDER BY id ASC`,
    params,
  );
  const active = await activeClientSet();
  const out = [];
  for (const assignment of rows) {
    if (!active.has(norm(assignment.client_name))) continue;
    for (const role of ROLES) {
      if (!namesEmployee(assignment[role.emp], employee)) continue;
      for (const task of parseTasks(assignment[role.tasks])) {
        out.push({ assignment, role, task });
      }
    }
  }
  return out;
}

const deadlineOf = (a) => dateKey(a.deadline || a.maintenance_date);

async function findTaskList(assignmentId, taskName, employee, employeeId) {
  const [rows] = await db.query(
    `SELECT id, no_of_rows, task_timing_id, submission_date
     FROM task_list
     WHERE task_assignment_id = ?
       AND LOWER(TRIM(deliverables)) = LOWER(TRIM(?))
       AND (employee_id = ? OR LOWER(TRIM(employee_name)) = LOWER(TRIM(?)))
     ORDER BY id DESC LIMIT 1`,
    [assignmentId, taskName, employeeId ?? -1, employee],
  );
  return rows[0] || null;
}

// Page / Ads handler tasks: make sure the task_list + one tracking row per assigned count exist.
async function ensureHandlerRows(assignment, task, employee, employeeId) {
  let taskList = await findTaskList(assignment.id, task.name, employee, employeeId);
  const deadline = deadlineOf(assignment) || null;
  if (!taskList) {
    const [ins] = await db.query(
      `INSERT INTO task_list
         (task_assignment_id, employee_id, employee_name, client_name,
          deliverables, submission_date, no_of_rows)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [assignment.id, employeeId, employee, assignment.client_name, task.name, deadline, task.count],
    );
    taskList = { id: ins.insertId, no_of_rows: task.count, task_timing_id: null };
  }
  const needed = Math.max(task.count, Number(taskList.no_of_rows) || 0);
  const [existing] = await db.query(
    'SELECT s_no FROM time_tracking_task_items WHERE task_list_id = ? AND parent_item_id IS NULL',
    [taskList.id],
  );
  const have = new Set(existing.map((r) => Number(r.s_no)));
  for (let sNo = 1; sNo <= needed; sNo += 1) {
    if (have.has(sNo)) continue;
    await db.query(
      `INSERT INTO time_tracking_task_items
         (task_list_id, task_timing_id, s_no, sub_no, submit_date, task_description,
          duration_secs, comment, performance, status)
       VALUES (?, ?, ?, 0, ?, ?, 0, '', 'N/A', 'IDLE')`,
      [taskList.id, taskList.task_timing_id ?? null, sNo, deadline, task.name],
    );
  }
  return taskList;
}

const ROW_SELECT = `
  SELECT tti.*, tl.deliverables, tl.client_name, tl.employee_name,
         tl.submission_date AS tl_submission_date,
         ta.deadline AS ta_deadline, ta.maintenance_date AS ta_maintenance,
         mr.manager_action, mr.manager_comment, mr.reviewed_at
  FROM time_tracking_task_items tti
  JOIN task_list tl ON tl.id = tti.task_list_id
  LEFT JOIN task_assignments ta ON ta.id = tl.task_assignment_id
  LEFT JOIN manager_review mr ON mr.tracking_item_id = tti.id`;

// The client card / workspace date is the admin assignment's deadline, so
// filter rows by that (falling back to the list / row dates for additional
// tasks). Using only tti.submit_date hid rows saved by older screens.
const dueKey = (r) =>
  dateKey(r.ta_deadline || r.ta_maintenance || r.tl_submission_date || r.submit_date);

// Non-handler roles only see rows the Page/Ads Handler has prepared and assigned.
async function loadRows(taskListId, handedOffOnly) {
  const [rows] = await db.query(
    `${ROW_SELECT}
     WHERE tti.task_list_id = ?
       ${handedOffOnly ? `AND (tti.content_calendar_assigned = 1 OR tti.parent_item_id IS NOT NULL
             OR tti.start_time IS NOT NULL OR UPPER(COALESCE(tti.status, 'IDLE')) <> 'IDLE')` : ''}
     ORDER BY tti.s_no ASC, tti.sub_no ASC, tti.id ASC`,
    [taskListId],
  );
  return rows;
}

const INHERITED = ['hook_headline', 'caption', 'cta', 'notes', 'publish_date'];

function shapeRows(rows) {
  const byId = new Map(rows.map((r) => [r.id, r]));
  return rows.map((r) => {
    const parent = r.parent_item_id ? byId.get(r.parent_item_id) : null;
    const pick = (field) => {
      const own = r[field];
      if (own !== null && own !== undefined && own !== '') return own;
      return parent ? parent[field] : own;
    };
    const subNo = Number(r.sub_no) || 0;
    const state = rowState(r);
    return {
      id: r.id,
      task_list_id: r.task_list_id,
      parent_item_id: r.parent_item_id,
      s_no: r.s_no,
      sub_no: subNo,
      display_no: subNo > 0 ? `${r.s_no}.${subNo}` : `${r.s_no}`,
      deliverable: r.deliverables,
      client_name: r.client_name,
      employee_name: r.employee_name || '',
      submit_date: dateKey(r.submit_date || r.tl_submission_date),
      publish_date: dateKey(pick('publish_date')),
      hook_headline: pick('hook_headline') || '',
      description_points: r.description_points || (subNo > 0 ? '' : (parent?.description_points || '')),
      caption: pick('caption') || '',
      cta: pick('cta') || '',
      notes: pick('notes') || '',
      employee_notes: r.employee_notes || '',
      description_rich: r.description_rich || '',
      task_description: r.task_description || '',
      comment: r.comment || '',
      // No task duration (additional / handler rows): finished = Achieved.
      performance: (!r.performance || r.performance === 'N/A') && !r.task_timing_id &&
        ['IN REVIEW', 'APPROVED'].includes(state)
        ? 'Achieved'
        : r.performance || 'N/A',
      status: upper(r.status || 'IDLE'),
      review_status: upper(r.review_status),
      state,
      current_secs: upper(r.status) === 'IN PROGRESS' ? workingDuration(r) : Number(r.duration_secs) || 0,
      start_time: r.start_time,
      complete_time: r.complete_time,
      manager_action: r.manager_action || 'ACTION',
      manager_comment: r.manager_comment || '',
      reviewed_at: r.reviewed_at,
    };
  });
}

function countStates(rows, assignedCount) {
  const counts = { approved: 0, in_review: 0, rework: 0, in_progress: 0, on_hold: 0, rejected: 0 };
  let topLevel = 0;
  let subRows = 0;
  for (const r of rows) {
    if (r.parent_item_id) subRows += 1; else topLevel += 1;
    const s = rowState(r);
    if (s === 'APPROVED') counts.approved += 1;
    else if (s === 'IN REVIEW') counts.in_review += 1;
    else if (s === 'REWORK') counts.rework += 1;
    else if (s === 'IN PROGRESS') counts.in_progress += 1;
    else if (s === 'ON HOLD') counts.on_hold += 1;
    else if (s === 'REJECTED') counts.rejected += 1;
  }
  const total = Math.max(assignedCount, topLevel) + subRows;
  const used = Object.values(counts).reduce((a, b) => a + b, 0);
  return { total, pending: Math.max(total - used, 0), ...counts };
}

async function additionalLists(employee, employeeId, clientName = null) {
  const params = [employeeId ?? -1, employee];
  let clientSql = '';
  if (clientName) {
    clientSql = 'AND LOWER(TRIM(client_name)) = LOWER(TRIM(?))';
    params.push(clientName);
  }
  const [rows] = await db.query(
    `SELECT id, client_name, deliverables, submission_date, no_of_rows
     FROM task_list
     WHERE additional_task_id IS NOT NULL
       AND (employee_id = ? OR LOWER(TRIM(employee_name)) = LOWER(TRIM(?)))
       ${clientSql}
     ORDER BY id ASC`,
    params,
  );
  const active = await activeClientSet();
  return rows.filter((r) => active.has(norm(r.client_name)));
}

// Rows moved to this employee from the Content Calendar "Edit" (they are not
// the role's named person on the admin assignment).
async function reassignedLists(employee, employeeId, coveredIds, clientName = null) {
  const params = [employeeId ?? -1, employee];
  let clientSql = '';
  if (clientName) {
    clientSql = 'AND LOWER(TRIM(tl.client_name)) = LOWER(TRIM(?))';
    params.push(clientName);
  }
  const [rows] = await db.query(
    `SELECT tl.id, tl.client_name, tl.deliverables, tl.no_of_rows,
            COALESCE(ta.deadline, ta.maintenance_date, tl.submission_date) AS due
     FROM task_list tl
     JOIN task_assignments ta ON ta.id = tl.task_assignment_id
     WHERE tl.additional_task_id IS NULL
       AND (tl.employee_id = ? OR LOWER(TRIM(tl.employee_name)) = LOWER(TRIM(?)))
       ${clientSql}
       AND EXISTS (SELECT 1 FROM time_tracking_task_items tti
                   WHERE tti.task_list_id = tl.id AND tti.content_calendar_assigned = 1)`,
    params,
  );
  const active = await activeClientSet();
  return rows.filter((r) => !coveredIds.has(r.id) && active.has(norm(r.client_name)));
}

// Who gave this employee the rows of a list that is NOT theirs on the admin
// assignment (Content Calendar reassign / emergency assign / Assign All by a
// Page or Ads Handler). → { name, role } e.g. { name: 'VIJI', role: 'Page Handler' }
const SYSTEM_ASSIGNERS = new Set(['', 'task assignment', 'admin', 'system']);
async function assignedByFor(listId, clientName) {
  let name = '';
  try {
    const [[r]] = await db.query(
      `SELECT cc.assigned_by_name AS cc_by, tti.cc_assigned_by_name AS tti_by
       FROM time_tracking_task_items tti
       LEFT JOIN content_calendar cc ON cc.task_item_id = tti.id
       WHERE tti.task_list_id = ?
       ORDER BY (cc.assigned_by_name IS NULL), tti.id DESC
       LIMIT 1`,
      [listId],
    );
    for (const v of [r?.cc_by, r?.tti_by]) {
      if (!SYSTEM_ASSIGNERS.has(norm(v))) { name = String(v).trim(); break; }
    }
  } catch (err) {
    // content_calendar / cc_assigned_by_name missing on an old database
  }
  if (!name) return null;
  let role = '';
  const [assignments] = await db.query(
    `SELECT page_handling, ads_handling FROM task_assignments
     WHERE LOWER(TRIM(client_name)) = LOWER(TRIM(?))`,
    [clientName],
  );
  for (const a of assignments) {
    if (namesEmployee(a.page_handling, name)) { role = 'Page Handler'; break; }
    if (namesEmployee(a.ads_handling, name)) { role = 'Ads Handler'; break; }
  }
  if (!role) {
    const [[u]] = await db.query(
      `SELECT * FROM employee_users WHERE LOWER(TRIM(full_name)) = LOWER(TRIM(?)) LIMIT 1`,
      [name],
    );
    const text = norm(u?.role || u?.designation || u?.department || '');
    if (text.includes('ads')) role = 'Ads Handler';
    else if (text.includes('page') || text.includes('handler')) role = 'Page Handler';
  }
  return { name, role };
}

// Card flag for the "ADDITIONAL TASK" ribbon + "Assigned by …" line.
function markAdditional(card, by) {
  card.additional = true;
  if (!by) return;
  const label = by.role ? `${by.name} (${by.role})` : by.name;
  card.additional_by = card.additional_by || [];
  if (!card.additional_by.includes(label)) card.additional_by.push(label);
}

const emit = (req, payload) => req.app.get('io')?.emit('task_updated', payload);

// Monthly "maintain day" (e.g. '12') from a task_assignments.maintenance_date
// that may be "12", "12/11/2026" or a real date.
function maintenanceDay(value) {
  const raw = String(value ?? '').trim();
  if (/^\d{1,2}$/.test(raw)) return raw;
  return dateKey(value).slice(8, 10);
}

// ─────────────────────────────────────────────────────────────────────────────
// Everyone assigned on this client (+ deadline): role, person, and each task
// category with completed (approved) / total.
async function clientTeam(clientName, date = '') {
  const [assignments] = await db.query(
    `SELECT * FROM task_assignments
     WHERE is_assigned = 1 AND LOWER(TRIM(client_name)) = LOWER(TRIM(?))
     ORDER BY id ASC`,
    [clientName],
  );
  const idCache = new Map();
  const team = new Map();
  for (const assignment of assignments) {
    if (date && deadlineOf(assignment) !== date) continue;
    for (const role of ROLES) {
      const people = String(assignment[role.emp] || '')
        .split(/,|&/)
        .map((p) => p.trim())
        .filter((p) => p && p.toUpperCase() !== 'NONE');
      for (const person of people) {
        if (!idCache.has(personKey(person))) idCache.set(personKey(person), await employeeIdFor(person));
        const personId = idCache.get(personKey(person));
        const key = `${role.key}|${personKey(person)}`;
        const entry = team.get(key) || { role: role.label, role_key: role.key, employee: person, tasks: [] };
        for (const task of parseTasks(assignment[role.tasks])) {
          const list = await findTaskList(assignment.id, task.name, person, personId);
          const rows = list ? await loadRows(list.id, !role.direct) : [];
          const parents = rows.filter((r) => !r.parent_item_id);
          entry.tasks.push({
            name: task.name,
            completed: parents.filter((r) => rowState(r) === 'APPROVED').length,
            total: Math.max(task.count, parents.length),
          });
        }
        if (entry.tasks.length) team.set(key, entry);
      }
    }
  }

  // Additional work on this client / date (admin, Page / Ads Handler or self added).
  const extra = new Map();
  try {
    const params = [clientName];
    let dateSql = '';
    if (date) {
      dateSql = 'AND DATE(submission_date) = ?';
      params.push(date);
    }
    const [lists] = await db.query(
      `SELECT id, employee_name, deliverables, no_of_rows, submission_date FROM task_list
       WHERE additional_task_id IS NOT NULL AND LOWER(TRIM(client_name)) = LOWER(TRIM(?)) ${dateSql}
       ORDER BY id ASC`,
      params,
    );
    for (const list of lists) {
      if (!list.employee_name) continue;
      const rows = await loadRows(list.id, false);
      const parents = rows.filter((r) => !r.parent_item_id);
      const by = await assignedByFor(list.id, clientName);
      const key = personKey(list.employee_name);
      const entry = extra.get(key) || {
        role: 'Additional task',
        role_key: 'additional',
        additional: true,
        employee: String(list.employee_name).trim(),
        tasks: [],
      };
      entry.tasks.push({
        name: list.deliverables,
        completed: parents.filter((r) => ['APPROVED', 'IN REVIEW'].includes(rowState(r))).length,
        total: Math.max(Number(list.no_of_rows) || 0, parents.length),
        added_by: by ? (by.role ? `${by.name} (${by.role})` : by.name) : 'Admin',
        submit_date: dateKey(list.submission_date),
      });
      extra.set(key, entry);
    }
  } catch (err) {
    console.error('clientTeam additional lists failed:', err.message);
  }
  return [...team.values(), ...extra.values()];
}

router.get('/cards', async (req, res) => {
  const employee = employeeFrom(req);
  if (!employee) return res.status(400).json({ success: false, message: 'employee is required' });
  try {
    const employeeId = await employeeIdFor(employee);
    const cards = new Map();
    const cardByAssignment = new Map(); // assignment id → card (Content Calendar)
    const cardFor = (client, date) => {
      const key = `${norm(client)}|${date}`;
      if (!cards.has(key)) {
        cards.set(key, { client_name: String(client).trim(), submission_date: date, tasks: [] });
      }
      return cards.get(key);
    };

    for (const { assignment, role, task } of await employeeAssignments(employee)) {
      const taskList = await findTaskList(assignment.id, task.name, employee, employeeId);
      const rows = taskList ? await loadRows(taskList.id, !role.direct) : [];
      // Designer / Video / Website work finished in the old Assigned Task page
      // without a Content Calendar share → nothing left to do here, hide it.
      if (!role.direct && rows.length && rows.every((r) =>
        Number(r.content_calendar_assigned) !== 1 && !r.parent_item_id &&
        ['IN REVIEW', 'APPROVED'].includes(rowState(r)))) {
        continue;
      }
      const card = cardFor(assignment.client_name, deadlineOf(assignment));
      cardByAssignment.set(String(assignment.id), card);
      // Package + monthly maintain day (from Tasks Assign) for the client card.
      card.package = card.package || String(assignment.deliverables || '').trim();
      card.maintenance_day = card.maintenance_day || maintenanceDay(assignment.maintenance_date);
      // Latest assignment time → the "NEW" ribbon on the card.
      const created = assignment.created_at ? new Date(assignment.created_at) : null;
      if (created && !Number.isNaN(created.getTime()) &&
          (!card.assigned_at || created > new Date(card.assigned_at))) {
        card.assigned_at = created.toISOString();
      }
      card.tasks.push({
        key: `${assignment.id}:${role.key}:${task.taskIndex}`,
        task_list_id: taskList?.id ?? null,
        name: task.name,
        role: role.label,
        role_key: role.key,
        is_additional: false,
        awaiting_handoff: !role.direct && rows.length === 0,
        ...countStates(rows, task.count),
      });
    }

    const coveredIds = new Set();
    for (const card of cards.values()) for (const t of card.tasks) if (t.task_list_id) coveredIds.add(t.task_list_id);
    for (const list of await reassignedLists(employee, employeeId, coveredIds)) {
      const rows = await loadRows(list.id, true);
      const card = cardFor(list.client_name, dateKey(list.due));
      const by = await assignedByFor(list.id, list.client_name);
      markAdditional(card, by);
      card.tasks.push({
        key: `reassigned:${list.id}`,
        name: list.deliverables,
        role: 'Reassigned task',
        role_key: 'reassigned',
        is_additional: false,
        handler_assigned: true,
        assigned_by: by?.name || '',
        assigned_by_role: by?.role || '',
        awaiting_handoff: false,
        ...countStates(rows, rows.length),
      });
    }

    for (const list of await additionalLists(employee, employeeId)) {
      const rows = await loadRows(list.id, false);
      const card = cardFor(list.client_name, dateKey(list.submission_date));
      const by = await assignedByFor(list.id, list.client_name);
      markAdditional(card, by || { name: 'Admin', role: '' });
      card.tasks.push({
        key: `additional:${list.id}`,
        name: list.deliverables,
        role: 'Additional task',
        role_key: 'additional',
        is_additional: true,
        handler_assigned: !!by,
        assigned_by: by?.name || 'Admin',
        assigned_by_role: by?.role || '',
        awaiting_handoff: false,
        ...countStates(rows, Number(list.no_of_rows) || 1),
      });
    }

    // Content Calendar categories this handler prepares count as one task
    // each — a running category makes the card PROCESSING, a held one HOLD.
    try {
      const sheets = await employeeSheets(employee, null, { includeStartable: true });
      for (const sh of sheets) {
        if (!sh.source_assignment_id) continue;
        const card = cardByAssignment.get(String(sh.source_assignment_id)) ||
          [...cards.values()].find((c) => norm(c.client_name) === norm(sh.client) &&
            c.submission_date === sh.due_date);
        if (!card) continue;
        const st = upper(sh.status);
        const done = st === 'ASSIGNED' || st === 'COMPLETED';
        card.tasks.push({
          key: sh.key,
          task_list_id: null,
          name: `Content Calendar · ${sh.deliverable}`,
          role: 'Content Calendar',
          role_key: 'content_calendar',
          is_additional: false,
          awaiting_handoff: false,
          total: 1,
          approved: done ? 1 : 0,
          in_progress: st === 'IN PROGRESS' ? 1 : 0,
          on_hold: st === 'ON HOLD' ? 1 : 0,
          in_review: 0,
          rework: 0,
          rejected: 0,
          pending: !done && st !== 'IN PROGRESS' && st !== 'ON HOLD' ? 1 : 0,
        });
      }
    } catch (err) {
      console.error('cards: content calendar summary failed:', err.message);
    }

    // Ads / Page Handler: how much team work on this client+date waits for them.
    const reviewerClients = new Set();
    for (const card of cards.values()) {
      if (!reviewerClients.has(norm(card.client_name))) {
        const ids = await reviewerAssignmentIds(employee, card.client_name);
        if (ids.length) reviewerClients.add(norm(card.client_name));
      }
    }
    for (const card of cards.values()) {
      card.to_review = 0;
      if (!reviewerClients.has(norm(card.client_name))) continue;
      const review = await buildReview(employee, card.client_name, card.submission_date);
      card.to_review = review.team.filter((r) => r.review_state === 'PENDING').length;
    }

    // Whole team on each card (all roles, people and categories).
    for (const card of cards.values()) {
      card.team = await clientTeam(card.client_name, card.submission_date);
    }

    const data = [...cards.values()].filter((c) => c.tasks.length > 0).sort(
      (a, b) => a.client_name.localeCompare(b.client_name) ||
        a.submission_date.localeCompare(b.submission_date),
    );
    return res.json({ success: true, data });
  } catch (err) {
    console.error('GET /workspace-tasks/cards ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

async function buildMyTasks(employee, client, date) {
    const employeeId = await employeeIdFor(employee);
    const groups = [];
    const items = (await employeeAssignments(employee, client))
      .filter(({ assignment }) => !date || deadlineOf(assignment) === date);

    for (const { assignment, role, task } of items) {
      const taskList = role.direct
        ? await ensureHandlerRows(assignment, task, employee, employeeId)
        : await findTaskList(assignment.id, task.name, employee, employeeId);
      const rows = taskList ? shapeRows(await loadRows(taskList.id, !role.direct)) : [];
      groups.push({
        key: `${assignment.id}:${role.key}:${task.taskIndex}`,
        task_list_id: taskList?.id ?? null,
        assignment_id: assignment.id,
        role: role.key,
        role_label: role.label,
        deliverable: task.name,
        nested: Boolean(role.nested),
        rich: Boolean(role.rich),
        // Page / Ads Handler, Developer, UI/UX: the employee writes the
        // headline / description and sets the submit date themselves.
        editable_content: Boolean(role.direct),
        assigned_count: task.count,
        awaiting_handoff: !role.direct && rows.length === 0,
        submission_date: deadlineOf(assignment),
        rows,
      });
    }

    const covered = new Set(groups.map((g) => g.task_list_id).filter(Boolean));
    for (const list of await reassignedLists(employee, employeeId, covered, client)) {
      if (date && dateKey(list.due) !== date) continue;
      const [[src]] = await db.query(
        `SELECT source_role FROM content_calendar WHERE task_item_id IN
           (SELECT id FROM time_tracking_task_items WHERE task_list_id = ?) LIMIT 1`,
        [list.id],
      );
      groups.push({
        key: `reassigned:${list.id}`,
        task_list_id: list.id,
        assignment_id: null,
        role: src?.source_role || 'reassigned',
        role_label: 'Reassigned task',
        deliverable: list.deliverables,
        nested: false,
        rich: src?.source_role === 'website_designer',
        assigned_count: Number(list.no_of_rows) || 0,
        awaiting_handoff: false,
        submission_date: dateKey(list.due),
        rows: shapeRows(await loadRows(list.id, true)),
      });
    }

    for (const list of await additionalLists(employee, employeeId, client)) {
      if (date && dateKey(list.submission_date) !== date) continue;
      const raw = await loadRows(list.id, false);
      // Rows this employee added themselves (Add Additional Task) → can edit.
      const selfAdded = raw.length > 0 && raw.every((r) => personKey(r.cc_assigned_by_name) === personKey(employee));
      const by = await assignedByFor(list.id, list.client_name);
      groups.push({
        key: `additional:${list.id}`,
        task_list_id: list.id,
        assignment_id: null,
        role: 'additional',
        role_label: selfAdded ? 'Additional task · added by you' : 'Additional task',
        deliverable: list.deliverables,
        nested: false,
        assigned_count: Number(list.no_of_rows) || 1,
        awaiting_handoff: false,
        submission_date: dateKey(list.submission_date),
        editable: selfAdded,
        added_by: by ? (by.role ? `${by.name} (${by.role})` : by.name) : 'Admin',
        rows: shapeRows(raw),
      });
    }
  return groups;
}

router.get('/my-tasks', async (req, res) => {
  const employee = employeeFrom(req);
  const client = String(req.query.client || '').trim();
  const date = dateKey(req.query.date);
  if (!employee || !client) {
    return res.status(400).json({ success: false, message: 'employee and client are required' });
  }
  try {
    return res.json({ success: true, data: await buildMyTasks(employee, client, date) });
  } catch (err) {
    console.error('GET /workspace-tasks/my-tasks ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

router.post('/my-tasks/:id/sub-rows', async (req, res) => {
  const employee = employeeFrom(req);
  try {
    const [[parent]] = await db.query(
      `SELECT tti.*, tl.task_assignment_id, tl.deliverables
       FROM time_tracking_task_items tti
       JOIN task_list tl ON tl.id = tti.task_list_id
       WHERE tti.id = ?`,
      [req.params.id],
    );
    if (!parent) return res.status(404).json({ success: false, message: 'Row not found' });
    if (parent.parent_item_id) {
      return res.status(400).json({ success: false, message: 'Add nested rows from the main row' });
    }
    const [[assignment]] = parent.task_assignment_id
      ? await db.query('SELECT ads_handling, ads_platform FROM task_assignments WHERE id = ?', [parent.task_assignment_id])
      : [[null]];
    const isAdsTask = assignment &&
      namesEmployee(assignment.ads_handling, employee) &&
      parseTasks(assignment.ads_platform).some((t) => norm(t.name) === norm(parent.deliverables));
    if (!isAdsTask) {
      return res.status(403).json({ success: false, message: 'Only the Ads Handler can add nested rows to this task' });
    }

    const [[{ nextSub }]] = await db.query(
      'SELECT COALESCE(MAX(sub_no), 0) + 1 AS nextSub FROM time_tracking_task_items WHERE parent_item_id = ?',
      [parent.id],
    );
    const [ins] = await db.query(
      `INSERT INTO time_tracking_task_items
         (task_list_id, parent_item_id, task_timing_id, s_no, sub_no, submit_date,
          task_description, hook_headline, description_points, caption, cta, notes,
          publish_date, duration_secs, comment, performance, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, '', ?, ?, ?, ?, 0, '', 'N/A', 'IDLE')`,
      [
        parent.task_list_id, parent.id, parent.task_timing_id ?? null, parent.s_no, nextSub,
        parent.submit_date, parent.task_description || parent.deliverables,
        parent.hook_headline ?? null, parent.caption ?? null, parent.cta ?? null,
        parent.notes ?? null, parent.publish_date ?? null,
      ],
    );
    emit(req, { type: 'WORKSPACE_SUB_ROW', trackingItemId: ins.insertId });
    return res.status(201).json({
      success: true,
      message: `Row ${parent.s_no}.${nextSub} added`,
      data: { id: ins.insertId, display_no: `${parent.s_no}.${nextSub}` },
    });
  } catch (err) {
    console.error('POST /workspace-tasks/my-tasks/:id/sub-rows ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// PATCH /my-tasks/:id
//   any row  : employee_notes (the employee's own notes)
//   nested   : description_points, submit_date
router.patch('/my-tasks/:id', async (req, res) => {
  try {
    const [[row]] = await db.query(
      `SELECT id, parent_item_id, review_status, content_calendar_assigned
       FROM time_tracking_task_items WHERE id = ?`,
      [req.params.id],
    );
    if (!row) return res.status(404).json({ success: false, message: 'Row not found' });
    if (upper(row.review_status) === 'APPROVED') {
      return res.status(409).json({ success: false, message: 'This row is approved and can no longer be changed' });
    }
    const sets = [];
    const values = [];
    if (Object.hasOwn(req.body, 'employee_notes')) {
      sets.push('employee_notes = ?');
      values.push(String(req.body.employee_notes ?? '').slice(0, 5000));
    }
    // Content prepared by the handler in the Content Calendar stays read-only;
    // rows the employee owns directly (and nested Ads rows) are editable.
    const contentFields = ['hook_headline', 'description_points', 'submit_date'].filter((k) => Object.hasOwn(req.body, k));
    if (contentFields.length && !row.parent_item_id && Number(row.content_calendar_assigned) === 1) {
      return res.status(403).json({
        success: false,
        message: 'This content was prepared in the Content Calendar — ask the Page / Ads Handler to correct it',
      });
    }
    if (Object.hasOwn(req.body, 'hook_headline')) {
      sets.push('hook_headline = ?');
      values.push(String(req.body.hook_headline ?? '').slice(0, 5000));
    }
    if (Object.hasOwn(req.body, 'description_points')) {
      const text = String(req.body.description_points ?? '');
      sets.push('description_points = ?', 'task_description = ?');
      values.push(text, text);
    }
    if (Object.hasOwn(req.body, 'submit_date')) {
      const d = dateKey(req.body.submit_date);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) {
        return res.status(400).json({ success: false, message: 'submit_date must be YYYY-MM-DD' });
      }
      sets.push('submit_date = ?');
      values.push(d);
    }
    if (!sets.length) return res.status(400).json({ success: false, message: 'Nothing to update' });
    await db.query(`UPDATE time_tracking_task_items SET ${sets.join(', ')} WHERE id = ?`, [...values, row.id]);
    emit(req, { type: 'WORKSPACE_ROW_EDIT', trackingItemId: row.id });
    return res.json({ success: true, message: 'Row updated' });
  } catch (err) {
    console.error('PATCH /workspace-tasks/my-tasks/:id ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

function reviewState(r) {
  if (r.state === 'APPROVED') return 'APPROVED';
  if (r.state === 'REJECTED') return 'REJECTED';
  if (r.review_status === 'REWORK' || r.state === 'REWORK') return 'REWORK';
  // Rejected and restarted by the employee → being redone.
  if (r.review_status === 'REJECTED' && r.state !== 'IN REVIEW') return 'REWORK';
  return 'PENDING';
}

const REVIEW_WHERE = `(tti.status IN ('COMPLETED', 'REWORK')
  OR UPPER(COALESCE(tti.review_status, '')) IN ('APPROVED', 'REWORK', 'REJECTED', 'PENDING'))`;

// Roles whose holder may approve / rework / reject the team's work for a client.
const REVIEWER_ROLES = ['ads_handling', 'page_handling'];

// Assignments (for this client) where the employee is the Ads/Page Handler.
async function reviewerAssignmentIds(employee, client) {
  const params = [];
  let clientSql = '';
  if (client) {
    clientSql = 'AND LOWER(TRIM(client_name)) = LOWER(TRIM(?))';
    params.push(client);
  }
  const [rows] = await db.query(
    `SELECT id, ${REVIEWER_ROLES.join(', ')} FROM task_assignments WHERE is_assigned = 1 ${clientSql}`,
    params,
  );
  return rows
    .filter((a) => REVIEWER_ROLES.some((role) => namesEmployee(a[role], employee)))
    .map((a) => a.id);
}

// GET /review — { data: my own reviewed rows, team: rows I can review }
async function buildReview(employee, client, date) {
    const employeeId = await employeeIdFor(employee);
    const params = [employeeId ?? -1, employee];
    let clientSql = '';
    if (client) {
      clientSql = 'AND LOWER(TRIM(tl.client_name)) = LOWER(TRIM(?))';
      params.push(client);
    }
    const byDate = (r) => !date || dueKey(r) === date;

    const [rows] = await db.query(
      `${ROW_SELECT}
       WHERE ${REVIEW_WHERE}
         AND (tl.employee_id = ? OR LOWER(TRIM(tl.employee_name)) = LOWER(TRIM(?)))
         ${clientSql}
       ORDER BY COALESCE(tti.complete_time, tti.updated_at) DESC, tti.id DESC`,
      params,
    );
    const data = shapeRows(rows.filter(byDate)).map((r) => ({ ...r, review_state: reviewState(r) }));

    let team = [];
    const assignmentIds = await reviewerAssignmentIds(employee, client);
    if (assignmentIds.length) {
      const [teamRows] = await db.query(
        `${ROW_SELECT}
         WHERE ${REVIEW_WHERE}
           AND tl.task_assignment_id IN (?)
         ORDER BY COALESCE(tti.complete_time, tti.updated_at) DESC, tti.id DESC`,
        [assignmentIds],
      );
      // Page / Ads Handler: the whole team's work AND their own handler work
      // (a person who is both Page and Ads Handler reviews their own rows too).
      const me = personKey(employee);
      team = shapeRows(teamRows.filter(byDate)).map((r) => ({
        ...r,
        review_state: reviewState(r),
        can_review: true,
        own: personKey(r.employee_name) === me,
      }));
    }
  return { data, team, is_reviewer: assignmentIds.length > 0 };
}

// GET /review — { data: my own reviewed rows, team: rows I can review }
router.get('/review', async (req, res) => {
  const employee = employeeFrom(req);
  const client = String(req.query.client || '').trim();
  const date = dateKey(req.query.date);
  if (!employee) return res.status(400).json({ success: false, message: 'employee is required' });
  try {
    // Main admin: the whole team's work on this client (any role), all decidable.
    const userType = String(req.user?.userType || req.user?.user_type || '').toLowerCase();
    if (String(req.query.admin) === '1' && (userType === 'admin' || await isAdminUser(employee))) {
      const params = [];
      let clientSql = '';
      if (client) {
        clientSql = 'AND LOWER(TRIM(tl.client_name)) = LOWER(TRIM(?))';
        params.push(client);
      }
      const [rows] = await db.query(
        `${ROW_SELECT}
         WHERE ${REVIEW_WHERE} ${clientSql}
         ORDER BY COALESCE(tti.complete_time, tti.updated_at) DESC, tti.id DESC`,
        params,
      );
      const team = shapeRows(rows.filter((r) => !date || dueKey(r) === date)).map((r) => ({
        ...r,
        review_state: reviewState(r),
        can_review: true,
      }));
      return res.json({ success: true, data: [], team, is_reviewer: true, admin: true });
    }
    return res.json({ success: true, ...(await buildReview(employee, client, date)) });
  } catch (err) {
    console.error('GET /workspace-tasks/review ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// POST /review/:id/decision { employee, action: APPROVED|REWORK|REJECTED, comment }
// Only the Ads/Page Handler of that task's client assignment may decide.
router.post('/review/:id/decision', async (req, res) => {
  const employee = employeeFrom(req);
  // PENDING puts a decided row back in the review queue.
  const action = upper(req.body.action) === 'PENDING' ? 'ACTION' : upper(req.body.action);
  const comment = String(req.body.comment ?? '').trim();
  if (!employee) return res.status(400).json({ success: false, message: 'employee is required' });
  if (!['APPROVED', 'REWORK', 'REJECTED', 'ACTION'].includes(action)) {
    return res.status(400).json({ success: false, message: 'action must be APPROVED, PENDING, REWORK or REJECTED' });
  }
  if ((action === 'REWORK' || action === 'REJECTED') && !comment) {
    return res.status(400).json({ success: false, message: 'Add a comment so the employee knows what to change' });
  }
  try {
    const [[item]] = await db.query(
      `SELECT tti.id, tti.status, tti.review_status, tl.task_assignment_id, tl.client_name
       FROM time_tracking_task_items tti
       JOIN task_list tl ON tl.id = tti.task_list_id
       WHERE tti.id = ?`,
      [req.params.id],
    );
    if (!item) return res.status(404).json({ success: false, message: 'Task row not found' });
    const allowed = await reviewerAssignmentIds(employee, item.client_name);
    const userType = String(req.user?.userType || req.user?.user_type || '').toLowerCase();
    const admin = userType === 'admin' || req.body?.as_admin === true && await isAdminUser(employee);
    if (!admin && (!item.task_assignment_id || !allowed.includes(item.task_assignment_id))) {
      return res.status(403).json({ success: false, message: 'Only the Ads / Page Handler of this client can review this task' });
    }
    if (upper(item.review_status) === 'APPROVED') {
      return res.status(409).json({ success: false, message: 'This task is already approved and cannot be changed' });
    }
    const status = upper(item.status);
    if (status === 'REWORK') {
      const current = upper(item.review_status);
      if ((action === 'REWORK' && current === 'REJECTED') || (action === 'REJECTED' && current === 'REWORK')) {
        // Not restarted yet: just switch between Rework and Rejected.
        await db.query('UPDATE time_tracking_task_items SET review_status = ? WHERE id = ?', [action, item.id]);
        await db.query(
          `UPDATE manager_review SET manager_action = ?, manager_comment = ? WHERE tracking_item_id = ?`,
          [action, comment, item.id],
        ).catch(() => {});
        req.app.get('io')?.emit('task_updated', { type: 'MANAGER_REVIEW', trackingItemId: item.id, action });
        return res.json({ success: true, message: `Marked ${action.toLowerCase()}` });
      }
      if (action === 'REWORK' || action === 'REJECTED') {
        return res.status(409).json({ success: false, message: `This task is already marked ${current.toLowerCase() || 'rework'}` });
      }
      // Rework not started yet → undo it so the new decision applies to the
      // completed work (the completion time comes back from the rework hold).
      const [[full]] = await db.query('SELECT * FROM time_tracking_task_items WHERE id = ?', [item.id]);
      let slot = null;
      for (let i = 10; i >= 1; i -= 1) {
        if (full[`hold_time_${i}`] && !full[`restart_time_${i}`]) { slot = i; break; }
      }
      await db.query(
        `UPDATE time_tracking_task_items
         SET status = 'COMPLETED',
             complete_time = ${slot ? `COALESCE(hold_time_${slot}, NOW())` : 'NOW()'}
             ${slot ? `, hold_time_${slot} = NULL` : ''}
         WHERE id = ?`,
        [item.id],
      );
    } else if (status !== 'COMPLETED') {
      return res.status(409).json({
        success: false,
        message: status === 'IN PROGRESS' || status === 'ON HOLD'
          ? 'The employee has already restarted this task — wait until they complete it again'
          : 'Only a completed task can be reviewed',
      });
    }
    const { recordReviewDecision } = require('./manager-review');
    await recordReviewDecision({ trackingItemId: item.id, action, comment, senderName: employee });
    req.app.get('io')?.emit('task_updated', { type: 'MANAGER_REVIEW', trackingItemId: item.id, action });
    return res.json({
      success: true,
      message: action === 'ACTION' ? 'Moved back to pending review' : `Marked ${action.toLowerCase()}`,
    });
  } catch (err) {
    console.error('POST /workspace-tasks/review/:id/decision ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// GET /counts?employee=&client=&date=
//   my_tasks.pending      rows still to do (not started / running / held / rework)
//   my_tasks.by_category  [{ name, pending }]
//   review.to_review      team rows waiting for MY decision (Ads/Page Handler)
//   review.my_in_review   my completed rows waiting for someone else
const OPEN_STATES = new Set(['IDLE', 'IN PROGRESS', 'ON HOLD', 'REWORK']);
async function buildCounts(employee, client, date) {
  const groups = await buildMyTasks(employee, client, date);
  const byCategory = [];
  let pending = 0;
  for (const g of groups) {
    const open = g.rows.filter((r) => OPEN_STATES.has(r.state)).length;
    pending += open;
    if (open) byCategory.push({ name: g.deliverable, pending: open });
  }
  const review = await buildReview(employee, client, date);
  return {
    my_tasks: { pending, by_category: byCategory },
    review: {
      is_reviewer: review.is_reviewer,
      to_review: review.team.filter((r) => r.review_state === 'PENDING').length,
      my_in_review: review.data.filter((r) => r.review_state === 'PENDING').length,
    },
  };
}

router.get('/counts', async (req, res) => {
  const employee = employeeFrom(req);
  const client = String(req.query.client || '').trim();
  const date = dateKey(req.query.date);
  if (!employee || !client) {
    return res.status(400).json({ success: false, message: 'employee and client are required' });
  }
  try {
    return res.json({ success: true, data: await buildCounts(employee, client, date) });
  } catch (err) {
    console.error('GET /workspace-tasks/counts ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ── Client team + group chat ─────────────────────────────────────────────────
// GET /team?client=  → everyone assigned on this client (any deadline)
router.get('/team', async (req, res) => {
  const client = String(req.query.client || '').trim();
  if (!client) return res.status(400).json({ success: false, message: 'client is required' });
  try {
    const team = await clientTeam(client);
    const members = new Map();
    for (const t of team) {
      const k = personKey(t.employee);
      const m = members.get(k) || { name: t.employee, roles: [] };
      if (!m.roles.includes(t.role)) m.roles.push(t.role);
      members.set(k, m);
    }
    return res.json({ success: true, data: { members: [...members.values()], team } });
  } catch (err) {
    console.error('GET /workspace-tasks/team ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

async function isClientMember(client, employee, req = null) {
  const team = await clientTeam(client);
  if (team.some((t) => personKey(t.employee) === personKey(employee))) return true;
  // Admins can read and post in every client group.
  const type = String(req?.user?.userType || req?.user?.user_type || '').toLowerCase();
  if (type === 'admin') return true;
  return isAdminUser(employee);
}

// GET /team/chat?client=  → client group messages (latest 300)
router.get('/team/chat', async (req, res) => {
  const client = String(req.query.client || '').trim();
  if (!client) return res.status(400).json({ success: false, message: 'client is required' });
  try {
    const [rows] = await db.query(
      `SELECT id, sender_name, message, created_at FROM workspace_client_chat
       WHERE LOWER(TRIM(client_name)) = LOWER(TRIM(?))
       ORDER BY id DESC LIMIT 300`,
      [client],
    );
    return res.json({ success: true, data: rows.reverse() });
  } catch (err) {
    console.error('GET /workspace-tasks/team/chat ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// POST /team/chat { client, employee, message } — members of the client only
router.post('/team/chat', async (req, res) => {
  const client = String(req.body.client || '').trim();
  const employee = employeeFrom(req);
  const message = String(req.body.message || '').trim().slice(0, 4000);
  if (!client || !employee || !message) {
    return res.status(400).json({ success: false, message: 'client, employee and message are required' });
  }
  try {
    if (!(await isClientMember(client, employee, req))) {
      return res.status(403).json({ success: false, message: 'Only employees assigned to this client can post in its group' });
    }
    const [ins] = await db.query(
      'INSERT INTO workspace_client_chat (client_name, sender_name, message) VALUES (?, ?, ?)',
      [client, employee, message],
    );
    req.app.get('io')?.emit('workspace_client_chat', { client, id: ins.insertId, sender: employee });
    res.status(201).json({ success: true, data: { id: ins.insertId } });
    // Mobile push to everyone on this client's team (works with the app closed).
    try {
      const { sendToEmployees } = require('../lib/pushNotifications');
      const team = await clientTeam(client);
      await sendToEmployees(team.map((t) => t.employee), {
        title: `${employee} • ${client}`,
        body: message,
        sender: employee,
        data: { type: 'client_group', chat: client, isGroup: '1' },
      });
    } catch (err) {
      console.error('Client chat push failed:', err.message);
    }
    return undefined;
  } catch (err) {
    console.error('POST /workspace-tasks/team/chat ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ── Client groups for the Notifications / Chat page ─────────────────────────
// Read markers: last message id each employee has seen in each client group.
let chatSeenReady = null;
function ensureChatSeenTable() {
  if (!chatSeenReady) {
    chatSeenReady = db.query(
      `CREATE TABLE IF NOT EXISTS workspace_client_chat_seen (
         employee_name VARCHAR(255) NOT NULL,
         client_name VARCHAR(255) NOT NULL,
         last_seen_id INT NOT NULL DEFAULT 0,
         updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
         PRIMARY KEY (employee_name, client_name)
       )`,
    ).catch((err) => {
      chatSeenReady = null;
      throw err;
    });
  }
  return chatSeenReady;
}

// Active clients this employee works on (assigned tasks + additional tasks).
async function memberClients(employee) {
  const clients = new Map();
  for (const { assignment } of await employeeAssignments(employee)) {
    const name = String(assignment.client_name || '').trim();
    if (name && !clients.has(norm(name))) clients.set(norm(name), name);
  }
  const active = await activeClientSet();
  try {
    const [lists] = await db.query(
      `SELECT DISTINCT client_name, employee_name FROM task_list
       WHERE additional_task_id IS NOT NULL AND client_name IS NOT NULL`,
    );
    for (const l of lists) {
      const name = String(l.client_name || '').trim();
      if (!name || clients.has(norm(name)) || !active.has(norm(name))) continue;
      if (personKey(l.employee_name) === personKey(employee)) clients.set(norm(name), name);
    }
  } catch (err) {
    console.error('memberClients additional lists failed:', err.message);
  }
  return [...clients.values()];
}

// GET /team/groups?employee=  → client groups I belong to, with the last
// message, unread count and members.
router.get('/team/groups', async (req, res) => {
  const employee = employeeFrom(req);
  if (!employee) return res.status(400).json({ success: false, message: 'employee is required' });
  try {
    await ensureChatSeenTable();
    const clients = await memberClients(employee);
    const out = [];
    for (const client of clients) {
      const [[last]] = await db.query(
        `SELECT id, sender_name, message, created_at FROM workspace_client_chat
         WHERE LOWER(TRIM(client_name)) = LOWER(TRIM(?)) ORDER BY id DESC LIMIT 1`,
        [client],
      );
      const [[seen]] = await db.query(
        `SELECT last_seen_id FROM workspace_client_chat_seen
         WHERE LOWER(TRIM(employee_name)) = LOWER(TRIM(?)) AND LOWER(TRIM(client_name)) = LOWER(TRIM(?))`,
        [employee, client],
      );
      const [[unread]] = await db.query(
        `SELECT COUNT(*) AS n FROM workspace_client_chat
         WHERE LOWER(TRIM(client_name)) = LOWER(TRIM(?)) AND id > ?
           AND LOWER(TRIM(sender_name)) <> LOWER(TRIM(?))`,
        [client, Number(seen?.last_seen_id) || 0, employee],
      );
      const team = await clientTeam(client);
      const members = [];
      for (const t of team) {
        if (!members.some((m) => personKey(m) === personKey(t.employee))) members.push(t.employee);
      }
      out.push({
        client_name: client,
        members,
        last_message: last
          ? { id: last.id, sender: last.sender_name, message: last.message, created_at: last.created_at }
          : null,
        unread: Number(unread?.n) || 0,
      });
    }
    // Latest conversation first, quiet groups alphabetically after.
    out.sort((a, b) => (b.last_message?.id || 0) - (a.last_message?.id || 0)
      || a.client_name.localeCompare(b.client_name));
    return res.json({ success: true, data: out });
  } catch (err) {
    console.error('GET /workspace-tasks/team/groups ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// POST /team/chat/seen { client, employee, lastId }
router.post('/team/chat/seen', async (req, res) => {
  const client = String(req.body.client || '').trim();
  const employee = employeeFrom(req);
  const lastId = Number(req.body.lastId) || 0;
  if (!client || !employee) return res.status(400).json({ success: false, message: 'client and employee are required' });
  try {
    await ensureChatSeenTable();
    await db.query(
      `INSERT INTO workspace_client_chat_seen (employee_name, client_name, last_seen_id) VALUES (?, ?, ?)
       ON DUPLICATE KEY UPDATE last_seen_id = GREATEST(last_seen_id, VALUES(last_seen_id))`,
      [employee, client, lastId],
    );
    return res.json({ success: true });
  } catch (err) {
    console.error('POST /workspace-tasks/team/chat/seen ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// GET /people/avatars → profile photo / colour of every active user (for chat).
router.get('/people/avatars', async (req, res) => {
  try {
    const [rows] = await db.query(
      `SELECT full_name, initials, avatar_color, profile_photo FROM employee_users
       WHERE is_active = 1 OR is_active IS NULL`,
    );
    return res.json({
      success: true,
      data: rows.map((r) => ({
        full_name: r.full_name,
        initials: r.initials || initialsOf(r.full_name),
        avatar_color: r.avatar_color || '',
        profile_photo: r.profile_photo || '',
      })),
    });
  } catch (err) {
    console.error('GET /workspace-tasks/people/avatars ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// GET /live — Live Tracking tab: my tracking rows + Content Calendar categories
// I am preparing (Page/Ads Handler), with running durations.
router.get('/live', async (req, res) => {
  const employee = employeeFrom(req);
  const client = String(req.query.client || '').trim();
  const date = dateKey(req.query.date);
  if (!employee || !client) {
    return res.status(400).json({ success: false, message: 'employee and client are required' });
  }
  try {
    const employeeId = await employeeIdFor(employee);
    const [rows] = await db.query(
      `${ROW_SELECT}
       WHERE (tl.employee_id = ? OR LOWER(TRIM(tl.employee_name)) = LOWER(TRIM(?)))
         AND LOWER(TRIM(tl.client_name)) = LOWER(TRIM(?))
         AND (tti.start_time IS NOT NULL OR tti.status <> 'IDLE')
       ORDER BY tti.s_no ASC, tti.sub_no ASC, tti.id ASC`,
      [employeeId ?? -1, employee, client],
    );
    const tasks = shapeRows(
      rows.filter((r) => !date || dueKey(r) === date),
    ).map((r) => ({
      kind: 'TASK',
      key: `task:${r.id}`,
      task_id: r.id,
      title: `${r.deliverable} · Row ${r.display_no}`,
      deliverable: r.deliverable,
      heading: r.hook_headline || r.task_description,
      status: r.state,
      duration_secs: r.current_secs,
      running: r.state === 'IN PROGRESS',
      started_at: r.start_time ?? null,
      completed_at: r.complete_time,
      submit_date: r.submit_date,
      review_action: r.manager_action,
      rows: 1,
    }));

    const [cc] = await db.query(
      `SELECT id, deliverable, source_assignment_id, source_role, source_task_index,
              source_row_number, submit_date, cc_status, cc_duration_secs, cc_started_at,
              cc_hold_reason, cc_last_activity_at, cc_handoff_at, assigned_to_name,
              cc_prepared_by_name
       FROM content_calendar
       WHERE LOWER(TRIM(client_name)) = LOWER(TRIM(?))
         AND source_assignment_id IS NOT NULL AND source_active = 1
         AND (cc_prepared_by_id = ? OR LOWER(TRIM(cc_prepared_by_name)) = LOWER(TRIM(?)))
       ORDER BY source_assignment_id, source_role, source_task_index, source_row_number`,
      [client, employeeId ?? -1, employee],
    );
    const sheets = new Map();
    for (const r of cc) {
      if (date && dateKey(r.submit_date) !== date) continue;
      const key = `${r.source_assignment_id}:${r.source_role}:${r.source_task_index}`;
      const sheet = sheets.get(key) || { rows: [], secs: 0, running: false, statuses: new Set() };
      sheet.rows.push(r);
      sheet.statuses.add(upper(r.cc_status || 'IDLE'));
      sheet.secs += Number(r.cc_duration_secs) || 0;
      if (r.cc_started_at && upper(r.cc_status) === 'IN PROGRESS') {
        sheet.running = true;
        sheet.secs += Math.max(Math.floor((Date.now() - new Date(r.cc_started_at)) / 1000), 0);
      }
      sheets.set(key, sheet);
    }
    const calendar = [...sheets.entries()].map(([key, sheet]) => {
      const first = sheet.rows[0];
      const statuses = sheet.statuses;
      const status = sheet.rows.every((r) => r.cc_handoff_at) ? 'ASSIGNED'
        : statuses.size === 1 ? [...statuses][0]
          : statuses.has('IN PROGRESS') ? 'IN PROGRESS'
            : statuses.has('ON HOLD') ? 'ON HOLD' : 'IN PROGRESS';
      return {
        kind: 'CONTENT_CALENDAR',
        key: `cc:${key}`,
        source_assignment_id: first.source_assignment_id,
        source_role: first.source_role,
        source_task_index: first.source_task_index,
        title: `Content Calendar · ${first.deliverable} (${sheet.rows.length} rows)`,
        deliverable: first.deliverable,
        heading: `Preparing for ${first.assigned_to_name || 'team'}`,
        status,
        duration_secs: sheet.secs,
        running: sheet.running,
        hold_reason: sheet.rows.find((r) => r.cc_hold_reason)?.cc_hold_reason || '',
        last_activity_at: sheet.rows.reduce(
          (m, r) => (r.cc_last_activity_at && (!m || r.cc_last_activity_at > m) ? r.cc_last_activity_at : m), null),
        submit_date: dateKey(first.submit_date),
        rows: sheet.rows.length,
      };
    });

    return res.json({ success: true, data: [...calendar, ...tasks] });
  } catch (err) {
    console.error('GET /workspace-tasks/live ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ── Employee-wide views (Day Planner actions, Live Tracking page, top bar) ──
function workIntervals(row, now = new Date()) {
  const out = [];
  if (!row.start_time) return out;
  let active = new Date(row.start_time);
  for (let i = 1; i <= 10; i += 1) {
    const hold = row[`hold_time_${i}`];
    const restart = row[`restart_time_${i}`];
    if (hold && active) {
      out.push([active, new Date(hold)]);
      active = null;
    }
    if (restart) active = new Date(restart);
    else if (hold) { active = null; break; }
  }
  if (active) out.push([active, row.complete_time ? new Date(row.complete_time) : now]);
  return out;
}

function secondsBetween(intervals, from, to) {
  let total = 0;
  for (const [a, b] of intervals) {
    const start = Math.max(a.getTime(), from.getTime());
    const end = Math.min(b.getTime(), to.getTime());
    if (end > start) total += Math.floor((end - start) / 1000);
  }
  return total;
}

function sessionStart(row) {
  let latest = row.start_time ? new Date(row.start_time) : null;
  for (let i = 1; i <= 10; i += 1) {
    const r = row[`restart_time_${i}`];
    if (r && (!latest || new Date(r) > latest)) latest = new Date(r);
  }
  return latest;
}

function dayBounds(day) {
  const [y, m, d] = day.split('-').map(Number);
  const from = new Date(y, m - 1, d, 0, 0, 0);
  const to = new Date(y, m - 1, d + 1, 0, 0, 0);
  return { from, to };
}

async function employeeTaskItems(employee, client = null) {
  const employeeId = await employeeIdFor(employee);
  const params = [employeeId ?? -1, employee];
  let clientSql = '';
  if (client) {
    clientSql = 'AND LOWER(TRIM(tl.client_name)) = LOWER(TRIM(?))';
    params.push(client);
  }
  const [rows] = await db.query(
    `${ROW_SELECT.replace('SELECT tti.*,', `SELECT tti.*,
       EXISTS (SELECT 1 FROM content_calendar ccx
               WHERE ccx.task_item_id = tti.id AND ccx.source_assignment_id IS NOT NULL
                 AND ccx.source_active = 1 AND ccx.cc_handoff_at IS NULL
                 AND COALESCE(ccx.is_emergency, 0) <> 1) AS awaiting_handoff,`)}
     WHERE (tl.employee_id = ? OR LOWER(TRIM(tl.employee_name)) = LOWER(TRIM(?)))
       ${clientSql}
     ORDER BY tl.client_name, tti.s_no, tti.sub_no, tti.id`,
    params,
  );
  const active = await activeClientSet();
  const live = rows.filter((r) => active.has(norm(r.client_name)));
  const shaped = shapeRows(live);
  return live.map((raw, i) => ({ raw, row: shaped[i] }));
}

// Only rows the employee really has in Employee Workspace → My Tasks:
//  · additional lists (admin / Page-Ads Handler "Add content" / emergency)
//  · direct roles (UI/UX, Developer, Page/Ads Handler) of an assignment naming them
//  · Designer / Video / Website rows only after the Page / Ads Handler shared
//    them from the Content Calendar (content_calendar_assigned = 1)
//  · rows a handler reassigned to them (shared)
// Old / unshared / unassigned rows are left out.
async function workspaceVisible(employee, items) {
  const ids = [...new Set(items.map(({ raw }) => raw.task_list_id).filter(Boolean))];
  if (!ids.length) return () => false;
  const [lists] = await db.query(
    'SELECT id, task_assignment_id, additional_task_id FROM task_list WHERE id IN (?)',
    [ids],
  );
  const info = new Map(lists.map((l) => [Number(l.id), l]));
  const named = new Map(); // "assignmentId|task" → is a direct role
  for (const { assignment, role, task } of await employeeAssignments(employee)) {
    const k = `${assignment.id}|${norm(task.name)}`;
    named.set(k, named.get(k) === true || Boolean(role.direct));
  }
  return ({ raw }) => {
    const l = info.get(Number(raw.task_list_id));
    if (!l) return false;
    if (l.additional_task_id) return true;
    // Shared from the Content Calendar — or already worked on in the old
    // Assigned Task page (started / held / completed), so it continues here.
    const handed = Number(raw.content_calendar_assigned) === 1 || Boolean(raw.parent_item_id) ||
      Boolean(raw.start_time) || upper(raw.status || 'IDLE') !== 'IDLE';
    if (!l.task_assignment_id) return false;
    const k = `${l.task_assignment_id}|${norm(raw.deliverables)}`;
    if (named.has(k)) return named.get(k) || handed;
    return handed;
  };
}

function taskItem({ raw, row }) {
  return {
    kind: 'TASK',
    key: `task:${row.id}`,
    task_id: row.id,
    client: row.client_name,
    deliverable: row.deliverable,
    title: `${row.deliverable} · Row ${row.display_no}`,
    heading: row.hook_headline || row.task_description,
    status: row.state,
    duration_secs: row.current_secs,
    running: row.state === 'IN PROGRESS',
    session_started_at: row.state === 'IN PROGRESS' ? sessionStart(raw) : null,
    review_action: row.manager_action,
    comment: row.manager_comment || raw.comment || '',
    submit_date: row.submit_date,
    // Client card date (assignment deadline) — used to open the right card.
    due_date: dueKey(raw),
    section: 'My Tasks',
  };
}

async function employeeSheets(employee, client = null, { includeStartable = false } = {}) {
  const employeeId = await employeeIdFor(employee);
  const params = [employeeId ?? -1, employee];
  let clientSql = '';
  if (client) {
    clientSql = 'AND LOWER(TRIM(client_name)) = LOWER(TRIM(?))';
    params.push(client);
  }
  let startableSql = '';
  if (includeStartable) {
    const ids = await reviewerAssignmentIds(employee, client);
    if (ids.length) {
      startableSql = `OR (source_assignment_id IN (${ids.map(Number).join(',')})
                          AND cc_prepared_by_id IS NULL AND cc_handoff_at IS NULL
                          AND COALESCE(is_emergency, 0) <> 1)`;
    }
  }
  const [cc] = await db.query(
    `SELECT id, client_name, deliverable, source_assignment_id, source_role, source_task_index,
            source_row_number, submit_date, cc_status, cc_duration_secs, cc_started_at,
            cc_hold_reason, cc_last_activity_at, cc_handoff_at, assigned_to_name
     FROM content_calendar
     WHERE source_assignment_id IS NOT NULL AND source_active = 1
       AND ((cc_prepared_by_id = ? OR LOWER(TRIM(cc_prepared_by_name)) = LOWER(TRIM(?))) ${startableSql})
       ${clientSql}
     ORDER BY client_name, source_assignment_id, source_role, source_task_index, source_row_number`,
    params,
  );
  const active = await activeClientSet();
  return groupSheets(cc.filter((r) => active.has(norm(r.client_name))));
}

// Rows of content_calendar → one item per category sheet (or manual row).
function groupSheets(cc) {
  const sheets = new Map();
  for (const r of cc) {
    const key = r.source_assignment_id
      ? `${r.source_assignment_id}:${r.source_role}:${r.source_task_index}`
      : `row:${r.id}`;
    const sh = sheets.get(key) || { rows: [], banked: 0, runningFrom: null, statuses: new Set(), last: null };
    sh.rows.push(r);
    sh.statuses.add(upper(r.cc_status || 'IDLE'));
    sh.banked += Number(r.cc_duration_secs) || 0;
    if (r.cc_started_at && upper(r.cc_status) === 'IN PROGRESS') sh.runningFrom = new Date(r.cc_started_at);
    if (r.cc_last_activity_at && (!sh.last || r.cc_last_activity_at > sh.last)) sh.last = r.cc_last_activity_at;
    sheets.set(key, sh);
  }
  const now = Date.now();
  return [...sheets.entries()].map(([key, sh]) => {
    const first = sh.rows[0];
    const st = sh.statuses;
    const status = sh.rows.every((r) => r.cc_handoff_at) ? 'ASSIGNED'
      : st.size === 1 ? [...st][0]
        : st.has('IN PROGRESS') ? 'IN PROGRESS' : st.has('ON HOLD') ? 'ON HOLD' : 'IN PROGRESS';
    const runningSecs = sh.runningFrom ? Math.max(Math.floor((now - sh.runningFrom.getTime()) / 1000), 0) : 0;
    return {
      kind: 'CONTENT_CALENDAR',
      key: `cc:${key}`,
      calendar_ids: sh.rows.map((r) => r.id),
      client: first.client_name,
      deliverable: first.deliverable,
      title: `Content Calendar · ${first.deliverable} (${sh.rows.length} rows)`,
      heading: `Preparing for ${first.assigned_to_name || 'team'}`,
      status,
      duration_secs: sh.banked + runningSecs,
      banked_secs: sh.banked,
      running: Boolean(sh.runningFrom),
      session_started_at: sh.runningFrom,
      last_activity_at: sh.last,
      hold_reason: sh.rows.find((r) => r.cc_hold_reason)?.cc_hold_reason || '',
      source_assignment_id: first.source_assignment_id,
      source_role: first.source_role,
      source_task_index: first.source_task_index,
      submit_date: dateKey(first.submit_date),
      due_date: dateKey(first.submit_date),
      section: 'Content Calendar',
    };
  });
}

// GET /actionable?employee=&client=  → things the employee can act on now
router.get('/actionable', async (req, res) => {
  const employee = employeeFrom(req);
  const client = String(req.query.client || '').trim() || null;
  if (!employee) return res.status(400).json({ success: false, message: 'employee is required' });
  try {
    const open = new Set(['IDLE', 'IN PROGRESS', 'ON HOLD', 'REWORK']);
    const allItems = await employeeTaskItems(employee, client);
    const visible = await workspaceVisible(employee, allItems);
    const tasks = allItems
      .filter(visible)
      .filter(({ raw, row }) => open.has(row.state) && !(row.state === 'IDLE' && Number(raw.awaiting_handoff) === 1))
      .map(taskItem);
    const sheets = (await employeeSheets(employee, client, { includeStartable: true }))
      .filter((s) => ['IDLE', 'IN PROGRESS', 'ON HOLD'].includes(s.status));
    const rank = (i) => (i.status === 'IN PROGRESS' ? 0 : ['ON HOLD', 'REWORK'].includes(i.status) ? 1 : 2);
    const data = [...sheets, ...tasks].sort((a, b) => rank(a) - rank(b));
    return res.json({ success: true, data });
  } catch (err) {
    console.error('GET /workspace-tasks/actionable ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// GET /dashboard?employee=&handler=1&filter=Today|This Week|This Month
//   pending          open rows (IDLE / IN PROGRESS / ON HOLD), by priority
//   week             this week's work only (submit date Mon–Sun): My Tasks,
//                    Content Calendar + Task Review for
//                    handlers; completed / in review this week at the bottom
//   rework           rows sent back (REWORK / REJECTED)
//   shared           Content Calendar rows a Page / Ads Handler shared with me
//   review_pending   Page / Ads Handler: team rows waiting for their decision
//   calendar_pending Page / Ads Handler: Content Calendar categories not shared yet
//   cards            hold_list (Hold Task card) + new_clients (New Clients card)
// Task items are the /actionable shape, so START / HOLD / COMPLETE / RESTART
// work exactly like the Employee Workspace (Day Planner too).
router.get('/dashboard', async (req, res) => {
  const employee = employeeFrom(req);
  if (!employee) return res.status(400).json({ success: false, message: 'employee is required' });
  const filter = String(req.query.filter || 'Today');
  try {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const monday = new Date(today);
    monday.setDate(today.getDate() - ((today.getDay() + 6) % 7));
    const sunday = new Date(monday);
    sunday.setDate(monday.getDate() + 6);
    const weekFrom = dateKey(monday);
    const weekTo = dateKey(sunday);
    const todayKey = dateKey(today);
    const monthFrom = `${todayKey.slice(0, 7)}-01`;
    const monthTo = `${todayKey.slice(0, 7)}-31`;
    const inPeriod = (d) => {
      if (!d) return false;
      if (filter === 'This Month') return d >= monthFrom && d <= monthTo;
      if (filter === 'This Week') return d >= weekFrom && d <= weekTo;
      return d === todayKey;
    };
    const periodFrom = filter === 'This Month' ? monthFrom : filter === 'This Week' ? weekFrom : todayKey;

    const due = (i) => i.submit_date || i.due_date || '';
    const byDue = (a, b) => (due(a) || '9999').localeCompare(due(b) || '9999');
    // Priority: running → overdue → rework → review to do → hold → to start
    // → in review; finished work always last.
    const prio = (i) => {
      if (i.done) return 9;
      if (i.status === 'IN PROGRESS') return 0;
      if (i.overdue) return 1;
      if (['REWORK', 'REJECTED'].includes(i.status)) return 2;
      if (i.kind === 'REVIEW') return 3;
      if (i.status === 'ON HOLD') return 4;
      if (i.status === 'IN REVIEW') return 6;
      return 5;
    };
    const byPrio = (a, b) => prio(a) - prio(b) || byDue(a, b);

    const allItems = await employeeTaskItems(employee);
    const visible = await workspaceVisible(employee, allItems);
    const tasks = allItems
      .filter(visible)
      .filter(({ raw, row }) => !(row.state === 'IDLE' && Number(raw.awaiting_handoff) === 1))
      .map(({ raw, row }) => {
        const d = row.submit_date || dueKey(raw);
        return {
          ...taskItem({ raw, row }),
          display_no: row.display_no,
          description: row.description_points || '',
          completed_at: dateKey(raw.complete_time),
          hold_at: raw.updated_at || null,
          assigned_by: raw.cc_assigned_by_name || '',
          overdue: !!d && d < todayKey && !['APPROVED', 'IN REVIEW'].includes(row.state),
        };
      });

    // Task Review + Content Calendar: Page / Ads Handler only (app sends handler=1).
    const reviewerIds = String(req.query.handler) === '1'
      ? await reviewerAssignmentIds(employee, null)
      : [];
    const isHandler = reviewerIds.length > 0;
    let allSheets = [];
    if (isHandler) {
      allSheets = (await employeeSheets(employee, null, { includeStartable: true })).map((sh) => ({
        ...sh,
        display_no: `${sh.calendar_ids.length} rows`,
        overdue: sh.status !== 'ASSIGNED' && !!due(sh) && due(sh) < todayKey,
      }));
    }
    const sheets = allSheets.filter((sh) => sh.status !== 'ASSIGNED');

    let reviewPending = [];
    if (isHandler) {
      const review = await buildReview(employee, null, '');
      reviewPending = review.team
        .filter((r) => r.review_state === 'PENDING' && r.state === 'IN REVIEW')
        .map((r) => ({
          kind: 'REVIEW',
          key: `review:${r.id}`,
          review_id: r.id,
          client: r.client_name,
          deliverable: r.deliverable,
          display_no: r.display_no,
          title: `${r.deliverable} · Row ${r.display_no}`,
          heading: r.hook_headline || r.task_description || '',
          description: r.description_points || '',
          employee_name: r.employee_name,
          own: !!r.own,
          status: 'IN REVIEW',
          submit_date: r.submit_date,
          completed_at: r.complete_time,
          duration_secs: r.current_secs,
          section: 'Task Review',
          due_date: r.submit_date,
        }))
        .sort(byDue);
    }

    const OPEN = new Set(['IDLE', 'IN PROGRESS', 'ON HOLD', 'REWORK', 'REJECTED']);
    const pending = tasks
      .filter((t) => ['IDLE', 'IN PROGRESS', 'ON HOLD'].includes(t.status))
      .sort(byPrio);
    const rework = tasks
      .filter((t) => ['REWORK', 'REJECTED'].includes(t.status))
      .sort(byPrio);

    // This week = must be done by Sunday (overdue too) + finished this week.
    const week = [];
    for (const t of tasks) {
      const d = due(t);
      const inWeek = !!d && d >= weekFrom && d <= weekTo;
      if (OPEN.has(t.status) && inWeek) {
        week.push({ ...t, done: false });
      } else if (['IN REVIEW', 'APPROVED'].includes(t.status) &&
                 (inWeek || (t.completed_at >= weekFrom && t.completed_at <= weekTo))) {
        week.push({ ...t, done: true });
      }
    }
    for (const sh of allSheets) {
      const d = due(sh);
      if (sh.status !== 'ASSIGNED' && d >= weekFrom && d <= weekTo) week.push({ ...sh, done: false });
      else if (sh.status === 'ASSIGNED' && d >= weekFrom && d <= weekTo) week.push({ ...sh, done: true });
    }
    for (const r of reviewPending) {
      if (due(r) >= weekFrom && due(r) <= weekTo) week.push({ ...r, done: false });
    }
    week.sort(byPrio);

    // Content Calendar rows a Page / Ads Handler shared with me.
    let shared = [];
    try {
      const employeeId = await employeeIdFor(employee);
      const [sh] = await db.query(
        `SELECT cc.client_name, cc.deliverable, COUNT(*) AS row_count,
                DATE_FORMAT(COALESCE(sa.deadline, sa.maintenance_date, cc.cc_card_date, cc.submit_date), '%Y-%m-%d') AS card_date,
                MIN(DATE_FORMAT(cc.submit_date, '%Y-%m-%d')) AS submit_date,
                MAX(cc.assigned_by_name) AS shared_by,
                MAX(COALESCE(cc.cc_handoff_at, cc.cc_last_activity_at)) AS shared_at,
                MAX(cc.is_emergency) AS emergency
         FROM content_calendar cc
         LEFT JOIN task_assignments sa ON sa.id = cc.source_assignment_id
         WHERE (cc.assigned_to_id = ? OR LOWER(TRIM(cc.assigned_to_name)) = LOWER(TRIM(?)))
           AND cc.task_item_id IS NOT NULL
           AND (cc.cc_handoff_at IS NOT NULL OR cc.source_assignment_id IS NULL OR cc.is_emergency = 1)
         GROUP BY cc.client_name, cc.deliverable, card_date
         ORDER BY shared_at DESC
         LIMIT 100`,
        [employeeId ?? -1, employee],
      );
      const active = await activeClientSet();
      shared = sh
        .filter((r) => active.has(norm(r.client_name)))
        .map((r) => ({
          kind: 'SHARED',
          key: `shared:${r.client_name}:${r.deliverable}:${r.card_date}`,
          client: r.client_name,
          deliverable: r.deliverable,
          display_no: `${r.row_count} rows`,
          title: `${r.deliverable} · ${r.row_count} rows`,
          submit_date: r.submit_date || r.card_date,
          due_date: r.card_date || r.submit_date,
          shared_by: r.shared_by || '',
          shared_at: r.shared_at,
          status: Number(r.emergency) === 1 ? 'EMERGENCY' : 'SHARED',
          section: 'My Tasks',
        }));
    } catch (err) {
      console.warn('dashboard shared list skipped:', err.message);
    }

    // Hold Task card.
    const holdList = [
      ...tasks.filter((t) => t.status === 'ON HOLD').map((t) => ({
        clientName: t.client,
        task: t.title,
        submissionDate: t.submit_date,
        holdDate: t.hold_at,
      })),
      ...sheets.filter((s) => s.status === 'ON HOLD').map((s) => ({
        clientName: s.client,
        task: s.title,
        submissionDate: s.submit_date,
        holdDate: s.last_activity_at,
      })),
    ];

    // New Clients card: new admin assignments + clients moved to me
    // (admin changed the person, or a handler assigned / reassigned rows).
    const newMap = new Map();
    const addNew = (client, info) => {
      const k = norm(client);
      if (!k || newMap.has(k)) return;
      newMap.set(k, { clientName: String(client).trim(), ...info });
    };
    for (const { assignment } of await employeeAssignments(employee)) {
      const created = dateKey(assignment.created_at ? new Date(assignment.created_at) : null);
      if (inPeriod(created)) {
        addNew(assignment.client_name, {
          submissionDate: deadlineOf(assignment) || created,
          note: 'New assignment',
          at: created,
        });
      }
    }
    try {
      await ensureEventsTable();
      const [events] = await db.query(
        `SELECT * FROM employee_assignment_events WHERE created_at >= ? ORDER BY created_at DESC`,
        [`${periodFrom} 00:00:00`],
      );
      const me = personKey(employee);
      const active = await activeClientSet();
      for (const ev of events) {
        if (personKey(ev.employee_name) !== me || !active.has(norm(ev.client_name))) continue;
        const at = dateKey(ev.created_at instanceof Date ? ev.created_at : new Date(ev.created_at));
        if (!inPeriod(at)) continue;
        const kind = upper(ev.kind);
        const note = kind.includes('REASSIGNED') && ev.from_employee
          ? `Moved from ${ev.from_employee}${ev.by_name ? ` by ${ev.by_name}` : ''}`
          : kind.includes('EMERGENCY')
            ? `Emergency task${ev.by_name ? ` from ${ev.by_name}` : ''}`
            : kind.startsWith('HANDLER')
              ? `Assigned by ${ev.by_name || 'handler'}`
              : `Assigned${ev.by_name ? ` by ${ev.by_name}` : ''}`;
        addNew(ev.client_name, { submissionDate: dateKey(ev.due_date) || at, note, at });
      }
    } catch (err) {
      console.warn('dashboard new-clients events skipped:', err.message);
    }
    const newClients = [...newMap.values()];

    return res.json({
      success: true,
      week_from: weekFrom,
      week_to: weekTo,
      is_handler: isHandler,
      data: {
        pending,
        week,
        week_open: week.filter((w) => !w.done).length,
        rework,
        shared,
        review_pending: reviewPending,
        calendar_pending: sheets.sort(byPrio),
      },
      cards: {
        hold_count: holdList.length,
        hold_list: holdList,
        new_clients_count: newClients.length,
        new_clients: newClients,
      },
    });
  } catch (err) {
    console.error('GET /workspace-tasks/dashboard ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// GET /items-by-ref?employee=&refs=task:21,cc:45
// Day Planner rows carry "[Task Row #id]" / "[Calendar Row #id]" markers; this
// turns them into live items (status, timer, actions).
router.get('/items-by-ref', async (req, res) => {
  const employee = employeeFrom(req);
  const refs = String(req.query.refs || '').split(',').map((r) => r.trim()).filter(Boolean);
  if (!employee) return res.status(400).json({ success: false, message: 'employee is required' });
  try {
    const out = {};
    const taskIds = refs.filter((r) => r.startsWith('task:')).map((r) => Number(r.slice(5))).filter(Boolean);
    if (taskIds.length) {
      const wanted = new Set(taskIds);
      for (const entry of await employeeTaskItems(employee)) {
        if (wanted.has(entry.row.id)) out[`task:${entry.row.id}`] = taskItem(entry);
      }
    }
    const calIds = refs.filter((r) => r.startsWith('cc:')).map((r) => Number(r.slice(3))).filter(Boolean);
    for (const id of calIds) {
      const [[row]] = await db.query('SELECT * FROM content_calendar WHERE id = ?', [id]);
      if (!row) continue;
      const [group] = row.source_assignment_id
        ? await db.query(
            `SELECT * FROM content_calendar
             WHERE source_assignment_id = ? AND source_role = ? AND source_task_index = ?
               AND source_active = 1
             ORDER BY source_row_number`,
            [row.source_assignment_id, row.source_role, row.source_task_index],
          )
        : [[row]];
      const [item] = groupSheets(group.length ? group : [row]);
      if (item) out[`cc:${id}`] = item;
    }
    return res.json({ success: true, data: out });
  } catch (err) {
    console.error('GET /workspace-tasks/items-by-ref ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ── "Today" for Live Tracking and the top bar ───────────────────────────────
// Days follow the office clock (India, UTC+05:30 — APP_TZ_OFFSET_MINUTES to
// change), whatever time zone the server runs in.
const APP_TZ_MIN = Number(process.env.APP_TZ_OFFSET_MINUTES ?? 330);
function appDay(d = new Date()) {
  const t = new Date(d.getTime() + APP_TZ_MIN * 60000);
  return `${t.getUTCFullYear()}-${pad(t.getUTCMonth() + 1)}-${pad(t.getUTCDate())}`;
}
function appBounds(day) {
  const [y, m, d] = day.split('-').map(Number);
  const from = new Date(Date.UTC(y, m - 1, d) - APP_TZ_MIN * 60000);
  return { from, to: new Date(from.getTime() + 86400000) };
}
const inDay = (v, from, to) => {
  if (!v) return false;
  const t = new Date(v).getTime();
  return t >= from.getTime() && t < to.getTime();
};

/**
 * Work done on one day:
 *  · only sessions STARTED that day count (started / restarted that day),
 *    so a task left running from an earlier day adds nothing until the
 *    employee holds and restarts it;
 *  · an item is listed when it was started, restarted, held or completed
 *    that day — an old held task shows again only once it is restarted;
 *  · for today, anything still running from an earlier day is listed too
 *    (flagged stale_running) so it can be put on hold.
 */
async function dayWork(employee, day) {
  const now = new Date();
  const today = appDay(now);
  const { from, to } = appBounds(day);
  const end = to < now ? to : now;
  const items = [];
  let totalSecs = 0;

  for (const { raw, row } of await employeeTaskItems(employee)) {
    const intervals = workIntervals(raw, now);
    let secs = 0;
    for (const [a, b] of intervals) {
      if (a >= from && a < to) secs += Math.max(Math.floor((Math.min(b, end) - a) / 1000), 0);
    }
    const events = [raw.start_time, raw.complete_time];
    for (let i = 1; i <= 10; i += 1) events.push(raw[`hold_time_${i}`], raw[`restart_time_${i}`]);
    const actedToday = events.some((v) => inDay(v, from, to));
    const running = row.state === 'IN PROGRESS';
    const session = running ? sessionStart(raw) : null;
    const stale = running && day === today && session && session < from;
    if (!actedToday && !stale) continue;
    totalSecs += secs;
    items.push({
      ...taskItem({ raw, row }),
      seconds_on_date: secs,
      today_running: running && day === today && !stale,
      stale_running: Boolean(stale),
      running_since: stale ? dateKey(session) : null,
    });
  }

  for (const s of await employeeSheets(employee)) {
    const started = s.session_started_at ? new Date(s.session_started_at) : null;
    const runningToday = s.running && day === today && started && started >= from;
    const stale = s.running && day === today && started && started < from;
    const actedToday = inDay(s.last_activity_at, from, to) || (started && started >= from && started < to);
    if (!actedToday && !stale && !runningToday) continue;
    const secs = runningToday ? Math.max(Math.floor((now - started) / 1000), 0) : 0;
    totalSecs += secs;
    items.push({
      ...s,
      seconds_on_date: secs,
      today_running: Boolean(runningToday),
      stale_running: Boolean(stale),
      running_since: stale ? dateKey(started) : null,
    });
  }

  const rank = (i) => (i.status === 'IN PROGRESS' ? 0 : ['ON HOLD', 'REWORK'].includes(i.status) ? 1 : 2);
  items.sort((a, b) => rank(a) - rank(b) || String(a.client).localeCompare(String(b.client)));
  return { items, totalSecs, now };
}

// GET /live-all?employee=&date=  → what was worked on that day, all clients
router.get('/live-all', async (req, res) => {
  const employee = employeeFrom(req);
  if (!employee) return res.status(400).json({ success: false, message: 'employee is required' });
  const day = dateKey(req.query.date) || appDay();
  try {
    const { items, totalSecs, now } = await dayWork(employee, day);
    return res.json({ success: true, date: day, serverNow: now.toISOString(), totalSecs, data: items });
  } catch (err) {
    console.error('GET /workspace-tasks/live-all ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// GET /running?employee=  → { running, totalSecs (today only), serverNow } for the top bar
router.get('/running', async (req, res) => {
  const employee = employeeFrom(req);
  if (!employee) return res.status(400).json({ success: false, message: 'employee is required' });
  try {
    const { items, totalSecs, now } = await dayWork(employee, appDay());
    // Prefer what is running today; else an old forgotten one (to hold it).
    const running = items.find((i) => i.today_running) || items.find((i) => i.stale_running) || null;
    return res.json({
      success: true,
      serverNow: now.toISOString(),
      totalSecs,
      running: running && {
        ...running,
        task: running.title,
        trackingItemId: running.task_id ?? null,
        sessionStartedAt: running.session_started_at
          ? new Date(running.session_started_at).toISOString()
          : null,
        elapsedSecs: running.duration_secs,
      },
    });
  } catch (err) {
    console.error('GET /workspace-tasks/running ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ═════════════════════════════════════════════════════════════════════════════
// Task deadline rules (compliance) + Admin Employee Workspace
// ═════════════════════════════════════════════════════════════════════════════
const { loadRules, matchRule, evaluate } = require('../lib/taskRules');

const splitPeople = (cell) => String(cell || '')
  .split(/,|&/)
  .map((p) => p.trim())
  .filter((p) => p && p.toUpperCase() !== 'NONE');

function windowCutoffKey(months = 3) {
  const d = new Date();
  d.setMonth(d.getMonth() - months);
  return dateKey(d);
}

/**
 * Every (assignment, role, person, task) with its tracking rows, plus every
 * Content Calendar category the Page/Ads Handler has to prepare.
 * Only assignments whose deadline is inside the last `months` months (or
 * later) are read.
 */
async function collectWork({ client = null, date = '', employee = null, months = 3 } = {}) {
  const params = [];
  let where = 'is_assigned = 1';
  if (client) {
    where += ' AND LOWER(TRIM(client_name)) = LOWER(TRIM(?))';
    params.push(client);
  }
  const [assignments] = await db.query(
    `SELECT * FROM task_assignments WHERE ${where} ORDER BY id ASC`,
    params,
  );
  const active = await activeClientSet();
  const cutoff = windowCutoffKey(months);
  const picked = assignments.filter((a) => {
    if (!active.has(norm(a.client_name))) return false;
    const due = deadlineOf(a);
    if (date) return due === date;
    return !due || due >= cutoff;
  });

  // All Content Calendar rows of these assignments in one query.
  const ccBySource = new Map();
  if (picked.length) {
    const ids = picked.map((a) => Number(a.id)).filter(Boolean);
    const [cc] = await db.query(
      `SELECT id, source_assignment_id, source_role, source_task_index, cc_status,
              cc_handoff_at, cc_started_at, cc_last_activity_at, cc_duration_secs,
              cc_prepared_by_name, deliverable
       FROM content_calendar
       WHERE source_active = 1 AND source_assignment_id IN (${ids.join(',')})`,
    );
    for (const r of cc) {
      const k = `${r.source_assignment_id}:${r.source_role}:${r.source_task_index}`;
      if (!ccBySource.has(k)) ccBySource.set(k, []);
      ccBySource.get(k).push(r);
    }
  }

  const idCache = new Map();
  const idOf = async (person) => {
    const k = personKey(person);
    if (!idCache.has(k)) idCache.set(k, await employeeIdFor(person));
    return idCache.get(k);
  };

  const work = [];
  const calendar = [];
  for (const a of picked) {
    const due = deadlineOf(a);
    for (const role of ROLES) {
      const tasks = parseTasks(a[role.tasks]);
      if (!tasks.length) continue;

      // Handler's preparation of this role's categories (non-direct roles).
      if (!role.direct) {
        const handlers = [...splitPeople(a.page_handling), ...splitPeople(a.ads_handling)];
        for (const task of tasks) {
          const cc = ccBySource.get(`${a.id}:${role.key}:${task.taskIndex}`) || [];
          const preparer = cc.find((r) => r.cc_prepared_by_name)?.cc_prepared_by_name || handlers[0] || '';
          if (!preparer) continue;
          if (employee && personKey(preparer) !== personKey(employee)) continue;
          const statuses = cc.map((r) => upper(r.cc_status || 'IDLE'));
          const handed = cc.length > 0 && cc.every((r) => r.cc_handoff_at);
          calendar.push({
            assignment: a,
            due,
            role_key: 'content_calendar',
            role_label: 'Content Calendar',
            for_role: role.label,
            person: preparer,
            task,
            total: 1,
            done: handed ? 1 : 0,
            started: cc.some((r) => r.cc_started_at || Number(r.cc_duration_secs) > 0 ||
              !['IDLE', ''].includes(upper(r.cc_status || 'IDLE'))),
            started_at: null,
            assigned_at: a.created_at,
            status: handed ? 'ASSIGNED'
              : statuses.includes('IN PROGRESS') ? 'IN PROGRESS'
                : statuses.includes('ON HOLD') ? 'ON HOLD'
                  : statuses.length && statuses.every((s) => s === 'COMPLETED') ? 'COMPLETED' : 'IDLE',
          });
        }
      }

      for (const person of splitPeople(a[role.emp])) {
        if (employee && personKey(person) !== personKey(employee)) continue;
        const personId = await idOf(person);
        for (const task of tasks) {
          const list = await findTaskList(a.id, task.name, person, personId);
          const rows = list ? await loadRows(list.id, !role.direct) : [];
          const parents = rows.filter((r) => !r.parent_item_id);
          const starts = rows.map((r) => r.start_time).filter(Boolean).map((t) => new Date(t));
          let assignedAt = a.created_at;
          if (!role.direct) {
            const handoffs = (ccBySource.get(`${a.id}:${role.key}:${task.taskIndex}`) || [])
              .map((r) => r.cc_handoff_at).filter(Boolean).map((t) => new Date(t));
            assignedAt = handoffs.length ? new Date(Math.min(...handoffs)) : null;
          }
          work.push({
            assignment: a,
            due,
            role,
            person,
            task,
            list,
            rows,
            total: Math.max(task.count, parents.length),
            done: parents.filter((r) => r.complete_time ||
              ['IN REVIEW', 'APPROVED'].includes(rowState(r))).length,
            started: starts.length > 0,
            started_at: starts.length ? new Date(Math.min(...starts)) : null,
            assigned_at: assignedAt,
          });
        }
      }
    }
  }
  return { work, calendar };
}

function complianceItems({ work, calendar }, rules) {
  const items = [];
  const push = (base, metrics) => {
    const rule = matchRule(rules, base.role_key, base.task, base.count);
    const ev = evaluate(rule, metrics);
    items.push({ ...base, ...metrics, ...ev });
  };
  for (const w of work) {
    push({
      key: `${w.assignment.id}:${w.role.key}:${w.task.taskIndex}`,
      client: w.assignment.client_name,
      submission_date: w.due,
      role_key: w.role.key,
      role_label: w.role.label,
      employee: w.person,
      task: w.task.name,
      count: w.task.count,
      awaiting_handoff: !w.role.direct && !w.assigned_at,
    }, {
      total: w.total,
      done: w.done,
      started: w.started,
      started_at: w.started_at,
      assigned_at: w.assigned_at,
    });
  }
  for (const c of calendar) {
    push({
      key: `cc:${c.assignment.id}:${c.task.taskIndex}:${c.for_role}`,
      client: c.assignment.client_name,
      submission_date: c.due,
      role_key: 'content_calendar',
      role_label: `Content Calendar · ${c.for_role}`,
      employee: c.person,
      task: c.task.name,
      count: c.task.count,
      calendar_status: c.status,
    }, {
      total: c.total,
      done: c.done,
      started: c.started,
      started_at: c.started_at,
      assigned_at: c.assigned_at,
    });
  }
  return items;
}

// GET /compliance?client=&date=&employee=&late=1
// Deadline-rule status of every task (or only the late ones).
router.get('/compliance', async (req, res) => {
  try {
    const rules = await loadRules(db);
    const collected = await collectWork({
      client: String(req.query.client || '').trim() || null,
      date: dateKey(req.query.date),
      employee: String(req.query.employee || '').trim() || null,
    });
    let items = complianceItems(collected, rules);
    if (String(req.query.late) === '1') items = items.filter((i) => i.status === 'LATE');
    items.sort((a, b) =>
      (b.status === 'LATE') - (a.status === 'LATE') ||
      Math.max(0, ...b.issues.map((i) => i.days_late)) - Math.max(0, ...a.issues.map((i) => i.days_late)) ||
      a.client.localeCompare(b.client));
    return res.json({ success: true, data: items });
  } catch (err) {
    console.error('GET /workspace-tasks/compliance ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// GET /admin/cards  → every client card (client + deadline), last 3 months,
// with the whole team's counts, team list and late count.
// Additional tasks are included too (as tasks flagged is_additional) so the
// admin workspace can show them inside the client's current card.
router.get('/admin/cards', async (req, res) => {
  try {
    const rules = await loadRules(db);
    const collected = await collectWork({});
    const compliance = complianceItems(collected, rules);
    const cards = new Map();
    const cardFor = (client, date) => {
      const k = `${norm(client)}|${date}`;
      if (!cards.has(k)) {
        cards.set(k, {
          client_name: String(client).trim(),
          submission_date: date,
          tasks: [],
          team: new Map(),
          late: 0,
          to_review: 0,
        });
      }
      return cards.get(k);
    };
    for (const w of collected.work) {
      const card = cardFor(w.assignment.client_name, w.due);
      // Package + monthly maintain day (from Tasks Assign) for the client card.
      card.package = card.package || String(w.assignment.deliverables || '').trim();
      card.maintenance_day = card.maintenance_day || maintenanceDay(w.assignment.maintenance_date);
      const created = w.assignment.created_at ? new Date(w.assignment.created_at) : null;
      if (created && !Number.isNaN(created.getTime()) &&
          (!card.assigned_at || created > new Date(card.assigned_at))) {
        card.assigned_at = created.toISOString();
      }
      const counts = countStates(w.rows, w.task.count);
      card.tasks.push({
        key: `${w.assignment.id}:${w.role.key}:${w.task.taskIndex}:${personKey(w.person)}`,
        name: w.task.name,
        role: w.role.label,
        role_key: w.role.key,
        employee: w.person,
        is_additional: false,
        awaiting_handoff: !w.role.direct && w.rows.length === 0,
        ...counts,
      });
      card.to_review += counts.in_review;
      const tk = `${w.role.key}|${personKey(w.person)}`;
      const member = card.team.get(tk) || { role: w.role.label, role_key: w.role.key, employee: w.person, tasks: [] };
      const parents = w.rows.filter((r) => !r.parent_item_id);
      member.tasks.push({
        name: w.task.name,
        completed: parents.filter((r) => rowState(r) === 'APPROVED').length,
        total: Math.max(w.task.count, parents.length),
        running: w.rows.some((r) => upper(r.status) === 'IN PROGRESS'),
      });
      card.team.set(tk, member);
    }
    for (const c of collected.calendar) {
      const card = cardFor(c.assignment.client_name, c.due);
      card.tasks.push({
        key: `cc:${c.assignment.id}:${c.task.taskIndex}:${c.for_role}`,
        name: `Content Calendar · ${c.task.name}`,
        role: 'Content Calendar',
        role_key: 'content_calendar',
        employee: c.person,
        is_additional: false,
        awaiting_handoff: false,
        total: 1,
        approved: c.done,
        in_progress: c.status === 'IN PROGRESS' ? 1 : 0,
        on_hold: c.status === 'ON HOLD' ? 1 : 0,
        in_review: 0,
        rework: 0,
        rejected: 0,
        pending: !c.done && !['IN PROGRESS', 'ON HOLD'].includes(c.status) ? 1 : 0,
      });
    }

    // Additional tasks (Page / Ads Handler "Add Additional Task", admin or
    // handler-assigned). The app attaches each one to the client's CURRENT card.
    try {
      const active = await activeClientSet();
      const [addLists] = await db.query(
        `SELECT id, client_name, employee_name, deliverables, submission_date, no_of_rows
         FROM task_list WHERE additional_task_id IS NOT NULL`,
      );
      for (const list of addLists) {
        if (!active.has(norm(list.client_name))) continue;
        const rows = await loadRows(list.id, false);
        const by = await assignedByFor(list.id, list.client_name);
        const card = cardFor(list.client_name, dateKey(list.submission_date));
        card.tasks.push({
          key: `additional:${list.id}`,
          name: list.deliverables,
          role: 'Additional task',
          role_key: 'additional',
          employee: String(list.employee_name || '').trim(),
          is_additional: true,
          handler_assigned: !!by,
          assigned_by: by?.name || 'Admin',
          assigned_by_role: by?.role || '',
          awaiting_handoff: false,
          ...countStates(rows, Number(list.no_of_rows) || 1),
        });
      }
    } catch (err) {
      console.error('admin/cards additional tasks failed:', err.message);
    }

    for (const item of compliance) {
      if (item.status !== 'LATE') continue;
      const card = cards.get(`${norm(item.client)}|${item.submission_date}`);
      if (card) card.late += 1;
    }
    const data = [...cards.values()]
      .map((c) => ({ ...c, team: [...c.team.values()] }))
      .sort((a, b) => a.client_name.localeCompare(b.client_name) ||
        a.submission_date.localeCompare(b.submission_date));
    return res.json({ success: true, data });
  } catch (err) {
    console.error('GET /workspace-tasks/admin/cards ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// GET /admin/tasks?client=&date=  → every team member's task groups (same
// shape as /my-tasks) for this card, with live status and rule compliance.
router.get('/admin/tasks', async (req, res) => {
  const client = String(req.query.client || '').trim();
  const date = dateKey(req.query.date);
  if (!client) return res.status(400).json({ success: false, message: 'client is required' });
  try {
    const rules = await loadRules(db);
    const collected = await collectWork({ client, date });
    const compliance = complianceItems(collected, rules);
    const people = new Map();
    for (const w of collected.work) {
      const k = personKey(w.person);
      const p = people.get(k) || { employee: w.person, roles: [] };
      if (!p.roles.includes(w.role.label)) p.roles.push(w.role.label);
      people.set(k, p);
    }
    const members = [];
    for (const p of people.values()) {
      const groups = await buildMyTasks(p.employee, client, date);
      for (const g of groups) {
        const c = compliance.find((i) => i.key === g.key && personKey(i.employee) === personKey(p.employee));
        g.compliance = c ? { status: c.status, issues: c.issues, start_due: c.start_due,
          complete_due: c.complete_due, per_week: c.per_week, expected_by_now: c.expected_by_now } : null;
      }
      members.push({ ...p, groups });
    }
    // Every Content Calendar category of this client (who prepares it, status, timer).
    const [ccRows] = await db.query(
      `SELECT id, client_name, deliverable, source_assignment_id, source_role, source_task_index,
              source_row_number, submit_date, cc_status, cc_duration_secs, cc_started_at,
              cc_hold_reason, cc_last_activity_at, cc_handoff_at, assigned_to_name,
              cc_prepared_by_name
       FROM content_calendar
       WHERE source_assignment_id IS NOT NULL AND source_active = 1
         AND LOWER(TRIM(client_name)) = LOWER(TRIM(?))
       ORDER BY source_assignment_id, source_role, source_task_index, source_row_number`,
      [client],
    );
    const preparedBy = new Map();
    for (const r of ccRows) {
      const k = `${r.source_assignment_id}:${r.source_role}:${r.source_task_index}`;
      if (r.cc_prepared_by_name && !preparedBy.has(k)) preparedBy.set(k, r.cc_prepared_by_name);
    }
    const assignmentIds = new Set(collected.work.map((w) => Number(w.assignment.id))
      .concat(collected.calendar.map((c) => Number(c.assignment.id))));
    const calendar = groupSheets(ccRows)
      .filter((s) => !date || assignmentIds.has(Number(s.source_assignment_id)))
      .map((s) => ({
        ...s,
        prepared_by: preparedBy.get(`${s.source_assignment_id}:${s.source_role}:${s.source_task_index}`) || '',
      }));
    return res.json({
      success: true,
      data: {
        members,
        calendar: compliance.filter((i) => i.role_key === 'content_calendar'),
        sheets: calendar,
        compliance,
      },
    });
  } catch (err) {
    console.error('GET /workspace-tasks/admin/tasks ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

async function isAdminUser(name) {
  if (!name) return false;
  const [rows] = await db.query(
    `SELECT id FROM employee_users
     WHERE LOWER(TRIM(full_name)) = LOWER(TRIM(?))
       AND (LOWER(user_type) = 'admin' OR is_main_admin = 1) LIMIT 1`,
    [name],
  ).catch(() => [[]]);
  return rows.length > 0;
}

// POST /day-plan/add { employee, task_id } — add ONE My Tasks row to today's
// Day Planner (row based, not category based). Safe to call twice.
router.post('/day-plan/add', async (req, res) => {
  const employee = employeeFrom(req);
  const taskId = Number(req.body?.task_id);
  if (!employee || !taskId) {
    return res.status(400).json({ success: false, message: 'employee and task_id are required' });
  }
  try {
    const [[row]] = await db.query(
      `SELECT tti.id, tl.employee_name, tl.employee_id
       FROM time_tracking_task_items tti JOIN task_list tl ON tl.id = tti.task_list_id
       WHERE tti.id = ?`,
      [taskId],
    );
    if (!row) return res.status(404).json({ success: false, message: 'Task row not found' });
    const employeeId = await employeeIdFor(employee);
    const mine = norm(row.employee_name) === norm(employee) ||
      (employeeId && Number(row.employee_id) === Number(employeeId));
    if (!mine) return res.status(403).json({ success: false, message: 'This row is not assigned to you' });

    const marker = `[Task Row #${taskId}]`;
    const [existing] = await db.query(
      `SELECT id FROM day_plan_rows
       WHERE LOWER(TRIM(employee_name)) = LOWER(TRIM(?)) AND plan_date = CURDATE()
         AND today_plan LIKE ? LIMIT 1`,
      [row.employee_name, `%${marker}%`],
    );
    if (existing.length) {
      return res.json({ success: true, added: false, message: 'Already in today’s Day Planner' });
    }
    const { ensureTaskInDayPlan } = require('./tracking-items');
    await ensureTaskInDayPlan(db, { id: taskId, employee_name: row.employee_name }, true);
    await syncDayPlanStatus(row.employee_name).catch(() => {});
    emit(req, { type: 'DAY_PLAN_UPDATED', trackingItemId: taskId });
    return res.json({ success: true, added: true, message: 'Added to today’s Day Planner' });
  } catch (err) {
    console.error('POST /workspace-tasks/day-plan/add ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// GET /day-plan/rows?employee=  → task row ids already in today's planner
// POST /day-plan/carry-forward { employee }
// Opening today's Day Planner: tasks left ON HOLD (or still running) from an
// earlier day are added to TODAY's plan automatically — unless they are
// already in it. Works for My Tasks rows and Content Calendar categories.
router.post('/day-plan/carry-forward', async (req, res) => {
  const employee = employeeFrom(req);
  if (!employee) return res.status(400).json({ success: false, message: 'employee is required' });
  try {
    const [today] = await db.query(
      `SELECT today_plan, is_submitted FROM day_plan_rows
       WHERE LOWER(TRIM(employee_name)) = LOWER(TRIM(?)) AND plan_date = CURDATE()`,
      [employee],
    );
    const inPlan = new Set();
    let submitted = 0;
    for (const r of today) {
      if (Number(r.is_submitted) === 1) submitted = 1;
      for (const m of String(r.today_plan || '').matchAll(/\[Task Row #(\d+)\]/g)) inPlan.add(`task:${m[1]}`);
      for (const m of String(r.today_plan || '').matchAll(/\[Calendar Row #(\d+)\]/g)) inPlan.add(`cc:${m[1]}`);
    }
    const [[roleRow]] = await db.query(
      'SELECT role FROM employee_users WHERE LOWER(TRIM(full_name)) = LOWER(TRIM(?)) LIMIT 1',
      [employee],
    );
    const insert = (client, due, plan, status) => db.query(
      `INSERT INTO day_plan_rows
         (employee_name, employee_role, plan_date, report_type, client_name,
          maintenance_date, today_plan, status, remarks, is_submitted)
       VALUES (?, ?, CURDATE(), 'Morning', ?, ?, ?, ?, ?, ?)`,
      [employee, roleRow?.role || null, client || null, due ? String(due).slice(0, 10) : null,
        plan, status, 'Carried forward — on hold from an earlier day', submitted],
    );

    const added = [];
    // My Tasks rows (only rows the employee really has in Employee Workspace).
    const all = await employeeTaskItems(employee);
    const visible = await workspaceVisible(employee, all);
    for (const entry of all.filter(visible)) {
      const { raw, row } = entry;
      if (!['ON HOLD', 'IN PROGRESS'].includes(row.state)) continue;
      if (inPlan.has(`task:${row.id}`)) continue;
      // Only work from an earlier day (today's holds are already in today's plan).
      const last = dateKey(raw.updated_at instanceof Date ? raw.updated_at : new Date(raw.updated_at || 0));
      if (last && last >= dateKey(new Date())) continue;
      const headline = String(row.hook_headline || '').trim();
      await insert(
        row.client_name,
        dueKey(raw),
        `[Task Row #${row.id}] ${row.deliverable} · Row ${row.display_no}${headline ? ` — ${headline}` : ''}`,
        row.state === 'IN PROGRESS' ? 'PROCESSING' : 'HOLD',
      );
      inPlan.add(`task:${row.id}`);
      added.push({ kind: 'TASK', client: row.client_name, title: `${row.deliverable} · Row ${row.display_no}` });
    }
    // Content Calendar categories this handler prepares.
    for (const sh of await employeeSheets(employee)) {
      if (!['ON HOLD', 'IN PROGRESS'].includes(sh.status)) continue;
      if (sh.calendar_ids.some((id) => inPlan.has(`cc:${id}`))) continue;
      const last = sh.last_activity_at ? dateKey(new Date(sh.last_activity_at)) : '';
      if (last && last >= dateKey(new Date())) continue;
      const leader = sh.calendar_ids[0];
      await insert(
        sh.client,
        sh.submit_date,
        `[Calendar Row #${leader}] Prepare ${sh.deliverable} (${sh.calendar_ids.length} rows)`,
        sh.status === 'IN PROGRESS' ? 'PROCESSING' : 'HOLD',
      );
      sh.calendar_ids.forEach((id) => inPlan.add(`cc:${id}`));
      added.push({ kind: 'CONTENT_CALENDAR', client: sh.client, title: `Content Calendar · ${sh.deliverable}` });
    }
    if (added.length) {
      await syncDayPlanStatus(employee).catch(() => {});
      emit(req, { type: 'DAY_PLAN_UPDATED', carried: added.length });
    }
    return res.json({ success: true, added: added.length, items: added });
  } catch (err) {
    console.error('POST /workspace-tasks/day-plan/carry-forward ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

router.get('/day-plan/rows', async (req, res) => {
  const employee = employeeFrom(req);
  if (!employee) return res.status(400).json({ success: false, message: 'employee is required' });
  try {
    const [rows] = await db.query(
      `SELECT today_plan FROM day_plan_rows
       WHERE LOWER(TRIM(employee_name)) = LOWER(TRIM(?)) AND plan_date = CURDATE()`,
      [employee],
    );
    const ids = new Set();
    const calendar = new Set();
    for (const r of rows) {
      for (const m of String(r.today_plan || '').matchAll(/\[Task Row #(\d+)\]/g)) ids.add(Number(m[1]));
      for (const m of String(r.today_plan || '').matchAll(/\[Calendar Row #(\d+)\]/g)) calendar.add(Number(m[1]));
    }
    return res.json({ success: true, data: [...ids], calendar: [...calendar] });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ═════════════════════════════════════════════════════════════════════════════
// Employee Performance (admin) — built on the same tracking data as
// Employee Workspace, Live Tracking and the top bar.
//
//   GET /performance/overview?mode=daily&date=YYYY-MM-DD
//   GET /performance/overview?mode=monthly&fromDate=…&toDate=…
//   GET /performance/detail?employeeName=…&(same range)
//
// Rules (shown on the screen too):
//  · Days follow office time (UTC+05:30). A work session counts only up to the
//    end of the day it started — a task left running overnight must be held
//    and restarted to count again.
//  · Tasks in the period = tasks due in the period + tasks started, held,
//    restarted, completed or reviewed in the period.
//  · Available time = working days (Mon–Sat, up to today) × WORK_DAY_HOURS (8).
//  · Score = Completion 35 · Productive time 20 · On-time 20 · Approval 15 ·
//    Day Planner 10. A part with no data is left out and the rest re-weighted.
// ═════════════════════════════════════════════════════════════════════════════
const WORK_DAY_SECS = Math.round((Number(process.env.WORK_DAY_HOURS) || 8) * 3600);
const MAX_SESSION_SECS = Math.round((Number(process.env.MAX_SESSION_HOURS) || 10) * 3600);
const PERF_CACHE_MS = 20000;
const perfCache = new Map();

const SCORE_WEIGHTS = [
  { key: 'completion', label: 'Task completion', weight: 35 },
  { key: 'productivity', label: 'Productive time', weight: 20 },
  { key: 'onTime', label: 'On-time delivery', weight: 20 },
  { key: 'approval', label: 'Manager approval', weight: 15 },
  { key: 'planner', label: 'Day Planner', weight: 10 },
];

const pct = (part, whole) => (whole > 0 ? Math.round((part / whole) * 1000) / 10 : 0);
function fmtSecs(secs) {
  const s = Math.max(0, Math.round(Number(secs) || 0));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (h && m) return `${h}h ${m}m`;
  if (h) return `${h}h`;
  return `${m}m`;
}
function gradeFor(score, active) {
  if (!active) return 'No Activity';
  if (score >= 85) return 'Excellent';
  if (score >= 70) return 'Good';
  if (score >= 50) return 'Average';
  return 'Needs Improvement';
}
const initialsOf = (name) => String(name || '?').trim().split(/\s+/).filter((w) => /[a-z]/i.test(w))
  .slice(0, 2).map((w) => w[0].toUpperCase()).join('') || '?';

function perfRange(q) {
  const today = appDay();
  let fromDay;
  let toDay;
  if (String(q.mode || 'daily') === 'daily') {
    fromDay = dateKey(q.date) || today;
    toDay = fromDay;
  } else {
    fromDay = dateKey(q.fromDate) || `${today.slice(0, 8)}01`;
    toDay = dateKey(q.toDate) || today;
  }
  if (toDay < fromDay) [fromDay, toDay] = [toDay, fromDay];
  const from = appBounds(fromDay).from;
  const to = appBounds(toDay).to;
  // Calendar days of the range (max 92) and working days (Mon–Sat, ≤ today).
  const days = [];
  for (let t = from.getTime(); t < to.getTime() && days.length < 92; t += 86400000) {
    days.push(appDay(new Date(t + 3600000)));
  }
  const workDays = days.filter((d) => {
    if (d > today) return false;
    const [y, m, dd] = d.split('-').map(Number);
    return new Date(Date.UTC(y, m - 1, dd)).getUTCDay() !== 0;
  });
  return { fromDay, toDay, from, to, days, workDays, today };
}

// Work sessions of a task row, each cut at the end of the day it started and
// at MAX_SESSION_HOURS (10h) — a forgotten Hold cannot add a whole day.
function cappedSessions(raw, now) {
  return workIntervals(raw, now).map(([a, b]) => {
    const dayEnd = appBounds(appDay(a)).to;
    const maxEnd = new Date(a.getTime() + MAX_SESSION_SECS * 1000);
    let end = b;
    if (end > dayEnd) end = dayEnd;
    if (end > maxEnd) end = maxEnd;
    return [a, end];
  }).filter(([a, b]) => b > a);
}

function sessionsInRange(sessions, from, to, now) {
  const end = to < now ? to : now;
  const out = [];
  for (const [a, b] of sessions) {
    const s = a > from ? a : from;
    const e = b < end ? b : end;
    if (e > s) out.push({ day: appDay(s), secs: Math.floor((e - s) / 1000) });
  }
  return out;
}

/** Everything the performance screen needs, for every employee in one go. */
async function buildPerformance(range) {
  const cacheKey = `${range.fromDay}|${range.toDay}`;
  const hit = perfCache.get(cacheKey);
  if (hit && Date.now() - hit.at < PERF_CACHE_MS) return hit.data;

  const now = new Date();
  const { from, to, fromDay, toDay } = range;
  const inRange = (v) => v && new Date(v) >= from && new Date(v) < to;

  // ── 1. Employees ──
  const [users] = await db.query(
    `SELECT id, full_name, initials, staff_id, role, user_type, is_main_admin
     FROM employee_users WHERE is_active = 1 ORDER BY full_name`,
  );
  const byId = new Map(users.map((u) => [Number(u.id), u]));
  const byKey = new Map(users.map((u) => [personKey(u.full_name), u]));
  const userFor = (id, name) => byId.get(Number(id)) || byKey.get(personKey(name)) || null;

  // ── 2. Active clients + assignments (who is named on what) ──
  const active = await activeClientSet();
  const [assignRows] = await db.query('SELECT * FROM task_assignments WHERE is_assigned = 1');
  const named = new Map(); // userId → Map("assignmentId|task" → direct?)
  for (const a of assignRows) {
    if (!active.has(norm(a.client_name))) continue;
    for (const role of ROLES) {
      const cell = a[role.emp];
      if (!cell) continue;
      for (const u of users) {
        if (!namesEmployee(cell, u.full_name)) continue;
        if (!named.has(u.id)) named.set(u.id, new Map());
        const m = named.get(u.id);
        for (const task of parseTasks(a[role.tasks])) {
          const k = `${a.id}|${norm(task.name)}`;
          m.set(k, m.get(k) === true || Boolean(role.direct));
        }
      }
    }
  }

  // ── 3. Task rows: worked on / open since before the range end, or not started ──
  const [taskRows] = await db.query(
    `SELECT tti.*, tl.deliverables, tl.client_name, tl.employee_name,
            tl.employee_id AS tl_employee_id, tl.task_assignment_id AS tl_assignment_id,
            tl.additional_task_id AS tl_additional, tl.submission_date AS tl_submission_date,
            ta.deadline AS ta_deadline, ta.maintenance_date AS ta_maintenance,
            mr.manager_action, mr.manager_comment, mr.reviewed_at
     FROM time_tracking_task_items tti
     JOIN task_list tl ON tl.id = tti.task_list_id
     LEFT JOIN task_assignments ta ON ta.id = tl.task_assignment_id
     LEFT JOIN manager_review mr ON mr.tracking_item_id = tti.id
     WHERE tti.start_time IS NULL
        OR (tti.start_time < ? AND (tti.complete_time IS NULL OR tti.complete_time >= ?
            OR mr.reviewed_at >= ?))`,
    [to, from, from],
  );

  const people = new Map(); // userId → accumulator
  const acc = (u) => {
    if (!people.has(u.id)) people.set(u.id, { user: u, tasks: [], planner: new Map() });
    return people.get(u.id);
  };

  for (const raw of taskRows) {
    if (!active.has(norm(raw.client_name))) continue;
    const u = userFor(raw.tl_employee_id, raw.employee_name);
    if (!u) continue;
    // Same visibility as Employee Workspace → My Tasks.
    const started = Boolean(raw.start_time) || upper(raw.status || 'IDLE') !== 'IDLE';
    if (!started && !raw.tl_additional) {
      const handed = Number(raw.content_calendar_assigned) === 1 || Boolean(raw.parent_item_id);
      const direct = raw.tl_assignment_id
        ? named.get(u.id)?.get(`${raw.tl_assignment_id}|${norm(raw.deliverables)}`)
        : undefined;
      if (!(direct === true || handed)) continue;
    }

    const due = dueKey(raw);
    const state = rowState(raw);
    const sessions = cappedSessions(raw, now);
    const worked = sessionsInRange(sessions, from, to, now);
    const events = [];
    const push = (v, type) => { if (inRange(v)) events.push({ at: new Date(v), type }); };
    push(raw.start_time, 'TASK_STARTED');
    for (let i = 1; i <= 10; i += 1) {
      push(raw[`hold_time_${i}`], 'TASK_HELD');
      push(raw[`restart_time_${i}`], 'TASK_RESTARTED');
    }
    push(raw.complete_time, 'TASK_COMPLETED');
    const review = upper(raw.review_status);
    if (['APPROVED', 'REWORK', 'REJECTED'].includes(review)) push(raw.reviewed_at, `MANAGER_${review}`);

    const dueIn = due && due >= fromDay && due <= toDay;
    if (!dueIn && !events.length && !worked.length) continue;

    const completedAt = raw.complete_time ? new Date(raw.complete_time) : null;
    acc(u).tasks.push({
      kind: 'TASK',
      id: raw.id,
      client: raw.client_name,
      deliverable: raw.deliverables,
      rowLabel: `Row ${Number(raw.sub_no) > 0 ? `${raw.s_no}.${raw.sub_no}` : raw.s_no}`,
      state,
      due,
      completedAt,
      review: ['APPROVED', 'REWORK', 'REJECTED'].includes(review) ? review : null,
      worked,
      events,
      staleRunning: state === 'IN PROGRESS' && sessions.length > 0 &&
        sessions[sessions.length - 1][1] < now && !raw.complete_time,
    });
  }

  // ── 4. Content Calendar categories prepared by Page / Ads Handlers ──
  const [ccRows] = await db.query(
    `SELECT id, client_name, deliverable, source_assignment_id, source_role, source_task_index,
            source_row_number, submit_date, cc_status, cc_duration_secs, cc_started_at,
            cc_hold_reason, cc_last_activity_at, cc_handoff_at, assigned_to_name,
            cc_prepared_by_id, cc_prepared_by_name
     FROM content_calendar
     WHERE source_assignment_id IS NOT NULL AND source_active = 1
       AND (cc_prepared_by_id IS NOT NULL OR COALESCE(cc_prepared_by_name, '') <> '')
       AND (cc_last_activity_at >= ? OR cc_handoff_at >= ? OR UPPER(cc_status) = 'IN PROGRESS'
            OR submit_date >= ?)`,
    [from, from, fromDay],
  );
  const ccByUser = new Map();
  for (const r of ccRows) {
    if (!active.has(norm(r.client_name))) continue;
    const u = userFor(r.cc_prepared_by_id, r.cc_prepared_by_name);
    if (!u) continue;
    if (!ccByUser.has(u.id)) ccByUser.set(u.id, { u, rows: [] });
    ccByUser.get(u.id).rows.push(r);
  }
  for (const { u, rows } of ccByUser.values()) {
    const byKey2 = new Map();
    for (const r of rows) {
      const k = `${r.source_assignment_id}:${r.source_role}:${r.source_task_index}`;
      if (!byKey2.has(k)) byKey2.set(k, []);
      byKey2.get(k).push(r);
    }
    for (const group of byKey2.values()) {
      const [sheet] = groupSheets(group);
      if (!sheet) continue;
      const handoffs = group.map((r) => r.cc_handoff_at).filter(Boolean).map((t) => new Date(t));
      const handedAt = handoffs.length === group.length && handoffs.length
        ? new Date(Math.max(...handoffs)) : null;
      const due = sheet.submit_date;
      const events = [];
      if (inRange(handedAt)) events.push({ at: handedAt, type: 'TASK_COMPLETED' });
      const lastAct = sheet.last_activity_at ? new Date(sheet.last_activity_at) : null;
      // Time: the running session (cut at its day end) + banked time on the
      // day of the last activity (the calendar keeps no per-session history).
      const worked = [];
      if (sheet.running && sheet.session_started_at) {
        worked.push(...sessionsInRange(cappedSessions({ start_time: sheet.session_started_at }, now), from, to, now));
      }
      if (inRange(lastAct) && Number(sheet.banked_secs) > 0) {
        worked.push({ day: appDay(lastAct), secs: Number(sheet.banked_secs) });
      }
      const dueIn = due && due >= fromDay && due <= toDay;
      if (!dueIn && !events.length && !worked.length && !inRange(lastAct)) continue;
      const state = sheet.status === 'ASSIGNED' ? 'SHARED'
        : sheet.status === 'COMPLETED' ? 'IN REVIEW' : sheet.status;
      acc(u).tasks.push({
        kind: 'CONTENT_CALENDAR',
        id: sheet.key,
        client: sheet.client,
        deliverable: `Content Calendar · ${sheet.deliverable}`,
        rowLabel: `${group.length} rows`,
        state,
        due,
        completedAt: handedAt,
        review: null,
        worked,
        events,
        staleRunning: false,
      });
    }
  }

  // ── 5. Day Planner submissions ──
  const [planRows] = await db.query(
    `SELECT employee_name, plan_date, report_type, MAX(is_submitted) AS submitted,
            MAX(submitted_at) AS submitted_at
     FROM day_plan_rows WHERE plan_date BETWEEN ? AND ?
     GROUP BY employee_name, plan_date, report_type`,
    [fromDay, toDay],
  );
  for (const p of planRows) {
    const u = userFor(null, p.employee_name);
    if (!u || !Number(p.submitted)) continue;
    const day = dateKey(p.plan_date);
    const a = acc(u);
    const rec = a.planner.get(day) || { morning: false, evening: false, at: null };
    if (/^even/i.test(String(p.report_type || ''))) rec.evening = true;
    else rec.morning = true;
    if (p.submitted_at && (!rec.at || new Date(p.submitted_at) > rec.at)) rec.at = new Date(p.submitted_at);
    a.planner.set(day, rec);
  }

  // ── 6. Employees shown: every non-admin + anyone with work in the period ──
  for (const u of users) {
    const isAdmin = String(u.user_type || '').toLowerCase() === 'admin' || Number(u.is_main_admin) === 1;
    if (!isAdmin) acc(u);
  }

  const data = [...people.values()].map((p) => summarise(p, range, now));
  perfCache.set(cacheKey, { at: Date.now(), data });
  if (perfCache.size > 30) perfCache.delete(perfCache.keys().next().value);
  return data;
}

function groupOf(state) {
  switch (state) {
    case 'IN REVIEW':
    case 'APPROVED':
    case 'SHARED':
    case 'COMPLETED':
      return 'completed';
    case 'IN PROGRESS':
      return 'processing';
    case 'ON HOLD':
      return 'onHold';
    case 'REWORK':
    case 'REJECTED':
      return 'rejected';
    default:
      return 'pending';
  }
}
const STATUS_LABEL = {
  IDLE: 'Not started',
  'IN PROGRESS': 'In progress',
  'ON HOLD': 'On hold',
  REWORK: 'Rework',
  REJECTED: 'Rejected',
  'IN REVIEW': 'Completed · in review',
  APPROVED: 'Approved',
  COMPLETED: 'Completed',
  SHARED: 'Shared with team',
};

function summarise({ user, tasks, planner }, range, now) {
  const { workDays, days, today } = range;
  const counts = { completed: 0, processing: 0, onHold: 0, pending: 0, rejected: 0 };
  let workedSecs = 0;
  let onTime = 0;
  let late = 0;
  const review = { approved: 0, rework: 0, rejected: 0, pendingReview: 0 };
  const perDay = new Map(days.map((d) => [d, { secs: 0, completed: 0, started: 0 }]));
  const clients = new Map();
  const timeline = [];

  for (const t of tasks) {
    const g = groupOf(t.state);
    counts[g] += 1;
    const secs = t.worked.reduce((s, w) => s + w.secs, 0);
    workedSecs += secs;
    for (const w of t.worked) if (perDay.has(w.day)) perDay.get(w.day).secs += w.secs;
    for (const e of t.events) {
      const d = perDay.get(appDay(e.at));
      if (d && e.type === 'TASK_COMPLETED') d.completed += 1;
      if (d && e.type === 'TASK_STARTED') d.started += 1;
    }

    let timing = '—';
    if (g === 'completed' && t.completedAt) {
      const doneDay = appDay(t.completedAt);
      if (t.due) {
        if (doneDay <= t.due) { onTime += 1; timing = 'On time'; } else { late += 1; timing = 'Late'; }
      } else timing = 'Done';
    } else if (t.due) {
      timing = t.due < today ? 'Overdue' : t.due === today ? 'Due today' : 'Upcoming';
    }

    if (t.review === 'APPROVED') review.approved += 1;
    else if (t.review === 'REWORK') review.rework += 1;
    else if (t.review === 'REJECTED') review.rejected += 1;
    else if (t.state === 'IN REVIEW') review.pendingReview += 1;

    const c = clients.get(t.client) || { clientName: t.client, tasks: [], secs: 0, ...Object.fromEntries(Object.keys(counts).map((k) => [k, 0])) };
    c[g] += 1;
    c.secs += secs;
    c.tasks.push({
      kind: t.kind,
      deliverable: t.deliverable,
      rowLabel: t.rowLabel,
      roleName: t.kind === 'CONTENT_CALENDAR' ? 'Content Calendar' : 'Task',
      status: t.state,
      statusGroup: g,
      statusLabel: STATUS_LABEL[t.state] || t.state,
      duration: fmtSecs(secs),
      secs,
      due: t.due || null,
      completedAt: t.completedAt ? t.completedAt.toISOString() : null,
      timing,
      performance: timing,
      reviewStatus: t.review || (t.state === 'IN REVIEW' ? 'Pending' : '-'),
      staleRunning: t.staleRunning,
    });
    clients.set(t.client, c);

    for (const e of t.events) {
      const verb = {
        TASK_STARTED: 'Started',
        TASK_HELD: 'Put on hold',
        TASK_RESTARTED: 'Restarted',
        TASK_COMPLETED: t.kind === 'CONTENT_CALENDAR' ? 'Shared with team' : 'Completed',
        MANAGER_APPROVED: 'Approved by manager',
        MANAGER_REWORK: 'Sent back for rework',
        MANAGER_REJECTED: 'Rejected by manager',
      }[e.type] || e.type;
      timeline.push({
        date: e.at.toISOString(),
        type: e.type,
        label: `${verb} · ${t.deliverable} ${t.rowLabel} · ${t.client}`,
      });
    }
  }

  // Day Planner
  let morning = 0;
  let evening = 0;
  let submittedDays = 0;
  const plannerDays = workDays.map((d) => {
    const rec = planner.get(d) || { morning: false, evening: false };
    if (rec.morning) morning += 1;
    if (rec.evening) evening += 1;
    if (rec.morning || rec.evening) submittedDays += 1;
    if (rec.at) timeline.push({ date: rec.at.toISOString(), type: 'PLANNER_SUBMITTED', label: `Day Planner submitted (${d})` });
    return { date: d, morningSubmitted: rec.morning, eveningSubmitted: rec.evening };
  });

  const total = tasks.length;
  const availableSecs = workDays.length * WORK_DAY_SECS;
  const productivityPct = Math.min(100, pct(workedSecs, availableSecs));
  const completedWithDue = onTime + late;
  const reviewed = review.approved + review.rework + review.rejected;

  const values = {
    completion: total ? pct(counts.completed, total) : null,
    productivity: availableSecs ? productivityPct : null,
    onTime: completedWithDue ? pct(onTime, completedWithDue) : null,
    approval: reviewed ? pct(review.approved, reviewed) : null,
    planner: workDays.length ? pct(submittedDays, workDays.length) : null,
  };
  const hasActivity = total > 0 || workedSecs > 0;
  const usable = SCORE_WEIGHTS.filter((w) => values[w.key] !== null);
  const weightSum = usable.reduce((s, w) => s + w.weight, 0);
  const score = hasActivity && weightSum
    ? Math.round(usable.reduce((s, w) => s + values[w.key] * w.weight, 0) / weightSum)
    : 0;
  const parts = SCORE_WEIGHTS.map((w) => ({
    key: w.key,
    label: w.label,
    weight: w.weight,
    valuePct: values[w.key],
    points: values[w.key] === null || !weightSum ? null
      : Math.round((values[w.key] * w.weight) / weightSum * 10) / 10,
  }));

  const activeDays = [...perDay.values()].filter((d) => d.secs > 0).length;
  const clientList = [...clients.values()].map((c) => {
    const n = c.tasks.length;
    const rank = { processing: 0, onHold: 1, rejected: 2, pending: 3, completed: 4 };
    c.tasks.sort((a, b) => rank[a.statusGroup] - rank[b.statusGroup] || String(a.due).localeCompare(String(b.due)));
    return {
      clientName: c.clientName,
      totalTasks: n,
      completed: c.completed,
      processing: c.processing,
      onHold: c.onHold,
      pending: c.pending,
      rejected: c.rejected,
      'ON HOLD': c.onHold,
      REJECTED: c.rejected,
      completionPct: Math.round(pct(c.completed, n)),
      totalSecs: c.secs,
      totalDuration: fmtSecs(c.secs),
      tasks: c.tasks,
    };
  }).sort((a, b) => b.totalSecs - a.totalSecs || b.totalTasks - a.totalTasks);

  timeline.sort((a, b) => b.date.localeCompare(a.date));
  const running = tasks.some((t) => t.state === 'IN PROGRESS' && !t.staleRunning);

  return {
    employee: {
      id: user.id,
      fullName: user.full_name,
      role: user.role || '',
      staffId: user.staff_id || '',
      initials: user.initials || initialsOf(user.full_name),
    },
    running,
    staleRunning: tasks.filter((t) => t.staleRunning).length,
    performance: { score, grade: gradeFor(score, hasActivity), parts },
    summary: {
      totalClients: clients.size,
      totalTasks: total,
      ...counts,
      completedPct: pct(counts.completed, total),
      processingPct: pct(counts.processing, total),
      onHoldPct: pct(counts.onHold, total),
      pendingPct: pct(counts.pending, total),
      rejectedPct: pct(counts.rejected, total),
      onTime,
      late,
      overdue: tasks.filter((t) => groupOf(t.state) !== 'completed' && t.due && t.due < today).length,
    },
    workingHours: {
      totalSecs: workedSecs,
      availableSecs,
      idleSecs: Math.max(0, availableSecs - workedSecs),
      total: fmtSecs(workedSecs),
      productive: fmtSecs(workedSecs),
      available: fmtSecs(availableSecs),
      idle: fmtSecs(Math.max(0, availableSecs - workedSecs)),
      workingDays: workDays.length,
      activeDays,
      dayHours: WORK_DAY_SECS / 3600,
      avgDaily: fmtSecs(activeDays ? workedSecs / activeDays : 0),
      avgTask: fmtSecs(counts.completed ? workedSecs / counts.completed : 0),
      productivityPct,
      efficiencyPct: values.onTime ?? 0,
    },
    managerReview: { ...review, reviewed, approvalRatePct: values.approval ?? 0 },
    dayPlanner: {
      workingDays: workDays.length,
      submittedDays,
      missedDays: Math.max(0, workDays.length - submittedDays),
      morningSubmittedCount: morning,
      eveningSubmittedCount: evening,
      consistencyPct: values.planner ?? 0,
      days: plannerDays,
    },
    trend: [...perDay.entries()].map(([date, d]) => ({
      date,
      workedSecs: d.secs,
      worked: fmtSecs(d.secs),
      completed: d.completed,
      started: d.started,
      dayPerformancePct: Math.min(100, pct(d.secs, WORK_DAY_SECS)),
    })),
    clients: clientList,
    timeline: timeline.slice(0, 80),
  };
}

function overviewRow(p) {
  return {
    ...p.employee,
    running: p.running,
    staleRunning: p.staleRunning,
    performancePct: p.performance.score,
    performanceGrade: p.performance.grade,
    totalTasks: p.summary.totalTasks,
    totalClients: p.summary.totalClients,
    completed: p.summary.completed,
    processing: p.summary.processing,
    onHold: p.summary.onHold,
    pending: p.summary.pending,
    rejected: p.summary.rejected,
    overdue: p.summary.overdue,
    completedPct: p.summary.completedPct,
    processingPct: p.summary.processingPct,
    onHoldPct: p.summary.onHoldPct,
    pendingPct: p.summary.pendingPct,
    rejectedPct: p.summary.rejectedPct,
    workingSecs: p.workingHours.totalSecs,
    workingHours: p.workingHours.total,
    productivityPct: p.workingHours.productivityPct,
    onTimePct: p.workingHours.efficiencyPct,
    approvalRatePct: p.managerReview.approvalRatePct,
    plannerPct: p.dayPlanner.consistencyPct,
  };
}

router.get('/performance/overview', async (req, res) => {
  try {
    const range = perfRange(req.query);
    const people = await buildPerformance(range);
    const employees = people.map(overviewRow);
    const sum = (k) => employees.reduce((s, e) => s + (Number(e[k]) || 0), 0);
    const activeOnes = employees.filter((e) => e.totalTasks > 0 || e.workingSecs > 0);
    return res.json({
      success: true,
      data: {
        range: { from: range.fromDay, to: range.toDay, workingDays: range.workDays.length },
        weights: SCORE_WEIGHTS,
        team: {
          employees: employees.length,
          activeEmployees: activeOnes.length,
          runningNow: employees.filter((e) => e.running).length,
          totalTasks: sum('totalTasks'),
          completed: sum('completed'),
          overdue: sum('overdue'),
          workingSecs: sum('workingSecs'),
          workingHours: fmtSecs(sum('workingSecs')),
          avgScore: activeOnes.length
            ? Math.round(activeOnes.reduce((s, e) => s + e.performancePct, 0) / activeOnes.length) : 0,
        },
        employees,
      },
    });
  } catch (err) {
    console.error('GET /workspace-tasks/performance/overview ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

router.get('/performance/detail', async (req, res) => {
  const name = String(req.query.employeeName || req.query.employee || '').trim();
  if (!name) return res.status(400).json({ success: false, message: 'employeeName is required' });
  try {
    const range = perfRange(req.query);
    const people = await buildPerformance(range);
    const p = people.find((x) => personKey(x.employee.fullName) === personKey(name));
    if (!p) return res.status(404).json({ success: false, message: `No employee named ${name}` });
    return res.json({
      success: true,
      data: { ...p, range: { from: range.fromDay, to: range.toDay, workingDays: range.workDays.length }, weights: SCORE_WEIGHTS },
    });
  } catch (err) {
    console.error('GET /workspace-tasks/performance/detail ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ═════════════════════════════════════════════════════════════════════════════
// Page / Ads Handler — "Add Additional Task" from Employee Workspace
//
//   GET  /additional-task/options?employee=   → { allowed, clients: [{ name, deliverables, card_date }] }
//   POST /additional-task  { employee, client, deliverable, count, description }
//
// No date is typed. The task joins the client's CURRENT card — the deadline
// from Tasks Assign (nearest today or later, otherwise the latest one) — and
// shows in that card's "Additional Tasks" tab. It never creates its own card.
// ═════════════════════════════════════════════════════════════════════════════
const COMMON_DELIVERABLES = [
  'Poster', 'Reel', 'Carousel', 'Story', 'Video', 'Meta Ads', 'Google Ads',
  'Instagram Post', 'Facebook Post', 'YouTube Video', 'Landing Page', 'Blog', 'Report',
];

// The card an additional task joins = the client's CURRENT card:
// nearest deadline today or later, otherwise the latest one (from Tasks Assign).
function pickCardDate(dates) {
  const today = appDay();
  const list = [...new Set(dates.filter(Boolean))].sort();
  return list.find((d) => d >= today) || list[list.length - 1] || '';
}

/** Page / Ads Handler = role says so, or named as page / ads handler on any assignment. */
async function handlerRoleOf(employee) {
  const [[u]] = await db.query(
    'SELECT id, full_name, role FROM employee_users WHERE LOWER(TRIM(full_name)) = LOWER(TRIM(?)) LIMIT 1',
    [employee],
  );
  if (!u) return { user: null, role: null };
  const text = norm(u.role);
  if (text.includes('ads')) return { user: u, role: 'Ads Handler' };
  if (text.includes('page')) return { user: u, role: 'Page Handler' };
  const [rows] = await db.query(
    `SELECT page_handling, ads_handling FROM task_assignments
     WHERE is_assigned = 1 AND (COALESCE(page_handling, '') <> '' OR COALESCE(ads_handling, '') <> '')`,
  );
  for (const a of rows) {
    if (namesEmployee(a.page_handling, u.full_name)) return { user: u, role: 'Page Handler' };
    if (namesEmployee(a.ads_handling, u.full_name)) return { user: u, role: 'Ads Handler' };
  }
  return { user: u, role: null };
}

router.get('/additional-task/options', async (req, res) => {
  const employee = employeeFrom(req);
  if (!employee) return res.status(400).json({ success: false, message: 'employee is required' });
  try {
    const { role } = await handlerRoleOf(employee);
    const [clients] = await db.query(
      'SELECT company_name FROM clients WHERE is_active = 1 ORDER BY company_name',
    );
    const [assignments] = await db.query('SELECT * FROM task_assignments WHERE is_assigned = 1');
    const byClient = new Map();
    const cardDates = new Map();
    for (const a of assignments) {
      const k = norm(a.client_name);
      if (!byClient.has(k)) byClient.set(k, new Set());
      if (!cardDates.has(k)) cardDates.set(k, []);
      cardDates.get(k).push(deadlineOf(a));
      for (const r of ROLES) for (const t of parseTasks(a[r.tasks])) if (t.name) byClient.get(k).add(t.name);
    }
    const active = await activeClientSet();
    const seen = new Set();
    const list = [];
    for (const c of clients) {
      const name = String(c.company_name || '').trim();
      if (!name || seen.has(norm(name)) || !active.has(norm(name))) continue;
      seen.add(norm(name));
      const own = [...(byClient.get(norm(name)) || [])];
      const all = [...own];
      for (const d of COMMON_DELIVERABLES) if (!all.some((x) => norm(x) === norm(d))) all.push(d);
      list.push({
        name,
        deliverables: all,
        assigned: own,
        card_date: pickCardDate(cardDates.get(norm(name)) || []),
      });
    }
    return res.json({ success: true, allowed: Boolean(role), role, clients: list });
  } catch (err) {
    console.error('GET /workspace-tasks/additional-task/options ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

router.post('/additional-task', async (req, res) => {
  const employee = employeeFrom(req);
  const client = String(req.body?.client || '').trim();
  const deliverable = String(req.body?.deliverable || '').trim().replace(/\s+/g, ' ');
  const count = Math.min(Math.max(parseInt(req.body?.count, 10) || 1, 1), 50);
  const description = String(req.body?.description || '').trim();

  if (!employee) return res.status(400).json({ success: false, message: 'employee is required' });
  if (!client) return res.status(400).json({ success: false, message: 'Choose a client' });
  if (!deliverable) return res.status(400).json({ success: false, message: 'Enter the deliverable' });
  if (deliverable.length > 120) return res.status(400).json({ success: false, message: 'Deliverable name is too long' });

  const connection = await db.getConnection();
  try {
    const { user, role } = await handlerRoleOf(employee);
    if (!user) return res.status(404).json({ success: false, message: 'Employee not found' });
    if (!role) {
      return res.status(403).json({ success: false, message: 'Only Page Handlers and Ads Handlers can add additional tasks here' });
    }
    const [[activeClient]] = await connection.query(
      'SELECT company_name FROM clients WHERE is_active = 1 AND LOWER(TRIM(company_name)) = LOWER(TRIM(?)) LIMIT 1',
      [client],
    );
    if (!activeClient || !(await activeClientSet()).has(norm(activeClient.company_name))) {
      return res.status(400).json({ success: false, message: `${client} is not an active client` });
    }
    const clientName = activeClient.company_name;

    // The card date comes from Tasks Assign (the client's current card).
    const [asg] = await connection.query(
      `SELECT deadline, maintenance_date FROM task_assignments
       WHERE is_assigned = 1 AND LOWER(TRIM(client_name)) = LOWER(TRIM(?))`,
      [clientName],
    );
    const date = pickCardDate(asg.map(deadlineOf));
    if (!date) {
      return res.status(400).json({
        success: false,
        message: `${clientName} has no assigned card yet. Assign it in Tasks Assign first.`,
      });
    }

    await connection.beginTransaction();
    // Same client + deliverable + card date → add rows to that list.
    const [[existing]] = await connection.query(
      `SELECT id, no_of_rows FROM task_list
       WHERE additional_task_id IS NOT NULL AND task_assignment_id IS NULL
         AND employee_id = ? AND LOWER(TRIM(client_name)) = LOWER(TRIM(?))
         AND LOWER(TRIM(deliverables)) = LOWER(TRIM(?)) AND DATE(submission_date) = ?
       ORDER BY id DESC LIMIT 1 FOR UPDATE`,
      [user.id, clientName, deliverable, date],
    );
    let listId;
    let startNo = 1;
    if (existing) {
      listId = existing.id;
      const [[mx]] = await connection.query(
        'SELECT COALESCE(MAX(s_no), 0) AS m FROM time_tracking_task_items WHERE task_list_id = ? AND parent_item_id IS NULL',
        [listId],
      );
      startNo = Number(mx.m) + 1;
      await connection.query('UPDATE task_list SET no_of_rows = ? WHERE id = ?', [startNo - 1 + count, listId]);
    } else {
      const [ins] = await connection.query(
        `INSERT INTO task_list
           (client_name, employee_id, employee_name, deliverables, submission_date, no_of_rows)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [clientName, user.id, user.full_name, deliverable, date, count],
      );
      listId = ins.insertId;
      await connection.query('UPDATE task_list SET additional_task_id = ? WHERE id = ?', [listId, listId]);
    }
    for (let i = 0; i < count; i += 1) {
      await connection.query(
        `INSERT INTO time_tracking_task_items
           (task_list_id, s_no, sub_no, submit_date, task_description, duration_secs,
            comment, performance, status, cc_assigned_by_name, cc_assigned_at)
         VALUES (?, ?, 0, ?, ?, 0, '', 'N/A', 'IDLE', ?, NOW())`,
        [listId, startNo + i, date, description || deliverable, user.full_name],
      );
    }
    await connection.commit();

    emit(req, { type: 'additional_task_added', employee: user.full_name, client: clientName });
    return res.status(201).json({
      success: true,
      message: `${count} ${deliverable} row${count === 1 ? '' : 's'} added for ${clientName}`,
      data: {
        task_list_id: listId,
        client: clientName,
        deliverable,
        due_date: date,
        rows: count,
        role,
        section: 'Additional Tasks',
      },
    });
  } catch (err) {
    try { await connection.rollback(); } catch (_) { /* ignore */ }
    console.error('POST /workspace-tasks/additional-task ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  } finally {
    connection.release();
  }
});

// Edit / add rows on an additional task the employee added themselves.
//   PUT  /additional-task/:listId        { employee, deliverable?, date?, description? }
//   POST /additional-task/:listId/rows   { employee, count, description? }
async function ownAdditionalList(connection, listId, employee) {
  const [[list]] = await connection.query(
    `SELECT id, client_name, deliverables, submission_date, no_of_rows, employee_id, employee_name
     FROM task_list WHERE id = ? AND additional_task_id IS NOT NULL FOR UPDATE`,
    [listId],
  );
  if (!list) return { error: [404, 'Additional task not found'] };
  if (personKey(list.employee_name) !== personKey(employee)) {
    return { error: [403, 'This additional task belongs to someone else'] };
  }
  const [rows] = await connection.query(
    'SELECT id, s_no, status, task_description, cc_assigned_by_name FROM time_tracking_task_items WHERE task_list_id = ?',
    [listId],
  );
  if (rows.length && !rows.every((r) => personKey(r.cc_assigned_by_name) === personKey(employee))) {
    return { error: [403, 'Only additional tasks you added yourself can be edited here'] };
  }
  return { list, rows };
}

router.put('/additional-task/:listId', async (req, res) => {
  const employee = employeeFrom(req);
  const listId = Number(req.params.listId);
  if (!employee || !listId) return res.status(400).json({ success: false, message: 'employee and task are required' });
  const deliverable = req.body?.deliverable == null ? null : String(req.body.deliverable).trim().replace(/\s+/g, ' ');
  const date = req.body?.date == null ? null : dateKey(req.body.date);
  const description = req.body?.description == null ? null : String(req.body.description).trim();
  if (deliverable !== null && !deliverable) return res.status(400).json({ success: false, message: 'Enter the deliverable name' });
  if (deliverable && deliverable.length > 120) return res.status(400).json({ success: false, message: 'Deliverable name is too long' });
  if (date !== null && !/^\d{4}-\d{2}-\d{2}$/.test(date)) return res.status(400).json({ success: false, message: 'Choose a valid date' });

  const connection = await db.getConnection();
  try {
    await connection.beginTransaction();
    const own = await ownAdditionalList(connection, listId, employee);
    if (own.error) {
      await connection.rollback();
      return res.status(own.error[0]).json({ success: false, message: own.error[1] });
    }
    const { list, rows } = own;
    const oldDate = dateKey(list.submission_date);
    if (date && date !== oldDate && date < appDay()) {
      await connection.rollback();
      return res.status(400).json({ success: false, message: 'The new date cannot be in the past' });
    }
    const newName = deliverable || list.deliverables;
    const newDate = date || oldDate;
    await connection.query(
      'UPDATE task_list SET deliverables = ?, submission_date = ? WHERE id = ?',
      [newName, newDate, listId],
    );
    if (newDate !== oldDate) {
      await connection.query('UPDATE time_tracking_task_items SET submit_date = ? WHERE task_list_id = ?', [newDate, listId]);
    }
    // Details: rows not started yet (and rows still showing the old name).
    if (description !== null) {
      const ids = rows.filter((r) => upper(r.status || 'IDLE') === 'IDLE').map((r) => r.id);
      if (ids.length) {
        await connection.query(
          'UPDATE time_tracking_task_items SET task_description = ? WHERE id IN (?)',
          [description || newName, ids],
        );
      }
    } else if (newName !== list.deliverables) {
      await connection.query(
        `UPDATE time_tracking_task_items SET task_description = ?
         WHERE task_list_id = ? AND LOWER(TRIM(task_description)) = LOWER(TRIM(?))`,
        [newName, listId, list.deliverables],
      );
    }
    await connection.commit();
    emit(req, { type: 'additional_task_edited', employee, client: list.client_name });
    return res.json({
      success: true,
      message: 'Additional task updated',
      data: { task_list_id: listId, client: list.client_name, deliverable: newName, due_date: newDate, section: 'Additional Tasks' },
    });
  } catch (err) {
    try { await connection.rollback(); } catch (_) { /* ignore */ }
    console.error('PUT /workspace-tasks/additional-task ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  } finally {
    connection.release();
  }
});

router.post('/additional-task/:listId/rows', async (req, res) => {
  const employee = employeeFrom(req);
  const listId = Number(req.params.listId);
  const count = Math.min(Math.max(parseInt(req.body?.count, 10) || 1, 1), 50);
  const description = String(req.body?.description || '').trim();
  if (!employee || !listId) return res.status(400).json({ success: false, message: 'employee and task are required' });

  const connection = await db.getConnection();
  try {
    await connection.beginTransaction();
    const own = await ownAdditionalList(connection, listId, employee);
    if (own.error) {
      await connection.rollback();
      return res.status(own.error[0]).json({ success: false, message: own.error[1] });
    }
    const { list, rows } = own;
    const start = rows.reduce((m, r) => Math.max(m, Number(r.s_no) || 0), 0) + 1;
    const due = dateKey(list.submission_date) || appDay();
    for (let i = 0; i < count; i += 1) {
      await connection.query(
        `INSERT INTO time_tracking_task_items
           (task_list_id, s_no, sub_no, submit_date, task_description, duration_secs,
            comment, performance, status, cc_assigned_by_name, cc_assigned_at)
         VALUES (?, ?, 0, ?, ?, 0, '', 'N/A', 'IDLE', ?, NOW())`,
        [listId, start + i, due, description || list.deliverables, list.employee_name],
      );
    }
    await connection.query('UPDATE task_list SET no_of_rows = ? WHERE id = ?', [start - 1 + count, listId]);
    await connection.commit();
    emit(req, { type: 'additional_task_rows', employee, client: list.client_name });
    return res.status(201).json({
      success: true,
      message: `${count} row${count === 1 ? '' : 's'} added to ${list.deliverables}`,
      data: { task_list_id: listId, rows: start - 1 + count },
    });
  } catch (err) {
    try { await connection.rollback(); } catch (_) { /* ignore */ }
    console.error('POST /workspace-tasks/additional-task/rows ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  } finally {
    connection.release();
  }
});

// ═════════════════════════════════════════════════════════════════════════════
// Content Calendar rows for the MAIN ADMIN and for the Page / Ads Handler named
// on that client in Tasks Assign (the employee's job role does not matter).
//   GET /admin/content-calendar/:client?employee=
// ═════════════════════════════════════════════════════════════════════════════
router.get('/admin/content-calendar/:client', async (req, res) => {
  try {
    const client = String(req.params.client || '').trim();
    const emp = String(req.query.employee || '').trim();
    const userType = String(req.user?.userType || req.user?.user_type || '').toLowerCase();
    const isAdmin = userType === 'admin' || (emp && await isAdminUser(emp));
    const isHandler = emp && (await reviewerAssignmentIds(emp, client)).length > 0;
    if (!isAdmin && !isHandler) {
      return res.status(403).json({
        success: false,
        message: 'Only the Page / Ads Handler of this client can open its Content Calendar',
      });
    }
    const holdCols = Array.from({ length: 10 }, (_, i) =>
      `tti.hold_time_${i + 1}, tti.restart_time_${i + 1}`).join(', ');
    const [rows] = await db.query(
      `SELECT cc.*,
              (COALESCE(tti.content_calendar_assigned, 0) = 1 OR cc.cc_handoff_at IS NOT NULL
               OR COALESCE(cc.is_emergency, 0) = 1) AS content_calendar_assigned,
              cc.assigned_to_name AS cc_assigned_to_name,
              tti.status AS task_status, tti.review_status AS review_status,
              tti.duration_secs AS task_duration_secs, tti.start_time AS task_start_time,
              tti.complete_time AS task_complete_time, tti.performance AS task_performance,
              tti.comment AS task_comment, tti.employee_notes AS task_employee_notes,
              tl.employee_name AS task_employee_name,
              mr.manager_action AS task_review_action, mr.manager_comment AS task_review_comment,
              COALESCE(ta.deadline, ta.maintenance_date) AS source_deadline, ${holdCols}
       FROM content_calendar cc
       LEFT JOIN time_tracking_task_items tti ON tti.id = cc.task_item_id
       LEFT JOIN task_list tl ON tl.id = tti.task_list_id
       LEFT JOIN manager_review mr ON mr.tracking_item_id = tti.id
       LEFT JOIN task_assignments ta ON ta.id = cc.source_assignment_id
       WHERE LOWER(TRIM(cc.client_name)) = LOWER(TRIM(?))
         AND (cc.source_assignment_id IS NULL OR cc.source_active = 1)
       ORDER BY cc.deliverable, cc.source_assignment_id, cc.source_task_index,
                cc.source_row_number, cc.id`,
      [client],
    );
    const ids = [...new Set(rows.map((r) => r.source_assignment_id).filter(Boolean))];
    const asg = new Map();
    if (ids.length) {
      const [a] = await db.query('SELECT * FROM task_assignments WHERE id IN (?)', [ids]);
      a.forEach((x) => asg.set(Number(x.id), x));
    }
    for (const r of rows) {
      if (r.s_no == null) r.s_no = r.source_row_number;
      r.submit_date = dateKey(r.submit_date);
      if (r.publish_date) r.publish_date = dateKey(r.publish_date);
      r.source_deadline = dateKey(r.source_deadline);
      const a = asg.get(Number(r.source_assignment_id));
      const role = ROLES.find((x) => x.key === r.source_role);
      if (a && role) {
        r.allocated_employee = splitPeople(a[role.emp])[0] || '';
        r.allocated_role = role.label;
      }
    }
    return res.json({ success: true, data: rows });
  } catch (err) {
    console.error('GET /workspace-tasks/admin/content-calendar ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;