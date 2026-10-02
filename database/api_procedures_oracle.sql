-- =====================================================================
--  MUT Shuttle — หลังบ้าน (Business logic) ทั้งหมดเป็น PL/SQL สำหรับ Oracle 19c
--  ฉบับเดียวกับ api_procedures.sql (MySQL) — ชื่อ procedure / พารามิเตอร์ / คอลัมน์ที่คืนเหมือนกัน
--
--  วิธีใช้:  รันหลัง mut_shuttle_oracle.sql (หรือรันกับฐานข้อมูลเดิมที่มีตารางอยู่แล้วได้เลย ไม่ลบข้อมูล)
--           SQL Developer → เปิดไฟล์นี้ → Run Script (F5)  หรือ  npm run db:init
--
--  กติกา
--  - หน้าเว็บเรียกได้เฉพาะ procedure ที่ชื่อขึ้นต้นด้วย api_ ผ่าน server.js
--  - พารามิเตอร์ตัวแรก p_uid = ผู้ใช้ที่ login (server.js ใส่ให้จาก session)
--  - ผลลัพธ์คืนด้วย DBMS_SQL.RETURN_RESULT (implicit result) — คืนได้หลายชุดเหมือน MySQL
--  - ข้อผิดพลาดใช้ RAISE_APPLICATION_ERROR(-20001, 'ช่อง|ข้อความ')
--      ช่อง = ชื่อ input ที่ผิด / !denied = ไม่มีสิทธิ์ / !notfound = ไม่พบข้อมูล / ไม่มี | = ข้อความทั่วไป
--  - บัญชีไม่มีสิทธิ์ CREATE VIEW จึงใช้ฟังก์ชัน mut_* คำนวณค่า Derived แทน view
-- =====================================================================


-- =====================================================================
-- 1) ฟังก์ชันช่วยทั่วไป
-- =====================================================================

-- แจ้ง error
CREATE OR REPLACE PROCEDURE mut_err(p_msg IN VARCHAR2) IS
BEGIN
  RAISE_APPLICATION_ERROR(-20001, SUBSTR(p_msg, 1, 2000));
END;
/

-- สร้างรหัส เช่น ('TR', 7, 3) → 'TR007' (ตัวเลขยาวเกินก็ไม่ตัด)
CREATE OR REPLACE FUNCTION mut_fmt_id(p_prefix IN VARCHAR2, p_n IN NUMBER, p_pad IN NUMBER) RETURN VARCHAR2 DETERMINISTIC IS
BEGIN
  RETURN p_prefix || LPAD(TO_CHAR(p_n), GREATEST(p_pad, LENGTH(TO_CHAR(p_n))), '0');
END;
/

-- ค่าว่าง (Oracle ถือ '' = NULL) → 1
CREATE OR REPLACE FUNCTION mut_blank(p IN VARCHAR2) RETURN NUMBER DETERMINISTIC IS
BEGIN
  RETURN CASE WHEN TRIM(p) IS NULL THEN 1 ELSE 0 END;
END;
/

CREATE OR REPLACE FUNCTION mut_is_int(p IN VARCHAR2) RETURN NUMBER DETERMINISTIC IS
BEGIN
  RETURN CASE WHEN REGEXP_LIKE(TRIM(p), '^-?[0-9]{1,9}$') THEN 1 ELSE 0 END;
END;
/

-- 'YYYY-MM-DD' ที่เป็นวันที่จริง → DATE / ไม่ใช่ → NULL
CREATE OR REPLACE FUNCTION mut_to_date(p IN VARCHAR2) RETURN DATE DETERMINISTIC IS
BEGIN
  IF p IS NULL OR NOT REGEXP_LIKE(p, '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') THEN
    RETURN NULL;
  END IF;
  RETURN TO_DATE(p, 'YYYY-MM-DD');
EXCEPTION
  WHEN OTHERS THEN RETURN NULL;
END;
/

CREATE OR REPLACE FUNCTION mut_is_email(p IN VARCHAR2) RETURN NUMBER DETERMINISTIC IS
BEGIN
  RETURN CASE WHEN LENGTH(p) <= 150 AND REGEXP_LIKE(p, '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') THEN 1 ELSE 0 END;
END;
/

CREATE OR REPLACE FUNCTION mut_is_username(p IN VARCHAR2) RETURN NUMBER DETERMINISTIC IS
BEGIN
  RETURN CASE WHEN REGEXP_LIKE(p, '^[A-Za-z0-9_.-]{3,50}$') THEN 1 ELSE 0 END;
END;
/

-- 'HH:MI' หรือ 'HH:MI:SS' → 'HH24:MI:SS' (รูปแบบเวลาที่เก็บในตาราง) / ไม่ถูกต้อง → NULL
CREATE OR REPLACE FUNCTION mut_norm_time(p IN VARCHAR2) RETURN VARCHAR2 DETERMINISTIC IS
BEGIN
  IF p IS NULL OR NOT REGEXP_LIKE(p, '^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$') THEN
    RETURN NULL;
  END IF;
  RETURN SUBSTR(p, 1, 5) || ':00';
END;
/

-- เวลา 'HH24:MI:SS' + นาที → 'HH24:MI' (วนรอบ 24 ชั่วโมง)
CREATE OR REPLACE FUNCTION mut_time_add(p_time IN VARCHAR2, p_minutes IN NUMBER) RETURN VARCHAR2 DETERMINISTIC IS
  v NUMBER;
BEGIN
  v := MOD(TO_NUMBER(SUBSTR(p_time, 1, 2)) * 60 + TO_NUMBER(SUBSTR(p_time, 4, 2)) + NVL(p_minutes, 0), 1440);
  RETURN LPAD(TRUNC(v / 60), 2, '0') || ':' || LPAD(MOD(v, 60), 2, '0');
END;
/

-- เวลา 'HH24:MI:SS' → นาทีนับจากเที่ยงคืน
CREATE OR REPLACE FUNCTION mut_minutes_of(p_time IN VARCHAR2) RETURN NUMBER DETERMINISTIC IS
BEGIN
  RETURN TO_NUMBER(SUBSTR(p_time, 1, 2)) * 60 + TO_NUMBER(SUBSTR(p_time, 4, 2));
END;
/

-- วันในสัปดาห์ 0 = อาทิตย์ … 6 = เสาร์ (ไม่ขึ้นกับ NLS)
CREATE OR REPLACE FUNCTION mut_weekday(p IN DATE) RETURN NUMBER DETERMINISTIC IS
BEGIN
  RETURN MOD(TRUNC(p) - TRUNC(p, 'IW') + 1, 7);
END;
/

-- ชุดวันที่วิ่ง 2 ชุด (เช่น '12345' กับ '06') มีวันร่วมกันหรือไม่
CREATE OR REPLACE FUNCTION mut_days_overlap(a IN VARCHAR2, b IN VARCHAR2) RETURN NUMBER DETERMINISTIC IS
BEGIN
  FOR i IN 0 .. 6 LOOP
    IF INSTR(a, TO_CHAR(i)) > 0 AND INSTR(b, TO_CHAR(i)) > 0 THEN
      RETURN 1;
    END IF;
  END LOOP;
  RETURN 0;
END;
/

-- รหัสผ่าน: SHA-256 hex (รูปแบบเดียวกับข้อมูลเดิมและ trigger trg_users_password)
CREATE OR REPLACE FUNCTION mut_hash_password(p_password IN VARCHAR2) RETURN VARCHAR2 IS
  v VARCHAR2(64);
BEGIN
  SELECT LOWER(RAWTOHEX(STANDARD_HASH(p_password, 'SHA256'))) INTO v FROM dual;
  RETURN v;
END;
/

CREATE OR REPLACE FUNCTION mut_check_password(p_password IN VARCHAR2, p_hash IN VARCHAR2) RETURN NUMBER IS
BEGIN
  IF p_password IS NULL OR p_hash IS NULL OR NOT REGEXP_LIKE(p_hash, '^[0-9a-fA-F]{64}$') THEN
    RETURN 0;
  END IF;
  RETURN CASE WHEN mut_hash_password(p_password) = LOWER(p_hash) THEN 1 ELSE 0 END;
END;
/


-- =====================================================================
-- 2) ค่าที่คำนวณได้ (แทน view ของฉบับ MySQL)
-- =====================================================================

-- ที่นั่งที่ถูกจองของรอบ (ไม่นับรายการที่ยกเลิก)
CREATE OR REPLACE FUNCTION mut_booked_seats(p_trip IN VARCHAR2) RETURN NUMBER IS
  v NUMBER;
BEGIN
  SELECT NVL(SUM(seats), 0) INTO v FROM booking_items WHERE trip_id = p_trip AND status <> 'ยกเลิก';
  RETURN v;
END;
/

-- เวลาสะสมจากต้นทางถึงลำดับจุดจอด (นาที)
CREATE OR REPLACE FUNCTION mut_cum_minutes(p_route IN VARCHAR2, p_order IN NUMBER) RETURN NUMBER IS
  v NUMBER;
BEGIN
  IF p_order IS NULL THEN
    RETURN NULL;
  END IF;
  SELECT NVL(SUM(travel_minutes), 0) INTO v FROM route_stops WHERE route_id = p_route AND stop_order <= p_order;
  RETURN v;
END;
/

-- ลำดับจุดขึ้น = ลำดับแรกที่ตรง
CREATE OR REPLACE FUNCTION mut_board_order(p_route IN VARCHAR2, p_board IN VARCHAR2) RETURN NUMBER IS
  v NUMBER;
BEGIN
  SELECT MIN(stop_order) INTO v FROM route_stops WHERE route_id = p_route AND stop_id = p_board;
  RETURN v;
END;
/

-- ลำดับจุดลง = ลำดับแรกหลังจุดขึ้น
CREATE OR REPLACE FUNCTION mut_alight_order(p_route IN VARCHAR2, p_board IN VARCHAR2, p_alight IN VARCHAR2) RETURN NUMBER IS
  v NUMBER;
BEGIN
  SELECT MIN(stop_order) INTO v FROM route_stops
   WHERE route_id = p_route AND stop_id = p_alight AND stop_order > mut_board_order(p_route, p_board);
  RETURN v;
END;
/

-- เวลาที่รถของรอบถึงลำดับจุดจอด
CREATE OR REPLACE FUNCTION mut_stop_time(p_date IN DATE, p_time IN VARCHAR2, p_route IN VARCHAR2, p_order IN NUMBER) RETURN DATE IS
BEGIN
  IF p_order IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN mut_ts(p_date, p_time) + mut_cum_minutes(p_route, p_order) / 1440;
END;
/


-- =====================================================================
-- 3) สิทธิ์
-- =====================================================================

-- p_action = NULL (เข้าถึง) / 'add' / 'edit' / 'delete'
CREATE OR REPLACE FUNCTION mut_can(p_uid IN VARCHAR2, p_screen IN VARCHAR2, p_action IN VARCHAR2) RETURN NUMBER IS
  v NUMBER;
BEGIN
  SELECT MAX(CASE p_action WHEN 'add' THEN p.can_add WHEN 'edit' THEN p.can_edit WHEN 'delete' THEN p.can_delete ELSE 1 END)
    INTO v
    FROM employees e JOIN permissions p ON p.position_id = e.position_id AND p.screen_id = p_screen
   WHERE e.user_id = p_uid;
  RETURN NVL(v, 0);
END;
/

-- มีหน้าจอหลังบ้านอย่างน้อย 1 หน้าจอ (SC01–SC11) = เข้า Dashboard ได้
CREATE OR REPLACE FUNCTION mut_has_admin(p_uid IN VARCHAR2) RETURN NUMBER IS
  v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM employees e JOIN permissions p ON p.position_id = e.position_id
   WHERE e.user_id = p_uid
     AND p.screen_id IN ('SC01','SC02','SC03','SC04','SC05','SC06','SC07','SC08','SC09','SC10','SC11');
  RETURN CASE WHEN v > 0 THEN 1 ELSE 0 END;
END;
/

-- หน้าแรกหลัง login ตามสิทธิ์
CREATE OR REPLACE FUNCTION mut_landing(p_uid IN VARCHAR2) RETURN VARCHAR2 IS
BEGIN
  RETURN CASE WHEN mut_can(p_uid, 'SC12', NULL) = 1 THEN '/driver/'
              WHEN mut_has_admin(p_uid) = 1 THEN '/admin/'
              ELSE '/' END;
END;
/

CREATE OR REPLACE PROCEDURE sp_require(p_uid IN VARCHAR2, p_screen IN VARCHAR2, p_action IN VARCHAR2) IS
BEGIN
  IF p_uid IS NULL OR mut_can(p_uid, p_screen, p_action) = 0 THEN
    mut_err('!denied|ตำแหน่งของคุณไม่มีสิทธิ์ใช้งานส่วนนี้');
  END IF;
END;
/

CREATE OR REPLACE PROCEDURE sp_require_admin(p_uid IN VARCHAR2) IS
BEGIN
  IF p_uid IS NULL OR mut_has_admin(p_uid) = 0 THEN
    mut_err('!denied|ตำแหน่งของคุณไม่มีสิทธิ์ใช้งานหลังบ้าน');
  END IF;
END;
/


-- =====================================================================
-- 4) รอบการเดินรถอัตโนมัติจากตารางเวลาเดินรถ (trip_schedules)
--    - ข้ามวัน/ตารางเวลาที่มีรอบอยู่แล้ว (รวมรอบที่ถูกยกเลิก)
--    - สร้างเฉพาะวันที่ตรงกับวันที่วิ่ง (run_days: 0 = อาทิตย์ … 6 = เสาร์)
--    - รถไม่พร้อมใช้งาน / รถหรือคนขับชนเวลา (trigger ปฏิเสธ) → ข้ามรอบนั้น
--    - server.js เรียก sp_ensure_trips(TRUNC(SYSDATE), 8) ตอนเปิดเว็บและทุกชั่วโมง
-- =====================================================================

CREATE OR REPLACE PROCEDURE sp_ensure_trips(p_from IN DATE, p_days IN NUMBER) IS
  v_first DATE := GREATEST(TRUNC(p_from), TRUNC(SYSDATE));
  v_last  DATE := LEAST(TRUNC(p_from) + p_days - 1, TRUNC(SYSDATE) + 60);
  v_date  DATE;
  v_n     NUMBER;
  v_has   NUMBER;
BEGIN
  v_date := v_first;
  WHILE v_date <= v_last LOOP
    FOR s IN (SELECT schedule_id, route_id, depart_time, vehicle_id, driver_id, run_days
                FROM trip_schedules WHERE active = 1 ORDER BY depart_time, route_id) LOOP
      IF INSTR(s.run_days, TO_CHAR(mut_weekday(v_date))) > 0 THEN
        SELECT COUNT(*) INTO v_has FROM trips t
         WHERE t.trip_date = v_date
           AND (t.schedule_id = s.schedule_id OR (t.route_id = s.route_id AND t.depart_time = s.depart_time));
        IF v_has = 0 THEN
          BEGIN
            SELECT NVL(MAX(TO_NUMBER(SUBSTR(trip_id, 3))), 0) + 1 INTO v_n FROM trips WHERE REGEXP_LIKE(trip_id, '^TR[0-9]+$');
            INSERT INTO trips (trip_id, trip_date, depart_time, status, vehicle_id, route_id, driver_id, schedule_id)
            VALUES (mut_fmt_id('TR', v_n, 3), v_date, s.depart_time, 'เปิด', s.vehicle_id, s.route_id, s.driver_id, s.schedule_id);
          EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN NULL;
            WHEN OTHERS THEN
              IF SQLCODE <> -20001 THEN RAISE; END IF;   -- trigger ปฏิเสธ → ข้ามรอบนี้
          END;
        END IF;
      END IF;
    END LOOP;
    v_date := v_date + 1;
  END LOOP;
END;
/

-- ลบรอบล่วงหน้าของตารางเวลาที่ยังไม่มีการจอง
CREATE OR REPLACE PROCEDURE sp_remove_upcoming(p_schedule IN VARCHAR2) IS
BEGIN
  DELETE FROM trips
   WHERE schedule_id = p_schedule AND status = 'เปิด' AND mut_ts(trip_date, depart_time) > SYSDATE
     AND NOT EXISTS (SELECT 1 FROM booking_items bi WHERE bi.trip_id = trips.trip_id);
END;
/

-- จำนวนที่นั่งของรอบที่ยังเปิด = จำนวนที่นั่งของประเภทรถ (หลังแก้ประเภทรถ/รถ)
CREATE OR REPLACE PROCEDURE sp_sync_trip_seats IS
BEGIN
  UPDATE trips t
     SET seat_count = (SELECT vt.seat_count FROM vehicles v JOIN vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id
                        WHERE v.vehicle_id = t.vehicle_id)
   WHERE t.status = 'เปิด'
     AND t.seat_count <> (SELECT vt.seat_count FROM vehicles v JOIN vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id
                           WHERE v.vehicle_id = t.vehicle_id);
END;
/


-- =====================================================================
-- 5) ชุดข้อมูลที่ใช้ซ้ำหลายหน้า (แทน view v_item_details / v_trip_details)
-- =====================================================================

-- รายการจอง + รอบ/เส้นทาง/รถ/จุดจอด + สถานะที่แสดง + ยกเลิกได้หรือไม่ + แท็บ
-- ตัวกรองที่เป็น NULL = ไม่กรอง / p_order: 'board_desc' 'board_asc' 'booked_desc' 'item'
CREATE OR REPLACE PROCEDURE sp_items(
  p_user IN VARCHAR2, p_item IN VARCHAR2, p_booking IN VARCHAR2, p_trip IN VARCHAR2, p_route IN VARCHAR2,
  p_from IN DATE, p_to IN DATE, p_status IN VARCHAR2, p_q IN VARCHAR2,
  p_upcoming IN NUMBER, p_order IN VARCHAR2, p_limit IN NUMBER) IS
  rc SYS_REFCURSOR;
BEGIN
  OPEN rc FOR
    SELECT y.* FROM (
      SELECT x.*,
             CASE WHEN x.checkin_at IS NOT NULL AND x.status = 'ยืนยัน' THEN 'Check-in แล้ว' ELSE x.status END AS display_status,
             CASE WHEN x.status = 'ยืนยัน' AND x.checkin_at IS NULL AND x.trip_status = 'เปิด' THEN 1 ELSE 0 END AS can_cancel,
             CASE WHEN x.status = 'ยกเลิก' OR x.trip_status = 'ยกเลิก' THEN 'cancelled'
                  WHEN x.checkin_at IS NOT NULL OR x.status = 'No Show' OR x.trip_status = 'เสร็จสิ้น' THEN 'done'
                  ELSE 'upcoming' END AS tab
        FROM (
          SELECT bi.booking_item_id, bi.booking_id, bi.trip_id, bi.seats, bi.status, bi.checkin_at,
                 mut_stop_time(tr.trip_date, tr.depart_time, tr.route_id, mut_board_order(tr.route_id, bi.board_stop_id)) AS board_at,
                 mut_stop_time(tr.trip_date, tr.depart_time, tr.route_id,
                               mut_alight_order(tr.route_id, bi.board_stop_id, bi.alight_stop_id)) AS alight_at,
                 u.user_id, u.name AS passenger_name,
                 bi.board_stop_id, bi.alight_stop_id, sb.stop_name AS board_stop, sa.stop_name AS alight_stop,
                 tr.trip_date, tr.depart_time, tr.status AS trip_status, tr.route_id, r.route_name,
                 v.plate_no, vt.type_name, bi.qr_code, b.booked_at
            FROM booking_items bi
            JOIN bookings b       ON b.booking_id = bi.booking_id
            JOIN users u          ON u.user_id = b.user_id
            JOIN trips tr         ON tr.trip_id = bi.trip_id
            JOIN routes r         ON r.route_id = tr.route_id
            JOIN vehicles v       ON v.vehicle_id = tr.vehicle_id
            JOIN vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id
            JOIN stops sb         ON sb.stop_id = bi.board_stop_id
            JOIN stops sa         ON sa.stop_id = bi.alight_stop_id
           WHERE (p_user IS NULL OR b.user_id = p_user)
             AND (p_item IS NULL OR bi.booking_item_id = p_item)
             AND (p_booking IS NULL OR bi.booking_id = p_booking)
             AND (p_trip IS NULL OR bi.trip_id = p_trip)
             AND (p_route IS NULL OR tr.route_id = p_route)
             AND (p_from IS NULL OR tr.trip_date >= p_from)
             AND (p_to IS NULL OR tr.trip_date <= p_to)
             AND (p_q IS NULL OR bi.booking_id LIKE '%' || p_q || '%' OR bi.booking_item_id LIKE '%' || p_q || '%'
                  OR u.name LIKE '%' || p_q || '%' OR bi.qr_code = p_q)
             AND (NVL(p_upcoming, 0) = 0 OR (bi.status = 'ยืนยัน' AND bi.checkin_at IS NULL AND tr.status IN ('เปิด', 'กำลังเดินทาง')))
        ) x
    ) y
     WHERE (p_status IS NULL OR y.display_status = p_status)
       AND (NVL(p_upcoming, 0) <> 2 OR y.board_at >= TRUNC(SYSDATE))
     ORDER BY CASE WHEN p_order = 'board_asc' THEN y.board_at END ASC,
              CASE WHEN p_order = 'board_desc' THEN y.board_at END DESC,
              CASE WHEN p_order = 'booked_desc' THEN y.booked_at END DESC,
              CASE WHEN p_order = 'item_asc' THEN y.booking_item_id END ASC,
              y.booking_item_id DESC
     FETCH FIRST NVL(p_limit, 100000) ROWS ONLY;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

-- รอบการเดินรถ + เส้นทาง/รถ/คนขับ/ที่นั่ง/เวลารวม/เวลาถึงปลายทาง
-- ตัวกรองที่เป็น NULL = ไม่กรอง / p_order: 'date_desc' (วันที่ใหม่ก่อน) หรือ อื่นๆ (วันที่ เวลา เก่าก่อน)
CREATE OR REPLACE PROCEDURE sp_trips(
  p_trip IN VARCHAR2, p_driver IN VARCHAR2, p_from IN DATE, p_to IN DATE, p_route IN VARCHAR2,
  p_vehicle IN VARCHAR2, p_status IN VARCHAR2, p_no_cancelled IN NUMBER, p_order IN VARCHAR2, p_limit IN NUMBER) IS
  rc SYS_REFCURSOR;
BEGIN
  OPEN rc FOR
    SELECT x.*, x.seat_count - x.booked_seats AS remaining_seats,
           mut_ts(x.trip_date, x.depart_time) + x.total_minutes / 1440 AS end_at
      FROM (
        SELECT tr.trip_id, tr.trip_date, tr.depart_time, tr.status, tr.route_id, tr.vehicle_id, tr.driver_id,
               r.route_name, v.plate_no, vt.type_name, tr.seat_count, mut_booked_seats(tr.trip_id) AS booked_seats,
               mut_route_minutes(tr.route_id) AS total_minutes, u.name AS driver_name
          FROM trips tr
          JOIN routes r         ON r.route_id = tr.route_id
          JOIN vehicles v       ON v.vehicle_id = tr.vehicle_id
          JOIN vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id
          JOIN users u          ON u.user_id = tr.driver_id
         WHERE (p_trip IS NULL OR tr.trip_id = p_trip)
           AND (p_driver IS NULL OR tr.driver_id = p_driver)
           AND (p_from IS NULL OR tr.trip_date >= p_from)
           AND (p_to IS NULL OR tr.trip_date <= p_to)
           AND (p_route IS NULL OR tr.route_id = p_route)
           AND (p_vehicle IS NULL OR tr.vehicle_id = p_vehicle)
           AND (p_status IS NULL OR tr.status = p_status)
           AND (NVL(p_no_cancelled, 0) = 0 OR tr.status <> 'ยกเลิก')
      ) x
     ORDER BY CASE WHEN p_order = 'date_desc' THEN x.trip_date END DESC, x.trip_date, x.depart_time
     FETCH FIRST NVL(p_limit, 100000) ROWS ONLY;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

-- คืนข้อความ 1 แถว (คอลัมน์ message และ id ถ้ามี)
CREATE OR REPLACE PROCEDURE sp_message(p_message IN VARCHAR2, p_id IN VARCHAR2 DEFAULT NULL) IS
  rc SYS_REFCURSOR;
BEGIN
  OPEN rc FOR SELECT p_id AS id, p_message AS message FROM dual;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/


-- =====================================================================
-- 6) เข้าสู่ระบบ / สมัครสมาชิก (server.js เรียกตรง — ยังไม่มี session)
-- =====================================================================

-- รหัสผ่านแบบ bcrypt (ระบบเดิมเวอร์ชัน EJS) PL/SQL ตรวจไม่ได้ → คืน bcrypt_hash ให้ server.js ตรวจแทน
CREATE OR REPLACE PROCEDURE sp_login(p_username IN VARCHAR2, p_password IN VARCHAR2) IS
  v_id   users.user_id%TYPE;
  v_hash users.password_hash%TYPE;
  v_name VARCHAR2(400) := TRIM(p_username);
  rc     SYS_REFCURSOR;
BEGIN
  IF v_name IS NULL THEN
    mut_err('username|กรุณากรอก username');
  END IF;
  IF p_password IS NULL THEN
    mut_err('password|กรุณากรอก password');
  END IF;
  SELECT MAX(user_id), MAX(password_hash) INTO v_id, v_hash FROM users WHERE username = v_name;
  IF v_id IS NULL THEN
    mut_err('username|ไม่พบ username นี้ในระบบ');
  END IF;

  IF v_hash LIKE '$2%' THEN
    OPEN rc FOR SELECT user_id, name, username, password_hash AS bcrypt_hash, mut_landing(user_id) AS landing
                  FROM users WHERE user_id = v_id;
  ELSE
    IF mut_check_password(p_password, v_hash) = 0 THEN
      mut_err('password|password ไม่ถูกต้อง');
    END IF;
    OPEN rc FOR SELECT user_id, name, username, CAST(NULL AS VARCHAR2(1)) AS bcrypt_hash, mut_landing(user_id) AS landing
                  FROM users WHERE user_id = v_id;
  END IF;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

-- ใช้หลัง server.js ตรวจ bcrypt ผ่าน: เปลี่ยนเป็น hash ของระบบนี้
CREATE OR REPLACE PROCEDURE sp_set_password(p_uid IN VARCHAR2, p_password IN VARCHAR2) IS
BEGIN
  UPDATE users SET password_hash = mut_hash_password(p_password) WHERE user_id = p_uid;
END;
/

-- สมัครสมาชิก: ผู้ใช้บริการ (ไม่ใช่พนักงาน) อยู่แผนก D003 = นักศึกษา
CREATE OR REPLACE PROCEDURE sp_register(p_name IN VARCHAR2, p_email IN VARCHAR2, p_username IN VARCHAR2,
                                        p_password IN VARCHAR2, p_confirm IN VARCHAR2) IS
  v_name     VARCHAR2(400) := TRIM(p_name);
  v_email    VARCHAR2(400) := TRIM(p_email);
  v_username VARCHAR2(400) := TRIM(p_username);
  v_id       VARCHAR2(10);
  v_n        NUMBER;
  rc         SYS_REFCURSOR;
BEGIN
  IF v_name IS NULL THEN
    mut_err('name|กรุณากรอกชื่อ-นามสกุล');
  ELSIF LENGTH(v_name) > 100 THEN
    mut_err('name|ชื่อยาวได้ไม่เกิน 100 ตัวอักษร');
  ELSIF mut_is_email(v_email) = 0 THEN
    mut_err('email|รูปแบบ email ไม่ถูกต้อง');
  ELSIF mut_is_username(v_username) = 0 THEN
    mut_err('username|username ใช้ a-z, 0-9, _ . - ความยาว 3–50 ตัวอักษร');
  ELSIF NVL(LENGTH(p_password), 0) < 4 THEN
    mut_err('password|password ต้องมีอย่างน้อย 4 ตัวอักษร');
  ELSIF p_confirm IS NULL OR p_password <> p_confirm THEN
    mut_err('confirm|ยืนยัน password ไม่ตรงกัน');
  END IF;
  SELECT COUNT(*) INTO v_n FROM users WHERE email = v_email;
  IF v_n > 0 THEN mut_err('email|email นี้ถูกใช้แล้ว'); END IF;
  SELECT COUNT(*) INTO v_n FROM users WHERE username = v_username;
  IF v_n > 0 THEN mut_err('username|username นี้ถูกใช้แล้ว'); END IF;

  SELECT NVL(MAX(TO_NUMBER(SUBSTR(user_id, 2))), 0) + 1 INTO v_n FROM users WHERE REGEXP_LIKE(user_id, '^U[0-9]+$');
  v_id := mut_fmt_id('U', v_n, 3);
  INSERT INTO users (user_id, name, email, username, password_hash, department_id)
  VALUES (v_id, v_name, v_email, v_username, mut_hash_password(p_password), 'D003');

  OPEN rc FOR SELECT user_id, name, username, mut_landing(user_id) AS landing FROM users WHERE user_id = v_id;
  DBMS_SQL.RETURN_RESULT(rc);
EXCEPTION
  WHEN DUP_VAL_ON_INDEX THEN
    mut_err('username|username หรือ email นี้ถูกใช้แล้ว');
END;
/

-- ข้อมูลผู้ใช้ที่ login + สิทธิ์: ชุดที่ 1 = ผู้ใช้ / ชุดที่ 2 = สิทธิ์รายหน้าจอ
CREATE OR REPLACE PROCEDURE api_me(p_uid IN VARCHAR2) IS
  rc1 SYS_REFCURSOR;
  rc2 SYS_REFCURSOR;
BEGIN
  OPEN rc1 FOR
    SELECT u.user_id, u.name, u.username, e.position_id,
           mut_can(u.user_id, 'SC12', NULL) AS is_driver, mut_has_admin(u.user_id) AS has_admin,
           mut_landing(u.user_id) AS landing, TO_CHAR(SYSDATE, 'YYYY-MM-DD') AS today
      FROM users u LEFT JOIN employees e ON e.user_id = u.user_id
     WHERE u.user_id = p_uid;
  DBMS_SQL.RETURN_RESULT(rc1);
  OPEN rc2 FOR
    SELECT p.screen_id, p.can_add, p.can_edit, p.can_delete
      FROM employees e JOIN permissions p ON p.position_id = e.position_id
     WHERE e.user_id = p_uid ORDER BY p.screen_id;
  DBMS_SQL.RETURN_RESULT(rc2);
END;
/


-- =====================================================================
-- 7) ผู้ใช้บริการ (จองรถ)
-- =====================================================================

-- หน้าหลัก: ชุดที่ 1 = การเดินทางถัดไป (0–1 แถว) / ชุดที่ 2 = จำนวนรายการที่กำลังจะถึง
CREATE OR REPLACE PROCEDURE api_home(p_uid IN VARCHAR2) IS
  rc SYS_REFCURSOR;
BEGIN
  sp_items(p_uid, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 2, 'board_asc', 1);
  OPEN rc FOR
    SELECT COUNT(*) AS n
      FROM booking_items bi JOIN bookings b ON b.booking_id = bi.booking_id JOIN trips tr ON tr.trip_id = bi.trip_id
     WHERE b.user_id = p_uid AND bi.status = 'ยืนยัน' AND bi.checkin_at IS NULL AND tr.status IN ('เปิด', 'กำลังเดินทาง');
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

-- ตัวเลือกหน้าค้นหา: ชุดที่ 1 = จุดจอด / ชุดที่ 2 = ลำดับจุดจอดทุกเส้นทาง / ชุดที่ 3 = ช่วงวันที่ค้นหาได้
CREATE OR REPLACE PROCEDURE api_search_form(p_uid IN VARCHAR2) IS
  rc1 SYS_REFCURSOR;
  rc2 SYS_REFCURSOR;
  rc3 SYS_REFCURSOR;
BEGIN
  OPEN rc1 FOR SELECT stop_id, stop_name FROM stops ORDER BY stop_id;
  DBMS_SQL.RETURN_RESULT(rc1);
  OPEN rc2 FOR SELECT route_id, stop_id FROM route_stops ORDER BY route_id, stop_order;
  DBMS_SQL.RETURN_RESULT(rc2);
  OPEN rc3 FOR SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD') AS min_date, TO_CHAR(SYSDATE + 60, 'YYYY-MM-DD') AS max_date FROM dual;
  DBMS_SQL.RETURN_RESULT(rc3);
END;
/

-- ค้นหารอบรถที่จองได้ (สร้างรอบจากตารางเวลาให้ก่อนถ้ายังไม่มี)
CREATE OR REPLACE PROCEDURE api_search(p_uid IN VARCHAR2, p_date IN VARCHAR2, p_board IN VARCHAR2, p_alight IN VARCHAR2) IS
  v_date DATE := mut_to_date(p_date);
  rc     SYS_REFCURSOR;
BEGIN
  IF p_board IS NULL OR p_alight IS NULL THEN
    mut_err('กรุณาเลือกจุดขึ้นและจุดลง');
  ELSIF p_board = p_alight THEN
    mut_err('จุดขึ้นและจุดลงต้องไม่ใช่จุดเดียวกัน');
  ELSIF v_date IS NULL THEN
    mut_err('กรุณาเลือกวันที่');
  ELSIF v_date < TRUNC(SYSDATE) THEN
    mut_err('ไม่สามารถค้นหารอบของวันที่ผ่านมาแล้ว');
  ELSIF v_date > TRUNC(SYSDATE) + 60 THEN
    mut_err('ค้นหาล่วงหน้าได้ไม่เกิน 60 วัน');
  END IF;
  sp_ensure_trips(v_date, 1);
  sp_search_trips(v_date, p_board, p_alight, rc);
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

-- รายละเอียดรอบ + ช่วงจุดขึ้น/ลงที่เลือก + เหตุผลถ้าจองไม่ได้
-- ชุดที่ 1: รอบ (seg_remaining = ที่นั่งว่างเฉพาะช่วงที่เลือก, blocked = เหตุผลที่จองไม่ได้ หรือ NULL)
-- ชุดที่ 2: จุดจอดทั้งหมดของรอบพร้อมเวลาถึง
CREATE OR REPLACE PROCEDURE api_trip(p_uid IN VARCHAR2, p_trip IN VARCHAR2, p_board IN VARCHAR2, p_alight IN VARCHAR2) IS
  v_status    trips.status%TYPE;
  v_route     trips.route_id%TYPE;
  v_date      DATE;
  v_time      trips.depart_time%TYPE;
  v_seats     NUMBER;
  v_b         NUMBER;
  v_a         NUMBER;
  v_remaining NUMBER;
  v_bookable  NUMBER := 0;
  v_blocked   VARCHAR2(200);
  rc1         SYS_REFCURSOR;
  rc2         SYS_REFCURSOR;
BEGIN
  SELECT MAX(status), MAX(route_id), MAX(trip_date), MAX(depart_time), MAX(seat_count)
    INTO v_status, v_route, v_date, v_time, v_seats FROM trips WHERE trip_id = p_trip;
  IF v_status IS NULL THEN
    mut_err('!notfound|ไม่พบรอบการเดินรถ');
  END IF;

  -- จุดขึ้น = ลำดับแรกที่ตรง / จุดลง = ลำดับแรกหลังจุดขึ้น
  v_b := mut_board_order(v_route, p_board);
  v_a := mut_alight_order(v_route, p_board, p_alight);
  IF v_b IS NOT NULL AND v_a IS NOT NULL THEN
    v_remaining := mut_segment_remaining(p_trip, p_board, p_alight, NULL);
    v_bookable := CASE WHEN mut_stop_time(v_date, v_time, v_route, v_b) >= SYSDATE + 20 / 1440 THEN 1 ELSE 0 END;
  ELSE
    v_remaining := v_seats - mut_booked_seats(p_trip);
  END IF;

  v_blocked := CASE
    WHEN v_b IS NULL OR v_a IS NULL THEN 'เลือกจุดขึ้นและจุดลงจากหน้าค้นหาก่อนจอง'
    WHEN v_status <> 'เปิด' THEN 'รอบนี้ไม่เปิดให้จอง'
    WHEN v_bookable = 0 THEN 'ปิดรับจองแล้ว (ต้องจองก่อนรถถึงจุดขึ้นอย่างน้อย 20 นาที)'
    WHEN v_remaining <= 0 THEN 'ที่นั่งเต็มในช่วงจุดขึ้น–จุดลงนี้'
    ELSE NULL END;

  OPEN rc1 FOR
    SELECT tr.trip_id, tr.trip_date, tr.depart_time, tr.status, tr.route_id, r.route_name, v.plate_no, vt.type_name,
           tr.seat_count, mut_route_minutes(tr.route_id) AS total_minutes,
           mut_ts(tr.trip_date, tr.depart_time) + mut_route_minutes(tr.route_id) / 1440 AS end_at,
           v_remaining AS seg_remaining, LEAST(4, GREATEST(0, v_remaining)) AS max_seats,
           v_blocked AS blocked, v_b AS board_order, v_a AS alight_order
      FROM trips tr
      JOIN routes r         ON r.route_id = tr.route_id
      JOIN vehicles v       ON v.vehicle_id = tr.vehicle_id
      JOIN vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id
     WHERE tr.trip_id = p_trip;
  DBMS_SQL.RETURN_RESULT(rc1);

  OPEN rc2 FOR
    SELECT x.*, CASE WHEN x.arrive_at >= SYSDATE + 20 / 1440 THEN 1 ELSE 0 END AS bookable
      FROM (SELECT rs.stop_order, rs.stop_id, s.stop_name, mut_cum_minutes(rs.route_id, rs.stop_order) AS cum_minutes,
                   mut_stop_time(v_date, v_time, v_route, rs.stop_order) AS arrive_at
              FROM route_stops rs JOIN stops s ON s.stop_id = rs.stop_id
             WHERE rs.route_id = v_route) x
     ORDER BY x.stop_order;
  DBMS_SQL.RETURN_RESULT(rc2);
END;
/

-- สร้างการจอง (sp_create_booking ตรวจที่นั่ง/เวลาอีกครั้ง) → คืนรหัสรายการจอง
CREATE OR REPLACE PROCEDURE api_book(p_uid IN VARCHAR2, p_trip IN VARCHAR2, p_board IN VARCHAR2,
                                     p_alight IN VARCHAR2, p_seats IN VARCHAR2) IS
  v_booking VARCHAR2(10);
  v_item    VARCHAR2(10);
  v_qr      VARCHAR2(64);
  rc        SYS_REFCURSOR;
BEGIN
  IF mut_is_int(p_seats) = 0 THEN
    mut_err('seats|จองได้ 1–4 ที่นั่งต่อรายการ');
  END IF;
  sp_create_booking(p_uid, p_trip, p_board, p_alight, TO_NUMBER(p_seats), v_booking, v_item, v_qr);
  OPEN rc FOR SELECT v_booking AS booking_id, v_item AS item_id, v_qr AS qr_code FROM dual;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

-- รายการจองของตนเอง 1 รายการ (หน้า QR Code)
CREATE OR REPLACE PROCEDURE api_item(p_uid IN VARCHAR2, p_item IN VARCHAR2) IS
  v_n NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_n FROM booking_items bi JOIN bookings b ON b.booking_id = bi.booking_id
   WHERE bi.booking_item_id = p_item AND b.user_id = p_uid;
  IF v_n = 0 THEN
    mut_err('!notfound|ไม่พบรายการจอง');
  END IF;
  sp_items(p_uid, p_item, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, 'item', 1);
END;
/

-- การจองของฉันทั้งหมด (หน้าเว็บแยกแท็บจากคอลัมน์ tab)
CREATE OR REPLACE PROCEDURE api_my(p_uid IN VARCHAR2) IS
BEGIN
  sp_items(p_uid, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, 'board_desc', NULL);
END;
/

-- ยกเลิกรายการจองของตนเอง (ยืนยัน + ยังไม่ Check-in + รอบยังไม่เริ่มเดินทาง)
CREATE OR REPLACE PROCEDURE api_cancel(p_uid IN VARCHAR2, p_item IN VARCHAR2) IS
  v_can NUMBER;
  v_msg VARCHAR2(400);
BEGIN
  SELECT MAX(CASE WHEN bi.status = 'ยืนยัน' AND bi.checkin_at IS NULL AND tr.status = 'เปิด' THEN 1 ELSE 0 END),
         MAX('ยกเลิกรายการจอง ' || bi.booking_item_id || ' แล้ว — คืน ' || bi.seats || ' ที่นั่งให้รอบ '
             || SUBSTR(tr.depart_time, 1, 5) || ' ' || r.route_name)
    INTO v_can, v_msg
    FROM booking_items bi
    JOIN bookings b ON b.booking_id = bi.booking_id
    JOIN trips tr   ON tr.trip_id = bi.trip_id
    JOIN routes r   ON r.route_id = tr.route_id
   WHERE bi.booking_item_id = p_item AND b.user_id = p_uid;
  IF NVL(v_can, 0) = 0 THEN
    mut_err('รายการนี้ยกเลิกไม่ได้');
  END IF;
  sp_cancel_booking_item(p_item, p_uid);
  sp_message(v_msg);
END;
/

CREATE OR REPLACE PROCEDURE api_profile(p_uid IN VARCHAR2) IS
  rc SYS_REFCURSOR;
BEGIN
  OPEN rc FOR
    SELECT u.user_id, u.name, u.email, u.username, d.department_name, e.phone, p.position_name
      FROM users u
      JOIN departments d ON d.department_id = u.department_id
      LEFT JOIN employees e ON e.user_id = u.user_id
      LEFT JOIN positions p ON p.position_id = e.position_id
     WHERE u.user_id = p_uid;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

CREATE OR REPLACE PROCEDURE api_change_password(p_uid IN VARCHAR2, p_current IN VARCHAR2,
                                                p_password IN VARCHAR2, p_confirm IN VARCHAR2) IS
  v_hash users.password_hash%TYPE;
BEGIN
  SELECT MAX(password_hash) INTO v_hash FROM users WHERE user_id = p_uid;
  IF v_hash LIKE '$2%' THEN
    mut_err('current|กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่ 1 ครั้งก่อนเปลี่ยน password');
  ELSIF mut_check_password(p_current, v_hash) = 0 THEN
    mut_err('current|password ปัจจุบันไม่ถูกต้อง');
  ELSIF NVL(LENGTH(p_password), 0) < 4 THEN
    mut_err('password|password ใหม่ต้องมีอย่างน้อย 4 ตัวอักษร');
  ELSIF p_confirm IS NULL OR p_password <> p_confirm THEN
    mut_err('confirm|ยืนยัน password ไม่ตรงกัน');
  END IF;
  UPDATE users SET password_hash = mut_hash_password(p_password) WHERE user_id = p_uid;
  sp_message('เปลี่ยน password เรียบร้อยแล้ว');
END;
/


-- =====================================================================
-- 8) คนขับ (ต้องมีสิทธิ์หน้าจอ SC12 และเป็นรอบของตนเอง)
-- =====================================================================

CREATE OR REPLACE PROCEDURE sp_require_my_trip(p_uid IN VARCHAR2, p_trip IN VARCHAR2) IS
  v_driver trips.driver_id%TYPE;
BEGIN
  sp_require(p_uid, 'SC12', NULL);
  SELECT MAX(driver_id) INTO v_driver FROM trips WHERE trip_id = p_trip;
  IF v_driver IS NULL THEN
    mut_err('!notfound|ไม่พบรอบการเดินรถ');
  ELSIF v_driver <> p_uid THEN
    mut_err('!denied|รอบนี้ไม่ใช่รอบที่คุณได้รับมอบหมาย');
  END IF;
END;
/

-- จำนวนที่นั่ง จองแล้ว / Check-in / รอขึ้นรถ / No Show ของรอบ
CREATE OR REPLACE PROCEDURE sp_trip_counts(p_trip IN VARCHAR2) IS
  rc SYS_REFCURSOR;
BEGIN
  OPEN rc FOR
    SELECT NVL(SUM(seats), 0) AS booked,
           NVL(SUM(CASE WHEN checkin_at IS NOT NULL THEN seats END), 0) AS checked_in,
           NVL(SUM(CASE WHEN checkin_at IS NULL AND status = 'ยืนยัน' THEN seats END), 0) AS waiting,
           NVL(SUM(CASE WHEN status = 'No Show' THEN seats END), 0) AS no_show
      FROM booking_items WHERE trip_id = p_trip AND status <> 'ยกเลิก';
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

-- ชุดที่ 1 = งานวันนี้ / ชุดที่ 2 = งานที่จะถึงใน 7 วัน
CREATE OR REPLACE PROCEDURE api_driver_today(p_uid IN VARCHAR2) IS
BEGIN
  sp_require(p_uid, 'SC12', NULL);
  sp_trips(NULL, p_uid, TRUNC(SYSDATE), TRUNC(SYSDATE), NULL, NULL, NULL, 0, NULL, NULL);
  sp_trips(NULL, p_uid, TRUNC(SYSDATE) + 1, TRUNC(SYSDATE) + 7, NULL, NULL, NULL, 1, NULL, NULL);
END;
/

-- ชุดที่ 1 = รอบ (+ today) / ชุดที่ 2 = จำนวนที่นั่ง / ชุดที่ 3 = ผู้โดยสารขึ้น/ลงตามลำดับจุดจอด
CREATE OR REPLACE PROCEDURE api_driver_trip(p_uid IN VARCHAR2, p_trip IN VARCHAR2) IS
  rc1 SYS_REFCURSOR;
  rc3 SYS_REFCURSOR;
BEGIN
  sp_require_my_trip(p_uid, p_trip);
  OPEN rc1 FOR
    SELECT tr.trip_id, tr.trip_date, tr.depart_time, tr.status, tr.route_id, tr.vehicle_id, tr.driver_id,
           r.route_name, v.plate_no, vt.type_name, tr.seat_count, mut_booked_seats(tr.trip_id) AS booked_seats,
           mut_route_minutes(tr.route_id) AS total_minutes,
           mut_ts(tr.trip_date, tr.depart_time) + mut_route_minutes(tr.route_id) / 1440 AS end_at,
           TO_CHAR(SYSDATE, 'YYYY-MM-DD') AS today
      FROM trips tr
      JOIN routes r         ON r.route_id = tr.route_id
      JOIN vehicles v       ON v.vehicle_id = tr.vehicle_id
      JOIN vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id
     WHERE tr.trip_id = p_trip;
  DBMS_SQL.RETURN_RESULT(rc1);
  sp_trip_counts(p_trip);
  OPEN rc3 FOR
    WITH ts AS (
      SELECT rs.stop_order, s.stop_name, mut_stop_time(t.trip_date, t.depart_time, t.route_id, rs.stop_order) AS arrive_at
        FROM trips t JOIN route_stops rs ON rs.route_id = t.route_id JOIN stops s ON s.stop_id = rs.stop_id
       WHERE t.trip_id = p_trip
    ), it AS (
      SELECT bi.booking_item_id, u.name AS passenger_name, bi.seats, bi.checkin_at, bi.status,
             mut_board_order(t.route_id, bi.board_stop_id) AS board_order,
             mut_alight_order(t.route_id, bi.board_stop_id, bi.alight_stop_id) AS alight_order
        FROM booking_items bi
        JOIN trips t    ON t.trip_id = bi.trip_id
        JOIN bookings b ON b.booking_id = bi.booking_id
        JOIN users u    ON u.user_id = b.user_id
       WHERE bi.trip_id = p_trip AND bi.status <> 'ยกเลิก'
    )
    SELECT ts.stop_order, ts.stop_name, ts.arrive_at,
           it.booking_item_id, it.passenger_name, it.seats, it.checkin_at, it.status,
           CASE WHEN it.board_order = ts.stop_order THEN 1 ELSE 0 END AS is_up,
           CASE WHEN it.alight_order = ts.stop_order THEN 1 ELSE 0 END AS is_down
      FROM ts LEFT JOIN it ON it.board_order = ts.stop_order OR it.alight_order = ts.stop_order
     ORDER BY ts.stop_order, it.booking_item_id;
  DBMS_SQL.RETURN_RESULT(rc3);
END;
/

-- เริ่มการเดินทาง (เฉพาะรอบของวันนี้)
CREATE OR REPLACE PROCEDURE api_driver_start(p_uid IN VARCHAR2, p_trip IN VARCHAR2) IS
  v_date DATE;
BEGIN
  sp_require_my_trip(p_uid, p_trip);
  SELECT MAX(trip_date) INTO v_date FROM trips WHERE trip_id = p_trip;
  IF v_date <> TRUNC(SYSDATE) THEN
    mut_err('เริ่มการเดินทางได้เฉพาะรอบของวันนี้ — รอบนี้เดินรถวันที่ ' || TO_CHAR(v_date, 'DD/MM/YYYY'));
  END IF;
  sp_start_trip(p_trip, p_uid);
  sp_message('เริ่มการเดินทางแล้ว — สแกน QR ผู้โดยสารได้เลย');
END;
/

-- หน้าสแกน: ชุดที่ 1 = รอบ / ชุดที่ 2 = จำนวนที่นั่ง
CREATE OR REPLACE PROCEDURE api_driver_scan(p_uid IN VARCHAR2, p_trip IN VARCHAR2) IS
BEGIN
  sp_require_my_trip(p_uid, p_trip);
  sp_trips(p_trip, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL);
  sp_trip_counts(p_trip);
END;
/

-- สแกน QR Check-in: ชุดที่ 1 = ผลการ Check-in / ชุดที่ 2 = จำนวนที่นั่งล่าสุด
CREATE OR REPLACE PROCEDURE api_driver_checkin(p_uid IN VARCHAR2, p_trip IN VARCHAR2, p_qr IN VARCHAR2) IS
  rc SYS_REFCURSOR;
BEGIN
  sp_require_my_trip(p_uid, p_trip);
  IF TRIM(p_qr) IS NULL THEN
    mut_err('qr|กรุณาสแกนหรือกรอกรหัส QR');
  END IF;
  sp_checkin(TRIM(p_qr), p_trip, rc);
  DBMS_SQL.RETURN_RESULT(rc);
  sp_trip_counts(p_trip);
END;
/

-- หน้าสรุปก่อนปิดงาน: ชุดที่ 1 = รอบ / ชุดที่ 2 = จำนวนที่นั่ง / ชุดที่ 3 = รายการที่จะเป็น No Show
CREATE OR REPLACE PROCEDURE api_driver_close_info(p_uid IN VARCHAR2, p_trip IN VARCHAR2) IS
  v_status trips.status%TYPE;
  rc       SYS_REFCURSOR;
BEGIN
  sp_require_my_trip(p_uid, p_trip);
  SELECT MAX(status) INTO v_status FROM trips WHERE trip_id = p_trip;
  IF v_status <> 'กำลังเดินทาง' THEN
    mut_err('ปิดงานได้เฉพาะรอบที่กำลังเดินทาง');
  END IF;
  sp_trips(p_trip, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL);
  sp_trip_counts(p_trip);
  OPEN rc FOR
    SELECT bi.booking_item_id, u.name AS passenger_name, bi.seats, s.stop_name AS board_stop,
           mut_stop_time(t.trip_date, t.depart_time, t.route_id, mut_board_order(t.route_id, bi.board_stop_id)) AS board_at
      FROM booking_items bi
      JOIN trips t    ON t.trip_id = bi.trip_id
      JOIN bookings b ON b.booking_id = bi.booking_id
      JOIN users u    ON u.user_id = b.user_id
      JOIN stops s    ON s.stop_id = bi.board_stop_id
     WHERE bi.trip_id = p_trip AND bi.status = 'ยืนยัน' AND bi.checkin_at IS NULL
     ORDER BY board_at;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

-- ปิดงาน: ไม่ได้ Check-in → No Show และสรุปผล (ชุดที่ 1 = สรุป / ชุดที่ 2 = รายชื่อ No Show)
CREATE OR REPLACE PROCEDURE api_driver_close(p_uid IN VARCHAR2, p_trip IN VARCHAR2) IS
  rc1 SYS_REFCURSOR;
  rc2 SYS_REFCURSOR;
BEGIN
  sp_require_my_trip(p_uid, p_trip);
  sp_close_trip(p_trip, rc1, rc2);
  DBMS_SQL.RETURN_RESULT(rc1);
  DBMS_SQL.RETURN_RESULT(rc2);
END;
/

-- ประวัติรอบที่ขับ (200 รอบล่าสุด)
CREATE OR REPLACE PROCEDURE api_driver_history(p_uid IN VARCHAR2) IS
  rc SYS_REFCURSOR;
BEGIN
  sp_require(p_uid, 'SC12', NULL);
  OPEN rc FOR
    SELECT tr.trip_id, tr.trip_date, tr.depart_time, tr.status, r.route_name, v.plate_no, vt.type_name,
           NVL(SUM(CASE WHEN bi.status <> 'ยกเลิก' THEN bi.seats END), 0) AS booked,
           NVL(SUM(CASE WHEN bi.checkin_at IS NOT NULL THEN bi.seats END), 0) AS actual,
           NVL(SUM(CASE WHEN bi.status = 'No Show' THEN bi.seats END), 0) AS no_show
      FROM trips tr
      JOIN routes r         ON r.route_id = tr.route_id
      JOIN vehicles v       ON v.vehicle_id = tr.vehicle_id
      JOIN vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id
      LEFT JOIN booking_items bi ON bi.trip_id = tr.trip_id
     WHERE tr.driver_id = p_uid AND (tr.trip_date < TRUNC(SYSDATE) OR tr.status IN ('เสร็จสิ้น', 'ยกเลิก'))
     GROUP BY tr.trip_id, tr.trip_date, tr.depart_time, tr.status, r.route_name, v.plate_no, vt.type_name
     ORDER BY tr.trip_date DESC, tr.depart_time DESC
     FETCH FIRST 200 ROWS ONLY;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/


-- =====================================================================
-- 9) หลังบ้าน: Dashboard + ตัวเลือกในฟอร์ม
-- =====================================================================

-- ชุดที่ 1 = ตัวเลขสรุปวันนี้ / ชุดที่ 2 = รอบวันนี้ / ชุดที่ 3 = รายการจองล่าสุด 8 รายการ
CREATE OR REPLACE PROCEDURE api_dashboard(p_uid IN VARCHAR2) IS
  rc SYS_REFCURSOR;
BEGIN
  sp_require_admin(p_uid);
  OPEN rc FOR
    SELECT
      (SELECT COUNT(*) FROM booking_items bi JOIN bookings b ON b.booking_id = bi.booking_id
        WHERE TRUNC(b.booked_at) = TRUNC(SYSDATE))                                           AS items_today,
      (SELECT COUNT(*) FROM trips WHERE trip_date = TRUNC(SYSDATE) AND status <> 'ยกเลิก')    AS trips_today,
      (SELECT NVL(SUM(bi.seats), 0) FROM booking_items bi JOIN trips t ON t.trip_id = bi.trip_id
        WHERE t.trip_date = TRUNC(SYSDATE) AND bi.status <> 'ยกเลิก')                         AS seats_today,
      (SELECT NVL(SUM(bi.seats), 0) FROM booking_items bi JOIN trips t ON t.trip_id = bi.trip_id
        WHERE t.trip_date = TRUNC(SYSDATE) AND bi.checkin_at IS NOT NULL)                      AS checkin_today,
      (SELECT COUNT(*) FROM booking_items bi JOIN trips t ON t.trip_id = bi.trip_id
        WHERE t.trip_date = TRUNC(SYSDATE) AND bi.status = 'No Show')                         AS noshow_today,
      (SELECT COUNT(*) FROM vehicles WHERE status = 'พร้อมใช้งาน')                              AS vehicles_ready,
      (SELECT COUNT(*) FROM vehicles)                                                          AS vehicles_total,
      TO_CHAR(SYSDATE, 'YYYY-MM-DD')                                                           AS today
      FROM dual;
  DBMS_SQL.RETURN_RESULT(rc);
  sp_trips(NULL, NULL, TRUNC(SYSDATE), TRUNC(SYSDATE), NULL, NULL, NULL, 0, NULL, NULL);
  sp_items(NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, 'booked_desc', 8);
END;
/

-- ตัวเลือกที่ใช้ในฟอร์ม/ตัวกรองหลังบ้าน (ลำดับชุดข้อมูลคงที่)
-- 1 ประเภทรถ 2 เส้นทาง 3 รถ 4 คนขับ 5 แผนก 6 ตำแหน่ง 7 จุดจอด 8 หน้าจอ
CREATE OR REPLACE PROCEDURE api_lookups(p_uid IN VARCHAR2) IS
  rc1 SYS_REFCURSOR; rc2 SYS_REFCURSOR; rc3 SYS_REFCURSOR; rc4 SYS_REFCURSOR;
  rc5 SYS_REFCURSOR; rc6 SYS_REFCURSOR; rc7 SYS_REFCURSOR; rc8 SYS_REFCURSOR;
BEGIN
  sp_require_admin(p_uid);
  OPEN rc1 FOR SELECT vehicle_type_id, type_name, seat_count FROM vehicle_types ORDER BY vehicle_type_id;
  DBMS_SQL.RETURN_RESULT(rc1);
  OPEN rc2 FOR SELECT route_id, route_name, mut_route_minutes(route_id) AS total_minutes FROM routes ORDER BY route_id;
  DBMS_SQL.RETURN_RESULT(rc2);
  OPEN rc3 FOR SELECT v.vehicle_id, v.plate_no, v.status, vt.type_name, vt.seat_count
                 FROM vehicles v JOIN vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id ORDER BY v.plate_no;
  DBMS_SQL.RETURN_RESULT(rc3);
  -- คนขับ = พนักงานที่ตำแหน่งมีสิทธิ์หน้าจองานคนขับ (SC12)
  OPEN rc4 FOR SELECT u.user_id, u.name, p.position_name
                 FROM employees e JOIN users u ON u.user_id = e.user_id JOIN positions p ON p.position_id = e.position_id
                WHERE e.position_id IN (SELECT position_id FROM permissions WHERE screen_id = 'SC12')
                ORDER BY u.name;
  DBMS_SQL.RETURN_RESULT(rc4);
  OPEN rc5 FOR SELECT department_id, department_name FROM departments ORDER BY department_id;
  DBMS_SQL.RETURN_RESULT(rc5);
  OPEN rc6 FOR SELECT position_id, position_name FROM positions ORDER BY position_id;
  DBMS_SQL.RETURN_RESULT(rc6);
  OPEN rc7 FOR SELECT stop_id, stop_name FROM stops ORDER BY stop_id;
  DBMS_SQL.RETURN_RESULT(rc7);
  OPEN rc8 FOR SELECT screen_id, screen_name FROM screens ORDER BY screen_id;
  DBMS_SQL.RETURN_RESULT(rc8);
END;
/


-- =====================================================================
-- 10) หลังบ้าน: ข้อมูลหลัก (list / get / save / delete)
--     save: p_id ว่าง = เพิ่ม (ต้องมีสิทธิ์ add) / มีค่า = แก้ไข (ต้องมีสิทธิ์ edit)
-- =====================================================================

-- ---------- 10.3 แผนก (SC08) ----------
CREATE OR REPLACE PROCEDURE api_departments_list(p_uid IN VARCHAR2, p_q IN VARCHAR2) IS
  v_q VARCHAR2(200) := TRIM(p_q);
  rc  SYS_REFCURSOR;
BEGIN
  sp_require(p_uid, 'SC08', NULL);
  OPEN rc FOR
    SELECT d.department_id, d.department_name,
           (SELECT COUNT(*) FROM users u WHERE u.department_id = d.department_id) AS user_count
      FROM departments d
     WHERE v_q IS NULL OR d.department_id LIKE '%' || v_q || '%' OR d.department_name LIKE '%' || v_q || '%'
     ORDER BY d.department_id;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

CREATE OR REPLACE PROCEDURE api_departments_get(p_uid IN VARCHAR2, p_id IN VARCHAR2) IS
  v_n NUMBER;
  rc  SYS_REFCURSOR;
BEGIN
  sp_require(p_uid, 'SC08', 'edit');
  SELECT COUNT(*) INTO v_n FROM departments WHERE department_id = p_id;
  IF v_n = 0 THEN mut_err('!notfound|ไม่พบแผนก'); END IF;
  OPEN rc FOR SELECT * FROM departments WHERE department_id = p_id;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

CREATE OR REPLACE PROCEDURE api_departments_save(p_uid IN VARCHAR2, p_id IN VARCHAR2, p_department_name IN VARCHAR2) IS
  v_name VARCHAR2(400) := TRIM(p_department_name);
  v_id   VARCHAR2(10);
  v_n    NUMBER;
BEGIN
  sp_require(p_uid, 'SC08', CASE WHEN p_id IS NULL THEN 'add' ELSE 'edit' END);
  IF v_name IS NULL THEN
    mut_err('department_name|กรุณากรอกชื่อแผนก');
  ELSIF LENGTH(v_name) > 100 THEN
    mut_err('department_name|ชื่อแผนกยาวได้ไม่เกิน 100 ตัวอักษร');
  END IF;
  IF p_id IS NULL THEN
    SELECT NVL(MAX(TO_NUMBER(SUBSTR(department_id, 2))), 0) + 1 INTO v_n FROM departments WHERE REGEXP_LIKE(department_id, '^D[0-9]+$');
    v_id := mut_fmt_id('D', v_n, 3);
    INSERT INTO departments (department_id, department_name) VALUES (v_id, v_name);
    sp_message('เพิ่มแผนก ' || v_id || ' เรียบร้อยแล้ว', v_id);
  ELSE
    UPDATE departments SET department_name = v_name WHERE department_id = p_id;
    IF SQL%ROWCOUNT = 0 THEN mut_err('!notfound|ไม่พบแผนก'); END IF;
    sp_message('บันทึกแผนก ' || p_id || ' เรียบร้อยแล้ว', p_id);
  END IF;
END;
/

CREATE OR REPLACE PROCEDURE api_departments_delete(p_uid IN VARCHAR2, p_id IN VARCHAR2) IS
  v_n NUMBER;
BEGIN
  sp_require(p_uid, 'SC08', 'delete');
  SELECT COUNT(*) INTO v_n FROM users WHERE department_id = p_id;
  IF v_n > 0 THEN mut_err('ลบไม่ได้ เนื่องจากมีผู้ใช้งาน ' || v_n || ' คนอยู่ในแผนกนี้'); END IF;
  DELETE FROM departments WHERE department_id = p_id;
  sp_message('ลบแผนก ' || p_id || ' เรียบร้อยแล้ว');
END;
/

-- ---------- 10.4 ตำแหน่ง (SC09) ----------
CREATE OR REPLACE PROCEDURE api_positions_list(p_uid IN VARCHAR2, p_q IN VARCHAR2) IS
  v_q VARCHAR2(200) := TRIM(p_q);
  rc  SYS_REFCURSOR;
BEGIN
  sp_require(p_uid, 'SC09', NULL);
  OPEN rc FOR
    SELECT p.position_id, p.position_name,
           (SELECT COUNT(*) FROM employees e WHERE e.position_id = p.position_id) AS employee_count,
           (SELECT COUNT(*) FROM permissions x WHERE x.position_id = p.position_id) AS screen_count
      FROM positions p
     WHERE v_q IS NULL OR p.position_id LIKE '%' || v_q || '%' OR p.position_name LIKE '%' || v_q || '%'
     ORDER BY p.position_id;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

CREATE OR REPLACE PROCEDURE api_positions_get(p_uid IN VARCHAR2, p_id IN VARCHAR2) IS
  v_n NUMBER;
  rc  SYS_REFCURSOR;
BEGIN
  sp_require(p_uid, 'SC09', 'edit');
  SELECT COUNT(*) INTO v_n FROM positions WHERE position_id = p_id;
  IF v_n = 0 THEN mut_err('!notfound|ไม่พบตำแหน่ง'); END IF;
  OPEN rc FOR SELECT * FROM positions WHERE position_id = p_id;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

CREATE OR REPLACE PROCEDURE api_positions_save(p_uid IN VARCHAR2, p_id IN VARCHAR2, p_position_name IN VARCHAR2) IS
  v_name VARCHAR2(400) := TRIM(p_position_name);
  v_id   VARCHAR2(10);
  v_n    NUMBER;
BEGIN
  sp_require(p_uid, 'SC09', CASE WHEN p_id IS NULL THEN 'add' ELSE 'edit' END);
  IF v_name IS NULL THEN
    mut_err('position_name|กรุณากรอกชื่อตำแหน่ง');
  ELSIF LENGTH(v_name) > 100 THEN
    mut_err('position_name|ชื่อตำแหน่งยาวได้ไม่เกิน 100 ตัวอักษร');
  END IF;
  IF p_id IS NULL THEN
    SELECT NVL(MAX(TO_NUMBER(SUBSTR(position_id, 2))), 0) + 1 INTO v_n FROM positions WHERE REGEXP_LIKE(position_id, '^P[0-9]+$');
    v_id := mut_fmt_id('P', v_n, 2);
    INSERT INTO positions (position_id, position_name) VALUES (v_id, v_name);
    sp_message('เพิ่มตำแหน่ง ' || v_id || ' เรียบร้อยแล้ว', v_id);
  ELSE
    UPDATE positions SET position_name = v_name WHERE position_id = p_id;
    IF SQL%ROWCOUNT = 0 THEN mut_err('!notfound|ไม่พบตำแหน่ง'); END IF;
    sp_message('บันทึกตำแหน่ง ' || p_id || ' เรียบร้อยแล้ว', p_id);
  END IF;
END;
/

CREATE OR REPLACE PROCEDURE api_positions_delete(p_uid IN VARCHAR2, p_id IN VARCHAR2) IS
  v_n NUMBER;
BEGIN
  sp_require(p_uid, 'SC09', 'delete');
  SELECT COUNT(*) INTO v_n FROM employees WHERE position_id = p_id;
  IF v_n > 0 THEN mut_err('ลบไม่ได้ เนื่องจากมีพนักงาน ' || v_n || ' คนอยู่ในตำแหน่งนี้'); END IF;
  DELETE FROM positions WHERE position_id = p_id;   -- สิทธิ์ของตำแหน่งลบตาม (CASCADE)
  sp_message('ลบตำแหน่ง ' || p_id || ' เรียบร้อยแล้ว');
END;
/

-- ---------- 10.5 หน้าจอ (SC10) ----------
CREATE OR REPLACE PROCEDURE api_screens_list(p_uid IN VARCHAR2, p_q IN VARCHAR2) IS
  v_q VARCHAR2(200) := TRIM(p_q);
  rc  SYS_REFCURSOR;
BEGIN
  sp_require(p_uid, 'SC10', NULL);
  OPEN rc FOR
    SELECT s.screen_id, s.screen_name,
           (SELECT COUNT(*) FROM permissions p WHERE p.screen_id = s.screen_id) AS position_count
      FROM screens s
     WHERE v_q IS NULL OR s.screen_id LIKE '%' || v_q || '%' OR s.screen_name LIKE '%' || v_q || '%'
     ORDER BY s.screen_id;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

CREATE OR REPLACE PROCEDURE api_screens_get(p_uid IN VARCHAR2, p_id IN VARCHAR2) IS
  v_n NUMBER;
  rc  SYS_REFCURSOR;
BEGIN
  sp_require(p_uid, 'SC10', 'edit');
  SELECT COUNT(*) INTO v_n FROM screens WHERE screen_id = p_id;
  IF v_n = 0 THEN mut_err('!notfound|ไม่พบหน้าจอ'); END IF;
  OPEN rc FOR SELECT * FROM screens WHERE screen_id = p_id;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

CREATE OR REPLACE PROCEDURE api_screens_save(p_uid IN VARCHAR2, p_id IN VARCHAR2, p_screen_name IN VARCHAR2) IS
  v_name VARCHAR2(400) := TRIM(p_screen_name);
  v_id   VARCHAR2(10);
  v_n    NUMBER;
BEGIN
  sp_require(p_uid, 'SC10', CASE WHEN p_id IS NULL THEN 'add' ELSE 'edit' END);
  IF v_name IS NULL THEN
    mut_err('screen_name|กรุณากรอกชื่อหน้าจอ');
  ELSIF LENGTH(v_name) > 100 THEN
    mut_err('screen_name|ชื่อหน้าจอยาวได้ไม่เกิน 100 ตัวอักษร');
  END IF;
  IF p_id IS NULL THEN
    SELECT NVL(MAX(TO_NUMBER(SUBSTR(screen_id, 3))), 0) + 1 INTO v_n FROM screens WHERE REGEXP_LIKE(screen_id, '^SC[0-9]+$');
    v_id := mut_fmt_id('SC', v_n, 2);
    INSERT INTO screens (screen_id, screen_name) VALUES (v_id, v_name);
    sp_message('เพิ่มหน้าจอ ' || v_id || ' เรียบร้อยแล้ว', v_id);
  ELSE
    UPDATE screens SET screen_name = v_name WHERE screen_id = p_id;
    IF SQL%ROWCOUNT = 0 THEN mut_err('!notfound|ไม่พบหน้าจอ'); END IF;
    sp_message('บันทึกหน้าจอ ' || p_id || ' เรียบร้อยแล้ว', p_id);
  END IF;
END;
/

CREATE OR REPLACE PROCEDURE api_screens_delete(p_uid IN VARCHAR2, p_id IN VARCHAR2) IS
BEGIN
  sp_require(p_uid, 'SC10', 'delete');
  IF p_id IN ('SC01','SC02','SC03','SC04','SC05','SC06','SC07','SC08','SC09','SC10','SC11','SC12') THEN
    mut_err('หน้าจอนี้ถูกใช้งานโดยระบบ ลบไม่ได้');
  END IF;
  DELETE FROM screens WHERE screen_id = p_id;
  sp_message('ลบหน้าจอ ' || p_id || ' เรียบร้อยแล้ว');
END;
/

-- ---------- 10.7 ประเภทรถ (SC03) ----------
CREATE OR REPLACE PROCEDURE api_vehicle_types_list(p_uid IN VARCHAR2, p_q IN VARCHAR2) IS
  v_q VARCHAR2(200) := TRIM(p_q);
  rc  SYS_REFCURSOR;
BEGIN
  sp_require(p_uid, 'SC03', NULL);
  OPEN rc FOR
    SELECT vt.vehicle_type_id, vt.type_name, vt.description, vt.seat_count,
           (SELECT COUNT(*) FROM vehicles v WHERE v.vehicle_type_id = vt.vehicle_type_id) AS vehicle_count
      FROM vehicle_types vt
     WHERE v_q IS NULL OR vt.vehicle_type_id LIKE '%' || v_q || '%'
        OR vt.type_name LIKE '%' || v_q || '%' OR vt.description LIKE '%' || v_q || '%'
     ORDER BY vt.vehicle_type_id;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

CREATE OR REPLACE PROCEDURE api_vehicle_types_get(p_uid IN VARCHAR2, p_id IN VARCHAR2) IS
  v_n NUMBER;
  rc  SYS_REFCURSOR;
BEGIN
  sp_require(p_uid, 'SC03', 'edit');
  SELECT COUNT(*) INTO v_n FROM vehicle_types WHERE vehicle_type_id = p_id;
  IF v_n = 0 THEN mut_err('!notfound|ไม่พบประเภทรถ'); END IF;
  OPEN rc FOR SELECT * FROM vehicle_types WHERE vehicle_type_id = p_id;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

CREATE OR REPLACE PROCEDURE api_vehicle_types_save(p_uid IN VARCHAR2, p_id IN VARCHAR2, p_type_name IN VARCHAR2,
                                                   p_description IN VARCHAR2, p_seat_count IN VARCHAR2) IS
  v_name VARCHAR2(400) := TRIM(p_type_name);
  v_desc VARCHAR2(2000) := TRIM(p_description);
  v_id   VARCHAR2(10);
  v_n    NUMBER;
BEGIN
  sp_require(p_uid, 'SC03', CASE WHEN p_id IS NULL THEN 'add' ELSE 'edit' END);
  IF v_name IS NULL THEN
    mut_err('type_name|กรุณากรอกชื่อประเภทรถ');
  ELSIF LENGTH(v_name) > 50 THEN
    mut_err('type_name|ชื่อประเภทรถยาวได้ไม่เกิน 50 ตัวอักษร');
  ELSIF NVL(LENGTH(v_desc), 0) > 255 THEN
    mut_err('description|รายละเอียดยาวได้ไม่เกิน 255 ตัวอักษร');
  ELSIF TRIM(p_seat_count) IS NULL THEN
    mut_err('seat_count|กรุณากรอกจำนวนที่นั่ง');
  ELSIF mut_is_int(p_seat_count) = 0 THEN
    mut_err('seat_count|จำนวนที่นั่งต้องเป็นจำนวนเต็ม');
  ELSIF TO_NUMBER(p_seat_count) < 1 THEN
    mut_err('seat_count|จำนวนที่นั่งต้องไม่น้อยกว่า 1');
  END IF;
  IF p_id IS NULL THEN
    SELECT NVL(MAX(TO_NUMBER(SUBSTR(vehicle_type_id, 2))), 0) + 1 INTO v_n FROM vehicle_types WHERE REGEXP_LIKE(vehicle_type_id, '^T[0-9]+$');
    v_id := mut_fmt_id('T', v_n, 2);
    INSERT INTO vehicle_types (vehicle_type_id, type_name, description, seat_count) VALUES (v_id, v_name, v_desc, TO_NUMBER(p_seat_count));
    sp_message('เพิ่มประเภทรถ ' || v_id || ' เรียบร้อยแล้ว', v_id);
  ELSE
    UPDATE vehicle_types SET type_name = v_name, description = v_desc, seat_count = TO_NUMBER(p_seat_count)
     WHERE vehicle_type_id = p_id;
    IF SQL%ROWCOUNT = 0 THEN mut_err('!notfound|ไม่พบประเภทรถ'); END IF;
    sp_sync_trip_seats;
    sp_message('บันทึกประเภทรถ ' || p_id || ' เรียบร้อยแล้ว', p_id);
  END IF;
END;
/

CREATE OR REPLACE PROCEDURE api_vehicle_types_delete(p_uid IN VARCHAR2, p_id IN VARCHAR2) IS
  v_n NUMBER;
BEGIN
  sp_require(p_uid, 'SC03', 'delete');
  SELECT COUNT(*) INTO v_n FROM vehicles WHERE vehicle_type_id = p_id;
  IF v_n > 0 THEN mut_err('ลบไม่ได้ เนื่องจากมีรถ ' || v_n || ' คันเป็นประเภทนี้'); END IF;
  DELETE FROM vehicle_types WHERE vehicle_type_id = p_id;
  sp_message('ลบประเภทรถ ' || p_id || ' เรียบร้อยแล้ว');
END;
/

-- ---------- 10.8 รถ (SC01) ----------
CREATE OR REPLACE PROCEDURE api_vehicles_list(p_uid IN VARCHAR2, p_q IN VARCHAR2, p_vehicle_type_id IN VARCHAR2, p_status IN VARCHAR2) IS
  v_q VARCHAR2(200) := TRIM(p_q);
  rc  SYS_REFCURSOR;
BEGIN
  sp_require(p_uid, 'SC01', NULL);
  OPEN rc FOR
    SELECT v.vehicle_id, v.plate_no, v.vehicle_type_id, vt.type_name, vt.seat_count, v.status
      FROM vehicles v JOIN vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id
     WHERE (v_q IS NULL OR v.vehicle_id LIKE '%' || v_q || '%' OR v.plate_no LIKE '%' || v_q || '%')
       AND (p_vehicle_type_id IS NULL OR v.vehicle_type_id = p_vehicle_type_id)
       AND (p_status IS NULL OR v.status = p_status)
     ORDER BY v.vehicle_id;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

CREATE OR REPLACE PROCEDURE api_vehicles_get(p_uid IN VARCHAR2, p_id IN VARCHAR2) IS
  v_n NUMBER;
  rc  SYS_REFCURSOR;
BEGIN
  sp_require(p_uid, 'SC01', 'edit');
  SELECT COUNT(*) INTO v_n FROM vehicles WHERE vehicle_id = p_id;
  IF v_n = 0 THEN mut_err('!notfound|ไม่พบรถ'); END IF;
  OPEN rc FOR SELECT * FROM vehicles WHERE vehicle_id = p_id;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

CREATE OR REPLACE PROCEDURE api_vehicles_save(p_uid IN VARCHAR2, p_id IN VARCHAR2, p_plate_no IN VARCHAR2,
                                              p_vehicle_type_id IN VARCHAR2, p_status IN VARCHAR2) IS
  v_plate VARCHAR2(400) := TRIM(p_plate_no);
  v_id    VARCHAR2(10);
  v_n     NUMBER;
BEGIN
  sp_require(p_uid, 'SC01', CASE WHEN p_id IS NULL THEN 'add' ELSE 'edit' END);
  SELECT COUNT(*) INTO v_n FROM vehicle_types WHERE vehicle_type_id = p_vehicle_type_id;
  IF v_plate IS NULL THEN
    mut_err('plate_no|กรุณากรอกทะเบียนรถ');
  ELSIF LENGTH(v_plate) > 20 THEN
    mut_err('plate_no|ทะเบียนรถยาวได้ไม่เกิน 20 ตัวอักษร');
  ELSIF v_n = 0 THEN
    mut_err('vehicle_type_id|กรุณาเลือกประเภทรถ');
  ELSIF p_status IS NULL OR p_status NOT IN ('พร้อมใช้งาน', 'ซ่อมบำรุง', 'ไม่พร้อมใช้งาน') THEN
    mut_err('status|กรุณาเลือกสถานะ');
  END IF;
  SELECT COUNT(*) INTO v_n FROM vehicles WHERE plate_no = v_plate AND vehicle_id <> NVL(p_id, '-');
  IF v_n > 0 THEN mut_err('plate_no|ทะเบียนรถนี้มีอยู่ในระบบแล้ว'); END IF;

  IF p_id IS NULL THEN
    SELECT NVL(MAX(TO_NUMBER(SUBSTR(vehicle_id, 2))), 0) + 1 INTO v_n FROM vehicles WHERE REGEXP_LIKE(vehicle_id, '^V[0-9]+$');
    v_id := mut_fmt_id('V', v_n, 3);
    INSERT INTO vehicles (vehicle_id, plate_no, status, vehicle_type_id) VALUES (v_id, v_plate, p_status, p_vehicle_type_id);
    sp_message('เพิ่มรถ ' || v_id || ' เรียบร้อยแล้ว', v_id);
  ELSE
    UPDATE vehicles SET plate_no = v_plate, status = p_status, vehicle_type_id = p_vehicle_type_id WHERE vehicle_id = p_id;
    IF SQL%ROWCOUNT = 0 THEN mut_err('!notfound|ไม่พบรถ'); END IF;
    sp_sync_trip_seats;
    sp_message('บันทึกรถ ' || p_id || ' เรียบร้อยแล้ว', p_id);
  END IF;
END;
/

CREATE OR REPLACE PROCEDURE api_vehicles_delete(p_uid IN VARCHAR2, p_id IN VARCHAR2) IS
  v_n NUMBER;
BEGIN
  sp_require(p_uid, 'SC01', 'delete');
  SELECT (SELECT COUNT(*) FROM trips WHERE vehicle_id = p_id) + (SELECT COUNT(*) FROM trip_schedules WHERE vehicle_id = p_id)
    INTO v_n FROM dual;
  IF v_n > 0 THEN
    mut_err('ลบไม่ได้ เนื่องจากรถคันนี้ถูกใช้ใน ' || v_n || ' รอบ/ตารางเวลา — เปลี่ยนสถานะเป็น "ไม่พร้อมใช้งาน" แทน');
  END IF;
  DELETE FROM vehicles WHERE vehicle_id = p_id;
  sp_message('ลบรถ ' || p_id || ' เรียบร้อยแล้ว');
END;
/

-- ---------- 10.9 จุดจอด (SC04) ----------
CREATE OR REPLACE PROCEDURE api_stops_list(p_uid IN VARCHAR2, p_q IN VARCHAR2) IS
  v_q VARCHAR2(200) := TRIM(p_q);
  rc  SYS_REFCURSOR;
BEGIN
  sp_require(p_uid, 'SC04', NULL);
  OPEN rc FOR
    SELECT s.stop_id, s.stop_name,
           (SELECT COUNT(DISTINCT rs.route_id) FROM route_stops rs WHERE rs.stop_id = s.stop_id) AS route_count,
           (SELECT COUNT(*) FROM booking_items bi WHERE bi.board_stop_id = s.stop_id OR bi.alight_stop_id = s.stop_id) AS item_count
      FROM stops s
     WHERE v_q IS NULL OR s.stop_id LIKE '%' || v_q || '%' OR s.stop_name LIKE '%' || v_q || '%'
     ORDER BY s.stop_id;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

CREATE OR REPLACE PROCEDURE api_stops_get(p_uid IN VARCHAR2, p_id IN VARCHAR2) IS
  v_n NUMBER;
  rc  SYS_REFCURSOR;
BEGIN
  sp_require(p_uid, 'SC04', 'edit');
  SELECT COUNT(*) INTO v_n FROM stops WHERE stop_id = p_id;
  IF v_n = 0 THEN mut_err('!notfound|ไม่พบจุดจอด'); END IF;
  OPEN rc FOR SELECT * FROM stops WHERE stop_id = p_id;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

CREATE OR REPLACE PROCEDURE api_stops_save(p_uid IN VARCHAR2, p_id IN VARCHAR2, p_stop_name IN VARCHAR2) IS
  v_name VARCHAR2(400) := TRIM(p_stop_name);
  v_id   VARCHAR2(10);
  v_n    NUMBER;
BEGIN
  sp_require(p_uid, 'SC04', CASE WHEN p_id IS NULL THEN 'add' ELSE 'edit' END);
  IF v_name IS NULL THEN
    mut_err('stop_name|กรุณากรอกชื่อจุดจอด');
  ELSIF LENGTH(v_name) > 150 THEN
    mut_err('stop_name|ชื่อจุดจอดยาวได้ไม่เกิน 150 ตัวอักษร');
  END IF;
  IF p_id IS NULL THEN
    SELECT NVL(MAX(TO_NUMBER(SUBSTR(stop_id, 2))), 0) + 1 INTO v_n FROM stops WHERE REGEXP_LIKE(stop_id, '^S[0-9]+$');
    v_id := mut_fmt_id('S', v_n, 3);
    INSERT INTO stops (stop_id, stop_name) VALUES (v_id, v_name);
    sp_message('เพิ่มจุดจอด ' || v_id || ' เรียบร้อยแล้ว', v_id);
  ELSE
    UPDATE stops SET stop_name = v_name WHERE stop_id = p_id;
    IF SQL%ROWCOUNT = 0 THEN mut_err('!notfound|ไม่พบจุดจอด'); END IF;
    sp_message('บันทึกจุดจอด ' || p_id || ' เรียบร้อยแล้ว', p_id);
  END IF;
END;
/

CREATE OR REPLACE PROCEDURE api_stops_delete(p_uid IN VARCHAR2, p_id IN VARCHAR2) IS
  v_routes NUMBER;
  v_items  NUMBER;
BEGIN
  sp_require(p_uid, 'SC04', 'delete');
  SELECT COUNT(DISTINCT route_id) INTO v_routes FROM route_stops WHERE stop_id = p_id;
  SELECT COUNT(*) INTO v_items FROM booking_items WHERE board_stop_id = p_id OR alight_stop_id = p_id;
  IF v_routes > 0 OR v_items > 0 THEN
    mut_err('ลบจุดจอดไม่ได้ เนื่องจากถูกใช้ใน ' || v_routes || ' เส้นทาง และ ' || v_items || ' รายการจอง');
  END IF;
  DELETE FROM stops WHERE stop_id = p_id;
  sp_message('ลบจุดจอด ' || p_id || ' เรียบร้อยแล้ว');
END;
/

-- ---------- ตารางเวลาเดินรถ (SC06) ----------
CREATE OR REPLACE PROCEDURE api_schedules_list(p_uid IN VARCHAR2, p_route_id IN VARCHAR2, p_driver_id IN VARCHAR2) IS
  rc SYS_REFCURSOR;
BEGIN
  sp_require(p_uid, 'SC06', NULL);
  OPEN rc FOR
    SELECT x.* FROM (
      SELECT s.schedule_id, s.route_id, r.route_name, s.depart_time, s.vehicle_id, s.driver_id, s.run_days, s.active,
             ROW_NUMBER() OVER (PARTITION BY s.route_id ORDER BY s.depart_time) AS round_no,
             v.plate_no, vt.type_name, vt.seat_count, u.name AS driver_name,
             CASE WHEN s.active = 1 THEN 'ใช้งาน' ELSE 'หยุดใช้งาน' END AS active_label
        FROM trip_schedules s
        JOIN routes r         ON r.route_id = s.route_id
        JOIN vehicles v       ON v.vehicle_id = s.vehicle_id
        JOIN vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id
        JOIN users u          ON u.user_id = s.driver_id
    ) x
     WHERE (p_route_id IS NULL OR x.route_id = p_route_id)
       AND (p_driver_id IS NULL OR x.driver_id = p_driver_id)
     ORDER BY x.route_id, x.depart_time;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

CREATE OR REPLACE PROCEDURE api_schedules_get(p_uid IN VARCHAR2, p_id IN VARCHAR2) IS
  v_n NUMBER;
  rc  SYS_REFCURSOR;
BEGIN
  sp_require(p_uid, 'SC06', 'edit');
  SELECT COUNT(*) INTO v_n FROM trip_schedules WHERE schedule_id = p_id;
  IF v_n = 0 THEN mut_err('!notfound|ไม่พบตารางเวลา'); END IF;
  OPEN rc FOR
    SELECT schedule_id, route_id, SUBSTR(depart_time, 1, 5) AS depart_time, vehicle_id, driver_id, run_days, active
      FROM trip_schedules WHERE schedule_id = p_id;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

-- ตรวจรถ/คนขับชนเวลากับตารางเวลาอื่นที่ใช้งานอยู่และมีวันวิ่งร่วมกัน แล้วสร้างรอบล่วงหน้าใหม่ตามค่าล่าสุด
CREATE OR REPLACE PROCEDURE api_schedules_save(p_uid IN VARCHAR2, p_id IN VARCHAR2, p_route_id IN VARCHAR2,
                                               p_depart_time IN VARCHAR2, p_run_days IN VARCHAR2, p_driver_id IN VARCHAR2,
                                               p_vehicle_id IN VARCHAR2, p_active IN VARCHAR2) IS
  v_time     VARCHAR2(8) := mut_norm_time(p_depart_time);
  v_id       VARCHAR2(10);
  v_n        NUMBER;
  v_start    NUMBER;
  v_end      NUMBER;
  v_conflict VARCHAR2(300);
  v_msg      VARCHAR2(300);
BEGIN
  sp_require(p_uid, 'SC06', CASE WHEN p_id IS NULL THEN 'add' ELSE 'edit' END);
  SELECT COUNT(*) INTO v_n FROM routes WHERE route_id = p_route_id;
  IF v_n = 0 THEN mut_err('route_id|กรุณาเลือกเส้นทาง'); END IF;
  IF v_time IS NULL THEN mut_err('depart_time|กรุณาระบุเวลาออก'); END IF;
  IF p_run_days IS NULL OR p_run_days NOT IN ('12345', '123456', '0123456', '06') THEN mut_err('run_days|กรุณาเลือกวันที่วิ่ง'); END IF;
  SELECT COUNT(*) INTO v_n FROM employees e
   WHERE e.user_id = p_driver_id AND e.position_id IN (SELECT position_id FROM permissions WHERE screen_id = 'SC12');
  IF v_n = 0 THEN mut_err('driver_id|กรุณาเลือกคนขับ'); END IF;
  SELECT COUNT(*) INTO v_n FROM vehicles WHERE vehicle_id = p_vehicle_id;
  IF v_n = 0 THEN mut_err('vehicle_id|กรุณาเลือกรถ'); END IF;
  IF p_active IS NULL OR p_active NOT IN ('0', '1') THEN mut_err('active|กรุณาเลือกสถานะ'); END IF;
  SELECT COUNT(*) INTO v_n FROM trip_schedules
   WHERE route_id = p_route_id AND depart_time = v_time AND schedule_id <> NVL(p_id, '-');
  IF v_n > 0 THEN mut_err('depart_time|เส้นทางนี้มีรอบเวลานี้อยู่แล้ว'); END IF;

  IF p_active = '1' THEN
    v_start := mut_minutes_of(v_time);
    v_end := v_start + GREATEST(1, mut_route_minutes(p_route_id));
    FOR c IN (
      SELECT s.schedule_id || ' ' || r.route_name || ' ' || SUBSTR(s.depart_time, 1, 5) || '–'
             || mut_time_add(s.depart_time, mut_route_minutes(s.route_id)) AS label,
             CASE WHEN s.vehicle_id = p_vehicle_id THEN 'vehicle' ELSE 'driver' END AS kind
        FROM trip_schedules s JOIN routes r ON r.route_id = s.route_id
       WHERE s.active = 1 AND s.schedule_id <> NVL(p_id, '-')
         AND (s.vehicle_id = p_vehicle_id OR s.driver_id = p_driver_id)
         AND mut_days_overlap(s.run_days, p_run_days) = 1
         AND mut_minutes_of(s.depart_time) < v_end
         AND v_start < mut_minutes_of(s.depart_time) + GREATEST(1, mut_route_minutes(s.route_id))
       ORDER BY 2 DESC
       FETCH FIRST 1 ROWS ONLY) LOOP
      IF c.kind = 'vehicle' THEN
        mut_err('vehicle_id|รถคันนี้ถูกใช้ในตารางเวลา ' || c.label);
      ELSE
        mut_err('driver_id|คนขับคนนี้มีงานในตารางเวลา ' || c.label);
      END IF;
    END LOOP;
  END IF;

  IF p_id IS NULL THEN
    SELECT NVL(MAX(TO_NUMBER(SUBSTR(schedule_id, 3))), 0) + 1 INTO v_n FROM trip_schedules WHERE REGEXP_LIKE(schedule_id, '^TS[0-9]+$');
    v_id := mut_fmt_id('TS', v_n, 3);
    INSERT INTO trip_schedules (schedule_id, route_id, depart_time, vehicle_id, driver_id, run_days, active)
    VALUES (v_id, p_route_id, v_time, p_vehicle_id, p_driver_id, p_run_days, TO_NUMBER(p_active));
    v_msg := 'เพิ่มตารางเวลาเดินรถ ' || v_id || ' เรียบร้อยแล้ว';
  ELSE
    v_id := p_id;
    UPDATE trip_schedules
       SET route_id = p_route_id, depart_time = v_time, vehicle_id = p_vehicle_id, driver_id = p_driver_id,
           run_days = p_run_days, active = TO_NUMBER(p_active)
     WHERE schedule_id = p_id;
    IF SQL%ROWCOUNT = 0 THEN mut_err('!notfound|ไม่พบตารางเวลา'); END IF;
    v_msg := 'บันทึกตารางเวลาเดินรถ ' || p_id || ' เรียบร้อยแล้ว';
  END IF;

  -- ลบรอบล่วงหน้าที่ยังไม่มีคนจองแล้วสร้างใหม่ตามค่าล่าสุด (รอบที่มีการจองแล้วคงไว้)
  sp_remove_upcoming(v_id);
  sp_ensure_trips(TRUNC(SYSDATE), 8);
  sp_message(v_msg, v_id);
END;
/

CREATE OR REPLACE PROCEDURE api_schedules_delete(p_uid IN VARCHAR2, p_id IN VARCHAR2) IS
BEGIN
  sp_require(p_uid, 'SC06', 'delete');
  sp_remove_upcoming(p_id);   -- รอบล่วงหน้าที่ยังไม่มีคนจองถูกลบด้วย / รอบอื่น schedule_id เป็น NULL
  DELETE FROM trip_schedules WHERE schedule_id = p_id;
  sp_message('ลบตารางเวลาเดินรถ ' || p_id || ' เรียบร้อยแล้ว');
END;
/


-- =====================================================================
-- 11) หลังบ้าน: ผู้ใช้งาน / พนักงาน (SC07) และสิทธิ์ตามตำแหน่ง (SC10)
-- =====================================================================

-- p_type: employee = เฉพาะพนักงาน / user = เฉพาะผู้ใช้บริการทั่วไป
CREATE OR REPLACE PROCEDURE api_users_list(p_uid IN VARCHAR2, p_q IN VARCHAR2, p_department IN VARCHAR2,
                                           p_position IN VARCHAR2, p_type IN VARCHAR2) IS
  v_q VARCHAR2(200) := TRIM(p_q);
  rc  SYS_REFCURSOR;
BEGIN
  sp_require(p_uid, 'SC07', NULL);
  OPEN rc FOR
    SELECT u.user_id, u.name, u.email, u.username, d.department_name, e.phone, p.position_name,
           CASE WHEN e.user_id IS NOT NULL THEN 1 ELSE 0 END AS is_employee
      FROM users u
      JOIN departments d ON d.department_id = u.department_id
      LEFT JOIN employees e ON e.user_id = u.user_id
      LEFT JOIN positions p ON p.position_id = e.position_id
     WHERE (v_q IS NULL OR u.user_id LIKE '%' || v_q || '%' OR u.name LIKE '%' || v_q || '%'
            OR u.email LIKE '%' || v_q || '%' OR u.username LIKE '%' || v_q || '%')
       AND (p_department IS NULL OR u.department_id = p_department)
       AND (p_position IS NULL OR e.position_id = p_position)
       AND (NVL(p_type, '-') <> 'employee' OR e.user_id IS NOT NULL)
       AND (NVL(p_type, '-') <> 'user' OR e.user_id IS NULL)
     ORDER BY u.user_id;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

CREATE OR REPLACE PROCEDURE api_users_get(p_uid IN VARCHAR2, p_id IN VARCHAR2) IS
  v_n NUMBER;
  rc  SYS_REFCURSOR;
BEGIN
  sp_require(p_uid, 'SC07', 'edit');
  SELECT COUNT(*) INTO v_n FROM users WHERE user_id = p_id;
  IF v_n = 0 THEN mut_err('!notfound|ไม่พบผู้ใช้งาน'); END IF;
  OPEN rc FOR
    SELECT u.user_id, u.name, u.email, u.username, u.department_id, e.phone, e.position_id,
           CASE WHEN e.user_id IS NOT NULL THEN 1 ELSE 0 END AS is_employee
      FROM users u LEFT JOIN employees e ON e.user_id = u.user_id WHERE u.user_id = p_id;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

-- พนักงาน = subclass ของผู้ใช้งาน (+ เบอร์โทร + ตำแหน่ง) / password ว่างตอนแก้ไข = ไม่เปลี่ยน
CREATE OR REPLACE PROCEDURE api_users_save(p_uid IN VARCHAR2, p_id IN VARCHAR2, p_name IN VARCHAR2, p_email IN VARCHAR2,
                                           p_username IN VARCHAR2, p_password IN VARCHAR2, p_department_id IN VARCHAR2,
                                           p_is_employee IN VARCHAR2, p_phone IN VARCHAR2, p_position_id IN VARCHAR2) IS
  v_new      BOOLEAN := p_id IS NULL;
  v_emp      BOOLEAN := NVL(p_is_employee, '0') IN ('1', 'true', 'on');
  v_name     VARCHAR2(400) := TRIM(p_name);
  v_email    VARCHAR2(400) := TRIM(p_email);
  v_username VARCHAR2(400) := TRIM(p_username);
  v_phone    VARCHAR2(400) := TRIM(p_phone);
  v_id       VARCHAR2(10);
  v_n        NUMBER;
  v_dep      NUMBER;
  v_pos      NUMBER;
  e_child    EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_child, -2292);
BEGIN
  sp_require(p_uid, 'SC07', CASE WHEN v_new THEN 'add' ELSE 'edit' END);
  IF NOT v_new THEN
    SELECT COUNT(*) INTO v_n FROM users WHERE user_id = p_id;
    IF v_n = 0 THEN mut_err('!notfound|ไม่พบผู้ใช้งาน'); END IF;
  END IF;
  SELECT COUNT(*) INTO v_dep FROM departments WHERE department_id = p_department_id;
  SELECT COUNT(*) INTO v_pos FROM positions WHERE position_id = p_position_id;

  IF v_name IS NULL THEN
    mut_err('name|กรุณากรอกชื่อ');
  ELSIF LENGTH(v_name) > 100 THEN
    mut_err('name|ชื่อยาวได้ไม่เกิน 100 ตัวอักษร');
  ELSIF mut_is_email(v_email) = 0 THEN
    mut_err('email|รูปแบบ email ไม่ถูกต้อง');
  ELSIF mut_is_username(v_username) = 0 THEN
    mut_err('username|username ใช้ a-z, 0-9, _ . - ความยาว 3–50 ตัวอักษร');
  ELSIF (v_new OR p_password IS NOT NULL) AND NVL(LENGTH(p_password), 0) < 4 THEN
    mut_err('password|password ต้องมีอย่างน้อย 4 ตัวอักษร');
  ELSIF v_dep = 0 THEN
    mut_err('department_id|กรุณาเลือกแผนก');
  ELSIF v_emp AND (v_phone IS NULL OR NOT REGEXP_LIKE(v_phone, '^[0-9+ -]{6,20}$')) THEN
    mut_err('phone|กรุณากรอกเบอร์โทร (ตัวเลข 6–20 หลัก)');
  ELSIF v_emp AND v_pos = 0 THEN
    mut_err('position_id|กรุณาเลือกตำแหน่ง');
  ELSIF NOT v_new AND p_id = p_uid AND NOT v_emp THEN
    mut_err('is_employee|ไม่สามารถยกเลิกสถานะพนักงานของตัวเองได้');
  END IF;
  SELECT COUNT(*) INTO v_n FROM users WHERE email = v_email AND user_id <> NVL(p_id, '-');
  IF v_n > 0 THEN mut_err('email|email นี้ถูกใช้แล้ว'); END IF;
  SELECT COUNT(*) INTO v_n FROM users WHERE username = v_username AND user_id <> NVL(p_id, '-');
  IF v_n > 0 THEN mut_err('username|username นี้ถูกใช้แล้ว'); END IF;

  IF v_new THEN
    SELECT NVL(MAX(TO_NUMBER(SUBSTR(user_id, 2))), 0) + 1 INTO v_n FROM users WHERE REGEXP_LIKE(user_id, '^U[0-9]+$');
    v_id := mut_fmt_id('U', v_n, 3);
    INSERT INTO users (user_id, name, email, username, password_hash, department_id)
    VALUES (v_id, v_name, v_email, v_username, mut_hash_password(p_password), p_department_id);
  ELSE
    v_id := p_id;
    UPDATE users SET name = v_name, email = v_email, username = v_username, department_id = p_department_id
     WHERE user_id = v_id;
    IF p_password IS NOT NULL THEN
      UPDATE users SET password_hash = mut_hash_password(p_password) WHERE user_id = v_id;
    END IF;
  END IF;

  IF v_emp THEN
    MERGE INTO employees e
    USING (SELECT v_id AS user_id FROM dual) s ON (e.user_id = s.user_id)
    WHEN MATCHED THEN UPDATE SET e.phone = v_phone, e.position_id = p_position_id
    WHEN NOT MATCHED THEN INSERT (user_id, phone, position_id) VALUES (v_id, v_phone, p_position_id);
  ELSE
    DELETE FROM employees WHERE user_id = v_id;
  END IF;

  sp_message(CASE WHEN v_new THEN 'เพิ่มผู้ใช้งาน ' || v_id || ' (' || v_name || ') เรียบร้อยแล้ว'
                  ELSE 'บันทึกผู้ใช้งาน ' || v_id || ' เรียบร้อยแล้ว' END, v_id);
EXCEPTION
  WHEN e_child THEN
    mut_err('is_employee|ยกเลิกสถานะพนักงานไม่ได้ เนื่องจากเป็นคนขับในรอบการเดินรถ');
  WHEN DUP_VAL_ON_INDEX THEN
    mut_err('username|username หรือ email นี้ถูกใช้แล้ว');
END;
/

CREATE OR REPLACE PROCEDURE api_users_delete(p_uid IN VARCHAR2, p_id IN VARCHAR2) IS
  v_bookings NUMBER;
  v_trips    NUMBER;
BEGIN
  sp_require(p_uid, 'SC07', 'delete');
  SELECT COUNT(*) INTO v_bookings FROM bookings WHERE user_id = p_id;
  SELECT (SELECT COUNT(*) FROM trips WHERE driver_id = p_id) + (SELECT COUNT(*) FROM trip_schedules WHERE driver_id = p_id)
    INTO v_trips FROM dual;
  IF p_id = p_uid THEN
    mut_err('ไม่สามารถลบบัญชีของตัวเองได้');
  ELSIF v_bookings > 0 THEN
    mut_err('ลบไม่ได้ เนื่องจากผู้ใช้งานนี้มีประวัติการจอง ' || v_bookings || ' รายการ');
  ELSIF v_trips > 0 THEN
    mut_err('ลบไม่ได้ เนื่องจากผู้ใช้งานนี้เป็นคนขับใน ' || v_trips || ' รอบ/ตารางเวลา');
  END IF;
  DELETE FROM users WHERE user_id = p_id;   -- employees ลบตาม (CASCADE)
  sp_message('ลบผู้ใช้งาน ' || p_id || ' เรียบร้อยแล้ว');
END;
/

-- Permission Matrix: ชุดที่ 1 = ตำแหน่งทั้งหมด / ชุดที่ 2 = ตำแหน่งที่เลือก + แก้ไขได้หรือไม่
--                    ชุดที่ 3 = หน้าจอทั้งหมด + สิทธิ์ของตำแหน่งที่เลือก
CREATE OR REPLACE PROCEDURE api_permissions(p_uid IN VARCHAR2, p_position IN VARCHAR2) IS
  v_pos positions.position_id%TYPE;
  rc1 SYS_REFCURSOR; rc2 SYS_REFCURSOR; rc3 SYS_REFCURSOR;
BEGIN
  sp_require(p_uid, 'SC10', NULL);
  SELECT NVL(MAX(CASE WHEN position_id = p_position THEN position_id END), MIN(position_id)) INTO v_pos FROM positions;
  OPEN rc1 FOR SELECT position_id, position_name FROM positions ORDER BY position_id;
  DBMS_SQL.RETURN_RESULT(rc1);
  OPEN rc2 FOR SELECT position_id, position_name, mut_can(p_uid, 'SC10', 'edit') AS editable FROM positions WHERE position_id = v_pos;
  DBMS_SQL.RETURN_RESULT(rc2);
  OPEN rc3 FOR
    SELECT s.screen_id, s.screen_name,
           CASE WHEN p.permission_id IS NULL THEN 0 ELSE 1 END AS has_access,
           NVL(p.can_add, 0) AS can_add, NVL(p.can_edit, 0) AS can_edit, NVL(p.can_delete, 0) AS can_delete
      FROM screens s
      LEFT JOIN permissions p ON p.screen_id = s.screen_id AND p.position_id = v_pos
     ORDER BY s.screen_id;
  DBMS_SQL.RETURN_RESULT(rc3);
END;
/

-- p_matrix = 'SC01=1111;SC02=1000;...' ตัวเลข 4 หลัก = เข้าถึง เพิ่ม แก้ไข ลบ (หน้าจอที่ไม่อยู่ในรายการ = ไม่มีสิทธิ์)
CREATE OR REPLACE PROCEDURE api_permissions_save(p_uid IN VARCHAR2, p_position IN VARCHAR2, p_matrix IN VARCHAR2) IS
  v_name   positions.position_name%TYPE;
  v_mypos  employees.position_id%TYPE;
  v_matrix VARCHAR2(4000) := ';' || p_matrix || ';';
  v_pos    NUMBER;
  v_flags  VARCHAR2(4);
  v_n      NUMBER;
  v_has    NUMBER;
BEGIN
  sp_require(p_uid, 'SC10', 'edit');
  SELECT MAX(position_name) INTO v_name FROM positions WHERE position_id = p_position;
  IF v_name IS NULL THEN mut_err('ไม่พบตำแหน่ง'); END IF;

  -- กันผู้ใช้ถอดสิทธิ์ เข้าถึง/แก้ไข หน้าจอจัดการสิทธิ์ ของตำแหน่งตัวเอง
  SELECT MAX(position_id) INTO v_mypos FROM employees WHERE user_id = p_uid;
  IF p_position = v_mypos THEN
    v_pos := INSTR(v_matrix, ';SC10=');
    IF v_pos = 0 OR SUBSTR(v_matrix, v_pos + 6, 1) <> '1' OR SUBSTR(v_matrix, v_pos + 8, 1) <> '1' THEN
      mut_err('ไม่สามารถถอดสิทธิ์ เข้าถึง/แก้ไข หน้าจอจัดการสิทธิ์ ของตำแหน่งตัวเองได้');
    END IF;
  END IF;

  SELECT NVL(MAX(TO_NUMBER(SUBSTR(permission_id, 3))), 0) INTO v_n FROM permissions WHERE REGEXP_LIKE(permission_id, '^PR[0-9]+$');
  FOR s IN (SELECT screen_id FROM screens ORDER BY screen_id) LOOP
    v_pos := INSTR(v_matrix, ';' || s.screen_id || '=');
    v_flags := CASE WHEN v_pos = 0 THEN '0000' ELSE SUBSTR(v_matrix, v_pos + LENGTH(s.screen_id) + 2, 4) END;
    SELECT COUNT(*) INTO v_has FROM permissions WHERE position_id = p_position AND screen_id = s.screen_id;
    IF SUBSTR(v_flags, 1, 1) = '1' THEN
      IF v_has > 0 THEN
        UPDATE permissions
           SET can_add = CASE WHEN SUBSTR(v_flags, 2, 1) = '1' THEN 1 ELSE 0 END,
               can_edit = CASE WHEN SUBSTR(v_flags, 3, 1) = '1' THEN 1 ELSE 0 END,
               can_delete = CASE WHEN SUBSTR(v_flags, 4, 1) = '1' THEN 1 ELSE 0 END
         WHERE position_id = p_position AND screen_id = s.screen_id;
      ELSE
        v_n := v_n + 1;
        INSERT INTO permissions (permission_id, can_add, can_edit, can_delete, position_id, screen_id)
        VALUES (mut_fmt_id('PR', v_n, 3),
                CASE WHEN SUBSTR(v_flags, 2, 1) = '1' THEN 1 ELSE 0 END,
                CASE WHEN SUBSTR(v_flags, 3, 1) = '1' THEN 1 ELSE 0 END,
                CASE WHEN SUBSTR(v_flags, 4, 1) = '1' THEN 1 ELSE 0 END,
                p_position, s.screen_id);
      END IF;
    ELSIF v_has > 0 THEN
      DELETE FROM permissions WHERE position_id = p_position AND screen_id = s.screen_id;
    END IF;
  END LOOP;
  sp_message('บันทึกสิทธิ์ของตำแหน่ง ' || v_name || ' เรียบร้อยแล้ว');
END;
/


-- =====================================================================
-- 12) หลังบ้าน: เส้นทาง (SC05) และรอบการเดินรถ (SC06)
-- =====================================================================

CREATE OR REPLACE PROCEDURE api_routes_list(p_uid IN VARCHAR2, p_q IN VARCHAR2) IS
  v_q VARCHAR2(200) := TRIM(p_q);
  rc  SYS_REFCURSOR;
BEGIN
  sp_require(p_uid, 'SC05', NULL);
  OPEN rc FOR
    SELECT r.route_id, r.route_name,
           (SELECT COUNT(*) FROM route_stops rs WHERE rs.route_id = r.route_id) AS stop_count,
           mut_route_minutes(r.route_id) AS total_minutes,
           (SELECT COUNT(*) FROM trips t WHERE t.route_id = r.route_id) AS trip_count
      FROM routes r
     WHERE v_q IS NULL OR r.route_id LIKE '%' || v_q || '%' OR r.route_name LIKE '%' || v_q || '%'
     ORDER BY r.route_id;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

-- ชุดที่ 1 = เส้นทาง + จำนวนรอบ / ชุดที่ 2 = ลำดับจุดจอดพร้อมเวลาสะสม
CREATE OR REPLACE PROCEDURE api_routes_get(p_uid IN VARCHAR2, p_id IN VARCHAR2) IS
  v_n NUMBER;
  rc1 SYS_REFCURSOR;
  rc2 SYS_REFCURSOR;
BEGIN
  sp_require(p_uid, 'SC05', NULL);
  SELECT COUNT(*) INTO v_n FROM routes WHERE route_id = p_id;
  IF v_n = 0 THEN mut_err('!notfound|ไม่พบเส้นทาง'); END IF;
  OPEN rc1 FOR
    SELECT r.route_id, r.route_name,
           (SELECT COUNT(*) FROM route_stops rs WHERE rs.route_id = r.route_id) AS stop_count,
           mut_route_minutes(r.route_id) AS total_minutes,
           (SELECT COUNT(*) FROM trips t WHERE t.route_id = r.route_id) AS trip_total,
           (SELECT COUNT(*) FROM trips t WHERE t.route_id = r.route_id AND t.status = 'เปิด') AS trip_open
      FROM routes r WHERE r.route_id = p_id;
  DBMS_SQL.RETURN_RESULT(rc1);
  OPEN rc2 FOR
    SELECT rs.route_id, rs.stop_order, rs.stop_id, s.stop_name, rs.travel_minutes,
           SUM(rs.travel_minutes) OVER (ORDER BY rs.stop_order ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_minutes
      FROM route_stops rs JOIN stops s ON s.stop_id = rs.stop_id
     WHERE rs.route_id = p_id
     ORDER BY rs.stop_order;
  DBMS_SQL.RETURN_RESULT(rc2);
END;
/

-- p_stops = 'S001:0,S002:5,S003:3' (จุดจอด:นาทีจากจุดก่อนหน้า ตามลำดับ) — ลำดับแรกเป็น 0 นาทีเสมอ
CREATE OR REPLACE PROCEDURE api_routes_save(p_uid IN VARCHAR2, p_id IN VARCHAR2, p_route_name IN VARCHAR2, p_stops IN VARCHAR2) IS
  TYPE t_stop IS RECORD (stop_id VARCHAR2(10), minutes NUMBER);
  TYPE t_stops IS TABLE OF t_stop;
  v_rows   t_stops := t_stops();
  v_name   VARCHAR2(400) := TRIM(p_route_name);
  v_list   VARCHAR2(4000) := TRIM(p_stops);
  v_count  NUMBER;
  v_token  VARCHAR2(100);
  v_stop   VARCHAR2(100);
  v_min    VARCHAR2(100);
  v_seq    VARCHAR2(4000) := ',';
  v_n      NUMBER;
  v_broken NUMBER;
  v_id     VARCHAR2(10);
  v_msg    VARCHAR2(300);
BEGIN
  sp_require(p_uid, 'SC05', CASE WHEN p_id IS NULL THEN 'add' ELSE 'edit' END);
  IF p_id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_n FROM routes WHERE route_id = p_id;
    IF v_n = 0 THEN mut_err('!notfound|ไม่พบเส้นทาง'); END IF;
  END IF;
  IF v_name IS NULL THEN
    mut_err('route_name|กรุณากรอกชื่อเส้นทาง');
  ELSIF LENGTH(v_name) > 100 THEN
    mut_err('route_name|ชื่อเส้นทางยาวได้ไม่เกิน 100 ตัวอักษร');
  END IF;

  -- แยกรายการจุดจอดพร้อมตรวจทีละลำดับ
  v_count := CASE WHEN v_list IS NULL THEN 0 ELSE REGEXP_COUNT(v_list, ',') + 1 END;
  IF v_count < 2 THEN mut_err('stops|เส้นทางต้องมีอย่างน้อย 2 จุดจอด'); END IF;
  FOR i IN 1 .. v_count LOOP
    v_token := TRIM(REGEXP_SUBSTR(v_list, '(.*?)(,|$)', 1, i, NULL, 1));
    IF INSTR(v_token, ':') > 0 THEN
      v_stop := TRIM(SUBSTR(v_token, 1, INSTR(v_token, ':') - 1));
      v_min := TRIM(SUBSTR(v_token, INSTR(v_token, ':') + 1));
    ELSE
      v_stop := v_token;
      v_min := NULL;
    END IF;
    IF i = 1 THEN v_min := '0'; END IF;
    SELECT COUNT(*) INTO v_n FROM stops WHERE stop_id = v_stop;
    IF v_n = 0 THEN
      mut_err('stops|ลำดับ ' || i || ': กรุณาเลือกจุดจอด');
    ELSIF i > 1 AND v_stop = v_rows(i - 1).stop_id THEN
      mut_err('stops|ลำดับ ' || i || ': จุดจอดติดกันต้องไม่ซ้ำกัน');
    ELSIF i > 1 AND (mut_is_int(v_min) = 0 OR TO_NUMBER(v_min) <= 0) THEN
      mut_err('stops|ลำดับ ' || i || ': เวลาเดินทางต้องเป็นจำนวนเต็มมากกว่า 0 นาที');
    END IF;
    v_rows.EXTEND;
    v_rows(i).stop_id := v_stop;
    v_rows(i).minutes := TO_NUMBER(v_min);
    v_seq := v_seq || v_stop || ',';
  END LOOP;

  -- รายการจองที่ยังใช้งานของเส้นทางนี้ต้องยังมีจุดขึ้นก่อนจุดลงในลำดับใหม่
  IF p_id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_broken FROM (
      SELECT DISTINCT bi.board_stop_id, bi.alight_stop_id
        FROM booking_items bi JOIN trips t ON t.trip_id = bi.trip_id
       WHERE t.route_id = p_id AND t.status IN ('เปิด', 'กำลังเดินทาง') AND bi.status = 'ยืนยัน'
    ) u
     WHERE INSTR(v_seq, ',' || u.board_stop_id || ',') = 0
        OR INSTR(v_seq, ',' || u.alight_stop_id || ',', INSTR(v_seq, ',' || u.board_stop_id || ',') + 1) = 0;
    IF v_broken > 0 THEN
      mut_err('stops|บันทึกไม่ได้ — มีรายการจองของรอบที่ยังเปิดใช้ช่วงจุดจอดที่ถูกตัดออก (' || v_broken || ' ช่วง)');
    END IF;
  END IF;

  IF p_id IS NULL THEN
    SELECT NVL(MAX(TO_NUMBER(SUBSTR(route_id, 2))), 0) + 1 INTO v_n FROM routes WHERE REGEXP_LIKE(route_id, '^R[0-9]+$');
    v_id := mut_fmt_id('R', v_n, 3);
    INSERT INTO routes (route_id, route_name) VALUES (v_id, v_name);
    v_msg := 'เพิ่มเส้นทาง ' || v_id || ' เรียบร้อยแล้ว';
  ELSE
    v_id := p_id;
    UPDATE routes SET route_name = v_name WHERE route_id = v_id;
    DELETE FROM route_stops WHERE route_id = v_id;
    v_msg := 'บันทึกเส้นทาง ' || v_id || ' เรียบร้อยแล้ว';
  END IF;
  FOR i IN 1 .. v_rows.COUNT LOOP
    INSERT INTO route_stops (route_id, stop_order, stop_id, travel_minutes) VALUES (v_id, i, v_rows(i).stop_id, v_rows(i).minutes);
  END LOOP;
  sp_message(v_msg, v_id);
END;
/

CREATE OR REPLACE PROCEDURE api_routes_delete(p_uid IN VARCHAR2, p_id IN VARCHAR2) IS
  v_n NUMBER;
BEGIN
  sp_require(p_uid, 'SC05', 'delete');
  SELECT COUNT(*) INTO v_n FROM trips WHERE route_id = p_id;
  IF v_n > 0 THEN mut_err('ลบไม่ได้ เนื่องจากเส้นทางนี้ถูกใช้ใน ' || v_n || ' รอบการเดินรถ'); END IF;
  DELETE FROM routes WHERE route_id = p_id;   -- route_stops / trip_schedules ลบตาม (CASCADE)
  sp_message('ลบเส้นทาง ' || p_id || ' เรียบร้อยแล้ว');
END;
/

-- p_date ว่าง = ทุกวัน (หน้าเว็บส่งวันนี้เป็นค่าเริ่มต้น) — แสดงไม่เกิน 500 รอบ
CREATE OR REPLACE PROCEDURE api_trips_list(p_uid IN VARCHAR2, p_date IN VARCHAR2, p_route IN VARCHAR2,
                                           p_driver IN VARCHAR2, p_vehicle IN VARCHAR2, p_status IN VARCHAR2) IS
  v_date DATE := mut_to_date(p_date);
BEGIN
  sp_require(p_uid, 'SC06', NULL);
  sp_trips(NULL, p_driver, v_date, v_date, p_route, p_vehicle, p_status, 0, 'date_desc', 500);
END;
/

-- ฟอร์มรอบ: ชุดที่ 1 = รอบ (ว่างถ้าเพิ่มใหม่) / ชุดที่ 2 = เส้นทาง
--           ชุดที่ 3 = รถที่พร้อมใช้งาน (+ คันเดิมของรอบ) / ชุดที่ 4 = คนขับ (+ คนเดิมของรอบ)
CREATE OR REPLACE PROCEDURE api_trips_form(p_uid IN VARCHAR2, p_id IN VARCHAR2) IS
  v_vehicle VARCHAR2(10);
  v_driver  VARCHAR2(10);
  v_n       NUMBER;
  rc2 SYS_REFCURSOR; rc3 SYS_REFCURSOR; rc4 SYS_REFCURSOR;
BEGIN
  sp_require(p_uid, 'SC06', CASE WHEN p_id IS NULL THEN 'add' ELSE 'edit' END);
  IF p_id IS NOT NULL THEN
    SELECT COUNT(*), MAX(vehicle_id), MAX(driver_id) INTO v_n, v_vehicle, v_driver FROM trips WHERE trip_id = p_id;
    IF v_n = 0 THEN mut_err('!notfound|ไม่พบรอบการเดินรถ'); END IF;
  END IF;
  sp_trips(NVL(p_id, '-'), NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, 1);
  OPEN rc2 FOR SELECT route_id, route_name, mut_route_minutes(route_id) AS total_minutes FROM routes ORDER BY route_id;
  DBMS_SQL.RETURN_RESULT(rc2);
  OPEN rc3 FOR
    SELECT v.vehicle_id, v.plate_no, v.status, vt.type_name, vt.seat_count
      FROM vehicles v JOIN vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id
     WHERE v.status = 'พร้อมใช้งาน' OR v.vehicle_id = v_vehicle
     ORDER BY v.plate_no;
  DBMS_SQL.RETURN_RESULT(rc3);
  OPEN rc4 FOR
    SELECT u.user_id, u.name, p.position_name
      FROM employees e JOIN users u ON u.user_id = e.user_id JOIN positions p ON p.position_id = e.position_id
     WHERE e.position_id IN (SELECT position_id FROM permissions WHERE screen_id = 'SC12') OR e.user_id = v_driver
     ORDER BY u.name;
  DBMS_SQL.RETURN_RESULT(rc4);
END;
/

-- เพิ่ม/แก้ไขรอบ + Conflict Validation (รถ/คนขับชนเวลา) — trigger ในตาราง trips เป็นด่านสุดท้าย
CREATE OR REPLACE PROCEDURE api_trips_save(p_uid IN VARCHAR2, p_id IN VARCHAR2, p_route_id IN VARCHAR2,
                                           p_trip_date IN VARCHAR2, p_depart_time IN VARCHAR2, p_vehicle_id IN VARCHAR2,
                                           p_driver_id IN VARCHAR2, p_status IN VARCHAR2) IS
  v_new         BOOLEAN := p_id IS NULL;
  v_date        DATE := mut_to_date(p_trip_date);
  v_time        VARCHAR2(8) := mut_norm_time(p_depart_time);
  v_status      VARCHAR2(30) := CASE WHEN p_id IS NULL THEN 'เปิด' ELSE p_status END;
  v_old_vehicle VARCHAR2(10);
  v_old_driver  VARCHAR2(10);
  v_old_route   VARCHAR2(10);
  v_booked      NUMBER := 0;
  v_vstatus     VARCHAR2(30);
  v_vseats      NUMBER;
  v_minutes     NUMBER;
  v_n           NUMBER;
  v_id          VARCHAR2(10);
  v_msg         VARCHAR2(300);
BEGIN
  sp_require(p_uid, 'SC06', CASE WHEN v_new THEN 'add' ELSE 'edit' END);
  IF NOT v_new THEN
    SELECT COUNT(*), MAX(vehicle_id), MAX(driver_id), MAX(route_id) INTO v_n, v_old_vehicle, v_old_driver, v_old_route
      FROM trips WHERE trip_id = p_id;
    IF v_n = 0 THEN mut_err('!notfound|ไม่พบรอบการเดินรถ'); END IF;
    v_booked := mut_booked_seats(p_id);
  END IF;
  SELECT MAX(v.status), MAX(vt.seat_count) INTO v_vstatus, v_vseats
    FROM vehicles v JOIN vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id WHERE v.vehicle_id = p_vehicle_id;
  SELECT COUNT(*) INTO v_n FROM routes WHERE route_id = p_route_id;

  IF v_n = 0 THEN
    mut_err('route_id|กรุณาเลือกเส้นทาง');
  ELSIF v_date IS NULL THEN
    mut_err('trip_date|กรุณาเลือกวันที่เดินรถ');
  ELSIF v_new AND v_date < TRUNC(SYSDATE) THEN
    mut_err('trip_date|ไม่สามารถจัดรอบย้อนหลังได้');
  ELSIF v_time IS NULL THEN
    mut_err('depart_time|กรุณาระบุเวลาออก');
  ELSIF v_vstatus IS NULL THEN
    mut_err('vehicle_id|กรุณาเลือกรถที่พร้อมใช้งาน');
  ELSIF v_vstatus <> 'พร้อมใช้งาน' AND (v_new OR p_vehicle_id <> v_old_vehicle) THEN
    mut_err('vehicle_id|รถคันนี้ไม่อยู่ในสถานะพร้อมใช้งาน');
  END IF;
  SELECT COUNT(*) INTO v_n FROM employees e
   WHERE e.user_id = p_driver_id
     AND (e.position_id IN (SELECT position_id FROM permissions WHERE screen_id = 'SC12') OR e.user_id = NVL(v_old_driver, '-'));
  IF v_n = 0 THEN
    mut_err('driver_id|กรุณาเลือกคนขับ');
  ELSIF v_status IS NULL OR v_status NOT IN ('เปิด', 'กำลังเดินทาง', 'เสร็จสิ้น', 'ยกเลิก') THEN
    mut_err('status|กรุณาเลือกสถานะรอบ');
  ELSIF NOT v_new AND p_route_id <> v_old_route AND v_booked > 0 THEN
    mut_err('route_id|เปลี่ยนเส้นทางไม่ได้ เนื่องจากรอบนี้มีการจองแล้ว');
  ELSIF NOT v_new AND v_vseats < v_booked THEN
    mut_err('vehicle_id|รถคันนี้มี ' || v_vseats || ' ที่นั่ง น้อยกว่าที่จองแล้ว ' || v_booked || ' ที่นั่ง');
  END IF;

  -- Conflict Validation: รอบอื่นที่ใช้รถ/คนขับเดียวกันและช่วงเวลาทับกัน
  IF v_status <> 'ยกเลิก' THEN
    v_minutes := mut_route_minutes(p_route_id);
    FOR c IN (
      SELECT t.trip_id || ' (' || SUBSTR(t.depart_time, 1, 5) || '–'
             || TO_CHAR(mut_ts(t.trip_date, t.depart_time) + mut_route_minutes(t.route_id) / 1440, 'HH24:MI') || ')' AS label,
             CASE WHEN t.vehicle_id = p_vehicle_id THEN 'vehicle' ELSE 'driver' END AS kind
        FROM trips t
       WHERE t.trip_date = v_date AND t.status <> 'ยกเลิก' AND t.trip_id <> NVL(p_id, '-')
         AND (t.vehicle_id = p_vehicle_id OR t.driver_id = p_driver_id)
         AND mut_ts(t.trip_date, t.depart_time) < mut_ts(v_date, v_time) + v_minutes / 1440
         AND mut_ts(v_date, v_time) < mut_ts(t.trip_date, t.depart_time) + mut_route_minutes(t.route_id) / 1440
       ORDER BY 2 DESC
       FETCH FIRST 1 ROWS ONLY) LOOP
      IF c.kind = 'vehicle' THEN
        mut_err('vehicle_id|ไม่สามารถจัดรอบนี้ได้ เนื่องจากรถถูกมอบหมายในรอบ ' || c.label);
      ELSE
        mut_err('driver_id|ไม่สามารถจัดรอบนี้ได้ เนื่องจากคนขับมีงานรอบ ' || c.label);
      END IF;
    END LOOP;
  END IF;

  IF v_new THEN
    SELECT NVL(MAX(TO_NUMBER(SUBSTR(trip_id, 3))), 0) + 1 INTO v_n FROM trips WHERE REGEXP_LIKE(trip_id, '^TR[0-9]+$');
    v_id := mut_fmt_id('TR', v_n, 3);
    INSERT INTO trips (trip_id, trip_date, depart_time, status, vehicle_id, route_id, driver_id)
    VALUES (v_id, v_date, v_time, 'เปิด', p_vehicle_id, p_route_id, p_driver_id);
    v_msg := 'เพิ่มรอบ ' || v_id || ' (' || TO_CHAR(v_date, 'DD/MM/YYYY') || ' ' || SUBSTR(v_time, 1, 5) || ') เรียบร้อยแล้ว';
  ELSE
    v_id := p_id;
    UPDATE trips SET trip_date = v_date, depart_time = v_time, status = v_status, vehicle_id = p_vehicle_id,
                     route_id = p_route_id, driver_id = p_driver_id
     WHERE trip_id = p_id;
    v_msg := 'บันทึกรอบ ' || v_id || ' เรียบร้อยแล้ว';
  END IF;
  DECLARE
    rc SYS_REFCURSOR;
  BEGIN
    OPEN rc FOR SELECT v_id AS id, TO_CHAR(v_date, 'YYYY-MM-DD') AS trip_date, v_msg AS message FROM dual;
    DBMS_SQL.RETURN_RESULT(rc);
  END;
END;
/

CREATE OR REPLACE PROCEDURE api_trips_delete(p_uid IN VARCHAR2, p_id IN VARCHAR2) IS
  v_n NUMBER;
BEGIN
  sp_require(p_uid, 'SC06', 'delete');
  SELECT COUNT(*) INTO v_n FROM booking_items WHERE trip_id = p_id;
  IF v_n > 0 THEN
    mut_err('ลบไม่ได้ เนื่องจากรอบ ' || p_id || ' มีรายการจอง ' || v_n || ' รายการ — เปลี่ยนสถานะรอบเป็น "ยกเลิก" แทน');
  END IF;
  DELETE FROM trips WHERE trip_id = p_id;
  sp_message('ลบรอบ ' || p_id || ' เรียบร้อยแล้ว');
END;
/


-- =====================================================================
-- 13) หลังบ้าน: การจอง (SC02)
-- =====================================================================

-- p_status: ยืนยัน (ยังไม่ Check-in) / Check-in แล้ว / ยกเลิก / No Show — แสดงไม่เกิน 500 รายการ
-- ชุดที่ 1 = รายการจอง / ชุดที่ 2 = เส้นทาง (ตัวกรอง)
CREATE OR REPLACE PROCEDURE api_bookings_list(p_uid IN VARCHAR2, p_q IN VARCHAR2, p_from IN VARCHAR2, p_to IN VARCHAR2,
                                              p_status IN VARCHAR2, p_route IN VARCHAR2, p_trip IN VARCHAR2) IS
  rc SYS_REFCURSOR;
BEGIN
  sp_require(p_uid, 'SC02', NULL);
  sp_items(NULL, NULL, NULL, p_trip, p_route, mut_to_date(p_from), mut_to_date(p_to), p_status, TRIM(p_q), 0, 'booked_desc', 500);
  OPEN rc FOR SELECT route_id, route_name FROM routes ORDER BY route_id;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/

-- ชุดที่ 1 = การจอง + ผู้จอง / ชุดที่ 2 = รายการจอง
CREATE OR REPLACE PROCEDURE api_bookings_get(p_uid IN VARCHAR2, p_id IN VARCHAR2) IS
  v_n NUMBER;
  rc  SYS_REFCURSOR;
BEGIN
  sp_require(p_uid, 'SC02', NULL);
  SELECT COUNT(*) INTO v_n FROM bookings WHERE booking_id = p_id;
  IF v_n = 0 THEN mut_err('!notfound|ไม่พบการจอง'); END IF;
  OPEN rc FOR
    SELECT b.booking_id, b.booked_at, u.user_id, u.name, u.email, u.username, d.department_name
      FROM bookings b JOIN users u ON u.user_id = b.user_id JOIN departments d ON d.department_id = u.department_id
     WHERE b.booking_id = p_id;
  DBMS_SQL.RETURN_RESULT(rc);
  sp_items(NULL, NULL, p_id, NULL, NULL, NULL, NULL, NULL, NULL, 0, 'item_asc', NULL);
END;
/

-- ยกเลิกรายการจองโดยเจ้าหน้าที่ (ไม่ตรวจเจ้าของ)
CREATE OR REPLACE PROCEDURE api_bookings_cancel_item(p_uid IN VARCHAR2, p_item IN VARCHAR2) IS
BEGIN
  sp_require(p_uid, 'SC02', 'edit');
  sp_cancel_booking_item(p_item, NULL);
  sp_message('ยกเลิกรายการจอง ' || p_item || ' แล้ว — คืนที่นั่งให้รอบเรียบร้อย');
END;
/

-- เปลี่ยนสถานะรายการจอง (trigger ตรวจที่นั่งเมื่อเปิดรายการที่ยกเลิกกลับมา)
CREATE OR REPLACE PROCEDURE api_bookings_set_status(p_uid IN VARCHAR2, p_item IN VARCHAR2, p_status IN VARCHAR2) IS
BEGIN
  sp_require(p_uid, 'SC02', 'edit');
  IF p_status IS NULL OR p_status NOT IN ('ยืนยัน', 'ยกเลิก', 'No Show') THEN
    mut_err('สถานะไม่ถูกต้อง');
  END IF;
  UPDATE booking_items SET status = p_status WHERE booking_item_id = p_item;
  IF SQL%ROWCOUNT = 0 THEN mut_err('!notfound|ไม่พบรายการจอง'); END IF;
  sp_message('เปลี่ยนสถานะรายการ ' || p_item || ' เป็น ' || p_status || ' แล้ว');
END;
/

CREATE OR REPLACE PROCEDURE api_bookings_delete(p_uid IN VARCHAR2, p_id IN VARCHAR2) IS
BEGIN
  sp_require(p_uid, 'SC02', 'delete');
  DELETE FROM bookings WHERE booking_id = p_id;   -- รายการจองลบตาม (CASCADE)
  sp_message('ลบการจอง ' || p_id || ' เรียบร้อยแล้ว');
END;
/


-- =====================================================================
-- 14) รายงาน 1–7 (SC11)
--     ชุดที่ 1 = ค่าที่ใช้ออกรายงาน (ปี ค.ศ. / ช่วงวันที่) / ชุดถัดไป = ข้อมูลของรายงาน
-- =====================================================================
CREATE OR REPLACE PROCEDURE api_report(p_uid IN VARCHAR2, p_report IN VARCHAR2, p_year IN VARCHAR2,
                                       p_from IN VARCHAR2, p_to IN VARCHAR2) IS
  v_year NUMBER;
  v_from DATE := mut_to_date(p_from);
  v_to   DATE := mut_to_date(p_to);
  v_tmp  DATE;
  v_y1   DATE;
  v_y2   DATE;
  rc0 SYS_REFCURSOR; rc SYS_REFCURSOR; rc2 SYS_REFCURSOR;
BEGIN
  sp_require(p_uid, 'SC11', NULL);

  -- ปีรับได้ทั้ง พ.ศ. (2568) และ ค.ศ. (2025) / ค่าเริ่มต้น = ปีนี้, ช่วงวันที่ = เดือนนี้
  v_year := CASE WHEN mut_is_int(p_year) = 1 AND TO_NUMBER(p_year) > 0 THEN TO_NUMBER(p_year) ELSE EXTRACT(YEAR FROM SYSDATE) END;
  IF v_year > 2400 THEN v_year := v_year - 543; END IF;
  v_from := NVL(v_from, TRUNC(SYSDATE, 'MM'));
  v_to := NVL(v_to, LAST_DAY(TRUNC(SYSDATE)));
  IF v_from > v_to THEN
    v_tmp := v_from; v_from := v_to; v_to := v_tmp;
  END IF;
  v_y1 := TO_DATE(v_year || '-01-01', 'YYYY-MM-DD');
  v_y2 := ADD_MONTHS(v_y1, 12);
  OPEN rc0 FOR SELECT v_year AS year_ad, TO_CHAR(v_from, 'YYYY-MM-DD') AS date_from, TO_CHAR(v_to, 'YYYY-MM-DD') AS date_to FROM dual;
  DBMS_SQL.RETURN_RESULT(rc0);

  CASE NVL(p_report, '1')
  -- รายงาน 1: จำนวนคนขึ้น–ลงรถรายปี แยกจุดจอด × เดือน (เฉพาะที่ Check-in)
  WHEN '1' THEN
    OPEN rc FOR
      SELECT k.type, s.stop_id, s.stop_name,
             NVL(SUM(CASE WHEN x.m = 1 THEN x.n END), 0) AS m1,   NVL(SUM(CASE WHEN x.m = 2 THEN x.n END), 0) AS m2,
             NVL(SUM(CASE WHEN x.m = 3 THEN x.n END), 0) AS m3,   NVL(SUM(CASE WHEN x.m = 4 THEN x.n END), 0) AS m4,
             NVL(SUM(CASE WHEN x.m = 5 THEN x.n END), 0) AS m5,   NVL(SUM(CASE WHEN x.m = 6 THEN x.n END), 0) AS m6,
             NVL(SUM(CASE WHEN x.m = 7 THEN x.n END), 0) AS m7,   NVL(SUM(CASE WHEN x.m = 8 THEN x.n END), 0) AS m8,
             NVL(SUM(CASE WHEN x.m = 9 THEN x.n END), 0) AS m9,   NVL(SUM(CASE WHEN x.m = 10 THEN x.n END), 0) AS m10,
             NVL(SUM(CASE WHEN x.m = 11 THEN x.n END), 0) AS m11, NVL(SUM(CASE WHEN x.m = 12 THEN x.n END), 0) AS m12,
             NVL(SUM(x.n), 0) AS total
        FROM (SELECT 1 AS sort, 'ขึ้นรถ' AS type FROM dual UNION ALL SELECT 2, 'ลงรถ' FROM dual) k
       CROSS JOIN stops s
        LEFT JOIN (
          SELECT 1 AS sort, EXTRACT(MONTH FROM t.trip_date) AS m, bi.board_stop_id AS stop_id, SUM(bi.seats) AS n
            FROM booking_items bi JOIN trips t ON t.trip_id = bi.trip_id
           WHERE bi.checkin_at IS NOT NULL AND t.trip_date >= v_y1 AND t.trip_date < v_y2
           GROUP BY EXTRACT(MONTH FROM t.trip_date), bi.board_stop_id
          UNION ALL
          SELECT 2, EXTRACT(MONTH FROM t.trip_date), bi.alight_stop_id, SUM(bi.seats)
            FROM booking_items bi JOIN trips t ON t.trip_id = bi.trip_id
           WHERE bi.checkin_at IS NOT NULL AND t.trip_date >= v_y1 AND t.trip_date < v_y2
           GROUP BY EXTRACT(MONTH FROM t.trip_date), bi.alight_stop_id
        ) x ON x.sort = k.sort AND x.stop_id = s.stop_id
       GROUP BY k.sort, k.type, s.stop_id, s.stop_name
       ORDER BY k.sort, s.stop_id;

  -- รายงาน 2: สถิติการจองรายปี (ครบ 12 เดือน)
  WHEN '2' THEN
    OPEN rc FOR
      SELECT mo.month_no,
             NVL(d.bookings, 0) AS bookings, NVL(d.booking_items, 0) AS booking_items,
             NVL(d.booked_seats, 0) AS booked_seats, NVL(d.cancelled, 0) AS cancelled,
             NVL(d.checked_in, 0) AS checked_in, NVL(d.no_show, 0) AS no_show
        FROM (SELECT LEVEL AS month_no FROM dual CONNECT BY LEVEL <= 12) mo
        LEFT JOIN (
          SELECT EXTRACT(MONTH FROM t.trip_date) AS month_no,
                 COUNT(DISTINCT bi.booking_id)                                  AS bookings,
                 COUNT(*)                                                       AS booking_items,
                 SUM(CASE WHEN bi.status <> 'ยกเลิก' THEN bi.seats ELSE 0 END)  AS booked_seats,
                 SUM(CASE WHEN bi.status = 'ยกเลิก' THEN 1 ELSE 0 END)          AS cancelled,
                 SUM(CASE WHEN bi.checkin_at IS NOT NULL THEN 1 ELSE 0 END)    AS checked_in,
                 SUM(CASE WHEN bi.status = 'No Show' THEN 1 ELSE 0 END)        AS no_show
            FROM booking_items bi JOIN trips t ON t.trip_id = bi.trip_id
           WHERE t.trip_date >= v_y1 AND t.trip_date < v_y2
           GROUP BY EXTRACT(MONTH FROM t.trip_date)
        ) d ON d.month_no = mo.month_no
       ORDER BY mo.month_no;

  -- รายงาน 3: พฤติกรรมผู้ใช้ตามช่วงวันที่
  WHEN '3' THEN
    OPEN rc FOR
      SELECT u.user_id, u.name,
             COUNT(*)                                                    AS total_items,
             SUM(CASE WHEN bi.checkin_at IS NOT NULL THEN 1 ELSE 0 END)  AS boarded,
             SUM(CASE WHEN bi.status = 'ยกเลิก' THEN 1 ELSE 0 END)        AS cancelled,
             SUM(CASE WHEN bi.status = 'No Show' THEN 1 ELSE 0 END)      AS no_show
        FROM booking_items bi
        JOIN bookings b ON b.booking_id = bi.booking_id
        JOIN users u    ON u.user_id = b.user_id
        JOIN trips t    ON t.trip_id = bi.trip_id
       WHERE t.trip_date BETWEEN v_from AND v_to
       GROUP BY u.user_id, u.name
       ORDER BY total_items DESC, u.user_id;

  -- รายงาน 4: ผู้ใช้บริการจริงแต่ละเส้นทาง รวมตามวันในสัปดาห์ (ชุดที่ 2 = เส้นทาง / ชุดที่ 3 = ข้อมูล, dow_no 1 = อาทิตย์)
  WHEN '4' THEN
    OPEN rc2 FOR SELECT route_id, route_name FROM routes ORDER BY route_id;
    DBMS_SQL.RETURN_RESULT(rc2);
    OPEN rc FOR
      SELECT mut_weekday(t.trip_date) + 1 AS dow_no, t.route_id, SUM(bi.seats) AS passengers
        FROM booking_items bi JOIN trips t ON t.trip_id = bi.trip_id
       WHERE bi.checkin_at IS NOT NULL AND t.trip_date BETWEEN v_from AND v_to
       GROUP BY mut_weekday(t.trip_date) + 1, t.route_id;

  -- รายงาน 5: การใช้บริการแต่ละจุดจอดตามรอบเวลา
  WHEN '5' THEN
    OPEN rc FOR
      WITH st AS (
        SELECT rs.route_id, rs.stop_order, s.stop_name,
               SUM(rs.travel_minutes) OVER (PARTITION BY rs.route_id ORDER BY rs.stop_order
                                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_minutes
          FROM route_stops rs JOIN stops s ON s.stop_id = rs.stop_id
      ), ts AS (
        SELECT t.trip_id, st.stop_order, st.stop_name,
               TO_CHAR(mut_ts(t.trip_date, t.depart_time) + st.cum_minutes / 1440, 'HH24:MI:SS') AS pass_time
          FROM trips t JOIN st ON st.route_id = t.route_id
         WHERE t.trip_date BETWEEN v_from AND v_to
      ), sg AS (
        SELECT bi.trip_id, bi.seats,
               (SELECT MIN(a.stop_order) FROM route_stops a WHERE a.route_id = t.route_id AND a.stop_id = bi.board_stop_id) AS board_order,
               (SELECT MIN(b.stop_order) FROM route_stops b
                 WHERE b.route_id = t.route_id AND b.stop_id = bi.alight_stop_id
                   AND b.stop_order > (SELECT MIN(a2.stop_order) FROM route_stops a2
                                        WHERE a2.route_id = t.route_id AND a2.stop_id = bi.board_stop_id)) AS alight_order
          FROM booking_items bi JOIN trips t ON t.trip_id = bi.trip_id
         WHERE bi.checkin_at IS NOT NULL AND t.trip_date BETWEEN v_from AND v_to
      )
      SELECT ts.stop_name, ts.pass_time,
             NVL(SUM(CASE WHEN sg.board_order  = ts.stop_order THEN sg.seats END), 0) AS boarding,
             NVL(SUM(CASE WHEN sg.alight_order = ts.stop_order THEN sg.seats END), 0) AS alighting
        FROM ts LEFT JOIN sg ON sg.trip_id = ts.trip_id AND (sg.board_order = ts.stop_order OR sg.alight_order = ts.stop_order)
       GROUP BY ts.stop_name, ts.pass_time
       ORDER BY ts.stop_name, ts.pass_time;

  -- รายงาน 6: การมอบหมายงานคนขับ ก่อน/หลัง 17:00 (ไม่นับรอบที่ยกเลิก)
  WHEN '6' THEN
    OPEN rc FOR
      SELECT u.user_id, u.name,
             COUNT(*)                                                     AS total_trips,
             SUM(CASE WHEN t.depart_time <  '17:00:00' THEN 1 ELSE 0 END) AS before_1700,
             SUM(CASE WHEN t.depart_time >= '17:00:00' THEN 1 ELSE 0 END) AS after_1700
        FROM trips t JOIN users u ON u.user_id = t.driver_id
       WHERE t.trip_date BETWEEN v_from AND v_to AND t.status <> 'ยกเลิก'
       GROUP BY u.user_id, u.name
       ORDER BY total_trips DESC, u.user_id;

  -- รายงาน 7: จำนวนรอบที่รถแต่ละคันได้รับมอบหมาย แยกประเภทรถ (ไม่นับรอบที่ยกเลิก)
  WHEN '7' THEN
    OPEN rc FOR
      SELECT vt.vehicle_type_id, vt.type_name, v.plate_no, COUNT(t.trip_id) AS trips
        FROM vehicle_types vt
        JOIN vehicles v   ON v.vehicle_type_id = vt.vehicle_type_id
        LEFT JOIN trips t ON t.vehicle_id = v.vehicle_id
                         AND t.trip_date BETWEEN v_from AND v_to AND t.status <> 'ยกเลิก'
       GROUP BY vt.vehicle_type_id, vt.type_name, v.plate_no
       ORDER BY vt.vehicle_type_id, v.plate_no;

  ELSE
    mut_err('ไม่พบรายงานนี้');
  END CASE;
  DBMS_SQL.RETURN_RESULT(rc);
END;
/
