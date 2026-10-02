// MUT Shuttle — ตัวกลางบางๆ ระหว่างหน้าเว็บ (public/*.html) กับฐานข้อมูล
// ไม่มี business logic ในไฟล์นี้: ทุกอย่างอยู่ใน stored procedure
//   Oracle: database/api_procedures_oracle.sql  /  MySQL: database/api_procedures.sql
//
//   POST /api/login     → CALL sp_login(...)     แล้วเก็บผู้ใช้ไว้ใน session
//   POST /api/register  → CALL sp_register(...)  แล้วเก็บผู้ใช้ไว้ใน session
//   POST /api/logout    → ล้าง session
//   POST /api/<ชื่อ>     → CALL api_<ชื่อ>(p_uid, ...) — p_uid มาจาก session เสมอ
//                          พารามิเตอร์อื่นจับคู่ตามชื่อ: p_date ← body.date
//   ไฟล์อื่นทั้งหมด      → เสิร์ฟจากโฟลเดอร์ public (/search → public/search.html)
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env'), quiet: true });
const express = require('express');
const session = require('express-session');
const bcrypt = require('bcryptjs');

// เลือกฐานข้อมูลด้วย DB_CLIENT ใน .env: oracle (เหมือนโปรเจกต์เดิม) หรือ mysql (XAMPP)
const CLIENT = (process.env.DB_CLIENT || 'mysql').toLowerCase();
const db = require(CLIENT === 'oracle' ? './db/oracle' : './db/mysql');
const call = db.call;

// รายชื่อพารามิเตอร์ของ procedure api_* (อ่านจากฐานข้อมูล — เพิ่ม procedure ใหม่ไม่ต้องแก้ไฟล์นี้)
let apiParams = null;
async function loadApi() {
  apiParams = await db.listApi();
}

// แปลง error จากฐานข้อมูลเป็น { status, error, field }
// SIGNAL '45000' ข้อความรูปแบบ 'ช่อง|ข้อความ' — ช่อง !denied = 403, !notfound = 404
function toError(err) {
  err = db.normalize(err);
  if (err.sqlState === '45000') {
    const m = String(err.sqlMessage).match(/^(!?[a-z_]+)\|([\s\S]*)$/);
    if (!m) return { status: 400, error: err.sqlMessage };
    if (m[1] === '!denied') return { status: 403, error: m[2] };
    if (m[1] === '!notfound') return { status: 404, error: m[2] };
    return { status: 400, error: m[2], field: m[1] };
  }
  const known = {
    1062: 'ข้อมูลซ้ำกับที่มีอยู่แล้วในระบบ',
    1451: 'ลบไม่ได้ เนื่องจากข้อมูลนี้ถูกใช้งานอยู่ในส่วนอื่นของระบบ',
    1452: 'ข้อมูลอ้างอิงไม่ถูกต้อง (ไม่พบข้อมูลที่เลือก)',
    3819: 'ข้อมูลไม่ผ่านเงื่อนไขที่กำหนด',
    4025: 'ข้อมูลไม่ผ่านเงื่อนไขที่กำหนด',
  };
  if (known[err.errno]) return { status: 400, error: known[err.errno] };
  console.error(err);
  if (['ECONNREFUSED', 'ER_ACCESS_DENIED_ERROR', 'ER_BAD_DB_ERROR', 'ETIMEDOUT', 'ENOTFOUND', 'EHOSTUNREACH'].includes(err.code)) {
    return { status: 500, error: 'เชื่อมต่อฐานข้อมูลไม่ได้ — ตรวจสอบว่าฐานข้อมูลเปิดอยู่ และค่าในไฟล์ .env ถูกต้อง' };
  }
  if (err.code === 'ER_SP_DOES_NOT_EXIST') {
    return { status: 500, error: `ไม่พบ procedure ในฐานข้อมูล — รัน npm run db:api ก่อน (${CLIENT === 'oracle' ? 'api_procedures_oracle.sql' : 'api_procedures.sql'})` };
  }
  return { status: 500, error: 'เกิดข้อผิดพลาดของระบบ' };
}

const sendError = (res, err) => {
  const e = toError(err);
  res.status(e.status).json({ error: e.error, field: e.field || null });
};

const app = express();
app.use(express.json({ limit: '100kb' }));
app.use(session({
  name: 'mut_sid',
  secret: process.env.SESSION_SECRET || 'dev-secret-change-me',
  resave: false,
  saveUninitialized: false,
  rolling: true,
  cookie: { httpOnly: true, sameSite: 'lax', maxAge: 2 * 60 * 60 * 1000 }, // 2 ชั่วโมงนับจากใช้งานล่าสุด
}));

// เริ่ม session ใหม่ให้ผู้ใช้
function signIn(req, user) {
  return new Promise((ok, fail) => req.session.regenerate((e) => {
    if (e) return fail(e);
    req.session.uid = user.user_id;
    req.session.save((e2) => (e2 ? fail(e2) : ok()));
  }));
}

const safeNext = (n) => (typeof n === 'string' && n.startsWith('/') && !n.startsWith('//') ? n : null);

app.post('/api/login', async (req, res) => {
  try {
    const { username, password, next } = req.body || {};
    const [[user]] = await call('sp_login', [username ?? null, password ?? null]);
    // รหัสผ่าน bcrypt จากระบบเดิม: ตรวจที่นี่แล้วเปลี่ยนเป็น hash ของระบบนี้
    if (user.bcrypt_hash) {
      if (!(await bcrypt.compare(String(password), user.bcrypt_hash))) {
        return res.status(400).json({ error: 'password ไม่ถูกต้อง', field: 'password' });
      }
      await call('sp_set_password', [user.user_id, String(password)]);
    }
    await signIn(req, user);
    res.json({ redirect: safeNext(next) || user.landing });
  } catch (err) {
    sendError(res, err);
  }
});

app.post('/api/register', async (req, res) => {
  try {
    const b = req.body || {};
    const [[user]] = await call('sp_register', [b.name ?? null, b.email ?? null, b.username ?? null, b.password ?? null, b.confirm ?? null]);
    await signIn(req, user);
    res.json({ redirect: user.landing, message: `สมัครสมาชิกเรียบร้อยแล้ว ยินดีต้อนรับ ${user.name}` });
  } catch (err) {
    sendError(res, err);
  }
});

app.post('/api/logout', (req, res) => {
  req.session.destroy(() => {
    res.clearCookie('mut_sid');
    res.json({ redirect: '/login?out=1' });
  });
});

const toArg = (v) => {
  if (v === undefined || v === null) return null;
  if (typeof v === 'boolean') return v ? '1' : '0';
  if (typeof v === 'object') return JSON.stringify(v);
  return String(v);
};

app.post('/api/:name', async (req, res) => {
  const proc = `api_${String(req.params.name).toLowerCase()}`;
  if (!/^api_[a-z0-9_]+$/.test(proc)) return res.status(404).json({ error: 'ไม่พบ API' });
  if (!req.session.uid) return res.status(401).json({ error: 'กรุณาเข้าสู่ระบบก่อนใช้งาน', login: true });
  try {
    if (!apiParams || !apiParams[proc]) await loadApi(); // โหลดใหม่เผื่อเพิ่ง import procedure
    const params = apiParams[proc];
    if (!params) return res.status(404).json({ error: 'ไม่พบ API' });
    const body = req.body || {};
    const args = params.map((p) => (p === 'p_uid' ? req.session.uid : toArg(body[p.replace(/^p_/, '')])));
    res.json({ sets: await call(proc, args) });
  } catch (err) {
    sendError(res, err);
  }
});

// หน้าเว็บ (HTML/CSS/JS) — /search → public/search.html, /admin/ → public/admin/index.html
const PUBLIC = path.join(__dirname, 'public');
app.use(express.static(PUBLIC, { extensions: ['html'] }));
app.use((req, res) => res.status(404).sendFile(path.join(PUBLIC, 'not-found.html')));

// สร้างรอบการเดินรถล่วงหน้าจากตารางเวลาเดินรถ ตอนเปิดเว็บและทุกชั่วโมง
function ensureTrips() {
  db.ensureTrips()
    .catch((err) => console.error('สร้างรอบการเดินรถจากตารางเวลาไม่สำเร็จ:', toError(err).error));
}

const port = Number(process.env.PORT || 3000);
app.listen(port, () => {
  console.log(`BusBuddy running at http://localhost:${port}`);
  console.log(`ฐานข้อมูล: ${db.name} @ ${process.env.DB_HOST || '127.0.0.1'}`);
  ensureTrips();
  setInterval(ensureTrips, 60 * 60 * 1000).unref();
});
