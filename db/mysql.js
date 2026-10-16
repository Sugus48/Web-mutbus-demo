// MySQL / MariaDB (XAMPP) — ใช้เมื่อ DB_CLIENT=mysql
// ทุก adapter (mysql.js / oracle.js) ส่งออกฟังก์ชันชุดเดียวกัน server.js จึงไม่ต้องรู้ว่าใช้ฐานข้อมูลไหน
//   call(name, args)  เรียก procedure → [[แถว...], ...]
//   listApi()         รายชื่อพารามิเตอร์ของ procedure api_*
//   ensureTrips()     สร้างรอบการเดินรถล่วงหน้า
//   normalize(err)    แปลง error ให้อยู่ในรูปแบบกลาง (แบบ MySQL)
const mysql = require('mysql2/promise');

// connection pool: ใช้การเชื่อมต่อซ้ำ ไม่ต้องเปิด/ปิดใหม่ทุก request (พร้อมกันได้สูงสุด 10)
const pool = mysql.createPool({
  host: process.env.DB_HOST || '127.0.0.1',
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'mut_shuttle',
  charset: 'utf8mb4',
  dateStrings: true, // DATE/DATETIME เป็นข้อความตามฐานข้อมูล ไม่แปลง timezone
  connectionLimit: 10,
});

// เรียก procedure แล้วคืนเฉพาะ result set: [[แถว...], [แถว...], ...]
// ค่าส่งผ่าน ? (placeholder) ไม่ต่อสตริงเอง → กัน SQL injection / mysql2 คืน OkPacket ปนมาด้วย จึงกรองเอาแค่ array
async function call(name, args) {
  const [res] = await pool.query(`CALL ${name}(${args.map(() => '?').join(', ')})`, args);
  return Array.isArray(res) ? res.filter(Array.isArray) : [];
}

// { api_xxx: ['p_uid', 'p_date', ...] } จาก information_schema
// อ่าน 2 ครั้ง: รายชื่อ procedure (รวมตัวที่ไม่มีพารามิเตอร์) + พารามิเตอร์ IN เรียงตามลำดับ
async function listApi() {
  const [routines] = await pool.query(
    `SELECT ROUTINE_NAME AS name FROM information_schema.ROUTINES
      WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_TYPE = 'PROCEDURE' AND ROUTINE_NAME LIKE 'api\\_%'`,
  );
  const [params] = await pool.query(
    `SELECT SPECIFIC_NAME AS name, PARAMETER_NAME AS param FROM information_schema.PARAMETERS
      WHERE SPECIFIC_SCHEMA = DATABASE() AND ROUTINE_TYPE = 'PROCEDURE' AND SPECIFIC_NAME LIKE 'api\\_%'
        AND PARAMETER_MODE = 'IN'
      ORDER BY SPECIFIC_NAME, ORDINAL_POSITION`,
  );
  const map = {};
  for (const r of routines) map[r.name.toLowerCase()] = [];
  for (const p of params) map[p.name.toLowerCase()].push(p.param.toLowerCase());
  return map;
}

// สร้างรอบจากตารางเวลาเดินรถ ตั้งแต่วันนี้ไปอีก 8 วัน (รอบที่มีแล้วไม่สร้างซ้ำ)
const ensureTrips = () => pool.query('CALL sp_ensure_trips(CURDATE(), 8)');

// error ของ mysql2 ใช้รูปแบบกลาง (sqlState 45000 = SIGNAL จาก procedure) อยู่แล้ว
const normalize = (err) => err;

module.exports = { name: 'MySQL', call, listApi, ensureTrips, normalize };
