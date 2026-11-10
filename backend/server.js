require('dotenv').config();
const express = require('express');
const cors    = require('cors');

const http    = require('http');
const path = require('path');
const { Server } = require("socket.io");
const cron = require('node-cron');
const db = require('./config/db');

const attendancePolicy = require('./lib/attendancePolicy');
const { runAutoAbsence } = require('./jobs/auto-absence');
const { runAutoCheckout, runEndOfDayClose } = require('./jobs/auto-checkout');
const { ensureAttendancePolicyTables } = require('./controllers/attendancePolicySettingsController');
const { ensureAuthSchema } = require('./lib/ensureAuthSchema');

// At 12:01 AM IST, mark only the preceding eligible working day absent.
// The job is idempotent, and startup reconciliation covers a missed run.
cron.schedule('1 0 * * *', async () => {
  try { console.log('Auto-absence result:', await runAutoAbsence()); }
  catch (error) { console.error('Auto-absence job failed:', error.message); }
}, { timezone: 'Asia/Kolkata' });
runAutoAbsence().catch((error) => console.error('Auto-absence reconciliation failed:', error.message));

// Auto-checkout: every minute, check open sessions for out-of-radius or no-GPS situations
cron.schedule('* * * * *', async () => {
  try {
    const result = await runAutoCheckout();
    if (result.checked > 0) console.log(`Auto-checkout: ${result.checked} session(s) closed on ${result.today}`);
  } catch (error) {
    console.error('Auto-checkout job failed:', error.message);
  }
}, { timezone: 'Asia/Kolkata' });

// End-of-day auto-close: at 11:59 PM IST, close any session still open
cron.schedule('59 23 * * *', async () => {
  try {
    const result = await runEndOfDayClose();
    if (result.closed > 0) console.log(`End-of-day close: ${result.closed} session(s) closed on ${result.today}`);
  } catch (error) {
    console.error('End-of-day close job failed:', error.message);
  }
}, { timezone: 'Asia/Kolkata' });


// Run every day at midnight (00:00) to check expired tasks and auto-create next cycle once per deadline
cron.schedule('0 0 * * *', async () => {
  console.log('ðŸ”„ Running Daily Task Auto-Rollover & Next Cycle Check...');
  try {
    const [expiredTasks] = await db.query(`
      SELECT * FROM task_assignments 
      WHERE is_assigned = 1 
        AND deadline IS NOT NULL 
        AND DATE(deadline) < CURDATE()
    `);

    console.log(`ðŸ“Œ Found ${expiredTasks.length} expired task(s) for auto-rollover check.`);

    for (const task of expiredTasks) {
      // ðŸŸ¢ Calculate next cycle dates (adding 1 month to maintenance & deadline)
      let nextMaintenance = task.maintenance_date ? new Date(task.maintenance_date) : new Date();
      if (!isNaN(nextMaintenance.getTime())) {
        nextMaintenance.setMonth(nextMaintenance.getMonth() + 1);
      } else {
        nextMaintenance = new Date();
        nextMaintenance.setMonth(nextMaintenance.getMonth() + 1);
      }

      let nextDeadline = task.deadline ? new Date(task.deadline) : new Date();
      if (!isNaN(nextDeadline.getTime())) {
        nextDeadline.setMonth(nextDeadline.getMonth() + 1);
      } else {
        nextDeadline = new Date();
        nextDeadline.setMonth(nextDeadline.getMonth() + 1);
      }

      const formatSqlDate = (d) => d instanceof Date ? d.toISOString().slice(0, 19).replace('T', ' ') : d.toISOString().slice(0, 19).replace('T', ' ');

      // ðŸŸ¢ Check if next cycle task already exists for this client and deliverables to prevent daily spamming
      const [existingNextCycle] = await db.query(`
        SELECT id FROM task_assignments 
        WHERE client_name = ? 
          AND deliverables = ? 
          AND deadline = ?
      `, [task.client_name, task.deliverables, formatSqlDate(nextDeadline)]);

      // Oru vela antha next cycle deadline-ku task illaiyendraal mattum, auto-assign seyyum (Once only)
      if (existingNextCycle.length === 0) {
        await db.query(`
          INSERT INTO task_assignments (
            client_name, deliverables, maintenance_date, 
            ads_handling, ads_platform, 
            page_handling, pages_platform, 
            designer, designer_tasks, 
            videographer, videographer_tasks, 
            video_editor, video_editor_task, 
            ui_ux_designer, ui_ux_tasks, 
            developer, developer_tasks, 
            website_designer, website_designer_tasks, 
            deadline, comments, is_assigned
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
        `, [
          task.client_name, 
          task.deliverables, 
          formatSqlDate(nextMaintenance),
          task.ads_handling, 
          task.ads_platform,
          task.page_handling, 
          task.pages_platform,
          task.designer, 
          task.designer_tasks,
          task.videographer, 
          task.videographer_tasks,
          task.video_editor, 
          task.video_editor_task,
          task.ui_ux_designer, 
          task.ui_ux_tasks,
          task.developer, 
          task.developer_tasks,
          task.website_designer, 
          task.website_designer_tasks,
          formatSqlDate(nextDeadline), 
          task.comments
        ]);
        console.log(`âœ… Auto-created next cycle task for client: ${task.client_name}`);
      }
    }
    console.log('âœ… Expired tasks automatic rollover process completed.');
  } catch (err) {
    console.error('âŒ Automatic rollover cron error:', err.message);
  }
});



const employeeRoutes = require('./routes/employees');
const timingRoutes    = require('./routes/timings'); 
const clientRoutes     = require('./routes/clients');        
const credentialRoutes = require('./routes/credentials'); 
const packageRoutes    = require('./routes/packages');   
const quotationRoutes  = require('./routes/quotations');
const invoiceRoutes    = require('./routes/invoices');
const invoiceAssignmentRoutes = require('./routes/invoiceAssignments');
const taskRoutes       = require('./routes/tasks');  
const authRoutes = require('./routes/auth');
const clientRepositoryRoutes = require('./routes/clientRepository');
const employeeTaskRoutes  = require('./routes/employee-tasks'); 
const dailyReportsRouter = require('./routes/daily-reports');
const taskPlannerRoutes   = require('./routes/task-planner');   
const videographerPlannerRoutes = require('./routes/videographer-planner');
const feedbackRoutes = require('./routes/feedback'); 
const taskMasterRoutes = require('./routes/task-master');
const taskRolesRoutes = require('./routes/task-roles');
const taskListRoutes = require('./routes/task-list');
const trackingItemsRoutes = require('./routes/tracking-items');
const contentCalendarWorkspaceRoutes = require('./routes/contentCalendarWorkspace');
const contentCalendarRoutes = require('./routes/contentCalendarRoutes');
const { ensureContentCalendarWorkspaceSchema } = require('./lib/ensureContentCalendarWorkspaceSchema');
const dashboardRoutes = require('./routes/dashboard');
const adminEmployeeStatusRoutes = require('./routes/admin-employee-status');
const notificationsRoutes = require('./routes/notifications');
const chatRoutes = require('./routes/chat');
const workspaceTaskRoutes = require('./routes/workspaceTasks');
   const { ensureWorkspaceTaskSchema } = require('./lib/ensureWorkspaceTaskSchema');

const push = require('./lib/pushNotifications'); // mobile push (works with the app closed)

const DayPlannerRoutes = require('./routes/day-planner');
const performanceRoutes = require('./routes/performance');

const attendanceRoutes = require('./routes/attendance');
const { createApp: createEmployeeAttendanceApp } = require('./attendance/app');
const { ensureAttendanceTables } = require('./lib/ensureAttendanceTables');
const hrmsEmployeesRoutes = require('./routes/hrmsEmployees');
const { ensureHrmsEmployeeTables } = require('./lib/ensureHrmsEmployeeTables');
const hrmsDashboardRoutes = require('./routes/hrmsDashboard');
const hrmsApprovalsRoutes = require('./routes/hrmsApprovals');
const hrmsPayrollRoutes = require('./routes/hrmsPayroll');
const hrmsTrackingRoutes = require('./routes/hrmsTracking');
const hrmsAnnouncementsRoutes = require('./routes/hrmsAnnouncements');
const hrmsPayslipRoutes = require('./routes/hrmsPayslips');
const { generatePayrollRun } = require('./controllers/hrmsPayrollController');

// near the other ensure imports
const { ensureHrmsTrackingTables } = require('./lib/ensureHrmsTrackingTables');
const { ensureClientRepositoryTables } = require('./lib/ensureClientRepositoryTables');

const app  = express();
const PORT = process.env.PORT || 3000;
const employeeAttendanceApp = createEmployeeAttendanceApp({
  pool: db,
  jwtSecret: authRoutes.JWT_SECRET,
  timeZone: process.env.ATTENDANCE_TIMEZONE || 'Asia/Kolkata',
  basePath: '',
});

// On the first day of each month, create a pending payroll snapshot for every
// active employee with an effective compensation record. Payment remains an
// explicit admin action.
cron.schedule('15 0 1 * *', async () => {
  try {
    const [year, month] = attendancePolicy.todayIstDate().split('-').map(Number);
    const result = await generatePayrollRun(year, month, attendancePolicy.todayIstDate());
    console.log(`Monthly payroll draft created: ${result.generatedCount} included, ${result.skippedCount} need compensation.`);
  } catch (err) {
    console.error('Automatic monthly payroll generation error:', err.message);
  }
}, { timezone: 'Asia/Kolkata' });

// â”€â”€ 1. Create HTTP Server & Initialize Socket.io â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST", "PUT", "PATCH", "DELETE"]
  }
});

io.use(async (socket, next) => {
  try {
    const token = socket.handshake.auth?.token;
    const user = require('jsonwebtoken').verify(token, require('./routes/auth').JWT_SECRET);
    const [[account]] = await db.query('SELECT id,is_active FROM employee_users WHERE id=?', [user.id]);
    if (!account || !Number(account.is_active)) return next(new Error('Employee account is inactive'));
    const [[session]] = await db.query('SELECT COALESCE(MAX(id),0) AS version FROM employee_exits WHERE employee_user_id=?', [account.id]);
    if (Number(user.sessionVersion || 0) !== Number(session.version)) return next(new Error('Please sign in again'));
    socket.data.employeeId = account.id;
    next();
  } catch (_) { next(new Error('Sign in to connect')); }
});
app.set('io', io);
push.attachIo(io); // chat + group socket messages also go to phones as push

io.on('connection', (socket) => {
  console.log(`âš¡ A user connected: ${socket.id}`);

  socket.on('disconnect', () => {
    console.log(`ðŸ”Œ User disconnected: ${socket.id}`);
  });
});

   
// â”€â”€ CORS middleware â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin',  '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
  res.header(
    'Access-Control-Allow-Headers',
    'Content-Type, Authorization, X-Attendance-Client, X-Attendance-Device-Id',
  );
  
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});

app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// âœ… Duplicate `const db` removed from here!
require('./jobs/day-planner-reminders')(db);

app.use(
  '/uploads',
  express.static(path.resolve(__dirname, 'uploads'))
);

// The browser Maps key is kept in the backend environment instead of the web
// build. Restrict this key in Google Cloud to the approved website origins.
app.get('/api/config/maps.js', (req, res) => {
  const apiKey = process.env.GOOGLE_MAPS_API_KEY;
  res.set('Cache-Control', 'no-store');
  res.type('application/javascript');
  if (!apiKey) return res.send('');
  return res.send(`window.googleMapsApiKey = ${JSON.stringify(apiKey)};`);
});

// â”€â”€ Routes â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
app.use('/api', (req, res, next) => {
  if (req.method === 'OPTIONS' || req.path === '/auth/login') return next();
  return require('./routes/auth').authenticateToken(req, res, next);
});
app.use('/api', require('./lib/employeeEligibility').liveWriteGuard);
app.use('/api/employees', require('./routes/employeeLifecycle'));
app.use('/api/employees', employeeRoutes);
app.use('/api/timings', timingRoutes);
app.use('/api/clients', clientRoutes);
app.use('/api/credentials', credentialRoutes);
// Client credential history
app.use(
  '/api/credential-history',
  require('./routes/credential_history')
);

// Employee credential visibility
app.use(
  '/api/employee-credential-visibility',
  require('./routes/employee_credential_visibility')
);
app.use('/api/packages', packageRoutes);
app.use('/api/quotations', quotationRoutes);
app.use('/api/invoices', invoiceAssignmentRoutes);
app.use('/api/invoices', invoiceRoutes); 
app.use('/api/tasks', taskRoutes);
app.use('/api/tasks', contentCalendarWorkspaceRoutes);
app.use('/api/auth', authRoutes);
app.use('/api/client-repository', clientRepositoryRoutes);
app.use('/api/employee-tasks', employeeTaskRoutes); 
app.use('/api/daily-reports', dailyReportsRouter);
app.use('/api/task-planner',   taskPlannerRoutes); 
app.use('/api/videographer-planner', videographerPlannerRoutes); 
app.use('/api/feedback', feedbackRoutes); 
app.use('/api/task-master', taskMasterRoutes);
app.use('/api/task-roles', taskRolesRoutes);
app.use('/api/task-list', taskListRoutes);
app.use('/api/tracking-items', trackingItemsRoutes);
app.use('/api/dashboard', dashboardRoutes);
app.use('/api/admin', adminEmployeeStatusRoutes);
app.use('/api/manager-review', require('./routes/manager-review'));
app.use('/api/notifications', notificationsRoutes);
app.use('/api/chat', chatRoutes);
app.use('/api/workspace-tasks', workspaceTaskRoutes);
app.use('/api/push', push.router); // phones register here after login

app.use('/api/day-planner', DayPlannerRoutes); 
app.use('/api/performance', performanceRoutes);

app.use('/api/attendance', attendanceRoutes);
app.use('/api/content-calendar', contentCalendarRoutes);
// Keep every attendance feature on the main API server. Existing clock and
// calendar routes above remain authoritative; this app supplies the employee
// leave, break, extra-hours, permission dashboard, header, and tracking routes.
app.use('/api/attendance', employeeAttendanceApp);
app.use('/api/hrms/employees', hrmsEmployeesRoutes);
app.use('/api/hrms/dashboard', hrmsDashboardRoutes);
app.use('/api/hrms/approvals', hrmsApprovalsRoutes);
app.use('/api/hrms/payroll', hrmsPayrollRoutes);
app.use('/api/hrms/tracking', hrmsTrackingRoutes);
app.use('/api/hrms/announcements', hrmsAnnouncementsRoutes);
app.use('/api/hrms/payslips', hrmsPayslipRoutes);
   app.use('/api/task-rules', require('./routes/taskRules'));
const broadcastRoutes = require('./routes/broadcast');
app.use('/api/broadcast', broadcastRoutes);


// Health check
app.get('/', (req, res) => {
  res.json({ message: 'GoDigital API is running', status: 'ok' });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ success: false, message: 'Route not found' });
});
app.use(express.json({ limit: '15mb' }));
// Global error handler
app.use((err, req, res, next) => {
  console.error('âŒ Global error:', err.code, err.message, err.stack);
  if (err.code === 'LIMIT_FILE_SIZE') {
    return res.status(413).json({ success: false, message: 'File too large. Maximum allowed size is 500MB.' });
  }
  if (err.code === 'LIMIT_UNEXPECTED_FILE') {
    return res.status(400).json({ success: false, message: 'Unexpected file field in upload.' });
  }
  res.status(500).json({ success: false, message: err.message || 'Internal server error' });
});

server.listen(PORT, async () => {
  console.log(`GoDigital API running at http://localhost:${PORT}`);
  console.log(`âœ… Socket.io server is active and running`);
  try {
    await ensureContentCalendarWorkspaceSchema(db);
    console.log('Content Calendar workspace schema is ready');
    await ensureAttendanceTables(db);
       await ensureWorkspaceTaskSchema(db);
   console.log('Workspace task schema is ready');
    await ensureAuthSchema(db);
    console.log('Login schema is ready');
    console.log('Attendance tables are ready');
    await ensureAttendancePolicyTables();
    await attendancePolicy.getTimeSettings(db);
    console.log('Attendance time settings are ready');
    await ensureHrmsEmployeeTables(db);
    await require('./lib/employeeLifecycle').ensureLifecycle();
    console.log('HRMS employee profiles are ready');
    const [currentYear, currentMonth] = attendancePolicy.todayIstDate().split('-').map(Number);
    const payrollRun = await generatePayrollRun(currentYear, currentMonth, attendancePolicy.todayIstDate());
    console.log(`Current payroll draft ready: ${payrollRun.generatedCount} included, ${payrollRun.skippedCount} need compensation.`);
    await ensureHrmsTrackingTables(db);
    await ensureClientRepositoryTables(db);
    console.log('HRMS tracking tables are ready');
    console.log('Client Work Repository tables are ready');
  } catch (error) {
    console.error('Could not ensure startup database tables:', error.message);
  }
  // Every new row in `notifications` (task assigned, review, planner …) → phone push.
  push.startNotificationWatcher();
});
