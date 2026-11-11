'use strict';
// routes/techProjects.js — Tech Projects (Tech Workspace + admin "Tech Projects")
//
// Mount in server.js (next to the other routes):
//   app.use('/api/tech-projects', require('./routes/techProjects'));
//
// Concept
//   Project  → members (picked persons, role comes from their profile) + ONE in-charge.
//   Task     → one row of daily work in a project, added by the person, the
//              in-charge or the admin. Every task keeps WHO added it, WHEN it was
//              started / completed / reviewed and WHO reviewed / approved it.
//   Flow     ADDED → IN PROGRESS ⇄ ON HOLD → IN REVIEW → APPROVED
//                                              └→ CORRECTION → (correction row) → … → APPROVED
//   Correction = its own row under the task (round 1, 2, 3) with a tag, its own
//              start / completed / review dates and its own reviewer.
//   Review   in-charge or admin (the in-charge's own tasks: admin only). Nobody
//              reviews their own task. The reviewer's name is stored.
//   History  every step is written to tech_task_history.
//
// Links: starting a task adds it to today's Day Planner ("[Tech Task #id]"),
//        GET /live and runningFor() feed Live Tracking / the top bar.
const express = require('express');
const router = express.Router();
const db = require('../config/db');
const { authenticateToken } = require('./auth');

router.use(authenticateToken);

const OPEN = ['ADDED', 'IN PROGRESS', 'ON HOLD', 'IN REVIEW', 'CORRECTION'];
const OPEN_CORRECTION = ['ADDED', 'IN PROGRESS', 'ON HOLD', 'IN REVIEW'];
const TAGS = ['Feature', 'Bug', 'Security', 'Design', 'Testing', 'Deployment', 'Other'];
const CORRECTION_TAGS = ['Bug', 'Design change', 'Client change', 'Security fix', 'Performance', 'Other'];
const PROJECT_STATUSES = ['PLANNING', 'ACTIVE', 'ON HOLD', 'COMPLETED'];

const norm = (v) => String(v ?? '').trim().replace(/\s+/g, ' ').toLowerCase();
const str = (v) => String(v ?? '').trim();
const isDay = (v) => /^\d{4}-\d{2}-\d{2}$/.test(String(v || ''));

// ── schema ───────────────────────────────────────────────────────────────────
let schemaReady = null;
function ensureSchema() {
  if (!schemaReady) {
    schemaReady = (async () => {
      await db.query(`CREATE TABLE IF NOT EXISTS tech_projects (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        client_name VARCHAR(255) NULL,
        description TEXT NULL,
        start_date DATE NULL,
        target_date DATE NULL,
        status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
        incharge_id INT NULL,
        incharge_name VARCHAR(255) NULL,
        created_by VARCHAR(255) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
      )`);
      await db.query(`CREATE TABLE IF NOT EXISTS tech_project_members (
        id INT AUTO_INCREMENT PRIMARY KEY,
        project_id INT NOT NULL,
        employee_id INT NOT NULL,
        employee_name VARCHAR(255) NOT NULL,
        role_label VARCHAR(120) NULL,
        is_incharge TINYINT NOT NULL DEFAULT 0,
        added_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uq_project_member (project_id, employee_id),
        KEY idx_member_name (employee_name)
      )`);
      await db.query(`CREATE TABLE IF NOT EXISTS tech_tasks (
        id INT AUTO_INCREMENT PRIMARY KEY,
        project_id INT NOT NULL,
        kind VARCHAR(12) NOT NULL DEFAULT 'TASK',
        parent_task_id INT NULL,
        round_no INT NOT NULL DEFAULT 0,
        correction_tag VARCHAR(40) NULL,
        task_date DATE NOT NULL,
        title VARCHAR(255) NOT NULL,
        details TEXT NULL,
        tag VARCHAR(40) NULL,
        assigned_to_id INT NULL,
        assigned_to_name VARCHAR(255) NOT NULL,
        added_by_name VARCHAR(255) NULL,
        added_by_role VARCHAR(40) NULL,
        status VARCHAR(20) NOT NULL DEFAULT 'ADDED',
        first_start_at DATETIME NULL,
        completed_at DATETIME NULL,
        reviewed_at DATETIME NULL,
        reviewed_by_name VARCHAR(255) NULL,
        review_comment TEXT NULL,
        review_result VARCHAR(20) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        KEY idx_task_project_date (project_id, task_date),
        KEY idx_task_assignee (assigned_to_name),
        KEY idx_task_parent (parent_task_id)
      )`);
      await db.query(`CREATE TABLE IF NOT EXISTS tech_task_sessions (
        id INT AUTO_INCREMENT PRIMARY KEY,
        task_id INT NOT NULL,
        started_at DATETIME NOT NULL,
        ended_at DATETIME NULL,
        end_reason VARCHAR(255) NULL,
        KEY idx_session_task (task_id)
      )`);
      await db.query(`CREATE TABLE IF NOT EXISTS tech_task_history (
        id INT AUTO_INCREMENT PRIMARY KEY,
        project_id INT NOT NULL,
        task_id INT NULL,
        action VARCHAR(40) NOT NULL,
        actor_name VARCHAR(255) NULL,
        note TEXT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        KEY idx_hist_project (project_id),
        KEY idx_hist_task (task_id)
      )`);
    })().catch((err) => {
      schemaReady = null;
      throw err;
    });
  }
  return schemaReady;
}

router.use(async (req, res, next) => {
  try {
    await ensureSchema();
    next();
  } catch (err) {
    console.error('Tech projects schema failed:', err.message);
    res.status(500).json({ success: false, message: `Database setup failed: ${err.message}` });
  }
});

// ── helpers ──────────────────────────────────────────────────────────────────
const emit = (req, payload) => {
  const io = req.app.get('io');
  io?.emit('tech_updated', payload);
  io?.emit('task_updated', { type: 'TECH', ...payload });
};

function actor(req) {
  return str(req.user?.fullName || req.user?.full_name || req.query?.employee || req.body?.employee);
}

async function isAdmin(req, name) {
  const type = str(req.user?.userType || req.user?.user_type).toLowerCase();
  if (type === 'admin') return true;
  if (!name) return false;
  const [rows] = await db.query(
    `SELECT id FROM employee_users
     WHERE LOWER(TRIM(full_name)) = LOWER(TRIM(?))
       AND (LOWER(user_type) = 'admin' OR is_main_admin = 1) LIMIT 1`,
    [name],
  ).catch(() => [[]]);
  return rows.length > 0;
}

async function accessFor(req, projectId) {
  const me = actor(req);
  const admin = await isAdmin(req, me);
  const [[member]] = await db.query(
    `SELECT * FROM tech_project_members
     WHERE project_id = ? AND LOWER(TRIM(employee_name)) = LOWER(TRIM(?)) LIMIT 1`,
    [projectId, me],
  );
  return { me, admin, member: member || null, incharge: Boolean(member && Number(member.is_incharge) === 1) };
}

const PROJECT_SQL = `SELECT id, name, client_name, description,
  DATE_FORMAT(start_date, '%Y-%m-%d') AS start_date,
  DATE_FORMAT(target_date, '%Y-%m-%d') AS target_date,
  status, incharge_id, incharge_name, created_by FROM tech_projects`;

const TASK_SQL = `SELECT t.id, t.project_id, p.name AS project_name, p.incharge_name,
  t.kind, t.parent_task_id, t.round_no, t.correction_tag,
  DATE_FORMAT(t.task_date, '%Y-%m-%d') AS task_date,
  t.title, t.details, t.tag, t.assigned_to_id, t.assigned_to_name,
  t.added_by_name, t.added_by_role, t.status,
  t.first_start_at, t.completed_at, t.reviewed_at, t.reviewed_by_name,
  t.review_comment, t.review_result, t.created_at
  FROM tech_tasks t JOIN tech_projects p ON p.id = t.project_id`;

async function history(projectId, taskId, action, who, note = '') {
  try {
    await db.query(
      'INSERT INTO tech_task_history (project_id, task_id, action, actor_name, note) VALUES (?, ?, ?, ?, ?)',
      [projectId, taskId ?? null, action, who || null, String(note || '').slice(0, 2000)],
    );
  } catch (err) {
    console.error('tech history failed:', err.message);
  }
}

async function notify(sender, recipient, preview, payload = {}) {
  if (!recipient || norm(recipient) === norm(sender)) return;
  try {
    const { createNotification } = require('./notifications');
    await createNotification({
      senderName: sender,
      recipientName: recipient,
      message: JSON.stringify({ preview, payload: { type: 'TECH_TASK', sender, recipient, ...payload } }),
    });
  } catch (err) {
    console.error('tech notify failed:', err.message);
  }
}

// ── Day Planner link ─────────────────────────────────────────────────────────
async function plannerAdd(task, status = 'PROCESSING') {
  try {
    const marker = `[Tech Task #${task.id}]`;
    const [existing] = await db.query(
      `SELECT id FROM day_plan_rows
       WHERE LOWER(TRIM(employee_name)) = LOWER(TRIM(?)) AND plan_date = CURDATE()
         AND today_plan LIKE ? LIMIT 1`,
      [task.assigned_to_name, `%${marker}%`],
    );
    if (existing.length) {
      await db.query('UPDATE day_plan_rows SET status = ? WHERE id = ?', [status, existing[0].id]);
      return 'updated';
    }
    const [[u]] = await db.query(
      'SELECT role FROM employee_users WHERE LOWER(TRIM(full_name)) = LOWER(TRIM(?)) LIMIT 1',
      [task.assigned_to_name],
    );
    await db.query(
      `INSERT INTO day_plan_rows
         (employee_name, employee_role, plan_date, report_type, client_name,
          maintenance_date, today_plan, status, remarks, is_submitted)
       VALUES (?, ?, CURDATE(), 'Morning', ?, NULL, ?, ?, 'Tech project task', 0)`,
      [task.assigned_to_name, u?.role || null, task.project_name,
        `${marker} ${task.kind === 'CORRECTION' ? 'Correction · ' : ''}${task.title}`, status],
    );
    return 'added';
  } catch (err) {
    console.warn('tech planner skipped:', err.message);
    return 'skipped';
  }
}

async function plannerStatus(task, status) {
  try {
    await db.query(
      `UPDATE day_plan_rows SET status = ?
       WHERE LOWER(TRIM(employee_name)) = LOWER(TRIM(?)) AND plan_date = CURDATE()
         AND today_plan LIKE ?`,
      [status, task.assigned_to_name, `%[Tech Task #${task.id}]%`],
    );
  } catch (err) {
    // planner table differs on this database — ignore
  }
}

// ── shaping ──────────────────────────────────────────────────────────────────
async function shapeTasks(rows, acc) {
  if (!rows.length) return [];
  const ids = rows.map((r) => r.id);
  const [sess] = await db.query(
    `SELECT task_id,
            SUM(TIMESTAMPDIFF(SECOND, started_at, COALESCE(ended_at, NOW()))) AS secs,
            MAX(CASE WHEN ended_at IS NULL THEN 1 ELSE 0 END) AS running
     FROM tech_task_sessions WHERE task_id IN (?) GROUP BY task_id`,
    [ids],
  );
  const byTask = new Map(sess.map((s) => [Number(s.task_id), s]));
  return rows.map((r) => {
    const s = byTask.get(Number(r.id));
    const mine = norm(r.assigned_to_name) === norm(acc.me);
    const assigneeIsIncharge = norm(r.assigned_to_name) === norm(r.incharge_name);
    const canReview = r.status === 'IN REVIEW' && !mine &&
      (acc.admin || (acc.incharge && !assigneeIsIncharge));
    return {
      ...r,
      secs: Number(s?.secs) || 0,
      running: Number(s?.running) === 1,
      can_work: mine,
      can_review: canReview,
      can_edit: r.kind === 'TASK' && r.status === 'ADDED' && (acc.admin || acc.incharge || mine),
    };
  });
}

async function withCorrections(rows, acc) {
  const tasks = await shapeTasks(rows, acc);
  if (!tasks.length) return tasks;
  const [cRows] = await db.query(
    `${TASK_SQL} WHERE t.kind = 'CORRECTION' AND t.parent_task_id IN (?) ORDER BY t.round_no ASC, t.id ASC`,
    [tasks.map((t) => t.id)],
  );
  const corrections = await shapeTasks(cRows, acc);
  const byParent = new Map();
  for (const c of corrections) {
    if (!byParent.has(Number(c.parent_task_id))) byParent.set(Number(c.parent_task_id), []);
    byParent.get(Number(c.parent_task_id)).push(c);
  }
  return tasks.map((t) => ({ ...t, corrections: byParent.get(Number(t.id)) || [] }));
}

async function projectCounts(ids) {
  const out = new Map(ids.map((id) => [Number(id), {
    total: 0, approved: 0, in_review: 0, in_progress: 0, on_hold: 0, added: 0, corrections_open: 0,
  }]));
  if (!ids.length) return out;
  const [rows] = await db.query(
    `SELECT project_id, kind, status, COUNT(*) AS n FROM tech_tasks
     WHERE project_id IN (?) GROUP BY project_id, kind, status`,
    [ids],
  );
  for (const r of rows) {
    const c = out.get(Number(r.project_id));
    if (!c) continue;
    const n = Number(r.n);
    if (r.kind === 'TASK') {
      c.total += n;
      if (r.status === 'APPROVED') c.approved += n;
      if (r.status === 'IN REVIEW') c.in_review += n;
      if (r.status === 'IN PROGRESS') c.in_progress += n;
      if (r.status === 'ON HOLD') c.on_hold += n;
      if (r.status === 'ADDED') c.added += n;
    } else if (OPEN_CORRECTION.includes(r.status)) {
      c.corrections_open += n;
    }
  }
  return out;
}

async function shapeProjects(projects) {
  if (!projects.length) return [];
  const ids = projects.map((p) => p.id);
  const [members] = await db.query(
    `SELECT project_id, employee_id, employee_name, role_label, is_incharge
     FROM tech_project_members WHERE project_id IN (?) ORDER BY is_incharge DESC, employee_name`,
    [ids],
  );
  const [working] = await db.query(
    `SELECT DISTINCT t.project_id, t.assigned_to_name
     FROM tech_task_sessions s JOIN tech_tasks t ON t.id = s.task_id
     WHERE s.ended_at IS NULL AND t.project_id IN (?)`,
    [ids],
  );
  const workingSet = new Set(working.map((w) => `${w.project_id}|${norm(w.assigned_to_name)}`));
  const counts = await projectCounts(ids);
  return projects.map((p) => {
    const c = counts.get(Number(p.id));
    return {
      ...p,
      members: members
        .filter((m) => Number(m.project_id) === Number(p.id))
        .map((m) => ({
          employee_id: m.employee_id,
          employee_name: m.employee_name,
          role_label: m.role_label || '',
          is_incharge: Number(m.is_incharge) === 1,
          working: workingSet.has(`${p.id}|${norm(m.employee_name)}`),
        })),
      counts: c,
      progress: c.total ? Math.round((c.approved * 100) / c.total) : 0,
    };
  });
}

async function needProject(req, res, id) {
  const [[project]] = await db.query(`${PROJECT_SQL} WHERE id = ?`, [id]);
  if (!project) {
    res.status(404).json({ success: false, message: 'Project not found' });
    return null;
  }
  const acc = await accessFor(req, project.id);
  if (!acc.admin && !acc.member) {
    res.status(403).json({ success: false, message: 'You are not a member of this project' });
    return null;
  }
  return { project, acc };
}

// ── people (team picker) ─────────────────────────────────────────────────────
router.get('/people', async (req, res) => {
  try {
    const [rows] = await db.query(
      `SELECT id, full_name, role FROM employee_users
       WHERE (is_active = 1 OR is_active IS NULL)
         AND LOWER(COALESCE(user_type, '')) <> 'admin'
       ORDER BY full_name`,
    );
    return res.json({
      success: true,
      data: rows.map((r) => ({ id: r.id, name: r.full_name, role: r.role || '' })),
    });
  } catch (err) {
    console.error('GET /tech-projects/people ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ── projects ─────────────────────────────────────────────────────────────────
router.get('/projects', async (req, res) => {
  try {
    const me = actor(req);
    const admin = await isAdmin(req, me);
    let rows;
    if (admin) {
      [rows] = await db.query(`${PROJECT_SQL} ORDER BY FIELD(status, 'ACTIVE', 'PLANNING', 'ON HOLD', 'COMPLETED'), id DESC`);
    } else {
      [rows] = await db.query(
        `${PROJECT_SQL}
         WHERE id IN (SELECT project_id FROM tech_project_members WHERE LOWER(TRIM(employee_name)) = LOWER(TRIM(?)))
         ORDER BY FIELD(status, 'ACTIVE', 'PLANNING', 'ON HOLD', 'COMPLETED'), id DESC`,
        [me],
      );
    }
    return res.json({ success: true, admin, data: await shapeProjects(rows) });
  } catch (err) {
    console.error('GET /tech-projects/projects ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

async function syncMembers(projectId, memberIds, inchargeId, who) {
  const ids = [...new Set(memberIds.map(Number).filter(Boolean))];
  const [people] = ids.length
    ? await db.query('SELECT id, full_name, role FROM employee_users WHERE id IN (?)', [ids])
    : [[]];
  const [existing] = await db.query(
    'SELECT employee_id, employee_name FROM tech_project_members WHERE project_id = ?',
    [projectId],
  );
  const have = new Map(existing.map((m) => [Number(m.employee_id), m.employee_name]));
  const keep = new Set(people.map((p) => Number(p.id)));

  for (const [empId, name] of have) {
    if (!keep.has(empId)) {
      await db.query('DELETE FROM tech_project_members WHERE project_id = ? AND employee_id = ?', [projectId, empId]);
      await history(projectId, null, 'MEMBER_REMOVED', who, name);
    }
  }
  for (const p of people) {
    await db.query(
      `INSERT INTO tech_project_members (project_id, employee_id, employee_name, role_label, is_incharge)
       VALUES (?, ?, ?, ?, 0)
       ON DUPLICATE KEY UPDATE employee_name = VALUES(employee_name), role_label = VALUES(role_label)`,
      [projectId, p.id, p.full_name, p.role || null],
    );
    if (!have.has(Number(p.id))) await history(projectId, null, 'MEMBER_ADDED', who, `${p.full_name}${p.role ? ` (${p.role})` : ''}`);
  }
  await db.query('UPDATE tech_project_members SET is_incharge = 0 WHERE project_id = ?', [projectId]);
  const lead = people.find((p) => Number(p.id) === Number(inchargeId));
  if (lead) {
    await db.query(
      'UPDATE tech_project_members SET is_incharge = 1 WHERE project_id = ? AND employee_id = ?',
      [projectId, lead.id],
    );
    await db.query('UPDATE tech_projects SET incharge_id = ?, incharge_name = ? WHERE id = ?', [lead.id, lead.full_name, projectId]);
  }
}

function projectBody(req) {
  const b = req.body || {};
  const status = str(b.status).toUpperCase();
  return {
    name: str(b.name),
    client_name: str(b.client_name) || null,
    description: str(b.description) || null,
    start_date: isDay(b.start_date) ? b.start_date : null,
    target_date: isDay(b.target_date) ? b.target_date : null,
    status: PROJECT_STATUSES.includes(status) ? status : 'ACTIVE',
    members: Array.isArray(b.members) ? b.members : [],
    incharge_id: Number(b.incharge_id) || null,
  };
}

router.post('/projects', async (req, res) => {
  const me = actor(req);
  try {
    if (!(await isAdmin(req, me))) return res.status(403).json({ success: false, message: 'Only admin can create projects' });
    const p = projectBody(req);
    if (!p.name) return res.status(400).json({ success: false, message: 'Enter the project name' });
    if (!p.members.length) return res.status(400).json({ success: false, message: 'Add at least one team member' });
    if (!p.incharge_id || !p.members.map(Number).includes(p.incharge_id)) {
      return res.status(400).json({ success: false, message: 'Choose the project in-charge from the team' });
    }
    const [ins] = await db.query(
      `INSERT INTO tech_projects (name, client_name, description, start_date, target_date, status, created_by)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [p.name, p.client_name, p.description, p.start_date, p.target_date, p.status, me],
    );
    await syncMembers(ins.insertId, p.members, p.incharge_id, me);
    await history(ins.insertId, null, 'PROJECT_CREATED', me, p.name);
    emit(req, { type: 'TECH_PROJECT', projectId: ins.insertId });
    return res.status(201).json({ success: true, message: 'Project created', data: { id: ins.insertId } });
  } catch (err) {
    console.error('POST /tech-projects/projects ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

router.put('/projects/:id', async (req, res) => {
  const me = actor(req);
  const id = Number(req.params.id);
  try {
    if (!(await isAdmin(req, me))) return res.status(403).json({ success: false, message: 'Only admin can edit projects' });
    const p = projectBody(req);
    if (!p.name) return res.status(400).json({ success: false, message: 'Enter the project name' });
    if (!p.members.length) return res.status(400).json({ success: false, message: 'Add at least one team member' });
    if (!p.incharge_id || !p.members.map(Number).includes(p.incharge_id)) {
      return res.status(400).json({ success: false, message: 'Choose the project in-charge from the team' });
    }
    const [r] = await db.query(
      `UPDATE tech_projects SET name = ?, client_name = ?, description = ?, start_date = ?, target_date = ?, status = ?
       WHERE id = ?`,
      [p.name, p.client_name, p.description, p.start_date, p.target_date, p.status, id],
    );
    if (!r.affectedRows) return res.status(404).json({ success: false, message: 'Project not found' });
    await syncMembers(id, p.members, p.incharge_id, me);
    await history(id, null, 'PROJECT_UPDATED', me, `${p.name} · ${p.status}`);
    emit(req, { type: 'TECH_PROJECT', projectId: id });
    return res.json({ success: true, message: 'Project updated' });
  } catch (err) {
    console.error('PUT /tech-projects/projects/:id ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

router.get('/projects/:id', async (req, res) => {
  try {
    const ctx = await needProject(req, res, Number(req.params.id));
    if (!ctx) return undefined;
    const [shaped] = await shapeProjects([ctx.project]);
    return res.json({
      success: true,
      data: {
        ...shaped,
        access: { me: ctx.acc.me, admin: ctx.acc.admin, incharge: ctx.acc.incharge, member: Boolean(ctx.acc.member) },
        tags: TAGS,
        correction_tags: CORRECTION_TAGS,
      },
    });
  } catch (err) {
    console.error('GET /tech-projects/projects/:id ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ── tasks ────────────────────────────────────────────────────────────────────
// GET /projects/:id/tasks?date=YYYY-MM-DD&scope=mine|all|open
router.get('/projects/:id/tasks', async (req, res) => {
  try {
    const ctx = await needProject(req, res, Number(req.params.id));
    if (!ctx) return undefined;
    const { acc } = ctx;
    const manager = acc.admin || acc.incharge;
    let scope = str(req.query.scope) || 'mine';
    if (!manager) scope = 'mine';
    const params = [ctx.project.id];
    let where = "WHERE t.project_id = ? AND t.kind = 'TASK'";
    if (scope === 'open') {
      where += ` AND t.status IN (${OPEN.map(() => '?').join(',')})`;
      params.push(...OPEN);
    } else if (isDay(req.query.date)) {
      where += ' AND t.task_date = ?';
      params.push(req.query.date);
    }
    if (scope === 'mine') {
      where += ' AND LOWER(TRIM(t.assigned_to_name)) = LOWER(TRIM(?))';
      params.push(acc.me);
    }
    const [rows] = await db.query(`${TASK_SQL} ${where} ORDER BY t.assigned_to_name, t.task_date DESC, t.id ASC`, params);
    return res.json({ success: true, data: await withCorrections(rows, acc) });
  } catch (err) {
    console.error('GET /tech-projects/projects/:id/tasks ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// GET /projects/:id/corrections?scope=mine|all  → open corrections of the project
router.get('/projects/:id/corrections', async (req, res) => {
  try {
    const ctx = await needProject(req, res, Number(req.params.id));
    if (!ctx) return undefined;
    const { acc } = ctx;
    const manager = acc.admin || acc.incharge;
    const scope = manager ? (str(req.query.scope) || 'all') : 'mine';
    const params = [ctx.project.id, ...OPEN_CORRECTION];
    let where = `WHERE t.project_id = ? AND t.kind = 'CORRECTION' AND t.status IN (${OPEN_CORRECTION.map(() => '?').join(',')})`;
    if (scope === 'mine') {
      where += ' AND LOWER(TRIM(t.assigned_to_name)) = LOWER(TRIM(?))';
      params.push(acc.me);
    }
    const [rows] = await db.query(`${TASK_SQL} ${where} ORDER BY t.id ASC`, params);
    const shaped = await shapeTasks(rows, acc);
    const parentIds = [...new Set(shaped.map((c) => c.parent_task_id).filter(Boolean))];
    const [parents] = parentIds.length
      ? await db.query('SELECT id, title FROM tech_tasks WHERE id IN (?)', [parentIds])
      : [[]];
    const titles = new Map(parents.map((p) => [Number(p.id), p.title]));
    return res.json({
      success: true,
      data: shaped.map((c) => ({ ...c, parent_title: titles.get(Number(c.parent_task_id)) || '' })),
    });
  } catch (err) {
    console.error('GET /tech-projects/projects/:id/corrections ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// POST /projects/:id/tasks { title, details, tag, task_date, assigned_to_id? }
router.post('/projects/:id/tasks', async (req, res) => {
  try {
    const ctx = await needProject(req, res, Number(req.params.id));
    if (!ctx) return undefined;
    const { acc, project } = ctx;
    const b = req.body || {};
    const title = str(b.title).slice(0, 250);
    if (!title) return res.status(400).json({ success: false, message: 'Enter the task' });
    if (project.status === 'COMPLETED') {
      return res.status(409).json({ success: false, message: 'This project is completed' });
    }
    const manager = acc.admin || acc.incharge;
    let assignee = acc.member;
    if (Number(b.assigned_to_id) && (!acc.member || Number(b.assigned_to_id) !== Number(acc.member.employee_id))) {
      if (!manager) return res.status(403).json({ success: false, message: 'Only the in-charge or admin can assign tasks to others' });
      const [[m]] = await db.query(
        'SELECT * FROM tech_project_members WHERE project_id = ? AND employee_id = ?',
        [project.id, Number(b.assigned_to_id)],
      );
      if (!m) return res.status(400).json({ success: false, message: 'That person is not in this project' });
      assignee = m;
    }
    if (!assignee) return res.status(400).json({ success: false, message: 'Choose who does this task' });
    const tag = TAGS.includes(str(b.tag)) ? str(b.tag) : 'Other';
    const date = isDay(b.task_date) ? b.task_date : null;
    const role = acc.admin ? 'Admin' : acc.incharge ? 'In-charge' : 'Member';
    const [ins] = await db.query(
      `INSERT INTO tech_tasks
         (project_id, kind, task_date, title, details, tag, assigned_to_id, assigned_to_name,
          added_by_name, added_by_role, status)
       VALUES (?, 'TASK', COALESCE(?, CURDATE()), ?, ?, ?, ?, ?, ?, ?, 'ADDED')`,
      [project.id, date, title, str(b.details) || null, tag, assignee.employee_id, assignee.employee_name, acc.me, role],
    );
    await history(project.id, ins.insertId, 'TASK_ADDED', acc.me,
      `${title} · ${tag} · for ${assignee.employee_name}${role === 'Member' ? '' : ` (added by ${role})`}`);
    if (norm(assignee.employee_name) !== norm(acc.me)) {
      await notify(acc.me, assignee.employee_name, `${acc.me} added a task for you in ${project.name}: ${title}`, { projectId: project.id, taskId: ins.insertId });
    }
    emit(req, { type: 'TECH_TASK', projectId: project.id, taskId: ins.insertId });
    return res.status(201).json({ success: true, message: 'Task added', data: { id: ins.insertId } });
  } catch (err) {
    console.error('POST /tech-projects/projects/:id/tasks ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

async function loadTask(id) {
  const [[t]] = await db.query(`${TASK_SQL} WHERE t.id = ?`, [id]);
  return t || null;
}

// PATCH /tasks/:id { title?, details?, tag?, task_date?, assigned_to_id? }  (only while ADDED)
router.patch('/tasks/:id', async (req, res) => {
  try {
    const task = await loadTask(Number(req.params.id));
    if (!task) return res.status(404).json({ success: false, message: 'Task not found' });
    const acc = await accessFor(req, task.project_id);
    const mine = norm(task.assigned_to_name) === norm(acc.me);
    if (!(acc.admin || acc.incharge || mine)) return res.status(403).json({ success: false, message: 'Not allowed' });
    if (task.kind !== 'TASK' || task.status !== 'ADDED') {
      return res.status(409).json({ success: false, message: 'Only a task that has not started can be edited' });
    }
    const b = req.body || {};
    const sets = [];
    const vals = [];
    if (b.title !== undefined && str(b.title)) { sets.push('title = ?'); vals.push(str(b.title).slice(0, 250)); }
    if (b.details !== undefined) { sets.push('details = ?'); vals.push(str(b.details) || null); }
    if (b.tag !== undefined && TAGS.includes(str(b.tag))) { sets.push('tag = ?'); vals.push(str(b.tag)); }
    if (b.task_date !== undefined && isDay(b.task_date)) { sets.push('task_date = ?'); vals.push(b.task_date); }
    if (Number(b.assigned_to_id) && (acc.admin || acc.incharge)) {
      const [[m]] = await db.query(
        'SELECT * FROM tech_project_members WHERE project_id = ? AND employee_id = ?',
        [task.project_id, Number(b.assigned_to_id)],
      );
      if (m) { sets.push('assigned_to_id = ?', 'assigned_to_name = ?'); vals.push(m.employee_id, m.employee_name); }
    }
    if (!sets.length) return res.status(400).json({ success: false, message: 'Nothing to update' });
    await db.query(`UPDATE tech_tasks SET ${sets.join(', ')} WHERE id = ?`, [...vals, task.id]);
    await history(task.project_id, task.id, 'TASK_EDITED', acc.me, task.title);
    emit(req, { type: 'TECH_TASK', projectId: task.project_id, taskId: task.id });
    return res.json({ success: true, message: 'Task updated' });
  } catch (err) {
    console.error('PATCH /tech-projects/tasks/:id ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ── timer actions ────────────────────────────────────────────────────────────
async function closeSessions(taskId, reason) {
  await db.query(
    'UPDATE tech_task_sessions SET ended_at = NOW(), end_reason = ? WHERE task_id = ? AND ended_at IS NULL',
    [String(reason || '').slice(0, 250), taskId],
  );
}

async function workAction(req, res, action) {
  try {
    const task = await loadTask(Number(req.params.id));
    if (!task) return res.status(404).json({ success: false, message: 'Task not found' });
    const acc = await accessFor(req, task.project_id);
    if (norm(task.assigned_to_name) !== norm(acc.me)) {
      return res.status(403).json({ success: false, message: 'Only the person this task is for can start, hold or complete it' });
    }
    const reason = str(req.body?.reason);

    if (action === 'start' || action === 'restart') {
      if (!['ADDED', 'ON HOLD'].includes(task.status)) {
        return res.status(409).json({ success: false, message: `This task is ${task.status.toLowerCase()} and cannot be started` });
      }
      const [others] = await db.query(
        `SELECT t.id, t.title FROM tech_task_sessions s JOIN tech_tasks t ON t.id = s.task_id
         WHERE s.ended_at IS NULL AND LOWER(TRIM(t.assigned_to_name)) = LOWER(TRIM(?)) AND t.id <> ?`,
        [acc.me, task.id],
      );
      if (others.length) {
        const autoReason = str(req.body?.auto_hold_reason);
        if (!autoReason) {
          return res.status(409).json({
            success: false,
            code: 'AUTO_HOLD_REASON_REQUIRED',
            message: 'Another task is running — it must be put on hold first',
            running: others.map((o) => ({ title: o.title })),
          });
        }
        for (const o of others) {
          await closeSessions(o.id, `Auto-hold: ${autoReason}`);
          await db.query("UPDATE tech_tasks SET status = 'ON HOLD' WHERE id = ?", [o.id]);
          const full = await loadTask(o.id);
          if (full) await plannerStatus(full, 'HOLD');
          await history(task.project_id, o.id, 'TASK_HELD', acc.me, `Auto-hold (another task started): ${autoReason}`);
        }
      }
      await db.query('INSERT INTO tech_task_sessions (task_id, started_at) VALUES (?, NOW())', [task.id]);
      await db.query(
        "UPDATE tech_tasks SET status = 'IN PROGRESS', first_start_at = COALESCE(first_start_at, NOW()) WHERE id = ?",
        [task.id],
      );
      await plannerAdd(task, 'PROCESSING');
      await history(task.project_id, task.id, action === 'start' ? 'TASK_STARTED' : 'TASK_RESTARTED', acc.me, task.title);
    } else if (action === 'hold') {
      if (task.status !== 'IN PROGRESS') return res.status(409).json({ success: false, message: 'Only a running task can be put on hold' });
      if (!reason) return res.status(400).json({ success: false, message: 'Enter the hold reason' });
      await closeSessions(task.id, reason);
      await db.query("UPDATE tech_tasks SET status = 'ON HOLD' WHERE id = ?", [task.id]);
      await plannerStatus(task, 'HOLD');
      await history(task.project_id, task.id, 'TASK_HELD', acc.me, reason);
    } else if (action === 'complete') {
      if (task.status !== 'IN PROGRESS') return res.status(409).json({ success: false, message: 'Start the task before completing it' });
      await closeSessions(task.id, 'completed');
      await db.query("UPDATE tech_tasks SET status = 'IN REVIEW', completed_at = NOW() WHERE id = ?", [task.id]);
      await plannerStatus(task, 'COMPLETED');
      await history(task.project_id, task.id, 'TASK_COMPLETED', acc.me, task.title);
      const [[project]] = await db.query('SELECT incharge_name FROM tech_projects WHERE id = ?', [task.project_id]);
      const reviewer = norm(project?.incharge_name) === norm(acc.me) ? null : project?.incharge_name;
      if (reviewer) {
        await notify(acc.me, reviewer, `${acc.me} completed "${task.title}" in ${task.project_name} — waiting for your review`, { projectId: task.project_id, taskId: task.id });
      }
    }
    emit(req, { type: 'TECH_TASK', projectId: task.project_id, taskId: task.id });
    const fresh = await loadTask(task.id);
    const [shaped] = await shapeTasks([fresh], acc);
    return res.json({ success: true, data: shaped });
  } catch (err) {
    console.error(`POST /tech-projects/tasks/:id/${action} ERROR:`, err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
}
for (const action of ['start', 'restart', 'hold', 'complete']) {
  router.post(`/tasks/:id/${action}`, (req, res) => workAction(req, res, action));
}

// POST /tasks/:id/planner — "Add to planner" without starting
router.post('/tasks/:id/planner', async (req, res) => {
  try {
    const task = await loadTask(Number(req.params.id));
    if (!task) return res.status(404).json({ success: false, message: 'Task not found' });
    const acc = await accessFor(req, task.project_id);
    if (norm(task.assigned_to_name) !== norm(acc.me)) {
      return res.status(403).json({ success: false, message: 'This task is not yours' });
    }
    const out = await plannerAdd(task, task.status === 'ON HOLD' ? 'HOLD' : 'PENDING');
    return res.json({ success: true, message: out === 'skipped' ? 'Could not reach the Day Planner' : 'Added to today’s Day Planner' });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ── review ───────────────────────────────────────────────────────────────────
// POST /tasks/:id/review { action: 'APPROVED' | 'CORRECTION', comment, tag }
router.post('/tasks/:id/review', async (req, res) => {
  try {
    const task = await loadTask(Number(req.params.id));
    if (!task) return res.status(404).json({ success: false, message: 'Task not found' });
    const acc = await accessFor(req, task.project_id);
    const mine = norm(task.assigned_to_name) === norm(acc.me);
    const assigneeIsIncharge = norm(task.assigned_to_name) === norm(task.incharge_name);
    const allowed = !mine && (acc.admin || (acc.incharge && !assigneeIsIncharge));
    if (!allowed) {
      return res.status(403).json({ success: false, message: assigneeIsIncharge
        ? 'The in-charge’s own work is reviewed by the admin'
        : 'Only the project in-charge or admin can review this task' });
    }
    if (task.status !== 'IN REVIEW') return res.status(409).json({ success: false, message: 'This task is not waiting for review' });

    const action = str(req.body?.action).toUpperCase();
    const comment = str(req.body?.comment);
    const parentId = task.kind === 'CORRECTION' ? task.parent_task_id : task.id;

    if (action === 'APPROVED') {
      await db.query(
        `UPDATE tech_tasks SET status = 'APPROVED', review_result = 'APPROVED', reviewed_at = NOW(),
                reviewed_by_name = ?, review_comment = ? WHERE id = ?`,
        [acc.me, comment || null, task.id],
      );
      await history(task.project_id, task.id, 'TASK_APPROVED', acc.me, comment || task.title);
      if (task.kind === 'CORRECTION') {
        const [[open]] = await db.query(
          `SELECT COUNT(*) AS n FROM tech_tasks WHERE parent_task_id = ? AND kind = 'CORRECTION'
             AND status IN (${OPEN_CORRECTION.map(() => '?').join(',')})`,
          [parentId, ...OPEN_CORRECTION],
        );
        if (!Number(open.n)) {
          await db.query(
            `UPDATE tech_tasks SET status = 'APPROVED', review_result = 'APPROVED', reviewed_at = NOW(),
                    reviewed_by_name = ? WHERE id = ?`,
            [acc.me, parentId],
          );
          await history(task.project_id, parentId, 'TASK_APPROVED', acc.me, 'All corrections approved');
        }
      }
      await notify(acc.me, task.assigned_to_name, `${acc.me} approved "${task.title}" in ${task.project_name}`, { projectId: task.project_id, taskId: task.id });
    } else if (action === 'CORRECTION') {
      const tag = CORRECTION_TAGS.includes(str(req.body?.tag)) ? str(req.body.tag) : 'Other';
      if (!comment) return res.status(400).json({ success: false, message: 'Write what must be corrected' });
      await db.query(
        `UPDATE tech_tasks SET status = 'CORRECTION', review_result = 'CORRECTION', reviewed_at = NOW(),
                reviewed_by_name = ?, review_comment = ? WHERE id = ?`,
        [acc.me, comment, task.id],
      );
      if (task.kind === 'CORRECTION') {
        await db.query("UPDATE tech_tasks SET status = 'CORRECTION' WHERE id = ? AND status <> 'APPROVED'", [parentId]);
      }
      const [[rounds]] = await db.query(
        "SELECT COUNT(*) AS n FROM tech_tasks WHERE parent_task_id = ? AND kind = 'CORRECTION'",
        [parentId],
      );
      const round = Number(rounds.n) + 1;
      const [[parent]] = await db.query('SELECT title FROM tech_tasks WHERE id = ?', [parentId]);
      const [ins] = await db.query(
        `INSERT INTO tech_tasks
           (project_id, kind, parent_task_id, round_no, correction_tag, task_date, title, details, tag,
            assigned_to_id, assigned_to_name, added_by_name, added_by_role, status)
         VALUES (?, 'CORRECTION', ?, ?, ?, CURDATE(), ?, ?, ?, ?, ?, ?, ?, 'ADDED')`,
        [task.project_id, parentId, round, tag, `Correction ${round}: ${parent?.title || task.title}`,
          comment, task.tag, task.assigned_to_id, task.assigned_to_name, acc.me,
          acc.admin ? 'Admin' : 'In-charge'],
      );
      await history(task.project_id, parentId, 'CORRECTION_RAISED', acc.me, `Round ${round} · ${tag}: ${comment}`);
      await notify(acc.me, task.assigned_to_name, `${acc.me} asked for a correction (${tag}) on "${parent?.title || task.title}" in ${task.project_name}`, { projectId: task.project_id, taskId: ins.insertId });
    } else {
      return res.status(400).json({ success: false, message: 'action must be APPROVED or CORRECTION' });
    }
    emit(req, { type: 'TECH_REVIEW', projectId: task.project_id, taskId: task.id });
    return res.json({ success: true, message: action === 'APPROVED' ? 'Approved' : 'Correction sent' });
  } catch (err) {
    console.error('POST /tech-projects/tasks/:id/review ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// GET /projects/:id/review → { pending, decided } (whole project; in-charge / admin)
router.get('/projects/:id/review', async (req, res) => {
  try {
    const ctx = await needProject(req, res, Number(req.params.id));
    if (!ctx) return undefined;
    const { acc } = ctx;
    if (!(acc.admin || acc.incharge)) {
      return res.json({ success: true, pending: [], decided: [], reviewer: false });
    }
    const [pend] = await db.query(`${TASK_SQL} WHERE t.project_id = ? AND t.status = 'IN REVIEW' ORDER BY t.completed_at ASC`, [ctx.project.id]);
    const [done] = await db.query(
      `${TASK_SQL} WHERE t.project_id = ? AND t.reviewed_at IS NOT NULL ORDER BY t.reviewed_at DESC LIMIT 60`,
      [ctx.project.id],
    );
    return res.json({
      success: true,
      reviewer: true,
      pending: await shapeTasks(pend, acc),
      decided: await shapeTasks(done, acc),
    });
  } catch (err) {
    console.error('GET /tech-projects/projects/:id/review ERROR:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ── history / live ───────────────────────────────────────────────────────────
router.get('/tasks/:id/history', async (req, res) => {
  try {
    const task = await loadTask(Number(req.params.id));
    if (!task) return res.status(404).json({ success: false, message: 'Task not found' });
    const acc = await accessFor(req, task.project_id);
    if (!acc.admin && !acc.member) return res.status(403).json({ success: false, message: 'Not allowed' });
    const [rows] = await db.query(
      `SELECT id, task_id, action, actor_name, note, created_at FROM tech_task_history
       WHERE task_id = ? OR task_id IN (SELECT id FROM tech_tasks WHERE parent_task_id = ?)
       ORDER BY id ASC`,
      [task.id, task.id],
    );
    return res.json({ success: true, data: rows });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

router.get('/projects/:id/history', async (req, res) => {
  try {
    const ctx = await needProject(req, res, Number(req.params.id));
    if (!ctx) return undefined;
    const [rows] = await db.query(
      `SELECT h.id, h.task_id, h.action, h.actor_name, h.note, h.created_at, t.title AS task_title
       FROM tech_task_history h LEFT JOIN tech_tasks t ON t.id = h.task_id
       WHERE h.project_id = ? ORDER BY h.id DESC LIMIT 300`,
      [ctx.project.id],
    );
    return res.json({ success: true, data: rows });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// Who is working / on hold right now in this project.
router.get('/projects/:id/live', async (req, res) => {
  try {
    const ctx = await needProject(req, res, Number(req.params.id));
    if (!ctx) return undefined;
    const [rows] = await db.query(
      `${TASK_SQL} WHERE t.project_id = ? AND t.status IN ('IN PROGRESS', 'ON HOLD')
       ORDER BY FIELD(t.status, 'IN PROGRESS', 'ON HOLD'), t.assigned_to_name`,
      [ctx.project.id],
    );
    return res.json({ success: true, data: await shapeTasks(rows, ctx.acc) });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// Items in the same shape as the Live Tracking / top-bar items of the client
// workspace, so those screens can merge them (kind 'TECH_TASK').
async function liveItemsFor(employee) {
  const [rows] = await db.query(
    `${TASK_SQL} WHERE LOWER(TRIM(t.assigned_to_name)) = LOWER(TRIM(?)) AND t.status IN ('IN PROGRESS', 'ON HOLD')`,
    [employee],
  );
  const shaped = await shapeTasks(rows, { me: employee, admin: false, incharge: false });
  const [sessions] = shaped.length
    ? await db.query(
        'SELECT task_id, MAX(started_at) AS started FROM tech_task_sessions WHERE task_id IN (?) AND ended_at IS NULL GROUP BY task_id',
        [shaped.map((t) => t.id)],
      )
    : [[]];
  const started = new Map(sessions.map((s) => [Number(s.task_id), s.started]));
  return shaped.map((t) => ({
    kind: 'TECH_TASK',
    key: `tech:${t.id}`,
    task_id: t.id,
    client: t.project_name,
    deliverable: t.title,
    title: `${t.kind === 'CORRECTION' ? 'Correction · ' : ''}${t.title}`,
    heading: `Tech · ${t.project_name}`,
    status: t.status,
    duration_secs: t.secs,
    running: t.running,
    session_started_at: started.get(Number(t.id)) || null,
    submit_date: t.task_date,
    due_date: t.task_date,
    section: 'Tech Workspace',
    project_id: t.project_id,
  }));
}

router.get('/live', async (req, res) => {
  try {
    const me = actor(req);
    return res.json({ success: true, data: await liveItemsFor(me) });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// For the top bar "running" chip: the running tech task of an employee (or null).
async function runningFor(employee) {
  const items = await liveItemsFor(employee);
  return items.find((i) => i.running) || null;
}

module.exports = router;
module.exports.runningFor = runningFor;
module.exports.liveItemsFor = liveItemsFor;