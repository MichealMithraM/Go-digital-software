const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

test('approval date queries find archived ranges and never truncate a month at 200 requests',
  { skip: process.env.EMPLOYEE_EXIT_MYSQL_TEST !== '1', timeout: 60000 }, async () => {
    require('dotenv').config({ quiet: true });
    const mysql = require('mysql2/promise');
    const name = `codex_approval_history_test_${Date.now()}_${process.pid}`;
    assert.match(name, /^codex_approval_history_test_\d+_\d+$/);
    const db = await mysql.createConnection({ host: process.env.DB_HOST || 'localhost',
      port: Number(process.env.DB_PORT || 3306), user: process.env.DB_USER || 'root', password: process.env.DB_PASSWORD || '' });
    try {
      await db.query(`CREATE DATABASE \`${name}\``);
      await db.changeUser({ database: name });
      await db.query('CREATE TABLE employee_users(id INT PRIMARY KEY, full_name VARCHAR(100), staff_id VARCHAR(30))');
      await db.query("INSERT INTO employee_users VALUES(7,'Ravi','E7')");
      await db.query(`CREATE TABLE attendance_permission_requests(id INT PRIMARY KEY, employee_id INT,
        request_type VARCHAR(30), request_date DATE, reason TEXT, status VARCHAR(20), created_at DATETIME,
        wfh_end_date DATE, home_latitude DOUBLE, home_longitude DOUBLE, home_accuracy_meters DOUBLE,
        home_captured_at DATETIME, home_address VARCHAR(500))`);
      await db.query(`CREATE TABLE employee_leaves(id INT PRIMARY KEY, leave_type VARCHAR(80), leave_type_id INT,
        from_date DATE, to_date DATE, duration_type VARCHAR(20), reason TEXT, days_count DECIMAL(5,1))`);
      await db.query('CREATE TABLE hrms_leave_approval_links(leave_id INT, approval_request_id INT)');
      await db.query('CREATE TABLE hrms_leave_types(id INT, abbreviation VARCHAR(20))');
      const rows = [[1, 7, 'earned_leave', '2019-10-04', 'Legacy summary', 'pending', '2019-10-01 09:00:00']];
      for (let id = 2; id <= 211; id++) rows.push([id, 7, 'earned_leave', '2026-11-02', 'Recent request', 'pending', '2026-11-01 09:00:00']);
      await db.query('INSERT INTO attendance_permission_requests(id,employee_id,request_type,request_date,reason,status,created_at) VALUES ?', [rows]);
      await db.query("INSERT INTO employee_leaves VALUES(1,'Earned Leave',1,'2019-10-04','2019-10-08','Full Day','Original archived reason',3)");
      await db.query('INSERT INTO hrms_leave_approval_links VALUES(1,1)');
      const moduleState = { exports: {} };
      vm.runInNewContext(fs.readFileSync(require.resolve('./hrmsApprovalsController'), 'utf8'), {
        module: moduleState, console, Date,
        require: p => p === '../config/db' ? db : p === '../lib/staffDirectory'
          ? { STAFF: { name: 'full_name', id: 'id', staffCode: 'staff_id' }, quote: v => v, staffFrom: () => 'employee_users' } : {},
      });
      async function get(query) {
        let code = 200, body;
        await moduleState.exports.list({ query: { tab: 'leave', ...query } }, { status(v) { code = v; return this; }, json(v) { body = v; } });
        assert.equal(code, 200);
        assert.equal(body.success, true);
        return body.data.items;
      }
      const archived = await get({ startDate: '2019-10-06', endDate: '2019-10-06' });
      assert.equal(archived.length, 1);
      assert.equal(archived[0].id, 1);
      assert.equal(archived[0].reason, 'Original archived reason');
      assert.equal(archived[0].dates, '4 Oct 2019 – 8 Oct 2019');
      assert.equal(archived[0].duration, '3 Days');
      const month = await get({ startDate: '2026-11-01', endDate: '2026-11-30' });
      assert.equal(month.length, 210);
      assert.equal((await get({ startDate: '2020-01-01', endDate: '2020-01-31' })).length, 0);
      assert.equal((await get({})).length, 211);
    } finally {
      if (/^codex_approval_history_test_\d+_\d+$/.test(name)) await db.query(`DROP DATABASE IF EXISTS \`${name}\``);
      await db.end();
    }
  });
