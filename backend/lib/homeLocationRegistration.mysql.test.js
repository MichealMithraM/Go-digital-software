const {test}=require('node:test');const assert=require('node:assert/strict');
test('home pin schema migration preserves existing approved homes and capture metadata',
{skip:process.env.EMPLOYEE_EXIT_MYSQL_TEST!=='1',timeout:60000},async()=>{
 require('dotenv').config({quiet:true});const mysql=require('mysql2/promise');
 const name=`codex_home_location_test_${Date.now()}_${process.pid}`;
 assert.match(name,/^codex_home_location_test_\d+_\d+$/);
 const c=await mysql.createConnection({host:process.env.DB_HOST||'localhost',port:Number(process.env.DB_PORT||3306),user:process.env.DB_USER||'root',password:process.env.DB_PASSWORD||''});
 try{
  await c.query(`CREATE DATABASE \`${name}\``);await c.changeUser({database:name});
  await c.query("CREATE TABLE hrms_employee_home_locations(employee_user_id INT PRIMARY KEY,latitude DECIMAL(10,7),longitude DECIMAL(10,7),approval_status VARCHAR(20))");
  await c.query("INSERT INTO hrms_employee_home_locations VALUES(7,13,80,'approved')");
  const {ensureHomeLocationTables}=require('./ensureHomeLocationTables');await ensureHomeLocationTables(c);
  let [[row]]=await c.query('SELECT * FROM hrms_employee_home_locations WHERE employee_user_id=7');
  assert.equal(row.approval_status,'approved');assert.equal(Number(row.latitude),13);assert.equal(row.capture_source,'gps');assert.equal(row.accuracy_meters,null);
  await c.query("UPDATE hrms_employee_home_locations SET capture_source='map_pin',approval_status='pending' WHERE employee_user_id=7");
  await ensureHomeLocationTables(c);[[row]]=await c.query('SELECT * FROM hrms_employee_home_locations WHERE employee_user_id=7');
  assert.equal(row.capture_source,'map_pin');assert.equal(row.approval_status,'pending');
 }finally{
  if(/^codex_home_location_test_\d+_\d+$/.test(name))await c.query(`DROP DATABASE IF EXISTS \`${name}\``);await c.end();
 }
});
