// ติดตั้งฐานข้อมูลจากไฟล์ SQL (เลือกตาม DB_CLIENT ใน .env)
//
//   npm run db:api      ติดตั้ง/อัปเดตเฉพาะ procedure ของระบบ — ไม่แตะข้อมูลเดิม (ใช้กับฐานข้อมูลที่มีอยู่แล้ว)
//   npm run db:init     สร้างใหม่ทั้งหมด — ลบตารางและข้อมูลเดิมของระบบนี้ทิ้ง! แล้วใส่ข้อมูลตัวอย่าง
//                       --no-demo    ไม่ใส่ข้อมูลตัวอย่าง
//                       --no-history ไม่ใส่ข้อมูลย้อนหลังสำหรับรายงาน (เร็วกว่า)
//
//   Oracle: mut_shuttle_oracle.sql → api_procedures_oracle.sql → demo_data_oracle.sql → history_*_oracle.sql
//   MySQL : mut_shuttle.sql        → api_procedures.sql        → demo_data.sql        → history_*.sql
const fs = require('fs');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env'), quiet: true });

const DIR = path.join(__dirname, '..', 'database');
const CLIENT = (process.env.DB_CLIENT || 'mysql').toLowerCase();
const apiOnly = process.argv.includes('--api-only');
const withDemo = !apiOnly && !process.argv.includes('--no-demo');
const withHistory = withDemo && !process.argv.includes('--no-history');
const hasCode = (lines) => lines.some((l) => l.trim() && !l.trim().startsWith('--'));

// MySQL: แยกคำสั่งโดยรองรับ DELIMITER แบบเดียวกับ mysql client / phpMyAdmin
function splitMysql(text) {
  const statements = [];
  let delimiter = ';';
  let buf = [];
  for (const line of text.split(/\r?\n/)) {
    const d = line.match(/^\s*DELIMITER\s+(\S+)\s*$/i);
    if (d) { delimiter = d[1]; continue; }
    buf.push(line);
    const t = line.trimEnd();
    if (!t.trim().startsWith('--') && t.endsWith(delimiter)) {
      if (hasCode(buf)) {
        const sql = buf.join('\n').trimEnd();
        statements.push(sql.slice(0, sql.length - delimiter.length));
      }
      buf = [];
    }
  }
  if (hasCode(buf)) statements.push(buf.join('\n'));
  return statements;
}

// Oracle: แบบ SQL*Plus / SQL Developer — คำสั่งทั่วไปจบด้วย ; และ PL/SQL จบด้วยบรรทัด /
function splitOracle(text) {
  const statements = [];
  let buf = [];
  let plsql = false;
  for (const line of text.split(/\r?\n/)) {
    const t = line.trim();
    if (!hasCode(buf)) {
      if (!t || t.startsWith('--')) continue;
      plsql = /^(CREATE\s+(OR\s+REPLACE\s+)?(FUNCTION|PROCEDURE|TRIGGER|PACKAGE|TYPE)\b|BEGIN\b|DECLARE\b)/i.test(t);
    }
    if (plsql) {
      if (t === '/') { statements.push(buf.join('\n')); buf = []; plsql = false; } else buf.push(line);
      continue;
    }
    buf.push(line);
    if (!t.startsWith('--') && t.endsWith(';')) {
      statements.push(buf.join('\n').trim().replace(/;$/, ''));
      buf = [];
    }
  }
  if (hasCode(buf)) statements.push(buf.join('\n'));
  return statements;
}

async function runFile(exec, file, split) {
  const statements = split(fs.readFileSync(path.join(DIR, file), 'utf8'));
  for (const sql of statements) {
    try {
      await exec(sql);
    } catch (err) {
      console.error(`\n✗ ${file} ผิดพลาดที่คำสั่ง:\n${sql.slice(0, 400)}\n→ ${err.message}`);
      throw err;
    }
  }
  console.log(`✓ ${file} (${statements.length} คำสั่ง)`);
}

async function initMysql() {
  const mysql = require('mysql2/promise');
  const conn = await mysql.createConnection({
    host: process.env.DB_HOST || '127.0.0.1',
    port: Number(process.env.DB_PORT || 3306),
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || '',
    database: apiOnly ? (process.env.DB_NAME || 'mut_shuttle') : undefined,
    charset: 'utf8mb4',
  });
  const [[ver]] = await conn.query('SELECT VERSION() AS v');
  console.log(`เชื่อมต่อ MySQL/MariaDB ${ver.v}`);
  const exec = (sql) => conn.query(sql);
  if (!apiOnly) await runFile(exec, 'mut_shuttle.sql', splitMysql);
  await runFile(exec, 'api_procedures.sql', splitMysql);
  if (withDemo) await runFile(exec, 'demo_data.sql', splitMysql);
  if (withHistory) {
    await runFile(exec, 'history_2568.sql', splitMysql);
    await runFile(exec, 'history_2569.sql', splitMysql);
  }
  await conn.query('CALL sp_ensure_trips(CURDATE(), 8)');
  await conn.end();
}

async function initOracle() {
  const oracledb = require('oracledb');
  const conn = await oracledb.getConnection({
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    connectString: `${process.env.DB_HOST}:${process.env.DB_PORT || 1521}/${process.env.DB_SERVICE}`,
  });
  console.log(`เชื่อมต่อ Oracle ${conn.oracleServerVersionString} เป็นผู้ใช้ ${process.env.DB_USER}`);
  const exec = async (sql) => {
    await conn.execute(sql, [], { autoCommit: true });
    // CREATE ... ที่คอมไพล์ไม่ผ่าน Oracle ไม่ throw — ตรวจจาก user_errors แทน
    const m = sql.match(/^\s*CREATE\s+(?:OR\s+REPLACE\s+)?(FUNCTION|PROCEDURE|TRIGGER)\s+(\w+)/i);
    if (m) {
      const errs = await conn.execute(
        'SELECT line, position, text FROM user_errors WHERE name = :n ORDER BY sequence', [m[2].toUpperCase()],
      );
      if (errs.rows.length) throw new Error(errs.rows.map((r) => `line ${r[0]}:${r[1]} ${r[2]}`).join('\n'));
    }
  };
  if (!apiOnly) await runFile(exec, 'mut_shuttle_oracle.sql', splitOracle);
  await runFile(exec, 'api_procedures_oracle.sql', splitOracle);
  if (withDemo) await runFile(exec, 'demo_data_oracle.sql', splitOracle);
  if (withHistory) {
    await runFile(exec, 'history_2568_oracle.sql', splitOracle);
    await runFile(exec, 'history_2569_oracle.sql', splitOracle);
  }
  await conn.execute('BEGIN sp_ensure_trips(TRUNC(SYSDATE), 8); END;', [], { autoCommit: true });
  await conn.close();
}

(CLIENT === 'oracle' ? initOracle() : initMysql())
  .then(() => console.log(`✓ สร้างรอบการเดินรถ 8 วันข้างหน้าแล้ว\nเสร็จแล้ว — รัน npm start แล้วเปิด http://localhost:${process.env.PORT || 3000}`))
  .catch((err) => {
    if (['ECONNREFUSED', 'ETIMEDOUT', 'ENOTFOUND'].includes(err.code) || /^NJS-5\d\d|ORA-12\d\d\d/.test(err.message)) {
      console.error(`เชื่อมต่อฐานข้อมูลไม่ได้ (${err.code || err.message.split('\n')[0]}) — ตรวจสอบว่าเครื่องเข้าถึงเซิร์ฟเวอร์ได้ และค่าใน .env ถูกต้อง`);
    } else console.error(err.message);
    process.exit(1);
  });
