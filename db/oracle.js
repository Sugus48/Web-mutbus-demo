// Oracle 19c (node-oracledb Thin mode — ไม่ต้องติดตั้ง Oracle Client) — ใช้เมื่อ DB_CLIENT=oracle
// procedure คืนผลลัพธ์ด้วย DBMS_SQL.RETURN_RESULT → อ่านจาก result.implicitResults
const oracledb = require('oracledb');

oracledb.outFormat = oracledb.OUT_FORMAT_OBJECT;

let poolPromise = null;
function getPool() {
  poolPromise ||= oracledb.createPool({
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    connectString: `${process.env.DB_HOST}:${process.env.DB_PORT || 1521}/${process.env.DB_SERVICE}`,
    poolMin: 0,
    poolMax: 10,
  }).catch((err) => { poolPromise = null; throw normalize(err); });
  return poolPromise;
}

// DATE → ข้อความแบบเดียวกับ MySQL ('YYYY-MM-DD' สำหรับวันที่ / 'YYYY-MM-DD HH:MM:SS' สำหรับวันเวลา)
const DATE_ONLY = new Set(['trip_date', 'today', 'min_date', 'max_date', 'date_from', 'date_to']);
const pad = (v) => String(v).padStart(2, '0');
function fmtDate(d, key) {
  const date = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  return DATE_ONLY.has(key) ? date : `${date} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}
function convRow(row) {
  const out = {};
  for (const [k, v] of Object.entries(row)) {
    const key = k.toLowerCase();
    out[key] = v instanceof Date ? fmtDate(v, key) : v;
  }
  return out;
}

// error ของ Oracle → รูปแบบเดียวกับ MySQL (server.js แปลงเป็นข้อความต่อ)
const ERRNO = { 1: 1062, 2292: 1451, 2291: 1452, 2290: 3819, 1400: 3819, 12899: 3819 };
function normalize(err) {
  if (!err || err.normalized) return err;
  err.normalized = true;
  const num = err.errorNum;
  if (num >= 20000 && num <= 20999) {
    err.sqlState = '45000'; // RAISE_APPLICATION_ERROR = SIGNAL ของ MySQL
    err.sqlMessage = String(err.message).split('\n')[0].replace(/^ORA-\d+:\s*/, '');
  } else if (ERRNO[num]) {
    err.errno = ERRNO[num];
    err.sqlState = '23000';
    err.sqlMessage = err.message;
  } else if (num === 6550 && /PLS-00306/.test(err.message)) {
    err.code = 'ER_SP_WRONG_NO_OF_ARGS'; // จำนวน/ชนิดพารามิเตอร์ไม่ตรง (procedure ถูกแก้หลังเปิดเว็บ) — ชื่อเดียวกับ MySQL
  } else if (num === 4068 || num === 6508 || num === 6550 || num === 4063) {
    err.code = 'ER_SP_DOES_NOT_EXIST'; // procedure ไม่มี / คอมไพล์ไม่ผ่าน
  } else if (/^(NJS-5\d\d|ORA-12\d\d\d|ORA-01017|ORA-28000)/.test(err.code || err.message) || err.code === 'ETIMEDOUT') {
    err.code = 'ECONNREFUSED';
  }
  return err;
}

async function withConn(fn) {
  const pool = await getPool();
  const conn = await pool.getConnection();
  try {
    return await fn(conn);
  } catch (err) {
    throw normalize(err);
  } finally {
    await conn.close();
  }
}

// เรียก procedure แล้วคืน result set ทั้งหมด: [[แถว...], [แถว...], ...]
const call = (name, args) => withConn(async (conn) => {
  const r = await conn.execute(
    `BEGIN ${name}(${args.map((_, i) => `:${i + 1}`).join(', ')}); END;`,
    args.map((v) => (v === undefined ? null : v)),
    { autoCommit: true },
  );
  return (r.implicitResults || []).map((rows) => rows.map(convRow));
});

// { api_xxx: ['p_uid', 'p_date', ...] } จาก user_procedures / user_arguments
const listApi = () => withConn(async (conn) => {
  const procs = await conn.execute(
    `SELECT object_name AS name FROM user_procedures
      WHERE object_type = 'PROCEDURE' AND object_name LIKE 'API\\_%' ESCAPE '\\'`,
  );
  const params = await conn.execute(
    `SELECT object_name AS name, argument_name AS param FROM user_arguments
      WHERE package_name IS NULL AND object_name LIKE 'API\\_%' ESCAPE '\\'
        AND argument_name IS NOT NULL AND in_out = 'IN'
      ORDER BY object_name, position`,
  );
  const map = {};
  for (const r of procs.rows) map[r.NAME.toLowerCase()] = [];
  for (const p of params.rows) (map[p.NAME.toLowerCase()] ||= []).push(p.PARAM.toLowerCase());
  return map;
});

const ensureTrips = () => withConn((conn) => conn.execute('BEGIN sp_ensure_trips(TRUNC(SYSDATE), 8); END;', [], { autoCommit: true }));

module.exports = { name: 'Oracle', call, listApi, ensureTrips, normalize, getPool };
