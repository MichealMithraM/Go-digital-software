async function ensureHomeLocationTables(db) {
  await db.query(`CREATE TABLE IF NOT EXISTS hrms_employee_home_locations (
    employee_user_id INT PRIMARY KEY,
    latitude DECIMAL(10,7) NOT NULL, longitude DECIMAL(10,7) NOT NULL,
    address VARCHAR(500) NULL, approval_status VARCHAR(20) NOT NULL DEFAULT 'pending',
    submitted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reviewed_by INT NULL, reviewed_at DATETIME NULL, rejection_reason VARCHAR(500) NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    capture_source VARCHAR(20) NOT NULL DEFAULT 'gps', accuracy_meters DOUBLE NULL
  )`);
  const [columns] = await db.query("SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='hrms_employee_home_locations'");
  for (const [name, definition] of [['capture_source', "VARCHAR(20) NOT NULL DEFAULT 'gps'"], ['accuracy_meters', 'DOUBLE NULL']]) {
    if (!columns.some(c => c.COLUMN_NAME === name)) {
      try { await db.query(`ALTER TABLE hrms_employee_home_locations ADD COLUMN ${name} ${definition}`); }
      catch (error) { if (error.code !== 'ER_DUP_FIELDNAME') throw error; }
    }
  }
}
module.exports = { ensureHomeLocationTables };
