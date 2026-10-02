# BusBuddy — MUT Shuttle (เวอร์ชัน HTML/CSS/JS + SQL)

ระบบจองรถรับส่งและบริหารการเดินรถ แปลงจากเวอร์ชัน Node.js + EJS เดิม

| ส่วน | อยู่ที่ไหน | เขียนด้วย |
|---|---|---|
| หน้าเว็บ (Frontend) | `public/` — ไฟล์ `.html` ทุกหน้า, `css/app.css`, `js/app.js`, `js/pages/*.js` | HTML / CSS / JavaScript |
| หลังบ้าน (Backend / Business logic) | **Oracle:** `database/api_procedures_oracle.sql` · **MySQL:** `database/api_procedures.sql` — stored procedure `api_*` (ชื่อ/ผลลัพธ์เหมือนกันทั้ง 2 ฉบับ) | PL/SQL (Oracle 19c) / SQL (MySQL) |
| ตัวกลาง | `server.js` + `db/oracle.js`, `db/mysql.js` — รับ request จากหน้าเว็บ แล้วเรียก procedure | Node.js |

> ทำไมยังต้องมี `server.js`? — เบราว์เซอร์คุยกับ MySQL ตรงๆ ไม่ได้ และถ้าให้ต่อตรงได้ ใครก็อ่าน/แก้ฐานข้อมูลได้ทั้งหมด
> `server.js` จึงทำแค่ 3 อย่าง: เสิร์ฟไฟล์หน้าเว็บ, เก็บว่าใคร login อยู่ (session), และส่งต่อคำขอไปเรียก procedure — **ไม่มี logic ของระบบอยู่ในนั้น**

## ติดตั้งและรัน

เลือกฐานข้อมูลด้วย `DB_CLIENT` ในไฟล์ `.env` (ดูตัวอย่างใน `.env.example`)

### Oracle (เซิร์ฟเวอร์มหาวิทยาลัย — แบบโปรเจกต์เดิม)

1. ใส่ค่าใน `.env`: `DB_CLIENT=oracle`, `DB_HOST`, `DB_PORT`, `DB_SERVICE`, `DB_USER`, `DB_PASSWORD`
2. ในโฟลเดอร์นี้:
   ```bash
   npm install
   npm run db:api      # ติดตั้ง procedure ของระบบ — ใช้ตารางและข้อมูลเดิมที่มีอยู่แล้ว (ไม่ลบอะไร)
   npm start
   ```
   ถ้ายังไม่เคยมีตาราง หรืออยากล้างข้อมูลทั้งหมดแล้วเริ่มใหม่ ใช้ `npm run db:init` แทน `db:api` (**ลบตารางและข้อมูลเดิมของระบบนี้!**)
3. เปิด http://localhost:3000

> ใช้ SQL Developer แทนได้: เปิด `database/api_procedures_oracle.sql` → Run Script (F5)
> (ถ้าสร้างใหม่ทั้งหมด: `mut_shuttle_oracle.sql` → `api_procedures_oracle.sql` → `demo_data_oracle.sql` → `history_2568_oracle.sql`, `history_2569_oracle.sql`)
>
> เครื่องต้องเข้าถึงเซิร์ฟเวอร์ Oracle ได้ (เช่น ใช้เครือข่าย/VPN ของมหาวิทยาลัย) — ถ้าขึ้น `ETIMEDOUT` แปลว่าเชื่อมต่อเซิร์ฟเวอร์ไม่ถึง

### MySQL / MariaDB (XAMPP)

1. เปิด **XAMPP Control Panel** → Start **MySQL** แล้วตั้ง `.env` เป็น `DB_CLIENT=mysql` (ดู `.env.example`)
2. `npm install` → `npm run db:init` (สร้างฐานข้อมูล `mut_shuttle` ใหม่ + ข้อมูลตัวอย่าง) → `npm start`

> phpMyAdmin: import `mut_shuttle.sql` → `api_procedures.sql` → `demo_data.sql` → (ถ้าต้องการ) `history_2568.sql`, `history_2569.sql`

## บัญชีทดลอง (password = `1234`)

| username | บทบาท |
|---|---|
| `admin` | ผู้ดูแลระบบ — เข้าหลังบ้านได้ทุกหน้าจอ |
| `somchai`, `somying`, `somkuan` | พนักงาน — คนขับ |
| `manee` | นักศึกษา — จองรถ |

## หน้าเว็บ → procedure ที่เรียก

| หน้า | ไฟล์ | Procedure |
|---|---|---|
| เข้าสู่ระบบ / สมัครสมาชิก | `login.html`, `register.html` | `sp_login`, `sp_register` |
| หน้าหลัก | `index.html` | `api_home` |
| ค้นหารอบรถ | `search.html` | `api_search_form`, `api_search` |
| รายละเอียดรอบ / เลือกที่นั่ง / ยืนยัน | `trip.html`, `book.html`, `book-confirm.html` | `api_trip`, `api_book` |
| QR Code / การจองของฉัน | `item.html`, `my.html` | `api_item`, `api_my`, `api_cancel` |
| โปรไฟล์ | `profile.html` | `api_profile`, `api_change_password` |
| คนขับ | `driver/*.html` | `api_driver_today`, `api_driver_trip`, `api_driver_start`, `api_driver_scan`, `api_driver_checkin`, `api_driver_close_info`, `api_driver_close`, `api_driver_history` |
| Dashboard | `admin/index.html` | `api_dashboard` |
| แผนก / ตำแหน่ง / หน้าจอ / ประเภทรถ / รถ / จุดจอด / ตารางเวลาเดินรถ | `admin/<ชื่อ>.html` (ใช้ `js/pages/admin-crud.js` ร่วมกัน) | `api_<ชื่อ>_list`, `_get`, `_save`, `_delete` |
| ผู้ใช้งาน / พนักงาน | `admin/users.html`, `admin/user-form.html` | `api_users_*` |
| สิทธิ์ตามตำแหน่ง | `admin/permissions.html` | `api_permissions`, `api_permissions_save` |
| เส้นทาง | `admin/routes.html`, `route.html`, `route-form.html` | `api_routes_*` |
| รอบการเดินรถ | `admin/trips.html`, `trip-form.html` | `api_trips_*` |
| การจอง | `admin/bookings.html`, `booking.html` | `api_bookings_*` |
| รายงาน 1–7 | `admin/reports.html` | `api_report` |

## กติกาของ procedure (ถ้าจะเพิ่มหน้าใหม่)

- หน้าเว็บเรียก `MUT.api('ชื่อ', { ... })` → server เรียก `CALL api_ชื่อ(...)`
- พารามิเตอร์ตัวแรกต้องเป็น `p_uid` (server ใส่รหัสผู้ใช้ที่ login ให้เอง ส่งจากหน้าเว็บไม่ได้)
- พารามิเตอร์อื่นจับคู่ตามชื่อ: `p_date` ← ค่า `date` ที่หน้าเว็บส่งมา
- ตรวจสิทธิ์ด้วย `sp_require(p_uid, 'SC06', 'edit')` (ค่าว่าง = เข้าถึง, `add`, `edit`, `delete`)
- แจ้ง error — Oracle: `mut_err('ชื่อช่อง|ข้อความ')` (= `RAISE_APPLICATION_ERROR(-20001, ...)`) / MySQL: `SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ชื่อช่อง|ข้อความ'` — หน้าเว็บจะแสดงข้อความใต้ช่องนั้น
- คืนผลลัพธ์ — Oracle: `OPEN rc FOR SELECT ...; DBMS_SQL.RETURN_RESULT(rc);` / MySQL: `SELECT ...` (คืนได้หลายชุด)
  (`!denied|...` = ไม่มีสิทธิ์, `!notfound|...` = ไม่พบข้อมูล, ไม่มี `|` = ข้อความทั่วไป)
- เพิ่ม procedure ใหม่แล้วไม่ต้องแก้ `server.js` — server อ่านรายชื่อพารามิเตอร์จากฐานข้อมูลเอง (`user_arguments` / `information_schema`)
- บัญชี Oracle ไม่มีสิทธิ์ CREATE VIEW — ฉบับ Oracle ใช้ฟังก์ชัน `mut_*` และ procedure `sp_items` / `sp_trips` แทน view

## หมายเหตุ

- รอบการเดินรถของแต่ละวันสร้างอัตโนมัติจากตารางเวลาเดินรถ (`sp_ensure_trips`) ตอนเปิดเว็บ ทุกชั่วโมง และตอนค้นหาวันที่ล่วงหน้า
- รหัสผ่านตรวจใน SQL (Oracle: SHA-256 แบบเดียวกับข้อมูลเดิม / MySQL: SHA-256 + salt) — บัญชีที่เคย login ในเวอร์ชันเดิม (bcrypt) ยัง login ได้ และจะถูกแปลงเป็นแบบใหม่อัตโนมัติ
- QR Code สร้างในเบราว์เซอร์ (`js/vendor/qrcode.js` ใช้ได้แบบออฟไลน์) ส่วนกล้องสแกน QR และกราฟรายงานโหลดจาก CDN (ต้องมีอินเทอร์เน็ต)
