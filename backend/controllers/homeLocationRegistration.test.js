const {test}=require('node:test');const assert=require('node:assert/strict');
const fs=require('fs');const vm=require('vm');const locationPolicy=require('../lib/attendanceLocationPolicy');
const {validateHomeRegistration}=require('../lib/homeLocationRegistration');
function setup(){
 const calls=[];let committed=0;let rolledBack=0;
 const home={latitude:13,longitude:80,address:'My home',approval_status:'pending',capture_source:'map_pin'};
 const db={getConnection:async()=>db,beginTransaction:async()=>{},commit:async()=>{committed++},rollback:async()=>{rolledBack++},release:()=>{},query:async(sql,params)=>{
   calls.push({sql,params});return sql.includes('FOR UPDATE')?[[home]]:[[]];
 }};
 const module={exports:{}};
 vm.runInNewContext(fs.readFileSync(require.resolve('./hrmsTrackingController'),'utf8'),{module,console,require:p=>p==='../config/db'?db:p==='../lib/homeLocationRegistration'?{validateHomeRegistration}:p==='../lib/attendanceLocationPolicy'?{...locationPolicy,profileFor:async()=>({}),settingsFor:async()=>({homeRadiusMeters:100})}:{}});
 const response=()=>({code:200,body:null,status(code){this.code=code;return this;},json(body){this.body=body;return body;}});
 return{controller:module.exports,calls,home,response,commits:()=>committed,rollbacks:()=>rolledBack};
}
test('employee map submission always becomes pending and resets prior approval',async()=>{
 const s=setup(),res=s.response();await s.controller.submitHomeLocation({user:{id:7},body:{captureSource:'map_pin',latitude:13,longitude:80,address:'My home',approval_status:'approved'}},res);
 assert.equal(res.code,200);assert.equal(s.commits(),1);
 const write=s.calls.find(c=>c.sql.includes('INSERT INTO hrms_employee_home_locations'));
 assert.match(write.sql,/approval_status = 'pending'/);assert.match(write.sql,/reviewed_by = NULL/);
 assert.deepEqual(Array.from(write.params),[7,13,80,'My home','map_pin',null]);
});
test('map approval requires admin verification and detects changed requests',async()=>{
 for(const [user,body,expected] of [
  [{id:7,userType:'employee'},{},403],
  [{id:1,userType:'admin'},{},400],
  [{id:1,userType:'admin'},{mapPinVerified:true,reviewedAddress:'old address'},409],
  [{id:1,userType:'admin'},{mapPinVerified:true,reviewedAddress:'My home',longitude:81},409],
  [{id:1,userType:'admin'},{mapPinVerified:true,reviewedAddress:'My home'},200],
 ]){
  const s=setup(),res=s.response();await s.controller.reviewHomeLocation({user,params:{employeeUserId:'7'},body:{approvalStatus:'approved',latitude:13,longitude:80,...body}},res);
  assert.equal(res.code,expected);assert.equal(s.commits(),expected===200?1:0);
 }
});
