async function ensureHrmsTrackingTables(db) {
  await require('./ensureHomeLocationTables').ensureHomeLocationTables(db);
  await db.query(`
    CREATE TABLE IF NOT EXISTS hrms_tracking_settings (
      id TINYINT PRIMARY KEY,
      office_name VARCHAR(120) NOT NULL,
      office_address VARCHAR(500) NOT NULL,
      office_latitude DECIMAL(10,7) NULL DEFAULT NULL,
      office_longitude DECIMAL(10,7) NULL DEFAULT NULL,
      office_radius_meters INT NULL DEFAULT NULL,
      outside_radius_grace_minutes INT NULL DEFAULT NULL,
      field_ping_interval_minutes INT NULL DEFAULT NULL,
      field_waiting_minutes INT NULL DEFAULT NULL,
      stationary_radius_meters INT NULL DEFAULT NULL,
      updated_by INT NULL,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )
  `);

  const [settingsColumns] = await db.query(
    `SELECT COLUMN_NAME, IS_NULLABLE, COLUMN_DEFAULT FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'hrms_tracking_settings'`
  );
  const hasCol = (name) => settingsColumns.some((c) => c.COLUMN_NAME === name);
  if (!hasCol('outside_radius_grace_minutes')) {
    await db.query('ALTER TABLE hrms_tracking_settings ADD COLUMN outside_radius_grace_minutes INT NULL DEFAULT NULL');
  }
  if (!hasCol('office_outside_radius_grace_minutes')) {
    await db.query('ALTER TABLE hrms_tracking_settings ADD COLUMN office_outside_radius_grace_minutes INT NULL DEFAULT NULL');
  }
  if (!hasCol('home_outside_radius_grace_minutes')) {
    await db.query('ALTER TABLE hrms_tracking_settings ADD COLUMN home_outside_radius_grace_minutes INT NULL DEFAULT NULL');
  }
  if (!hasCol('office_no_gps_timeout_minutes')) {
    await db.query('ALTER TABLE hrms_tracking_settings ADD COLUMN office_no_gps_timeout_minutes INT NULL DEFAULT NULL');
  }
  if (!hasCol('home_no_gps_timeout_minutes')) {
    await db.query('ALTER TABLE hrms_tracking_settings ADD COLUMN home_no_gps_timeout_minutes INT NULL DEFAULT NULL');
  }
  if (!hasCol('home_radius_meters')) {
    await db.query('ALTER TABLE hrms_tracking_settings ADD COLUMN home_radius_meters INT NULL DEFAULT NULL');
  }
  if (!hasCol('home_tracking_enabled')) {
    await db.query('ALTER TABLE hrms_tracking_settings ADD COLUMN home_tracking_enabled TINYINT NOT NULL DEFAULT 1');
  }

  // Drop old policy defaults without modifying any saved admin values.
  const policyColumns = ['office_radius_meters', 'outside_radius_grace_minutes',
    'field_ping_interval_minutes', 'field_waiting_minutes', 'stationary_radius_meters',
    'office_outside_radius_grace_minutes', 'home_outside_radius_grace_minutes',
    'office_no_gps_timeout_minutes', 'home_no_gps_timeout_minutes', 'home_radius_meters'];
  for (const name of policyColumns) {
    const column = settingsColumns.find(item => item.COLUMN_NAME === name);
    if (column && (column.IS_NULLABLE !== 'YES' || (column.COLUMN_DEFAULT != null && String(column.COLUMN_DEFAULT).toUpperCase() !== 'NULL'))) {
      await db.query(`ALTER TABLE hrms_tracking_settings MODIFY COLUMN ${name} INT NULL DEFAULT NULL`);
    }
  }

  for (const name of ['office_latitude', 'office_longitude']) {
    const column = settingsColumns.find(item => item.COLUMN_NAME === name);
    if (column && column.IS_NULLABLE !== 'YES') {
      await db.query(`ALTER TABLE hrms_tracking_settings MODIFY COLUMN ${name} DECIMAL(10,7) NULL DEFAULT NULL`);
    }
  }

  await db.query(`
    INSERT IGNORE INTO hrms_tracking_settings (id, office_name, office_address)
    VALUES (1, 'Main Office', 'Configure this address in Admin > Tracking')
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS hrms_employee_location_status (
      employee_user_id INT PRIMARY KEY,
      status ENUM('office','home','hybrid') NOT NULL DEFAULT 'office',
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )
  `);

  // Safely replace the legacy "field" status with the Hybrid status without
  // invalidating existing live-location records.
  const [statusColumns] = await db.query(
    `SELECT COLUMN_TYPE FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME = 'hrms_employee_location_status'
       AND COLUMN_NAME = 'status'`
  );
  if (String(statusColumns[0] && statusColumns[0].COLUMN_TYPE).includes("'field'")) {
    await db.query(
      "ALTER TABLE hrms_employee_location_status MODIFY status ENUM('office','home','field','hybrid') NOT NULL DEFAULT 'office'"
    );
    await db.query("UPDATE hrms_employee_location_status SET status = 'hybrid' WHERE status = 'field'");
    await db.query(
      "ALTER TABLE hrms_employee_location_status MODIFY status ENUM('office','home','hybrid') NOT NULL DEFAULT 'office'"
    );
  }

  await db.query(`
    CREATE TABLE IF NOT EXISTS hrms_location_pings (
      id INT AUTO_INCREMENT PRIMARY KEY,
      employee_user_id INT NOT NULL,
      latitude DECIMAL(10,7) NOT NULL,
      longitude DECIMAL(10,7) NOT NULL,
      accuracy_meters DECIMAL(6,1) NULL,
      address VARCHAR(255) NULL,
      recorded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_employee_recorded (employee_user_id, recorded_at)
    )
  `);
}

module.exports = { ensureHrmsTrackingTables };
