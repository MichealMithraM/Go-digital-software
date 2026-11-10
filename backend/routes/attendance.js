const express = require('express');
const router = express.Router();
const { authenticateToken } = require('./auth');
const attendance = require('../controllers/attendanceController');
const calendarNotifications = require('../controllers/calendarNotificationsController');

router.use(authenticateToken);
const leavePolicies = require('../controllers/leavePolicies');
const attendancePolicies = require('../controllers/attendancePolicySettingsController');
router.use('/leave/policies', attendance.requireAdmin);
router.get('/leave/policies', attendance.requireAdmin, leavePolicies.list);
router.post('/leave/policies', attendance.requireAdmin, leavePolicies.create);
router.put('/leave/policies', attendance.requireAdmin, leavePolicies.saveAll);
router.put('/leave/policies/:id', attendance.requireAdmin, leavePolicies.save);

// Both portals keep their existing URL.  The signed-in user determines the
// response shape, while both response paths read the same attendance_records.
router.get('/dashboard', function (req, res, next) {
  const userType = String((req.user && req.user.userType) || '').toLowerCase();
  if (userType === 'admin') return attendance.dashboard(req, res, next);
  return attendance.employeeDashboard(req, res, next);
});
router.get('/clock-logs', attendance.requireAdmin, attendance.clockLogs);
router.get('/clock-logs/calendar', attendance.requireAdmin, attendance.employeeCalendar);
router.patch('/clock-logs/status', attendance.requireAdmin, attendance.correctStatus);
router.get('/policies', attendance.requireAdmin, attendancePolicies.list);
router.put('/policies', attendance.requireAdmin, attendancePolicies.save);
router.get('/export', attendance.requireAdmin, attendance.exportCsv);
router.get('/permissions', attendance.requireAdmin, attendance.adminPermissions);
router.patch('/permissions/:id', attendance.requireAdmin, attendance.reviewPermission);

router.get('/me', attendance.myHistory);
router.get('/me/day', attendance.dayDetail);
router.get('/calendar-notifications', calendarNotifications.mine);
router.patch('/calendar-notifications/:id/read', calendarNotifications.markRead);
router.get('/me/export', attendance.myExport);
router.get('/check-in-policy', attendance.checkInPolicy);
router.post('/ios-web-devices/register', attendance.registerIosWebDevice);
router.get('/ios-web-devices', attendance.requireAdmin, attendance.listIosWebDevices);
router.patch('/ios-web-devices/:id', attendance.requireAdmin, attendance.updateIosWebDevice);
router.post('/check-in', attendance.checkIn);
router.post('/check-out', attendance.checkOut);
router.post('/heartbeat', attendance.heartbeat);
router.post('/location-heartbeat', attendance.heartbeat);
// Compatibility with the employee module's original API contract.
router.post('/clock-in', attendance.checkIn);
router.post('/clock-out', attendance.checkOut);
router.post('/break-in', attendance.startBreak);
router.post('/break-out', attendance.endBreak);
router.get('/breaks/:id/review', attendance.requireAdmin, attendance.getBreakReview);
router.patch('/breaks/:id/review', attendance.requireAdmin, attendance.reviewBreak);
router.post('/checkout/undo', attendance.undoCheckout);
router.post('/checkout/correction-request', attendance.requestCheckoutCorrection);
router.post('/corrections', attendance.requestAttendanceCorrection);
router.get('/checkout/correction-requests', attendance.requireAdmin, attendance.listCorrectionRequests);
router.patch('/checkout/correction-requests/:id/approve', attendance.requireAdmin, attendance.approveCorrectionRequest);
router.patch('/checkout/correction-requests/:id/reject', attendance.requireAdmin, attendance.rejectCorrectionRequest);
// Clear, shared routes for all attendance correction types.  The checkout
// routes above remain so older portal builds continue to work.
router.get('/correction-requests', attendance.requireAdmin, attendance.listCorrectionRequests);
router.patch('/correction-requests/:id/approve', attendance.requireAdmin, attendance.approveCorrectionRequest);
router.patch('/correction-requests/:id/reject', attendance.requireAdmin, attendance.rejectCorrectionRequest);
router.get('/permissions/mine', attendance.myPermissions);
router.post('/permissions', attendance.createPermission);

module.exports = router;
