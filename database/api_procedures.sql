-- =====================================================================
--  MUT Shuttle — หลังบ้าน (Business logic) ทั้งหมดเป็น SQL
--  รันหลัง mut_shuttle.sql (MySQL 8.0+ / MariaDB 10.5+)
--
--  กติกา
--  - หน้าเว็บ (HTML/JS) เรียกได้เฉพาะ procedure ที่ชื่อขึ้นต้นด้วย api_ ผ่าน server.js
--  - พารามิเตอร์ตัวแรก p_uid = ผู้ใช้ที่ login อยู่ (server.js ใส่ให้จาก session ห้ามส่งจากหน้าเว็บ)
--  - พารามิเตอร์อื่นรับเป็นข้อความ แล้วตรวจ/แปลงในนี้ (ชื่อ p_xxx ↔ ช่อง xxx ที่หน้าเว็บส่งมา)
--  - ข้อผิดพลาดใช้ SIGNAL SQLSTATE '45000' ข้อความรูปแบบ 'ช่อง|ข้อความ'
--      ช่อง = ชื่อ input ที่ผิด  /  !denied = ไม่มีสิทธิ์  /  !notfound = ไม่พบข้อมูล
--      ไม่มี | = ข้อความทั่วไป
-- =====================================================================
USE mut_shuttle;

-- ปรับโครงสร้างฐานข้อมูลเดิม (รันซ้ำได้ — ข้ามถ้ามีแล้ว)
-- ตำแหน่งสังกัดแผนก (positions.department_id — NULL = ใช้ได้ทุกแผนก)
DELIMITER $$
DROP PROCEDURE IF EXISTS mut_migrate$$
CREATE PROCEDURE mut_migrate()
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'positions' AND COLUMN_NAME = 'department_id') THEN
    ALTER TABLE positions
      ADD COLUMN department_id VARCHAR(10) NULL COMMENT 'แผนกของตำแหน่ง (FK) — NULL = ใช้ได้ทุกแผนก' AFTER position_name,
      ADD CONSTRAINT fk_positions_department FOREIGN KEY (department_id) REFERENCES departments (department_id);
  END IF;
END$$
DELIMITER ;
CALL mut_migrate();
DROP PROCEDURE mut_migrate;

-- ลบของเดิม (รันไฟล์นี้ซ้ำได้)
DROP VIEW IF EXISTS v_item_details;
DROP VIEW IF EXISTS v_trip_details;

-- =====================================================================
-- 1) Views ที่ใช้ซ้ำหลายหน้า
-- =====================================================================

-- รายการจอง + ข้อมูลรอบ/เส้นทาง/รถ/จุดจอด + สถานะที่แสดง + ยกเลิกได้หรือไม่ + แท็บในหน้า "การจองของฉัน"
CREATE VIEW v_item_details AS
SELECT t.booking_item_id, t.booking_id, t.trip_id, t.seats, t.status, t.checkin_at,
       t.board_at, t.alight_at, t.user_id, t.passenger_name,
       t.board_stop_id, t.alight_stop_id, sb.stop_name AS board_stop, sa.stop_name AS alight_stop,
       tr.trip_date, tr.depart_time, tr.status AS trip_status, tr.route_id, r.route_name,
       v.plate_no, vt.type_name, bi.qr_code, b.booked_at,
       CASE WHEN t.checkin_at IS NOT NULL AND t.status = 'ยืนยัน' THEN 'Check-in แล้ว' ELSE t.status END AS display_status,
       CASE WHEN t.status = 'ยืนยัน' AND t.checkin_at IS NULL AND tr.status = 'เปิด' THEN 1 ELSE 0 END AS can_cancel,
       CASE WHEN t.status = 'ยกเลิก' OR tr.status = 'ยกเลิก' THEN 'cancelled'
            WHEN t.checkin_at IS NOT NULL OR t.status = 'No Show' OR tr.status = 'เสร็จสิ้น' THEN 'done'
            ELSE 'upcoming' END AS tab
FROM v_booking_item_times t
JOIN booking_items bi ON bi.booking_item_id = t.booking_item_id
JOIN bookings b       ON b.booking_id = t.booking_id
JOIN trips tr         ON tr.trip_id = t.trip_id
JOIN routes r         ON r.route_id = tr.route_id
JOIN vehicles v       ON v.vehicle_id = tr.vehicle_id
JOIN vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id
JOIN stops sb         ON sb.stop_id = t.board_stop_id
JOIN stops sa         ON sa.stop_id = t.alight_stop_id;

-- รอบการเดินรถ + เส้นทาง/รถ/คนขับ/ที่นั่ง/เวลารวม/เวลาถึงปลายทาง
CREATE VIEW v_trip_details AS
SELECT tr.trip_id, tr.trip_date, tr.depart_time, tr.status, tr.route_id, tr.vehicle_id, tr.driver_id,
       r.route_name, v.plate_no, vt.type_name, s.seat_count, s.booked_seats, s.remaining_seats,
       rt.total_minutes, u.name AS driver_name,
       TIMESTAMP(tr.trip_date, tr.depart_time) + INTERVAL rt.total_minutes MINUTE AS end_at
FROM trips tr
JOIN routes r          ON r.route_id = tr.route_id
JOIN v_route_totals rt ON rt.route_id = tr.route_id
JOIN vehicles v        ON v.vehicle_id = tr.vehicle_id
JOIN vehicle_types vt  ON vt.vehicle_type_id = v.vehicle_type_id
JOIN v_trip_seats s    ON s.trip_id = tr.trip_id
JOIN users u           ON u.user_id = tr.driver_id;


DELIMITER $$

-- =====================================================================
-- 2) ฟังก์ชันช่วย
-- =====================================================================

DROP FUNCTION IF EXISTS mut_fmt_id$$
-- สร้างรหัส เช่น ('TR', 7, 3) → 'TR007' (ตัวเลขยาวเกินก็ไม่ตัด)
CREATE FUNCTION mut_fmt_id(p_prefix VARCHAR(5), p_n INT, p_pad INT) RETURNS VARCHAR(20)
DETERMINISTIC NO SQL
RETURN CONCAT(p_prefix, LPAD(p_n, GREATEST(p_pad, CHAR_LENGTH(p_n)), '0'))$$

DROP FUNCTION IF EXISTS mut_blank$$
-- ค่าว่างหรือ NULL
CREATE FUNCTION mut_blank(p VARCHAR(4000)) RETURNS TINYINT
DETERMINISTIC NO SQL
RETURN p IS NULL OR TRIM(p) = ''$$

DROP FUNCTION IF EXISTS mut_is_int$$
-- เป็นจำนวนเต็มหรือไม่ (รวมค่าติดลบ)
CREATE FUNCTION mut_is_int(p VARCHAR(50)) RETURNS TINYINT
DETERMINISTIC NO SQL
RETURN p IS NOT NULL AND TRIM(p) REGEXP '^-?[0-9]{1,9}$'$$

DROP FUNCTION IF EXISTS mut_is_date$$
-- รูปแบบ YYYY-MM-DD และเป็นวันที่จริง
CREATE FUNCTION mut_is_date(p VARCHAR(20)) RETURNS TINYINT
DETERMINISTIC NO SQL
RETURN p IS NOT NULL AND p REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' AND STR_TO_DATE(p, '%Y-%m-%d') IS NOT NULL$$

DROP FUNCTION IF EXISTS mut_is_email$$
CREATE FUNCTION mut_is_email(p VARCHAR(255)) RETURNS TINYINT
DETERMINISTIC NO SQL
RETURN p IS NOT NULL AND CHAR_LENGTH(p) <= 150 AND p REGEXP '^[^[:space:]@]+@[^[:space:]@]+\\.[^[:space:]@]+$'$$

DROP FUNCTION IF EXISTS mut_is_username$$
CREATE FUNCTION mut_is_username(p VARCHAR(255)) RETURNS TINYINT
DETERMINISTIC NO SQL
RETURN p IS NOT NULL AND p REGEXP '^[A-Za-z0-9_.-]{3,50}$'$$

DROP FUNCTION IF EXISTS mut_time_add$$
-- เวลา + นาที → 'HH:MM' (วนรอบ 24 ชั่วโมง)
CREATE FUNCTION mut_time_add(p_time TIME, p_minutes INT) RETURNS VARCHAR(5)
DETERMINISTIC NO SQL
RETURN TIME_FORMAT(SEC_TO_TIME(MOD(TIME_TO_SEC(p_time) + COALESCE(p_minutes, 0) * 60, 86400)), '%H:%i')$$

DROP FUNCTION IF EXISTS mut_days_overlap$$
-- ชุดวันที่วิ่ง 2 ชุด (เช่น '12345' กับ '06') มีวันร่วมกันหรือไม่
CREATE FUNCTION mut_days_overlap(a VARCHAR(7), b VARCHAR(7)) RETURNS TINYINT
DETERMINISTIC NO SQL
BEGIN
  DECLARE i INT DEFAULT 0;
  WHILE i <= 6 DO
    IF LOCATE(SUBSTRING('0123456', i + 1, 1), a) > 0 AND LOCATE(SUBSTRING('0123456', i + 1, 1), b) > 0 THEN
      RETURN 1;
    END IF;
    SET i = i + 1;
  END WHILE;
  RETURN 0;
END$$

DROP FUNCTION IF EXISTS mut_runs_on$$
-- วันที่นี้อยู่ในชุดวันที่วิ่ง (เช่น '12345') หรือไม่ — ใส่ตัวแปรก่อนเทียบ ให้ collation ตรงกับคอลัมน์ (กัน Illegal mix of collations)
CREATE FUNCTION mut_runs_on(p_days VARCHAR(7), p_date DATE) RETURNS TINYINT
DETERMINISTIC NO SQL
BEGIN
  DECLARE v_day CHAR(1) DEFAULT CAST(DAYOFWEEK(p_date) - 1 AS CHAR);   -- DAYOFWEEK 1 = อาทิตย์ → '0'
  RETURN LOCATE(v_day, p_days) > 0;
END$$

DROP FUNCTION IF EXISTS mut_sha256$$
-- SHA2-256 (hex) — ห่อเป็นฟังก์ชันให้ผลลัพธ์ใช้ collation เดียวกับฐานข้อมูล (กัน Illegal mix of collations)
CREATE FUNCTION mut_sha256(p VARCHAR(600)) RETURNS VARCHAR(64)
DETERMINISTIC NO SQL
RETURN LOWER(SHA2(p, 256))$$

DROP FUNCTION IF EXISTS mut_hash_password$$
-- hash รหัสผ่าน: 'sha256$<salt>$<SHA2(salt + password)>'
CREATE FUNCTION mut_hash_password(p_password VARCHAR(255)) RETURNS VARCHAR(255)
NOT DETERMINISTIC NO SQL
BEGIN
  DECLARE v_salt VARCHAR(16) DEFAULT LEFT(mut_sha256(CONCAT(UUID(), RAND())), 16);
  RETURN CONCAT('sha256$', v_salt, '$', mut_sha256(CONCAT(v_salt, p_password)));
END$$

DROP FUNCTION IF EXISTS mut_check_password$$
-- ตรวจรหัสผ่าน รองรับ 2 แบบ: sha256$salt$hash (ระบบนี้) และ SHA2-256 hex ไม่มี salt (ข้อมูล seed)
CREATE FUNCTION mut_check_password(p_password VARCHAR(255), p_hash VARCHAR(255)) RETURNS TINYINT
DETERMINISTIC NO SQL
BEGIN
  IF p_password IS NULL OR p_hash IS NULL THEN
    RETURN 0;
  END IF;
  IF p_hash LIKE 'sha256$%$%' THEN
    RETURN mut_sha256(CONCAT(SUBSTRING_INDEX(SUBSTRING_INDEX(p_hash, '$', 2), '$', -1), p_password))
           = LOWER(SUBSTRING_INDEX(p_hash, '$', -1));
  END IF;
  IF p_hash REGEXP '^[0-9a-fA-F]{64}$' THEN
    RETURN mut_sha256(p_password) = LOWER(p_hash);
  END IF;
  RETURN 0;
END$$

DROP FUNCTION IF EXISTS mut_can$$
-- สิทธิ์ของผู้ใช้ต่อหน้าจอ: p_action = '' (เข้าถึง) / 'add' / 'edit' / 'delete'
CREATE FUNCTION mut_can(p_uid VARCHAR(10), p_screen VARCHAR(10), p_action VARCHAR(10)) RETURNS TINYINT
READS SQL DATA
RETURN COALESCE((
  SELECT CASE p_action WHEN 'add' THEN p.can_add WHEN 'edit' THEN p.can_edit WHEN 'delete' THEN p.can_delete ELSE 1 END
    FROM employees e
    JOIN permissions p ON p.position_id = e.position_id AND p.screen_id = p_screen
   WHERE e.user_id = p_uid
   LIMIT 1), 0)$$

DROP FUNCTION IF EXISTS mut_has_admin$$
-- มีหน้าจอหลังบ้านอย่างน้อย 1 หน้าจอ (SC01–SC11) = เข้า Dashboard ได้
CREATE FUNCTION mut_has_admin(p_uid VARCHAR(10)) RETURNS TINYINT
READS SQL DATA
RETURN EXISTS (
  SELECT 1 FROM employees e JOIN permissions p ON p.position_id = e.position_id
   WHERE e.user_id = p_uid
     AND p.screen_id IN ('SC01','SC02','SC03','SC04','SC05','SC06','SC07','SC08','SC09','SC10','SC11'))$$

DROP FUNCTION IF EXISTS mut_can_assign$$
-- จัดการผู้ใช้ในตำแหน่งนี้ได้หรือไม่ (กันผู้มีสิทธิ์จัดการผู้ใช้ ยกระดับตัวเอง/ยึดบัญชีที่มีสิทธิ์สูงกว่า)
-- ได้ = ตำแหน่งนั้นไม่มีสิทธิ์ใดเกินสิทธิ์ของผู้ใช้ / หรือผู้ใช้แก้ไขสิทธิ์ได้ (SC10 edit กำหนดสิทธิ์ตัวเองได้อยู่แล้ว)
-- p_position NULL (ผู้ใช้บริการ ไม่ใช่พนักงาน) = ได้
CREATE FUNCTION mut_can_assign(p_uid VARCHAR(10), p_position VARCHAR(10)) RETURNS TINYINT
READS SQL DATA
RETURN mut_can(p_uid, 'SC10', 'edit') = 1 OR NOT EXISTS (
  SELECT 1 FROM permissions t
   WHERE t.position_id = p_position
     AND NOT EXISTS (SELECT 1 FROM employees e JOIN permissions m ON m.position_id = e.position_id AND m.screen_id = t.screen_id
                      WHERE e.user_id = p_uid
                        AND m.can_add >= t.can_add AND m.can_edit >= t.can_edit AND m.can_delete >= t.can_delete))$$

DROP FUNCTION IF EXISTS mut_driver_busy$$
-- ยังมีงานขับ: เป็นคนขับในรอบตั้งแต่วันนี้ที่ยังไม่จบ หรือในตารางเวลาที่ใช้งานอยู่ (กันถอดสิทธิ์ SC12 แล้วรอบไม่มีคนขับเข้าได้)
CREATE FUNCTION mut_driver_busy(p_user VARCHAR(10)) RETURNS TINYINT
READS SQL DATA
RETURN EXISTS (SELECT 1 FROM trips WHERE driver_id = p_user AND trip_date >= CURDATE() AND status IN ('เปิด', 'กำลังเดินทาง'))
    OR EXISTS (SELECT 1 FROM trip_schedules WHERE driver_id = p_user AND active = 1)$$

DROP FUNCTION IF EXISTS mut_landing$$
-- หน้าแรกหลัง login ตามสิทธิ์
CREATE FUNCTION mut_landing(p_uid VARCHAR(10)) RETURNS VARCHAR(20)
READS SQL DATA
RETURN CASE WHEN mut_can(p_uid, 'SC12', '') = 1 THEN '/driver/'
            WHEN mut_has_admin(p_uid) = 1 THEN '/admin/'
            ELSE '/' END$$

DROP PROCEDURE IF EXISTS sp_require$$
-- ตรวจสิทธิ์ ไม่ผ่าน → !denied
CREATE PROCEDURE sp_require(IN p_uid VARCHAR(10), IN p_screen VARCHAR(10), IN p_action VARCHAR(10))
BEGIN
  IF p_uid IS NULL OR mut_can(p_uid, p_screen, p_action) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!denied|ตำแหน่งของคุณไม่มีสิทธิ์ใช้งานส่วนนี้';
  END IF;
END$$

DROP PROCEDURE IF EXISTS sp_require_admin$$
CREATE PROCEDURE sp_require_admin(IN p_uid VARCHAR(10))
BEGIN
  IF p_uid IS NULL OR mut_has_admin(p_uid) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!denied|ตำแหน่งของคุณไม่มีสิทธิ์ใช้งานหลังบ้าน';
  END IF;
END$$


-- =====================================================================
-- 3) รอบการเดินรถอัตโนมัติจากตารางเวลาเดินรถ (trip_schedules)
--    - ข้ามวัน/ตารางเวลาที่มีรอบอยู่แล้ว (รวมรอบที่ถูกยกเลิก จึงไม่สร้างรอบที่ admin ยกเลิกกลับมา)
--    - สร้างเฉพาะวันที่ตรงกับวันที่วิ่ง (run_days: 0 = อาทิตย์ … 6 = เสาร์)
--    - รถไม่พร้อมใช้งาน / รถหรือคนขับชนเวลา (trigger ปฏิเสธ) → ข้ามรอบนั้น
--    - server.js เรียก sp_ensure_trips(CURDATE(), 8) ตอนเปิดเว็บและทุกชั่วโมง
-- =====================================================================

DROP PROCEDURE IF EXISTS sp_ensure_trips$$
CREATE PROCEDURE sp_ensure_trips(IN p_from DATE, IN p_days INT)
BEGIN
  DECLARE v_first DATE;
  DECLARE v_last DATE;
  DECLARE v_date DATE;
  DECLARE v_day CHAR(1);
  DECLARE v_done INT DEFAULT 0;
  DECLARE v_lock INT;
  DECLARE v_n INT;
  DECLARE s_id, s_route, s_vehicle, s_driver VARCHAR(10);
  DECLARE s_time TIME;
  DECLARE s_days VARCHAR(7);
  DECLARE cur CURSOR FOR
    SELECT schedule_id, route_id, depart_time, vehicle_id, driver_id, run_days
      FROM trip_schedules WHERE active = 1 ORDER BY depart_time, route_id;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

  SET v_first = GREATEST(p_from, CURDATE());
  SET v_last = LEAST(p_from + INTERVAL (p_days - 1) DAY, CURDATE() + INTERVAL 60 DAY);

  -- ทำทีละงาน (เรียกพร้อมกันหลายที่จะไม่สร้างรอบซ้ำ)
  SET v_lock = GET_LOCK('mut_ensure_trips', 15);
  SET v_date = v_first;
  WHILE v_date <= v_last DO
    SET v_day = CAST(DAYOFWEEK(v_date) - 1 AS CHAR);   -- DAYOFWEEK 1 = อาทิตย์ → '0'
    SET v_done = 0;
    OPEN cur;
    read_loop: LOOP
      FETCH cur INTO s_id, s_route, s_time, s_vehicle, s_driver, s_days;
      IF v_done = 1 THEN
        LEAVE read_loop;
      END IF;
      IF LOCATE(v_day, s_days) > 0
         AND NOT EXISTS (SELECT 1 FROM trips t
                          WHERE t.trip_date = v_date
                            AND (t.schedule_id = s_id OR (t.route_id = s_route AND t.depart_time = s_time))) THEN
        BEGIN
          -- trigger ปฏิเสธ (รถไม่พร้อม/ชนเวลา) → ข้ามรอบนี้
          DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' BEGIN END;
          SET v_n = (SELECT COALESCE(MAX(CAST(SUBSTRING(trip_id, 3) AS UNSIGNED)), 0) + 1 FROM trips WHERE trip_id LIKE 'TR%');
          INSERT INTO trips (trip_id, trip_date, depart_time, status, vehicle_id, route_id, driver_id, schedule_id)
          VALUES (mut_fmt_id('TR', v_n, 3), v_date, s_time, 'เปิด', s_vehicle, s_route, s_driver, s_id);
        END;
      END IF;
    END LOOP;
    CLOSE cur;
    SET v_date = v_date + INTERVAL 1 DAY;
  END WHILE;
  SET v_lock = RELEASE_LOCK('mut_ensure_trips');
END$$

DROP PROCEDURE IF EXISTS sp_remove_upcoming$$
-- ลบรอบล่วงหน้าของตารางเวลาที่ยังไม่มีการจอง
CREATE PROCEDURE sp_remove_upcoming(IN p_schedule VARCHAR(10))
BEGIN
  DELETE FROM trips
   WHERE schedule_id = p_schedule AND status = 'เปิด' AND TIMESTAMP(trip_date, depart_time) > NOW()
     AND NOT EXISTS (SELECT 1 FROM booking_items bi WHERE bi.trip_id = trips.trip_id);
END$$

DROP PROCEDURE IF EXISTS sp_sync_trip_seats$$
-- จำนวนที่นั่งของรอบที่ยังเปิด = จำนวนที่นั่งของประเภทรถ (หลังแก้ประเภทรถ/รถ)
CREATE PROCEDURE sp_sync_trip_seats()
BEGIN
  UPDATE trips t
    JOIN vehicles v       ON v.vehicle_id = t.vehicle_id
    JOIN vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id
     SET t.seat_count = vt.seat_count
   WHERE t.status = 'เปิด' AND t.seat_count <> vt.seat_count;
END$$


-- =====================================================================
-- 4) เข้าสู่ระบบ / สมัครสมาชิก (server.js เรียกตรง — ไม่ใช่ api_ เพราะยังไม่มี session)
-- =====================================================================

DROP PROCEDURE IF EXISTS sp_login$$
-- คืนข้อมูลผู้ใช้ + หน้าแรก
-- รหัสผ่านแบบ bcrypt (จากระบบเดิมเวอร์ชัน EJS) SQL ตรวจไม่ได้ → คืน bcrypt_hash ให้ server.js ตรวจแทน
CREATE PROCEDURE sp_login(IN p_username VARCHAR(100), IN p_password VARCHAR(255))
proc: BEGIN
  DECLARE v_id VARCHAR(10);
  DECLARE v_hash VARCHAR(255);
  SET p_username = TRIM(COALESCE(p_username, ''));

  IF p_username = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'username|กรุณากรอก username';
  END IF;
  IF COALESCE(p_password, '') = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'password|กรุณากรอก password';
  END IF;

  SET v_id = (SELECT user_id FROM users WHERE username = p_username);
  IF v_id IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'username|ไม่พบ username นี้ในระบบ';
  END IF;
  SET v_hash = (SELECT password_hash FROM users WHERE user_id = v_id);

  IF v_hash LIKE '$2%' THEN
    SELECT user_id, name, username, password_hash AS bcrypt_hash, mut_landing(user_id) AS landing
      FROM users WHERE user_id = v_id;
    LEAVE proc;
  END IF;

  IF mut_check_password(p_password, v_hash) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'password|password ไม่ถูกต้อง';
  END IF;

  -- อัปเกรด hash แบบไม่มี salt (seed) เป็นแบบมี salt
  IF v_hash NOT LIKE 'sha256$%' THEN
    UPDATE users SET password_hash = mut_hash_password(p_password) WHERE user_id = v_id;
  END IF;

  SELECT user_id, name, username, NULL AS bcrypt_hash, mut_landing(user_id) AS landing
    FROM users WHERE user_id = v_id;
END$$

DROP PROCEDURE IF EXISTS sp_set_password$$
-- ใช้หลัง server.js ตรวจ bcrypt ผ่าน: เปลี่ยนเป็น hash ของระบบนี้
CREATE PROCEDURE sp_set_password(IN p_uid VARCHAR(10), IN p_password VARCHAR(255))
BEGIN
  UPDATE users SET password_hash = mut_hash_password(p_password) WHERE user_id = p_uid;
END$$

DROP PROCEDURE IF EXISTS sp_register$$
-- สมัครสมาชิก: ผู้ใช้บริการ (ไม่ใช่พนักงาน) อยู่แผนก D003 = นักศึกษา
CREATE PROCEDURE sp_register(IN p_name VARCHAR(255), IN p_email VARCHAR(255), IN p_username VARCHAR(255),
                             IN p_password VARCHAR(255), IN p_confirm VARCHAR(255))
BEGIN
  DECLARE v_id VARCHAR(10);
  DECLARE v_n INT;
  DECLARE EXIT HANDLER FOR 1062
  BEGIN
    ROLLBACK;
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'username|username หรือ email นี้ถูกใช้แล้ว';
  END;

  SET p_name = TRIM(COALESCE(p_name, ''));
  SET p_email = TRIM(COALESCE(p_email, ''));
  SET p_username = TRIM(COALESCE(p_username, ''));
  SET p_password = COALESCE(p_password, '');

  IF p_name = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'name|กรุณากรอกชื่อ-นามสกุล';
  ELSEIF CHAR_LENGTH(p_name) > 100 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'name|ชื่อยาวได้ไม่เกิน 100 ตัวอักษร';
  ELSEIF mut_is_email(p_email) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'email|รูปแบบ email ไม่ถูกต้อง';
  ELSEIF mut_is_username(p_username) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'username|username ใช้ a-z, 0-9, _ . - ความยาว 3–50 ตัวอักษร';
  ELSEIF CHAR_LENGTH(p_password) < 4 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'password|password ต้องมีอย่างน้อย 4 ตัวอักษร';
  ELSEIF p_password <> COALESCE(p_confirm, '') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'confirm|ยืนยัน password ไม่ตรงกัน';
  ELSEIF EXISTS (SELECT 1 FROM users WHERE email = p_email) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'email|email นี้ถูกใช้แล้ว';
  ELSEIF EXISTS (SELECT 1 FROM users WHERE username = p_username) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'username|username นี้ถูกใช้แล้ว';
  END IF;

  START TRANSACTION;
    SET v_n = (SELECT COALESCE(MAX(CAST(SUBSTRING(user_id, 2) AS UNSIGNED)), 0) + 1 FROM users WHERE user_id LIKE 'U%');
    SET v_id = mut_fmt_id('U', v_n, 3);
    INSERT INTO users (user_id, name, email, username, password_hash, department_id)
    VALUES (v_id, p_name, p_email, p_username, mut_hash_password(p_password), 'D003');
  COMMIT;

  SELECT user_id, name, username, mut_landing(user_id) AS landing FROM users WHERE user_id = v_id;
END$$

DROP PROCEDURE IF EXISTS api_me$$
-- ข้อมูลผู้ใช้ที่ login + สิทธิ์ (หน้าเว็บใช้แสดงเมนู/ปุ่ม)
-- ชุดที่ 1: ผู้ใช้ / ชุดที่ 2: สิทธิ์รายหน้าจอ
CREATE PROCEDURE api_me(IN p_uid VARCHAR(10))
BEGIN
  SELECT u.user_id, u.name, u.username, e.position_id,
         mut_can(u.user_id, 'SC12', '') AS is_driver,
         mut_has_admin(u.user_id) AS has_admin,
         mut_landing(u.user_id) AS landing,
         CURDATE() AS today
    FROM users u LEFT JOIN employees e ON e.user_id = u.user_id
   WHERE u.user_id = p_uid;
  SELECT p.screen_id, p.can_add, p.can_edit, p.can_delete
    FROM employees e JOIN permissions p ON p.position_id = e.position_id
   WHERE e.user_id = p_uid
   ORDER BY p.screen_id;
END$$

DELIMITER ;


-- =====================================================================
-- 5) ผู้ใช้บริการ (จองรถ)
-- =====================================================================
DELIMITER $$

DROP PROCEDURE IF EXISTS api_home$$
-- หน้าหลัก: ชุดที่ 1 = การเดินทางถัดไป (0–1 แถว) / ชุดที่ 2 = จำนวนรายการที่กำลังจะถึง
CREATE PROCEDURE api_home(IN p_uid VARCHAR(10))
BEGIN
  SELECT * FROM v_item_details t
   WHERE t.user_id = p_uid AND t.status = 'ยืนยัน' AND t.checkin_at IS NULL
     AND t.trip_status IN ('เปิด', 'กำลังเดินทาง') AND t.board_at >= CURDATE()
   ORDER BY t.board_at LIMIT 1;
  SELECT COUNT(*) AS n FROM v_item_details t
   WHERE t.user_id = p_uid AND t.status = 'ยืนยัน' AND t.checkin_at IS NULL
     AND t.trip_status IN ('เปิด', 'กำลังเดินทาง');
END$$

DROP PROCEDURE IF EXISTS api_search_form$$
-- ตัวเลือกหน้าค้นหา: ชุดที่ 1 = จุดจอด / ชุดที่ 2 = ลำดับจุดจอดทุกเส้นทาง (จำกัดจุดลงให้อยู่หลังจุดขึ้น)
--                    ชุดที่ 3 = ช่วงวันที่ค้นหาได้ (วันนี้ ถึง +60 วัน)
CREATE PROCEDURE api_search_form(IN p_uid VARCHAR(10))
BEGIN
  SELECT stop_id, stop_name FROM stops ORDER BY stop_id;
  SELECT route_id, stop_id FROM route_stops ORDER BY route_id, stop_order;
  SELECT CURDATE() AS min_date, CURDATE() + INTERVAL 60 DAY AS max_date;
END$$

DROP PROCEDURE IF EXISTS api_search$$
-- ค้นหารอบรถที่จองได้ (สร้างรอบจากตารางเวลาให้ก่อนถ้ายังไม่มี)
CREATE PROCEDURE api_search(IN p_uid VARCHAR(10), IN p_date VARCHAR(20), IN p_board VARCHAR(10), IN p_alight VARCHAR(10))
BEGIN
  DECLARE v_date DATE;
  IF mut_blank(p_board) OR mut_blank(p_alight) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'กรุณาเลือกจุดขึ้นและจุดลง';
  END IF;
  IF p_board = p_alight THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'จุดขึ้นและจุดลงต้องไม่ใช่จุดเดียวกัน';
  END IF;
  IF mut_is_date(p_date) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'กรุณาเลือกวันที่';
  END IF;
  SET v_date = STR_TO_DATE(p_date, '%Y-%m-%d');
  IF v_date < CURDATE() THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ไม่สามารถค้นหารอบของวันที่ผ่านมาแล้ว';
  END IF;
  IF v_date > CURDATE() + INTERVAL 60 DAY THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ค้นหาล่วงหน้าได้ไม่เกิน 60 วัน';
  END IF;

  CALL sp_ensure_trips(v_date, 1);
  CALL sp_search_trips(v_date, p_board, p_alight);
END$$

DROP PROCEDURE IF EXISTS api_trip$$
-- รายละเอียดรอบ + ช่วงจุดขึ้น/ลงที่เลือก + เหตุผลถ้าจองไม่ได้ (ใช้ทั้งหน้ารายละเอียดรอบ/เลือกที่นั่ง/ยืนยัน)
-- ชุดที่ 1: รอบ (seg_remaining = ที่นั่งว่างเฉพาะช่วงที่เลือก, blocked = เหตุผลที่จองไม่ได้ หรือ NULL)
-- ชุดที่ 2: จุดจอดทั้งหมดของรอบพร้อมเวลาถึง
CREATE PROCEDURE api_trip(IN p_uid VARCHAR(10), IN p_trip VARCHAR(10), IN p_board VARCHAR(10), IN p_alight VARCHAR(10))
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE v_b INT;
  DECLARE v_a INT;
  DECLARE v_bookable INT DEFAULT 0;
  DECLARE v_remaining INT;
  DECLARE v_blocked VARCHAR(200);

  SET v_status = (SELECT status FROM trips WHERE trip_id = p_trip);
  IF v_status IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบรอบการเดินรถ';
  END IF;

  -- จุดขึ้น = ลำดับแรกที่ตรง / จุดลง = ลำดับแรกหลังจุดขึ้น
  SET v_b = (SELECT MIN(stop_order) FROM v_trip_stop_times WHERE trip_id = p_trip AND stop_id = p_board);
  SET v_a = (SELECT MIN(stop_order) FROM v_trip_stop_times WHERE trip_id = p_trip AND stop_id = p_alight AND stop_order > v_b);

  IF v_b IS NOT NULL AND v_a IS NOT NULL THEN
    SET v_remaining = mut_segment_remaining(p_trip, p_board, p_alight, NULL);
    SET v_bookable = (SELECT arrive_at >= NOW() + INTERVAL 20 MINUTE FROM v_trip_stop_times
                       WHERE trip_id = p_trip AND stop_order = v_b);
  ELSE
    SET v_remaining = (SELECT remaining_seats FROM v_trip_seats WHERE trip_id = p_trip);
  END IF;

  SET v_blocked = CASE
    WHEN v_b IS NULL OR v_a IS NULL THEN 'เลือกจุดขึ้นและจุดลงจากหน้าค้นหาก่อนจอง'
    WHEN v_status <> 'เปิด' THEN 'รอบนี้ไม่เปิดให้จอง'
    WHEN v_bookable = 0 THEN 'ปิดรับจองแล้ว (ต้องจองก่อนรถถึงจุดขึ้นอย่างน้อย 20 นาที)'
    WHEN v_remaining <= 0 THEN 'ที่นั่งเต็มในช่วงจุดขึ้น–จุดลงนี้'
    ELSE NULL END;

  SELECT d.trip_id, d.trip_date, d.depart_time, d.status, d.route_id, d.route_name, d.plate_no, d.type_name,
         d.seat_count, d.total_minutes, d.end_at,
         v_remaining AS seg_remaining, LEAST(4, GREATEST(0, v_remaining)) AS max_seats,
         v_blocked AS blocked, v_b AS board_order, v_a AS alight_order
    FROM v_trip_details d WHERE d.trip_id = p_trip;

  SELECT stop_order, stop_id, stop_name, cum_minutes, arrive_at,
         CASE WHEN arrive_at >= NOW() + INTERVAL 20 MINUTE THEN 1 ELSE 0 END AS bookable
    FROM v_trip_stop_times WHERE trip_id = p_trip ORDER BY stop_order;
END$$

DROP PROCEDURE IF EXISTS api_book$$
-- สร้างการจอง (sp_create_booking ตรวจที่นั่ง/เวลาอีกครั้งภายใน transaction) → คืนรหัสรายการจอง
CREATE PROCEDURE api_book(IN p_uid VARCHAR(10), IN p_trip VARCHAR(10), IN p_board VARCHAR(10),
                          IN p_alight VARCHAR(10), IN p_seats VARCHAR(10))
BEGIN
  DECLARE v_booking VARCHAR(10);
  DECLARE v_item VARCHAR(10);
  DECLARE v_qr VARCHAR(64);
  IF mut_is_int(p_seats) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'seats|จองได้ 1–4 ที่นั่งต่อรายการ';
  END IF;
  CALL sp_create_booking(p_uid, p_trip, p_board, p_alight, CAST(p_seats AS SIGNED), v_booking, v_item, v_qr);
  SELECT v_booking AS booking_id, v_item AS item_id, v_qr AS qr_code;
END$$

DROP PROCEDURE IF EXISTS api_item$$
-- รายการจองของตนเอง 1 รายการ (หน้า QR Code)
CREATE PROCEDURE api_item(IN p_uid VARCHAR(10), IN p_item VARCHAR(10))
BEGIN
  IF NOT EXISTS (SELECT 1 FROM booking_items bi JOIN bookings b ON b.booking_id = bi.booking_id
                  WHERE bi.booking_item_id = p_item AND b.user_id = p_uid) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบรายการจอง';
  END IF;
  SELECT * FROM v_item_details WHERE booking_item_id = p_item;
END$$

DROP PROCEDURE IF EXISTS api_my$$
-- การจองของฉันทั้งหมด (หน้าเว็บแยกแท็บจากคอลัมน์ tab)
CREATE PROCEDURE api_my(IN p_uid VARCHAR(10))
BEGIN
  SELECT * FROM v_item_details WHERE user_id = p_uid ORDER BY board_at DESC;
END$$

DROP PROCEDURE IF EXISTS api_cancel$$
-- ยกเลิกรายการจองของตนเอง (ยืนยัน + ยังไม่ Check-in + รอบยังไม่เริ่มเดินทาง)
CREATE PROCEDURE api_cancel(IN p_uid VARCHAR(10), IN p_item VARCHAR(10))
BEGIN
  DECLARE v_can INT;
  DECLARE v_msg VARCHAR(255);
  SELECT can_cancel, CONCAT('ยกเลิกรายการจอง ', booking_item_id, ' แล้ว — คืน ', seats, ' ที่นั่งให้รอบ ',
                            TIME_FORMAT(depart_time, '%H:%i'), ' ', route_name)
    INTO v_can, v_msg
    FROM v_item_details WHERE booking_item_id = p_item AND user_id = p_uid
   LIMIT 1;
  IF COALESCE(v_can, 0) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'รายการนี้ยกเลิกไม่ได้';
  END IF;
  CALL sp_cancel_booking_item(p_item, p_uid);
  SELECT v_msg AS message;
END$$

DROP PROCEDURE IF EXISTS api_profile$$
CREATE PROCEDURE api_profile(IN p_uid VARCHAR(10))
BEGIN
  SELECT u.user_id, u.name, u.email, u.username, d.department_name, e.phone, p.position_name
    FROM users u
    JOIN departments d ON d.department_id = u.department_id
    LEFT JOIN employees e ON e.user_id = u.user_id
    LEFT JOIN positions p ON p.position_id = e.position_id
   WHERE u.user_id = p_uid;
END$$

DROP PROCEDURE IF EXISTS api_change_password$$
CREATE PROCEDURE api_change_password(IN p_uid VARCHAR(10), IN p_current VARCHAR(255),
                                     IN p_password VARCHAR(255), IN p_confirm VARCHAR(255))
BEGIN
  DECLARE v_hash VARCHAR(255);
  SET v_hash = (SELECT password_hash FROM users WHERE user_id = p_uid);
  IF v_hash LIKE '$2%' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'current|กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่ 1 ครั้งก่อนเปลี่ยน password';
  END IF;
  IF mut_check_password(COALESCE(p_current, ''), v_hash) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'current|password ปัจจุบันไม่ถูกต้อง';
  END IF;
  IF CHAR_LENGTH(COALESCE(p_password, '')) < 4 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'password|password ใหม่ต้องมีอย่างน้อย 4 ตัวอักษร';
  END IF;
  IF p_password <> COALESCE(p_confirm, '') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'confirm|ยืนยัน password ไม่ตรงกัน';
  END IF;
  UPDATE users SET password_hash = mut_hash_password(p_password) WHERE user_id = p_uid;
  SELECT 'เปลี่ยน password เรียบร้อยแล้ว' AS message;
END$$

DELIMITER ;


-- =====================================================================
-- 6) คนขับ (ต้องมีสิทธิ์หน้าจอ SC12 และเป็นรอบของตนเอง)
-- =====================================================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_require_my_trip$$
CREATE PROCEDURE sp_require_my_trip(IN p_uid VARCHAR(10), IN p_trip VARCHAR(10))
BEGIN
  DECLARE v_driver VARCHAR(10);
  CALL sp_require(p_uid, 'SC12', '');
  SET v_driver = (SELECT driver_id FROM trips WHERE trip_id = p_trip);
  IF v_driver IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบรอบการเดินรถ';
  END IF;
  IF v_driver <> p_uid THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!denied|รอบนี้ไม่ใช่รอบที่คุณได้รับมอบหมาย';
  END IF;
END$$

DROP PROCEDURE IF EXISTS sp_trip_counts$$
-- จำนวนที่นั่ง จองแล้ว / Check-in / รอขึ้นรถ / No Show ของรอบ
CREATE PROCEDURE sp_trip_counts(IN p_trip VARCHAR(10))
BEGIN
  SELECT COALESCE(SUM(seats), 0) AS booked,
         COALESCE(SUM(CASE WHEN checkin_at IS NOT NULL THEN seats END), 0) AS checked_in,
         COALESCE(SUM(CASE WHEN checkin_at IS NULL AND status = 'ยืนยัน' THEN seats END), 0) AS waiting,
         COALESCE(SUM(CASE WHEN status = 'No Show' THEN seats END), 0) AS no_show
    FROM booking_items WHERE trip_id = p_trip AND status <> 'ยกเลิก';
END$$

DROP PROCEDURE IF EXISTS api_driver_today$$
-- ชุดที่ 1 = งานวันนี้ / ชุดที่ 2 = งานที่จะถึงใน 7 วัน
CREATE PROCEDURE api_driver_today(IN p_uid VARCHAR(10))
BEGIN
  CALL sp_require(p_uid, 'SC12', '');
  SELECT * FROM v_trip_details WHERE driver_id = p_uid AND trip_date = CURDATE() ORDER BY depart_time;
  SELECT * FROM v_trip_details
   WHERE driver_id = p_uid AND trip_date > CURDATE() AND trip_date <= CURDATE() + INTERVAL 7 DAY AND status <> 'ยกเลิก'
   ORDER BY trip_date, depart_time;
END$$

DROP PROCEDURE IF EXISTS api_driver_trip$$
-- ชุดที่ 1 = รอบ / ชุดที่ 2 = จำนวนที่นั่ง / ชุดที่ 3 = ผู้โดยสารขึ้น/ลงตามลำดับจุดจอด (role = up/down)
CREATE PROCEDURE api_driver_trip(IN p_uid VARCHAR(10), IN p_trip VARCHAR(10))
BEGIN
  CALL sp_require_my_trip(p_uid, p_trip);
  SELECT d.*, CURDATE() AS today FROM v_trip_details d WHERE d.trip_id = p_trip;
  CALL sp_trip_counts(p_trip);
  SELECT ts.stop_order, ts.stop_name, ts.arrive_at,
         bi.booking_item_id, bi.passenger_name, bi.seats, bi.checkin_at, bi.status,
         CASE WHEN bi.board_order = ts.stop_order THEN 1 ELSE 0 END AS is_up,
         CASE WHEN bi.alight_order = ts.stop_order THEN 1 ELSE 0 END AS is_down
    FROM v_trip_stop_times ts
    LEFT JOIN v_booking_item_times bi
           ON bi.trip_id = ts.trip_id AND bi.status <> 'ยกเลิก'
          AND (bi.board_order = ts.stop_order OR bi.alight_order = ts.stop_order)
   WHERE ts.trip_id = p_trip
   ORDER BY ts.stop_order, bi.booking_item_id;
END$$

DROP PROCEDURE IF EXISTS api_driver_start$$
-- เริ่มการเดินทาง (เฉพาะรอบของวันนี้)
CREATE PROCEDURE api_driver_start(IN p_uid VARCHAR(10), IN p_trip VARCHAR(10))
BEGIN
  DECLARE v_date DATE;
  DECLARE v_msg VARCHAR(200);
  CALL sp_require_my_trip(p_uid, p_trip);
  SET v_date = (SELECT trip_date FROM trips WHERE trip_id = p_trip);
  IF v_date <> CURDATE() THEN
    SET v_msg = CONCAT('เริ่มการเดินทางได้เฉพาะรอบของวันนี้ — รอบนี้เดินรถวันที่ ', DATE_FORMAT(v_date, '%d/%m/%Y'));
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;
  -- กันงานขับซ้อน: คนขับยังมีรอบอื่นที่ยังไม่ปิดงาน / รถยังวิ่งอยู่ในรอบอื่น
  SET v_msg = (SELECT CONCAT('ยังมีรอบ ', trip_id, ' ที่กำลังเดินทางอยู่ — ปิดงานรอบนั้นก่อนเริ่มรอบใหม่')
                 FROM trips WHERE driver_id = p_uid AND status = 'กำลังเดินทาง' AND trip_id <> p_trip
                ORDER BY trip_date, depart_time LIMIT 1);
  IF v_msg IS NOT NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;
  SET v_msg = (SELECT CONCAT('รถคันนี้ยังอยู่ในรอบ ', o.trip_id, ' ที่กำลังเดินทาง (คนขับ ', u.name, ') — รอให้ปิดงานก่อน')
                 FROM trips t
                 JOIN trips o ON o.vehicle_id = t.vehicle_id AND o.trip_id <> t.trip_id AND o.status = 'กำลังเดินทาง'
                 JOIN users u ON u.user_id = o.driver_id
                WHERE t.trip_id = p_trip LIMIT 1);
  IF v_msg IS NOT NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;
  CALL sp_start_trip(p_trip, p_uid);
  SELECT 'เริ่มการเดินทางแล้ว — สแกน QR ผู้โดยสารได้เลย' AS message;
END$$

DROP PROCEDURE IF EXISTS api_driver_scan$$
-- หน้าสแกน: ชุดที่ 1 = รอบ / ชุดที่ 2 = จำนวนที่นั่ง
CREATE PROCEDURE api_driver_scan(IN p_uid VARCHAR(10), IN p_trip VARCHAR(10))
BEGIN
  CALL sp_require_my_trip(p_uid, p_trip);
  SELECT * FROM v_trip_details WHERE trip_id = p_trip;
  CALL sp_trip_counts(p_trip);
END$$

DROP PROCEDURE IF EXISTS api_driver_checkin$$
-- สแกน QR Check-in: ชุดที่ 1 = ผลการ Check-in / ชุดที่ 2 = จำนวนที่นั่งล่าสุด
CREATE PROCEDURE api_driver_checkin(IN p_uid VARCHAR(10), IN p_trip VARCHAR(10), IN p_qr VARCHAR(100))
BEGIN
  CALL sp_require_my_trip(p_uid, p_trip);
  IF mut_blank(p_qr) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'qr|กรุณาสแกนหรือกรอกรหัส QR';
  END IF;
  CALL sp_checkin(TRIM(p_qr), p_trip);
  CALL sp_trip_counts(p_trip);
END$$

DROP PROCEDURE IF EXISTS api_driver_close_info$$
-- หน้าสรุปก่อนปิดงาน: ชุดที่ 1 = รอบ / ชุดที่ 2 = จำนวนที่นั่ง / ชุดที่ 3 = รายการที่จะเป็น No Show
CREATE PROCEDURE api_driver_close_info(IN p_uid VARCHAR(10), IN p_trip VARCHAR(10))
BEGIN
  CALL sp_require_my_trip(p_uid, p_trip);
  IF (SELECT status FROM trips WHERE trip_id = p_trip) <> 'กำลังเดินทาง' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ปิดงานได้เฉพาะรอบที่กำลังเดินทาง';
  END IF;
  SELECT * FROM v_trip_details WHERE trip_id = p_trip;
  CALL sp_trip_counts(p_trip);
  SELECT t.booking_item_id, t.passenger_name, t.seats, s.stop_name AS board_stop, t.board_at
    FROM v_booking_item_times t JOIN stops s ON s.stop_id = t.board_stop_id
   WHERE t.trip_id = p_trip AND t.status = 'ยืนยัน' AND t.checkin_at IS NULL
   ORDER BY t.board_at;
END$$

DROP PROCEDURE IF EXISTS api_driver_close$$
-- ปิดงาน: ไม่ได้ Check-in → No Show และสรุปผล
CREATE PROCEDURE api_driver_close(IN p_uid VARCHAR(10), IN p_trip VARCHAR(10))
BEGIN
  CALL sp_require_my_trip(p_uid, p_trip);
  CALL sp_close_trip(p_trip);
END$$

DROP PROCEDURE IF EXISTS api_driver_history$$
-- ประวัติรอบที่ขับ (200 รอบล่าสุด)
CREATE PROCEDURE api_driver_history(IN p_uid VARCHAR(10))
BEGIN
  CALL sp_require(p_uid, 'SC12', '');
  SELECT tr.trip_id, tr.trip_date, tr.depart_time, tr.status, r.route_name, v.plate_no, vt.type_name,
         COALESCE(SUM(CASE WHEN bi.status <> 'ยกเลิก' THEN bi.seats END), 0) AS booked,
         COALESCE(SUM(CASE WHEN bi.checkin_at IS NOT NULL THEN bi.seats END), 0) AS actual,
         COALESCE(SUM(CASE WHEN bi.status = 'No Show' THEN bi.seats END), 0) AS no_show
    FROM trips tr
    JOIN routes r         ON r.route_id = tr.route_id
    JOIN vehicles v       ON v.vehicle_id = tr.vehicle_id
    JOIN vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id
    LEFT JOIN booking_items bi ON bi.trip_id = tr.trip_id
   WHERE tr.driver_id = p_uid AND (tr.trip_date < CURDATE() OR tr.status IN ('เสร็จสิ้น', 'ยกเลิก'))
   GROUP BY tr.trip_id, tr.trip_date, tr.depart_time, tr.status, r.route_name, v.plate_no, vt.type_name
   ORDER BY tr.trip_date DESC, tr.depart_time DESC
   LIMIT 200;
END$$

DELIMITER ;


-- =====================================================================
-- 7) หลังบ้าน: Dashboard + ตัวเลือกในฟอร์ม
-- =====================================================================
DELIMITER $$

DROP PROCEDURE IF EXISTS api_dashboard$$
-- ชุดที่ 1 = ตัวเลขสรุปวันนี้ / ชุดที่ 2 = รอบวันนี้ (ต้องมีสิทธิ์ SC06) / ชุดที่ 3 = รายการจองล่าสุด 8 รายการ (ต้องมีสิทธิ์ SC02)
-- ไม่มีสิทธิ์ = ชุดว่าง (เช่น คนขับที่ดูข้อมูลรถได้ ไม่ควรเห็นชื่อผู้โดยสาร)
CREATE PROCEDURE api_dashboard(IN p_uid VARCHAR(10))
BEGIN
  CALL sp_require_admin(p_uid);
  SELECT
    (SELECT COUNT(*) FROM booking_items bi JOIN bookings b ON b.booking_id = bi.booking_id
      WHERE DATE(b.booked_at) = CURDATE())                                                AS items_today,
    (SELECT COUNT(*) FROM trips WHERE trip_date = CURDATE() AND status <> 'ยกเลิก')       AS trips_today,
    (SELECT COALESCE(SUM(bi.seats), 0) FROM booking_items bi JOIN trips t ON t.trip_id = bi.trip_id
      WHERE t.trip_date = CURDATE() AND bi.status <> 'ยกเลิก')                            AS seats_today,
    (SELECT COALESCE(SUM(bi.seats), 0) FROM booking_items bi JOIN trips t ON t.trip_id = bi.trip_id
      WHERE t.trip_date = CURDATE() AND bi.checkin_at IS NOT NULL)                         AS checkin_today,
    (SELECT COUNT(*) FROM booking_items bi JOIN trips t ON t.trip_id = bi.trip_id
      WHERE t.trip_date = CURDATE() AND bi.status = 'No Show')                            AS noshow_today,
    (SELECT COUNT(*) FROM vehicles WHERE status = 'พร้อมใช้งาน')                            AS vehicles_ready,
    (SELECT COUNT(*) FROM vehicles)                                                        AS vehicles_total,
    CURDATE() AS today;
  SELECT * FROM v_trip_details WHERE trip_date = CURDATE() AND mut_can(p_uid, 'SC06', '') = 1 ORDER BY depart_time;
  SELECT * FROM v_item_details WHERE mut_can(p_uid, 'SC02', '') = 1
   ORDER BY booked_at DESC, booking_item_id DESC LIMIT 8;
END$$

DROP PROCEDURE IF EXISTS api_lookups$$
-- ตัวเลือกที่ใช้ในฟอร์ม/ตัวกรองหลังบ้าน (ลำดับชุดข้อมูลคงที่ — public/js/admin.js อ้างตามลำดับนี้)
-- 1 ประเภทรถ 2 เส้นทาง 3 รถ 4 คนขับ 5 แผนก 6 ตำแหน่ง 7 จุดจอด 8 หน้าจอ
CREATE PROCEDURE api_lookups(IN p_uid VARCHAR(10))
BEGIN
  CALL sp_require_admin(p_uid);
  SELECT vehicle_type_id, type_name, seat_count FROM vehicle_types ORDER BY vehicle_type_id;
  SELECT route_id, route_name, total_minutes FROM v_route_totals ORDER BY route_id;
  SELECT v.vehicle_id, v.plate_no, v.status, vt.type_name, vt.seat_count
    FROM vehicles v JOIN vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id ORDER BY v.plate_no;
  -- คนขับ = พนักงานที่ตำแหน่งมีสิทธิ์หน้าจองานคนขับ (SC12) — ใช้ในหน้ารอบ/ตารางเวลา จึงให้เฉพาะผู้มีสิทธิ์ SC06
  SELECT u.user_id, u.name, p.position_name
    FROM employees e JOIN users u ON u.user_id = e.user_id JOIN positions p ON p.position_id = e.position_id
   WHERE e.position_id IN (SELECT position_id FROM permissions WHERE screen_id = 'SC12')
     AND mut_can(p_uid, 'SC06', '') = 1
   ORDER BY u.name;
  SELECT department_id, department_name FROM departments ORDER BY department_id;
  SELECT position_id, position_name, department_id FROM positions ORDER BY position_id;
  SELECT stop_id, stop_name FROM stops ORDER BY stop_id;
  SELECT screen_id, screen_name FROM screens ORDER BY screen_id;
END$$


-- =====================================================================
-- 8) หลังบ้าน: ข้อมูลหลัก (list / get / save / delete)
--    save: p_id ว่าง = เพิ่ม (ต้องมีสิทธิ์ add) / มีค่า = แก้ไข (ต้องมีสิทธิ์ edit)
-- =====================================================================

-- ---------- 10.3 แผนก (SC08) ----------
DROP PROCEDURE IF EXISTS api_departments_list$$
CREATE PROCEDURE api_departments_list(IN p_uid VARCHAR(10), IN p_q VARCHAR(100))
BEGIN
  CALL sp_require(p_uid, 'SC08', '');
  SELECT d.department_id, d.department_name,
         (SELECT COUNT(*) FROM users u WHERE u.department_id = d.department_id) AS user_count
    FROM departments d
   WHERE mut_blank(p_q) OR d.department_id LIKE CONCAT('%', TRIM(p_q), '%') OR d.department_name LIKE CONCAT('%', TRIM(p_q), '%')
   ORDER BY d.department_id;
END$$

DROP PROCEDURE IF EXISTS api_departments_get$$
CREATE PROCEDURE api_departments_get(IN p_uid VARCHAR(10), IN p_id VARCHAR(10))
BEGIN
  CALL sp_require(p_uid, 'SC08', 'edit');
  IF NOT EXISTS (SELECT 1 FROM departments WHERE department_id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบแผนก';
  END IF;
  SELECT * FROM departments WHERE department_id = p_id;
END$$

DROP PROCEDURE IF EXISTS api_departments_save$$
CREATE PROCEDURE api_departments_save(IN p_uid VARCHAR(10), IN p_id VARCHAR(10), IN p_department_name VARCHAR(255))
BEGIN
  DECLARE v_id VARCHAR(10);
  SET p_department_name = TRIM(COALESCE(p_department_name, ''));
  CALL sp_require(p_uid, 'SC08', IF(mut_blank(p_id), 'add', 'edit'));
  IF p_department_name = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'department_name|กรุณากรอกชื่อแผนก';
  ELSEIF CHAR_LENGTH(p_department_name) > 100 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'department_name|ชื่อแผนกยาวได้ไม่เกิน 100 ตัวอักษร';
  END IF;
  IF mut_blank(p_id) THEN
    SET v_id = mut_fmt_id('D', (SELECT COALESCE(MAX(CAST(SUBSTRING(department_id, 2) AS UNSIGNED)), 0) + 1
                                  FROM departments WHERE department_id LIKE 'D%'), 3);
    INSERT INTO departments (department_id, department_name) VALUES (v_id, p_department_name);
    SELECT v_id AS id, CONCAT('เพิ่มแผนก ', v_id, ' เรียบร้อยแล้ว') AS message;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM departments WHERE department_id = p_id) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบแผนก';
    END IF;
    UPDATE departments SET department_name = p_department_name WHERE department_id = p_id;
    SELECT p_id AS id, CONCAT('บันทึกแผนก ', p_id, ' เรียบร้อยแล้ว') AS message;
  END IF;
END$$

DROP PROCEDURE IF EXISTS api_departments_delete$$
CREATE PROCEDURE api_departments_delete(IN p_uid VARCHAR(10), IN p_id VARCHAR(10))
BEGIN
  DECLARE v_n INT;
  DECLARE v_msg VARCHAR(200);
  CALL sp_require(p_uid, 'SC08', 'delete');
  SET v_n = (SELECT COUNT(*) FROM users WHERE department_id = p_id);
  IF v_n > 0 THEN
    SET v_msg = CONCAT('ลบไม่ได้ เนื่องจากมีผู้ใช้งาน ', v_n, ' คนอยู่ในแผนกนี้');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;
  SET v_n = (SELECT COUNT(*) FROM positions WHERE department_id = p_id);
  IF v_n > 0 THEN
    SET v_msg = CONCAT('ลบไม่ได้ เนื่องจากมี ', v_n, ' ตำแหน่งสังกัดแผนกนี้ — ย้ายตำแหน่งไปแผนกอื่นก่อน');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;
  DELETE FROM departments WHERE department_id = p_id;
  SELECT CONCAT('ลบแผนก ', p_id, ' เรียบร้อยแล้ว') AS message;
END$$

-- ---------- 10.4 ตำแหน่ง (SC09) ----------
DROP PROCEDURE IF EXISTS api_positions_list$$
CREATE PROCEDURE api_positions_list(IN p_uid VARCHAR(10), IN p_q VARCHAR(100))
BEGIN
  CALL sp_require(p_uid, 'SC09', '');
  SELECT p.position_id, p.position_name, p.department_id, d.department_name,
         (SELECT COUNT(*) FROM employees e WHERE e.position_id = p.position_id) AS employee_count,
         (SELECT COUNT(*) FROM permissions x WHERE x.position_id = p.position_id) AS screen_count
    FROM positions p LEFT JOIN departments d ON d.department_id = p.department_id
   WHERE mut_blank(p_q) OR p.position_id LIKE CONCAT('%', TRIM(p_q), '%') OR p.position_name LIKE CONCAT('%', TRIM(p_q), '%')
   ORDER BY p.position_id;
END$$

DROP PROCEDURE IF EXISTS api_positions_get$$
CREATE PROCEDURE api_positions_get(IN p_uid VARCHAR(10), IN p_id VARCHAR(10))
BEGIN
  CALL sp_require(p_uid, 'SC09', 'edit');
  IF NOT EXISTS (SELECT 1 FROM positions WHERE position_id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบตำแหน่ง';
  END IF;
  SELECT * FROM positions WHERE position_id = p_id;
END$$

DROP PROCEDURE IF EXISTS api_positions_save$$
-- p_department_id ว่าง = ใช้ได้ทุกแผนก
CREATE PROCEDURE api_positions_save(IN p_uid VARCHAR(10), IN p_id VARCHAR(10), IN p_position_name VARCHAR(255),
                                    IN p_department_id VARCHAR(10))
BEGIN
  DECLARE v_id VARCHAR(10);
  DECLARE v_n INT;
  DECLARE v_msg VARCHAR(200);
  SET p_position_name = TRIM(COALESCE(p_position_name, ''));
  SET p_department_id = NULLIF(TRIM(p_department_id), '');
  CALL sp_require(p_uid, 'SC09', IF(mut_blank(p_id), 'add', 'edit'));
  IF p_position_name = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'position_name|กรุณากรอกชื่อตำแหน่ง';
  ELSEIF CHAR_LENGTH(p_position_name) > 100 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'position_name|ชื่อตำแหน่งยาวได้ไม่เกิน 100 ตัวอักษร';
  ELSEIF p_department_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM departments WHERE department_id = p_department_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'department_id|ไม่พบแผนกที่เลือก';
  END IF;
  IF mut_blank(p_id) THEN
    SET v_id = mut_fmt_id('P', (SELECT COALESCE(MAX(CAST(SUBSTRING(position_id, 2) AS UNSIGNED)), 0) + 1
                                  FROM positions WHERE position_id LIKE 'P%'), 2);
    INSERT INTO positions (position_id, position_name, department_id) VALUES (v_id, p_position_name, p_department_id);
    SELECT v_id AS id, CONCAT('เพิ่มตำแหน่ง ', v_id, ' เรียบร้อยแล้ว') AS message;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM positions WHERE position_id = p_id) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบตำแหน่ง';
    END IF;
    -- ย้ายตำแหน่งไปแผนกอื่น: พนักงานที่อยู่ในตำแหน่งนี้ต้องอยู่แผนกนั้นด้วย
    SET v_n = (SELECT COUNT(*) FROM employees e JOIN users u ON u.user_id = e.user_id
                WHERE e.position_id = p_id AND p_department_id IS NOT NULL AND u.department_id <> p_department_id);
    IF v_n > 0 THEN
      SET v_msg = CONCAT('department_id|เปลี่ยนแผนกไม่ได้ เนื่องจากมีพนักงาน ', v_n, ' คนในตำแหน่งนี้อยู่แผนกอื่น');
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;
    UPDATE positions SET position_name = p_position_name, department_id = p_department_id WHERE position_id = p_id;
    SELECT p_id AS id, CONCAT('บันทึกตำแหน่ง ', p_id, ' เรียบร้อยแล้ว') AS message;
  END IF;
END$$

DROP PROCEDURE IF EXISTS api_positions_delete$$
CREATE PROCEDURE api_positions_delete(IN p_uid VARCHAR(10), IN p_id VARCHAR(10))
BEGIN
  DECLARE v_n INT;
  DECLARE v_msg VARCHAR(200);
  CALL sp_require(p_uid, 'SC09', 'delete');
  SET v_n = (SELECT COUNT(*) FROM employees WHERE position_id = p_id);
  IF v_n > 0 THEN
    SET v_msg = CONCAT('ลบไม่ได้ เนื่องจากมีพนักงาน ', v_n, ' คนอยู่ในตำแหน่งนี้');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;
  DELETE FROM positions WHERE position_id = p_id;   -- สิทธิ์ของตำแหน่งลบตาม (CASCADE)
  SELECT CONCAT('ลบตำแหน่ง ', p_id, ' เรียบร้อยแล้ว') AS message;
END$$

-- ---------- 10.5 หน้าจอ (SC10) ----------
DROP PROCEDURE IF EXISTS api_screens_list$$
CREATE PROCEDURE api_screens_list(IN p_uid VARCHAR(10), IN p_q VARCHAR(100))
BEGIN
  CALL sp_require(p_uid, 'SC10', '');
  SELECT s.screen_id, s.screen_name,
         (SELECT COUNT(*) FROM permissions p WHERE p.screen_id = s.screen_id) AS position_count
    FROM screens s
   WHERE mut_blank(p_q) OR s.screen_id LIKE CONCAT('%', TRIM(p_q), '%') OR s.screen_name LIKE CONCAT('%', TRIM(p_q), '%')
   ORDER BY s.screen_id;
END$$

DROP PROCEDURE IF EXISTS api_screens_get$$
CREATE PROCEDURE api_screens_get(IN p_uid VARCHAR(10), IN p_id VARCHAR(10))
BEGIN
  CALL sp_require(p_uid, 'SC10', 'edit');
  IF NOT EXISTS (SELECT 1 FROM screens WHERE screen_id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบหน้าจอ';
  END IF;
  SELECT * FROM screens WHERE screen_id = p_id;
END$$

DROP PROCEDURE IF EXISTS api_screens_save$$
CREATE PROCEDURE api_screens_save(IN p_uid VARCHAR(10), IN p_id VARCHAR(10), IN p_screen_name VARCHAR(255))
BEGIN
  DECLARE v_id VARCHAR(10);
  SET p_screen_name = TRIM(COALESCE(p_screen_name, ''));
  CALL sp_require(p_uid, 'SC10', IF(mut_blank(p_id), 'add', 'edit'));
  IF p_screen_name = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'screen_name|กรุณากรอกชื่อหน้าจอ';
  ELSEIF CHAR_LENGTH(p_screen_name) > 100 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'screen_name|ชื่อหน้าจอยาวได้ไม่เกิน 100 ตัวอักษร';
  END IF;
  IF mut_blank(p_id) THEN
    SET v_id = mut_fmt_id('SC', (SELECT COALESCE(MAX(CAST(SUBSTRING(screen_id, 3) AS UNSIGNED)), 0) + 1
                                   FROM screens WHERE screen_id LIKE 'SC%'), 2);
    INSERT INTO screens (screen_id, screen_name) VALUES (v_id, p_screen_name);
    SELECT v_id AS id, CONCAT('เพิ่มหน้าจอ ', v_id, ' เรียบร้อยแล้ว') AS message;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM screens WHERE screen_id = p_id) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบหน้าจอ';
    END IF;
    UPDATE screens SET screen_name = p_screen_name WHERE screen_id = p_id;
    SELECT p_id AS id, CONCAT('บันทึกหน้าจอ ', p_id, ' เรียบร้อยแล้ว') AS message;
  END IF;
END$$

DROP PROCEDURE IF EXISTS api_screens_delete$$
CREATE PROCEDURE api_screens_delete(IN p_uid VARCHAR(10), IN p_id VARCHAR(10))
BEGIN
  CALL sp_require(p_uid, 'SC10', 'delete');
  IF p_id IN ('SC01','SC02','SC03','SC04','SC05','SC06','SC07','SC08','SC09','SC10','SC11','SC12') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'หน้าจอนี้ถูกใช้งานโดยระบบ ลบไม่ได้';
  END IF;
  DELETE FROM screens WHERE screen_id = p_id;
  SELECT CONCAT('ลบหน้าจอ ', p_id, ' เรียบร้อยแล้ว') AS message;
END$$

-- ---------- 10.7 ประเภทรถ (SC03) ----------
DROP PROCEDURE IF EXISTS api_vehicle_types_list$$
CREATE PROCEDURE api_vehicle_types_list(IN p_uid VARCHAR(10), IN p_q VARCHAR(100))
BEGIN
  CALL sp_require(p_uid, 'SC03', '');
  SELECT vt.vehicle_type_id, vt.type_name, vt.description, vt.seat_count,
         (SELECT COUNT(*) FROM vehicles v WHERE v.vehicle_type_id = vt.vehicle_type_id) AS vehicle_count
    FROM vehicle_types vt
   WHERE mut_blank(p_q) OR vt.vehicle_type_id LIKE CONCAT('%', TRIM(p_q), '%')
      OR vt.type_name LIKE CONCAT('%', TRIM(p_q), '%') OR vt.description LIKE CONCAT('%', TRIM(p_q), '%')
   ORDER BY vt.vehicle_type_id;
END$$

DROP PROCEDURE IF EXISTS api_vehicle_types_get$$
CREATE PROCEDURE api_vehicle_types_get(IN p_uid VARCHAR(10), IN p_id VARCHAR(10))
BEGIN
  CALL sp_require(p_uid, 'SC03', 'edit');
  IF NOT EXISTS (SELECT 1 FROM vehicle_types WHERE vehicle_type_id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบประเภทรถ';
  END IF;
  SELECT * FROM vehicle_types WHERE vehicle_type_id = p_id;
END$$

DROP PROCEDURE IF EXISTS api_vehicle_types_save$$
CREATE PROCEDURE api_vehicle_types_save(IN p_uid VARCHAR(10), IN p_id VARCHAR(10), IN p_type_name VARCHAR(255),
                                        IN p_description VARCHAR(1000), IN p_seat_count VARCHAR(20))
BEGIN
  DECLARE v_id VARCHAR(10);
  SET p_type_name = TRIM(COALESCE(p_type_name, ''));
  SET p_description = NULLIF(TRIM(COALESCE(p_description, '')), '');
  CALL sp_require(p_uid, 'SC03', IF(mut_blank(p_id), 'add', 'edit'));
  IF p_type_name = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'type_name|กรุณากรอกชื่อประเภทรถ';
  ELSEIF CHAR_LENGTH(p_type_name) > 50 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'type_name|ชื่อประเภทรถยาวได้ไม่เกิน 50 ตัวอักษร';
  ELSEIF CHAR_LENGTH(COALESCE(p_description, '')) > 255 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'description|รายละเอียดยาวได้ไม่เกิน 255 ตัวอักษร';
  ELSEIF mut_blank(p_seat_count) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'seat_count|กรุณากรอกจำนวนที่นั่ง';
  ELSEIF mut_is_int(p_seat_count) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'seat_count|จำนวนที่นั่งต้องเป็นจำนวนเต็ม';
  ELSEIF CAST(p_seat_count AS SIGNED) < 1 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'seat_count|จำนวนที่นั่งต้องไม่น้อยกว่า 1';
  END IF;
  IF mut_blank(p_id) THEN
    SET v_id = mut_fmt_id('T', (SELECT COALESCE(MAX(CAST(SUBSTRING(vehicle_type_id, 2) AS UNSIGNED)), 0) + 1
                                  FROM vehicle_types WHERE vehicle_type_id LIKE 'T%'), 2);
    INSERT INTO vehicle_types (vehicle_type_id, type_name, description, seat_count)
    VALUES (v_id, p_type_name, p_description, CAST(p_seat_count AS SIGNED));
    SELECT v_id AS id, CONCAT('เพิ่มประเภทรถ ', v_id, ' เรียบร้อยแล้ว') AS message;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM vehicle_types WHERE vehicle_type_id = p_id) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบประเภทรถ';
    END IF;
    UPDATE vehicle_types SET type_name = p_type_name, description = p_description, seat_count = CAST(p_seat_count AS SIGNED)
     WHERE vehicle_type_id = p_id;
    CALL sp_sync_trip_seats();
    SELECT p_id AS id, CONCAT('บันทึกประเภทรถ ', p_id, ' เรียบร้อยแล้ว') AS message;
  END IF;
END$$

DROP PROCEDURE IF EXISTS api_vehicle_types_delete$$
CREATE PROCEDURE api_vehicle_types_delete(IN p_uid VARCHAR(10), IN p_id VARCHAR(10))
BEGIN
  DECLARE v_n INT;
  DECLARE v_msg VARCHAR(200);
  CALL sp_require(p_uid, 'SC03', 'delete');
  SET v_n = (SELECT COUNT(*) FROM vehicles WHERE vehicle_type_id = p_id);
  IF v_n > 0 THEN
    SET v_msg = CONCAT('ลบไม่ได้ เนื่องจากมีรถ ', v_n, ' คันเป็นประเภทนี้');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;
  DELETE FROM vehicle_types WHERE vehicle_type_id = p_id;
  SELECT CONCAT('ลบประเภทรถ ', p_id, ' เรียบร้อยแล้ว') AS message;
END$$

-- ---------- 10.8 รถ (SC01) ----------
DROP PROCEDURE IF EXISTS api_vehicles_list$$
CREATE PROCEDURE api_vehicles_list(IN p_uid VARCHAR(10), IN p_q VARCHAR(100), IN p_vehicle_type_id VARCHAR(10), IN p_status VARCHAR(30))
BEGIN
  CALL sp_require(p_uid, 'SC01', '');
  SELECT v.vehicle_id, v.plate_no, v.vehicle_type_id, vt.type_name, vt.seat_count, v.status
    FROM vehicles v JOIN vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id
   WHERE (mut_blank(p_q) OR v.vehicle_id LIKE CONCAT('%', TRIM(p_q), '%') OR v.plate_no LIKE CONCAT('%', TRIM(p_q), '%'))
     AND (mut_blank(p_vehicle_type_id) OR v.vehicle_type_id = p_vehicle_type_id)
     AND (mut_blank(p_status) OR v.status = p_status)
   ORDER BY v.vehicle_id;
END$$

DROP PROCEDURE IF EXISTS api_vehicles_get$$
CREATE PROCEDURE api_vehicles_get(IN p_uid VARCHAR(10), IN p_id VARCHAR(10))
BEGIN
  CALL sp_require(p_uid, 'SC01', 'edit');
  IF NOT EXISTS (SELECT 1 FROM vehicles WHERE vehicle_id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบรถ';
  END IF;
  SELECT * FROM vehicles WHERE vehicle_id = p_id;
END$$

DROP PROCEDURE IF EXISTS api_vehicles_save$$
CREATE PROCEDURE api_vehicles_save(IN p_uid VARCHAR(10), IN p_id VARCHAR(10), IN p_plate_no VARCHAR(100),
                                   IN p_vehicle_type_id VARCHAR(10), IN p_status VARCHAR(30))
BEGIN
  DECLARE v_id VARCHAR(10);
  DECLARE EXIT HANDLER FOR 1062
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'plate_no|ทะเบียนรถนี้มีอยู่ในระบบแล้ว';
  SET p_plate_no = TRIM(COALESCE(p_plate_no, ''));
  CALL sp_require(p_uid, 'SC01', IF(mut_blank(p_id), 'add', 'edit'));
  IF p_plate_no = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'plate_no|กรุณากรอกทะเบียนรถ';
  ELSEIF CHAR_LENGTH(p_plate_no) > 20 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'plate_no|ทะเบียนรถยาวได้ไม่เกิน 20 ตัวอักษร';
  ELSEIF NOT EXISTS (SELECT 1 FROM vehicle_types WHERE vehicle_type_id = p_vehicle_type_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'vehicle_type_id|กรุณาเลือกประเภทรถ';
  ELSEIF COALESCE(p_status, '') NOT IN ('พร้อมใช้งาน', 'ซ่อมบำรุง', 'ไม่พร้อมใช้งาน') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'status|กรุณาเลือกสถานะ';
  END IF;
  IF mut_blank(p_id) THEN
    SET v_id = mut_fmt_id('V', (SELECT COALESCE(MAX(CAST(SUBSTRING(vehicle_id, 2) AS UNSIGNED)), 0) + 1
                                  FROM vehicles WHERE vehicle_id LIKE 'V%'), 3);
    INSERT INTO vehicles (vehicle_id, plate_no, status, vehicle_type_id) VALUES (v_id, p_plate_no, p_status, p_vehicle_type_id);
    SELECT v_id AS id, CONCAT('เพิ่มรถ ', v_id, ' เรียบร้อยแล้ว') AS message;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM vehicles WHERE vehicle_id = p_id) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบรถ';
    END IF;
    UPDATE vehicles SET plate_no = p_plate_no, status = p_status, vehicle_type_id = p_vehicle_type_id WHERE vehicle_id = p_id;
    CALL sp_sync_trip_seats();
    SELECT p_id AS id, CONCAT('บันทึกรถ ', p_id, ' เรียบร้อยแล้ว') AS message;
  END IF;
END$$

DROP PROCEDURE IF EXISTS api_vehicles_delete$$
CREATE PROCEDURE api_vehicles_delete(IN p_uid VARCHAR(10), IN p_id VARCHAR(10))
BEGIN
  DECLARE v_n INT;
  DECLARE v_msg VARCHAR(200);
  CALL sp_require(p_uid, 'SC01', 'delete');
  SET v_n = (SELECT COUNT(*) FROM trips WHERE vehicle_id = p_id) + (SELECT COUNT(*) FROM trip_schedules WHERE vehicle_id = p_id);
  IF v_n > 0 THEN
    SET v_msg = CONCAT('ลบไม่ได้ เนื่องจากรถคันนี้ถูกใช้ใน ', v_n, ' รอบ/ตารางเวลา — เปลี่ยนสถานะเป็น "ไม่พร้อมใช้งาน" แทน');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;
  DELETE FROM vehicles WHERE vehicle_id = p_id;
  SELECT CONCAT('ลบรถ ', p_id, ' เรียบร้อยแล้ว') AS message;
END$$

-- ---------- 10.9 จุดจอด (SC04) ----------
DROP PROCEDURE IF EXISTS api_stops_list$$
CREATE PROCEDURE api_stops_list(IN p_uid VARCHAR(10), IN p_q VARCHAR(100))
BEGIN
  CALL sp_require(p_uid, 'SC04', '');
  SELECT s.stop_id, s.stop_name,
         (SELECT COUNT(DISTINCT rs.route_id) FROM route_stops rs WHERE rs.stop_id = s.stop_id) AS route_count,
         (SELECT COUNT(*) FROM booking_items bi WHERE bi.board_stop_id = s.stop_id OR bi.alight_stop_id = s.stop_id) AS item_count
    FROM stops s
   WHERE mut_blank(p_q) OR s.stop_id LIKE CONCAT('%', TRIM(p_q), '%') OR s.stop_name LIKE CONCAT('%', TRIM(p_q), '%')
   ORDER BY s.stop_id;
END$$

DROP PROCEDURE IF EXISTS api_stops_get$$
CREATE PROCEDURE api_stops_get(IN p_uid VARCHAR(10), IN p_id VARCHAR(10))
BEGIN
  CALL sp_require(p_uid, 'SC04', 'edit');
  IF NOT EXISTS (SELECT 1 FROM stops WHERE stop_id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบจุดจอด';
  END IF;
  SELECT * FROM stops WHERE stop_id = p_id;
END$$

DROP PROCEDURE IF EXISTS api_stops_save$$
CREATE PROCEDURE api_stops_save(IN p_uid VARCHAR(10), IN p_id VARCHAR(10), IN p_stop_name VARCHAR(255))
BEGIN
  DECLARE v_id VARCHAR(10);
  SET p_stop_name = TRIM(COALESCE(p_stop_name, ''));
  CALL sp_require(p_uid, 'SC04', IF(mut_blank(p_id), 'add', 'edit'));
  IF p_stop_name = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'stop_name|กรุณากรอกชื่อจุดจอด';
  ELSEIF CHAR_LENGTH(p_stop_name) > 150 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'stop_name|ชื่อจุดจอดยาวได้ไม่เกิน 150 ตัวอักษร';
  END IF;
  IF mut_blank(p_id) THEN
    SET v_id = mut_fmt_id('S', (SELECT COALESCE(MAX(CAST(SUBSTRING(stop_id, 2) AS UNSIGNED)), 0) + 1
                                  FROM stops WHERE stop_id LIKE 'S%'), 3);
    INSERT INTO stops (stop_id, stop_name) VALUES (v_id, p_stop_name);
    SELECT v_id AS id, CONCAT('เพิ่มจุดจอด ', v_id, ' เรียบร้อยแล้ว') AS message;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM stops WHERE stop_id = p_id) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบจุดจอด';
    END IF;
    UPDATE stops SET stop_name = p_stop_name WHERE stop_id = p_id;
    SELECT p_id AS id, CONCAT('บันทึกจุดจอด ', p_id, ' เรียบร้อยแล้ว') AS message;
  END IF;
END$$

DROP PROCEDURE IF EXISTS api_stops_delete$$
CREATE PROCEDURE api_stops_delete(IN p_uid VARCHAR(10), IN p_id VARCHAR(10))
BEGIN
  DECLARE v_routes INT;
  DECLARE v_items INT;
  DECLARE v_msg VARCHAR(200);
  CALL sp_require(p_uid, 'SC04', 'delete');
  SET v_routes = (SELECT COUNT(DISTINCT route_id) FROM route_stops WHERE stop_id = p_id);
  SET v_items = (SELECT COUNT(*) FROM booking_items WHERE board_stop_id = p_id OR alight_stop_id = p_id);
  IF v_routes > 0 OR v_items > 0 THEN
    SET v_msg = CONCAT('ลบจุดจอดไม่ได้ เนื่องจากถูกใช้ใน ', v_routes, ' เส้นทาง และ ', v_items, ' รายการจอง');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;
  DELETE FROM stops WHERE stop_id = p_id;
  SELECT CONCAT('ลบจุดจอด ', p_id, ' เรียบร้อยแล้ว') AS message;
END$$

-- ---------- ตารางเวลาเดินรถ (SC06) ----------
DROP PROCEDURE IF EXISTS api_schedules_list$$
CREATE PROCEDURE api_schedules_list(IN p_uid VARCHAR(10), IN p_route_id VARCHAR(10), IN p_driver_id VARCHAR(10))
BEGIN
  CALL sp_require(p_uid, 'SC06', '');
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
   WHERE (mut_blank(p_route_id) OR x.route_id = p_route_id)
     AND (mut_blank(p_driver_id) OR x.driver_id = p_driver_id)
   ORDER BY x.route_id, x.depart_time;
END$$

DROP PROCEDURE IF EXISTS api_schedules_get$$
CREATE PROCEDURE api_schedules_get(IN p_uid VARCHAR(10), IN p_id VARCHAR(10))
BEGIN
  CALL sp_require(p_uid, 'SC06', 'edit');
  IF NOT EXISTS (SELECT 1 FROM trip_schedules WHERE schedule_id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบตารางเวลา';
  END IF;
  SELECT schedule_id, route_id, TIME_FORMAT(depart_time, '%H:%i') AS depart_time, vehicle_id, driver_id, run_days, active
    FROM trip_schedules WHERE schedule_id = p_id;
END$$

DROP PROCEDURE IF EXISTS api_schedules_save$$
-- ตรวจรถ/คนขับชนเวลากับตารางเวลาอื่นที่ใช้งานอยู่และมีวันวิ่งร่วมกัน แล้วสร้างรอบล่วงหน้าใหม่ตามค่าล่าสุด
CREATE PROCEDURE api_schedules_save(IN p_uid VARCHAR(10), IN p_id VARCHAR(10), IN p_route_id VARCHAR(10),
                                    IN p_depart_time VARCHAR(10), IN p_run_days VARCHAR(10), IN p_driver_id VARCHAR(10),
                                    IN p_vehicle_id VARCHAR(10), IN p_active VARCHAR(5))
BEGIN
  DECLARE v_id VARCHAR(10);
  DECLARE v_time TIME;
  DECLARE v_start INT;
  DECLARE v_end INT;
  DECLARE v_conflict VARCHAR(200);
  DECLARE v_msg VARCHAR(255);
  DECLARE EXIT HANDLER FOR 1062
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'depart_time|เส้นทางนี้มีรอบเวลานี้อยู่แล้ว';

  CALL sp_require(p_uid, 'SC06', IF(mut_blank(p_id), 'add', 'edit'));
  IF NOT EXISTS (SELECT 1 FROM routes WHERE route_id = p_route_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'route_id|กรุณาเลือกเส้นทาง';
  ELSEIF COALESCE(p_depart_time, '') NOT REGEXP '^[0-9]{2}:[0-9]{2}(:[0-9]{2})?$' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'depart_time|กรุณาระบุเวลาออก';
  ELSEIF COALESCE(p_run_days, '') NOT IN ('12345', '123456', '0123456', '06') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'run_days|กรุณาเลือกวันที่วิ่ง';
  ELSEIF NOT EXISTS (SELECT 1 FROM employees e WHERE e.user_id = p_driver_id
                        AND e.position_id IN (SELECT position_id FROM permissions WHERE screen_id = 'SC12')) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'driver_id|กรุณาเลือกคนขับ';
  ELSEIF NOT EXISTS (SELECT 1 FROM vehicles WHERE vehicle_id = p_vehicle_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'vehicle_id|กรุณาเลือกรถ';
  ELSEIF COALESCE(p_active, '') NOT IN ('0', '1') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'active|กรุณาเลือกสถานะ';
  END IF;
  SET v_time = CAST(CONCAT(LEFT(p_depart_time, 5), ':00') AS TIME);

  IF p_active = '1' THEN
    SET v_start = TIME_TO_SEC(v_time) DIV 60;
    SET v_end = v_start + GREATEST(1, (SELECT total_minutes FROM v_route_totals WHERE route_id = p_route_id));

    SET v_conflict = (
      SELECT CONCAT(s.schedule_id, ' ', r.route_name, ' ', TIME_FORMAT(s.depart_time, '%H:%i'), '–', mut_time_add(s.depart_time, rt.total_minutes))
        FROM trip_schedules s JOIN routes r ON r.route_id = s.route_id JOIN v_route_totals rt ON rt.route_id = s.route_id
       WHERE s.active = 1 AND s.schedule_id <> COALESCE(NULLIF(p_id, ''), '-') AND s.vehicle_id = p_vehicle_id
         AND mut_days_overlap(s.run_days, p_run_days) = 1
         AND TIME_TO_SEC(s.depart_time) DIV 60 < v_end
         AND v_start < TIME_TO_SEC(s.depart_time) DIV 60 + GREATEST(1, rt.total_minutes)
       LIMIT 1);
    IF v_conflict IS NOT NULL THEN
      SET v_msg = CONCAT('vehicle_id|รถคันนี้ถูกใช้ในตารางเวลา ', v_conflict);
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;

    SET v_conflict = (
      SELECT CONCAT(s.schedule_id, ' ', r.route_name, ' ', TIME_FORMAT(s.depart_time, '%H:%i'), '–', mut_time_add(s.depart_time, rt.total_minutes))
        FROM trip_schedules s JOIN routes r ON r.route_id = s.route_id JOIN v_route_totals rt ON rt.route_id = s.route_id
       WHERE s.active = 1 AND s.schedule_id <> COALESCE(NULLIF(p_id, ''), '-') AND s.driver_id = p_driver_id
         AND mut_days_overlap(s.run_days, p_run_days) = 1
         AND TIME_TO_SEC(s.depart_time) DIV 60 < v_end
         AND v_start < TIME_TO_SEC(s.depart_time) DIV 60 + GREATEST(1, rt.total_minutes)
       LIMIT 1);
    IF v_conflict IS NOT NULL THEN
      SET v_msg = CONCAT('driver_id|คนขับคนนี้มีงานในตารางเวลา ', v_conflict);
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;

    -- รอบที่จัดเอง/แก้ไขเองตั้งแต่วันนี้ไป ที่ใช้รถ/คนขับเดียวกันในวันที่ตารางนี้วิ่งและเวลาทับกัน
    -- (ไม่ตรวจ = sp_ensure_trips จะข้ามรอบของตารางนี้ไปเงียบๆ เพราะ trigger ปฏิเสธ)
    SET v_msg = (
      SELECT CONCAT(IF(t.vehicle_id = p_vehicle_id, 'vehicle_id|รถคันนี้ถูกใช้ในรอบ ', 'driver_id|คนขับคนนี้มีงานรอบ '),
                    t.trip_id, ' วันที่ ', DATE_FORMAT(t.trip_date, '%d/%m/%Y'), ' ', rt.route_name, ' ',
                    TIME_FORMAT(t.depart_time, '%H:%i'), '–', mut_time_add(t.depart_time, rt.total_minutes))
        FROM trips t JOIN v_route_totals rt ON rt.route_id = t.route_id
       WHERE t.trip_date >= CURDATE() AND t.status <> 'ยกเลิก'
         AND (t.schedule_id IS NULL OR t.schedule_id <> COALESCE(NULLIF(p_id, ''), '-'))
         AND NOT (t.route_id = p_route_id AND t.depart_time = v_time)   -- รอบเดียวกัน: sp_ensure_trips ไม่สร้างซ้ำอยู่แล้ว
         AND (t.vehicle_id = p_vehicle_id OR t.driver_id = p_driver_id)
         AND mut_runs_on(p_run_days, t.trip_date) = 1
         AND TIME_TO_SEC(t.depart_time) DIV 60 < v_end
         AND v_start < TIME_TO_SEC(t.depart_time) DIV 60 + rt.total_minutes
       ORDER BY t.vehicle_id = p_vehicle_id DESC, t.trip_date, t.depart_time
       LIMIT 1);
    IF v_msg IS NOT NULL THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;
  END IF;

  IF mut_blank(p_id) THEN
    SET v_id = mut_fmt_id('TS', (SELECT COALESCE(MAX(CAST(SUBSTRING(schedule_id, 3) AS UNSIGNED)), 0) + 1
                                   FROM trip_schedules WHERE schedule_id LIKE 'TS%'), 3);
    INSERT INTO trip_schedules (schedule_id, route_id, depart_time, vehicle_id, driver_id, run_days, active)
    VALUES (v_id, p_route_id, v_time, p_vehicle_id, p_driver_id, p_run_days, CAST(p_active AS SIGNED));
    SET v_msg = CONCAT('เพิ่มตารางเวลาเดินรถ ', v_id, ' เรียบร้อยแล้ว');
  ELSE
    IF NOT EXISTS (SELECT 1 FROM trip_schedules WHERE schedule_id = p_id) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบตารางเวลา';
    END IF;
    SET v_id = p_id;
    UPDATE trip_schedules
       SET route_id = p_route_id, depart_time = v_time, vehicle_id = p_vehicle_id, driver_id = p_driver_id,
           run_days = p_run_days, active = CAST(p_active AS SIGNED)
     WHERE schedule_id = p_id;
    SET v_msg = CONCAT('บันทึกตารางเวลาเดินรถ ', p_id, ' เรียบร้อยแล้ว');
  END IF;

  -- ลบรอบล่วงหน้าที่ยังไม่มีคนจองแล้วสร้างใหม่ตามค่าล่าสุด (รอบที่มีการจองแล้วคงไว้)
  CALL sp_remove_upcoming(v_id);
  CALL sp_ensure_trips(CURDATE(), 8);
  SELECT v_id AS id, v_msg AS message;
END$$

DROP PROCEDURE IF EXISTS api_schedules_delete$$
CREATE PROCEDURE api_schedules_delete(IN p_uid VARCHAR(10), IN p_id VARCHAR(10))
BEGIN
  CALL sp_require(p_uid, 'SC06', 'delete');
  CALL sp_remove_upcoming(p_id);   -- รอบล่วงหน้าที่ยังไม่มีคนจองถูกลบด้วย / รอบอื่น schedule_id เป็น NULL
  DELETE FROM trip_schedules WHERE schedule_id = p_id;
  SELECT CONCAT('ลบตารางเวลาเดินรถ ', p_id, ' เรียบร้อยแล้ว') AS message;
END$$

DELIMITER ;


-- =====================================================================
-- 9) หลังบ้าน: ผู้ใช้งาน / พนักงาน (SC07) และสิทธิ์ตามตำแหน่ง (SC10)
-- =====================================================================
DELIMITER $$

DROP PROCEDURE IF EXISTS api_users_list$$
-- p_type: employee = เฉพาะพนักงาน / user = เฉพาะผู้ใช้บริการทั่วไป
CREATE PROCEDURE api_users_list(IN p_uid VARCHAR(10), IN p_q VARCHAR(100), IN p_department VARCHAR(10),
                                IN p_position VARCHAR(10), IN p_type VARCHAR(10))
BEGIN
  CALL sp_require(p_uid, 'SC07', '');
  SELECT u.user_id, u.name, u.email, u.username, d.department_name, e.phone, p.position_name,
         CASE WHEN e.user_id IS NOT NULL THEN 1 ELSE 0 END AS is_employee
    FROM users u
    JOIN departments d ON d.department_id = u.department_id
    LEFT JOIN employees e ON e.user_id = u.user_id
    LEFT JOIN positions p ON p.position_id = e.position_id
   WHERE (mut_blank(p_q) OR u.user_id LIKE CONCAT('%', TRIM(p_q), '%') OR u.name LIKE CONCAT('%', TRIM(p_q), '%')
          OR u.email LIKE CONCAT('%', TRIM(p_q), '%') OR u.username LIKE CONCAT('%', TRIM(p_q), '%'))
     AND (mut_blank(p_department) OR u.department_id = p_department)
     AND (mut_blank(p_position) OR e.position_id = p_position)
     AND (COALESCE(p_type, '') <> 'employee' OR e.user_id IS NOT NULL)
     AND (COALESCE(p_type, '') <> 'user' OR e.user_id IS NULL)
   ORDER BY u.user_id;
END$$

DROP PROCEDURE IF EXISTS api_users_get$$
CREATE PROCEDURE api_users_get(IN p_uid VARCHAR(10), IN p_id VARCHAR(10))
BEGIN
  CALL sp_require(p_uid, 'SC07', 'edit');
  IF NOT EXISTS (SELECT 1 FROM users WHERE user_id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบผู้ใช้งาน';
  END IF;
  IF mut_can_assign(p_uid, (SELECT position_id FROM employees WHERE user_id = p_id)) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!denied|ไม่สามารถจัดการผู้ใช้ที่ตำแหน่งมีสิทธิ์มากกว่าคุณได้';
  END IF;
  SELECT u.user_id, u.name, u.email, u.username, u.department_id, e.phone, e.position_id,
         CASE WHEN e.user_id IS NOT NULL THEN 1 ELSE 0 END AS is_employee
    FROM users u LEFT JOIN employees e ON e.user_id = u.user_id WHERE u.user_id = p_id;
END$$

DROP PROCEDURE IF EXISTS api_users_save$$
-- พนักงาน = subclass ของผู้ใช้งาน (+ เบอร์โทร + ตำแหน่ง) / password ว่างตอนแก้ไข = ไม่เปลี่ยน
CREATE PROCEDURE api_users_save(IN p_uid VARCHAR(10), IN p_id VARCHAR(10), IN p_name VARCHAR(255), IN p_email VARCHAR(255),
                                IN p_username VARCHAR(255), IN p_password VARCHAR(255), IN p_confirm VARCHAR(255),
                                IN p_department_id VARCHAR(10),
                                IN p_is_employee VARCHAR(5), IN p_phone VARCHAR(50), IN p_position_id VARCHAR(10))
BEGIN
  DECLARE v_id VARCHAR(10);
  DECLARE v_new INT DEFAULT mut_blank(p_id);
  DECLARE v_emp INT DEFAULT COALESCE(p_is_employee, '') IN ('1', 'true', 'on');
  DECLARE v_old_pos VARCHAR(10);
  DECLARE EXIT HANDLER FOR 1062
  BEGIN
    ROLLBACK;
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'username|username หรือ email นี้ถูกใช้แล้ว';
  END;
  DECLARE EXIT HANDLER FOR 1451
  BEGIN
    ROLLBACK;
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'is_employee|ยกเลิกสถานะพนักงานไม่ได้ เนื่องจากเป็นคนขับในรอบการเดินรถ';
  END;

  SET p_name = TRIM(COALESCE(p_name, ''));
  SET p_email = TRIM(COALESCE(p_email, ''));
  SET p_username = TRIM(COALESCE(p_username, ''));
  SET p_password = COALESCE(p_password, '');
  SET p_phone = REPLACE(REPLACE(TRIM(COALESCE(p_phone, '')), '-', ''), ' ', '');   -- 081-234-5678 → 0812345678
  CALL sp_require(p_uid, 'SC07', IF(v_new, 'add', 'edit'));
  IF NOT v_new AND NOT EXISTS (SELECT 1 FROM users WHERE user_id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบผู้ใช้งาน';
  END IF;
  -- แก้ไข/รีเซ็ต password ผู้ใช้ที่ตำแหน่งมีสิทธิ์มากกว่าตัวเองไม่ได้
  SET v_old_pos = (SELECT position_id FROM employees WHERE user_id = p_id);
  IF NOT v_new AND mut_can_assign(p_uid, v_old_pos) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!denied|ไม่สามารถจัดการผู้ใช้ที่ตำแหน่งมีสิทธิ์มากกว่าคุณได้';
  END IF;

  IF p_name = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'name|กรุณากรอกชื่อ';
  ELSEIF CHAR_LENGTH(p_name) > 100 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'name|ชื่อยาวได้ไม่เกิน 100 ตัวอักษร';
  ELSEIF mut_is_email(p_email) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'email|รูปแบบ email ไม่ถูกต้อง';
  ELSEIF mut_is_username(p_username) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'username|username ใช้ a-z, 0-9, _ . - ความยาว 3–50 ตัวอักษร';
  ELSEIF (v_new OR p_password <> '') AND CHAR_LENGTH(p_password) < 4 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'password|password ต้องมีอย่างน้อย 4 ตัวอักษร';
  ELSEIF p_password <> '' AND p_password <> COALESCE(p_confirm, '') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'confirm|ยืนยัน password ไม่ตรงกัน';
  ELSEIF NOT EXISTS (SELECT 1 FROM departments WHERE department_id = p_department_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'department_id|กรุณาเลือกแผนก';
  ELSEIF v_emp AND p_phone NOT REGEXP '^0[0-9]{9}$' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'phone|เบอร์โทรต้องเป็นตัวเลข 10 หลัก ขึ้นต้นด้วย 0 (เช่น 0812345678)';
  ELSEIF v_emp AND NOT EXISTS (SELECT 1 FROM positions WHERE position_id = p_position_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'position_id|กรุณาเลือกตำแหน่ง';
  ELSEIF v_emp AND EXISTS (SELECT 1 FROM positions WHERE position_id = p_position_id
                              AND department_id IS NOT NULL AND department_id <> p_department_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'position_id|ตำแหน่งนี้ไม่อยู่ในแผนกที่เลือก';
  ELSEIF NOT v_new AND p_id = p_uid AND NOT v_emp THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'is_employee|ไม่สามารถยกเลิกสถานะพนักงานของตัวเองได้';
  ELSEIF NOT v_new AND p_id = p_uid AND NOT (p_position_id <=> v_old_pos) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'position_id|ไม่สามารถเปลี่ยนตำแหน่งของตัวเองได้';
  ELSEIF v_emp AND mut_can_assign(p_uid, p_position_id) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'position_id|ไม่สามารถกำหนดตำแหน่งที่มีสิทธิ์มากกว่าตำแหน่งของคุณได้';
  ELSEIF NOT v_new AND v_emp AND NOT (p_position_id <=> v_old_pos) AND mut_driver_busy(p_id) = 1
     AND NOT EXISTS (SELECT 1 FROM permissions WHERE position_id = p_position_id AND screen_id = 'SC12') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'position_id|เปลี่ยนเป็นตำแหน่งนี้ไม่ได้ เนื่องจากผู้ใช้นี้ยังมีรอบ/ตารางเวลาที่ต้องขับ แต่ตำแหน่งใหม่ไม่มีสิทธิ์งานคนขับ';
  ELSEIF EXISTS (SELECT 1 FROM users WHERE email = p_email AND user_id <> COALESCE(NULLIF(p_id, ''), '-')) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'email|email นี้ถูกใช้แล้ว';
  ELSEIF EXISTS (SELECT 1 FROM users WHERE username = p_username AND user_id <> COALESCE(NULLIF(p_id, ''), '-')) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'username|username นี้ถูกใช้แล้ว';
  END IF;

  START TRANSACTION;
  IF v_new THEN
    SET v_id = mut_fmt_id('U', (SELECT COALESCE(MAX(CAST(SUBSTRING(user_id, 2) AS UNSIGNED)), 0) + 1
                                  FROM users WHERE user_id LIKE 'U%'), 3);
    INSERT INTO users (user_id, name, email, username, password_hash, department_id)
    VALUES (v_id, p_name, p_email, p_username, mut_hash_password(p_password), p_department_id);
  ELSE
    SET v_id = p_id;
    UPDATE users SET name = p_name, email = p_email, username = p_username, department_id = p_department_id,
                     password_hash = IF(p_password = '', password_hash, mut_hash_password(p_password))
     WHERE user_id = v_id;
  END IF;

  IF v_emp THEN
    INSERT INTO employees (user_id, phone, position_id) VALUES (v_id, p_phone, p_position_id)
      ON DUPLICATE KEY UPDATE phone = VALUES(phone), position_id = VALUES(position_id);
  ELSE
    DELETE FROM employees WHERE user_id = v_id;
  END IF;
  COMMIT;

  SELECT v_id AS id,
         IF(v_new, CONCAT('เพิ่มผู้ใช้งาน ', v_id, ' (', p_name, ') เรียบร้อยแล้ว'),
                   CONCAT('บันทึกผู้ใช้งาน ', v_id, ' เรียบร้อยแล้ว')) AS message;
END$$

DROP PROCEDURE IF EXISTS api_users_delete$$
CREATE PROCEDURE api_users_delete(IN p_uid VARCHAR(10), IN p_id VARCHAR(10))
BEGIN
  DECLARE v_bookings INT;
  DECLARE v_trips INT;
  DECLARE v_msg VARCHAR(200);
  CALL sp_require(p_uid, 'SC07', 'delete');
  SET v_bookings = (SELECT COUNT(*) FROM bookings WHERE user_id = p_id);
  SET v_trips = (SELECT COUNT(*) FROM trips WHERE driver_id = p_id) + (SELECT COUNT(*) FROM trip_schedules WHERE driver_id = p_id);
  IF p_id = p_uid THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ไม่สามารถลบบัญชีของตัวเองได้';
  ELSEIF mut_can_assign(p_uid, (SELECT position_id FROM employees WHERE user_id = p_id)) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!denied|ไม่สามารถจัดการผู้ใช้ที่ตำแหน่งมีสิทธิ์มากกว่าคุณได้';
  ELSEIF v_bookings > 0 THEN
    SET v_msg = CONCAT('ลบไม่ได้ เนื่องจากผู้ใช้งานนี้มีประวัติการจอง ', v_bookings, ' รายการ');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  ELSEIF v_trips > 0 THEN
    SET v_msg = CONCAT('ลบไม่ได้ เนื่องจากผู้ใช้งานนี้เป็นคนขับใน ', v_trips, ' รอบ/ตารางเวลา');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;
  DELETE FROM users WHERE user_id = p_id;   -- employees ลบตาม (CASCADE)
  SELECT CONCAT('ลบผู้ใช้งาน ', p_id, ' เรียบร้อยแล้ว') AS message;
END$$

DROP PROCEDURE IF EXISTS api_permissions$$
-- Permission Matrix: ชุดที่ 1 = ตำแหน่งทั้งหมด / ชุดที่ 2 = ตำแหน่งที่เลือก + แก้ไขได้หรือไม่
--                    ชุดที่ 3 = หน้าจอทั้งหมด + สิทธิ์ของตำแหน่งที่เลือก (has_access = มีแถวใน permissions)
CREATE PROCEDURE api_permissions(IN p_uid VARCHAR(10), IN p_position VARCHAR(10))
BEGIN
  DECLARE v_pos VARCHAR(10);
  CALL sp_require(p_uid, 'SC10', '');
  SET v_pos = COALESCE((SELECT position_id FROM positions WHERE position_id = p_position),
                       (SELECT MIN(position_id) FROM positions));
  SELECT position_id, position_name FROM positions ORDER BY position_id;
  SELECT position_id, position_name, mut_can(p_uid, 'SC10', 'edit') AS editable FROM positions WHERE position_id = v_pos;
  SELECT s.screen_id, s.screen_name,
         CASE WHEN p.permission_id IS NULL THEN 0 ELSE 1 END AS has_access,
         COALESCE(p.can_add, 0) AS can_add, COALESCE(p.can_edit, 0) AS can_edit, COALESCE(p.can_delete, 0) AS can_delete
    FROM screens s
    LEFT JOIN permissions p ON p.screen_id = s.screen_id AND p.position_id = v_pos
   ORDER BY s.screen_id;
END$$

DROP PROCEDURE IF EXISTS api_permissions_save$$
-- p_matrix = 'SC01=1111;SC02=1000;...' ตัวเลข 4 หลัก = เข้าถึง เพิ่ม แก้ไข ลบ (หน้าจอที่ไม่อยู่ในรายการ = ไม่มีสิทธิ์)
CREATE PROCEDURE api_permissions_save(IN p_uid VARCHAR(10), IN p_position VARCHAR(10), IN p_matrix VARCHAR(2000))
BEGIN
  DECLARE v_done INT DEFAULT 0;
  DECLARE v_screen VARCHAR(10);
  DECLARE v_flags CHAR(4);
  DECLARE v_pos INT;
  DECLARE v_name VARCHAR(100);
  DECLARE v_n INT;
  DECLARE v_matrix VARCHAR(2010);
  DECLARE v_msg VARCHAR(255);
  DECLARE cur CURSOR FOR SELECT screen_id FROM screens ORDER BY screen_id;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  CALL sp_require(p_uid, 'SC10', 'edit');
  SET v_name = (SELECT position_name FROM positions WHERE position_id = p_position);
  IF v_name IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ไม่พบตำแหน่ง';
  END IF;
  SET v_matrix = CONCAT(';', COALESCE(p_matrix, ''), ';');

  -- กันผู้ใช้ถอดสิทธิ์ เข้าถึง/แก้ไข หน้าจอจัดการสิทธิ์ ของตำแหน่งตัวเอง
  IF p_position = (SELECT position_id FROM employees WHERE user_id = p_uid) THEN
    SET v_pos = LOCATE(';SC10=', v_matrix);
    IF v_pos = 0 OR SUBSTRING(v_matrix, v_pos + 6, 1) <> '1' OR SUBSTRING(v_matrix, v_pos + 8, 1) <> '1' THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ไม่สามารถถอดสิทธิ์ เข้าถึง/แก้ไข หน้าจอจัดการสิทธิ์ ของตำแหน่งตัวเองได้';
    END IF;
  END IF;

  -- กันถอดสิทธิ์งานคนขับ (SC12) ขณะที่พนักงานในตำแหน่งนี้ยังมีรอบ/ตารางเวลาที่ต้องขับ
  SET v_pos = LOCATE(';SC12=', v_matrix);
  IF (v_pos = 0 OR SUBSTRING(v_matrix, v_pos + 6, 1) <> '1')
     AND EXISTS (SELECT 1 FROM permissions WHERE position_id = p_position AND screen_id = 'SC12') THEN
    SET v_n = (SELECT COUNT(*) FROM employees WHERE position_id = p_position AND mut_driver_busy(user_id) = 1);
    IF v_n > 0 THEN
      SET v_msg = CONCAT('ถอดสิทธิ์งานคนขับไม่ได้ เนื่องจากพนักงานในตำแหน่งนี้ ', v_n,
                         ' คนยังมีรอบ/ตารางเวลาที่ต้องขับ — เปลี่ยนคนขับในรอบและตารางเวลาเหล่านั้นก่อน');
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;
  END IF;

  START TRANSACTION;
  SET v_n = (SELECT COALESCE(MAX(CAST(SUBSTRING(permission_id, 3) AS UNSIGNED)), 0) FROM permissions WHERE permission_id LIKE 'PR%');
  OPEN cur;
  read_loop: LOOP
    FETCH cur INTO v_screen;
    IF v_done = 1 THEN
      LEAVE read_loop;
    END IF;
    SET v_pos = LOCATE(CONCAT(';', v_screen, '='), v_matrix);
    SET v_flags = IF(v_pos = 0, '0000', SUBSTRING(v_matrix, v_pos + CHAR_LENGTH(v_screen) + 2, 4));
    IF LEFT(v_flags, 1) = '1' THEN
      IF EXISTS (SELECT 1 FROM permissions WHERE position_id = p_position AND screen_id = v_screen) THEN
        UPDATE permissions
           SET can_add = (SUBSTRING(v_flags, 2, 1) = '1'), can_edit = (SUBSTRING(v_flags, 3, 1) = '1'),
               can_delete = (SUBSTRING(v_flags, 4, 1) = '1')
         WHERE position_id = p_position AND screen_id = v_screen;
      ELSE
        SET v_n = v_n + 1;
        INSERT INTO permissions (permission_id, can_add, can_edit, can_delete, position_id, screen_id)
        VALUES (mut_fmt_id('PR', v_n, 3), (SUBSTRING(v_flags, 2, 1) = '1'), (SUBSTRING(v_flags, 3, 1) = '1'),
                (SUBSTRING(v_flags, 4, 1) = '1'), p_position, v_screen);
      END IF;
    ELSE
      DELETE FROM permissions WHERE position_id = p_position AND screen_id = v_screen;
    END IF;
  END LOOP;
  CLOSE cur;
  COMMIT;
  SELECT CONCAT('บันทึกสิทธิ์ของตำแหน่ง ', v_name, ' เรียบร้อยแล้ว') AS message;
END$$

DELIMITER ;


-- =====================================================================
-- 10) หลังบ้าน: เส้นทาง (SC05) และรอบการเดินรถ (SC06)
-- =====================================================================
DELIMITER $$

DROP PROCEDURE IF EXISTS api_routes_list$$
CREATE PROCEDURE api_routes_list(IN p_uid VARCHAR(10), IN p_q VARCHAR(100))
BEGIN
  CALL sp_require(p_uid, 'SC05', '');
  SELECT rt.*, (SELECT COUNT(*) FROM trips t WHERE t.route_id = rt.route_id) AS trip_count
    FROM v_route_totals rt
   WHERE mut_blank(p_q) OR rt.route_id LIKE CONCAT('%', TRIM(p_q), '%') OR rt.route_name LIKE CONCAT('%', TRIM(p_q), '%')
   ORDER BY rt.route_id;
END$$

DROP PROCEDURE IF EXISTS api_routes_get$$
-- ชุดที่ 1 = เส้นทาง + จำนวนรอบ / ชุดที่ 2 = ลำดับจุดจอดพร้อมเวลาสะสม
CREATE PROCEDURE api_routes_get(IN p_uid VARCHAR(10), IN p_id VARCHAR(10))
BEGIN
  CALL sp_require(p_uid, 'SC05', '');
  IF NOT EXISTS (SELECT 1 FROM routes WHERE route_id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบเส้นทาง';
  END IF;
  SELECT rt.*,
         (SELECT COUNT(*) FROM trips t WHERE t.route_id = rt.route_id) AS trip_total,
         (SELECT COUNT(*) FROM trips t WHERE t.route_id = rt.route_id AND t.status = 'เปิด') AS trip_open
    FROM v_route_totals rt WHERE rt.route_id = p_id;
  SELECT * FROM v_route_stop_times WHERE route_id = p_id ORDER BY stop_order;
END$$

DROP PROCEDURE IF EXISTS api_routes_save$$
-- p_stops = 'S001:0,S002:5,S003:3' (จุดจอด:นาทีจากจุดก่อนหน้า ตามลำดับ) — ลำดับแรกเป็น 0 นาทีเสมอ
CREATE PROCEDURE api_routes_save(IN p_uid VARCHAR(10), IN p_id VARCHAR(10), IN p_route_name VARCHAR(255), IN p_stops VARCHAR(2000))
BEGIN
  DECLARE v_id VARCHAR(10);
  DECLARE v_count INT;
  DECLARE v_i INT DEFAULT 1;
  DECLARE v_token VARCHAR(50);
  DECLARE v_stop VARCHAR(10);
  DECLARE v_min VARCHAR(20);
  DECLARE v_prev VARCHAR(10) DEFAULT NULL;
  DECLARE v_seq VARCHAR(2000) DEFAULT ',';
  DECLARE v_broken INT;
  DECLARE v_total INT;
  DECLARE v_msg VARCHAR(255);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  SET p_route_name = TRIM(COALESCE(p_route_name, ''));
  SET p_stops = TRIM(COALESCE(p_stops, ''));
  CALL sp_require(p_uid, 'SC05', IF(mut_blank(p_id), 'add', 'edit'));
  IF NOT mut_blank(p_id) AND NOT EXISTS (SELECT 1 FROM routes WHERE route_id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบเส้นทาง';
  END IF;
  IF p_route_name = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'route_name|กรุณากรอกชื่อเส้นทาง';
  ELSEIF CHAR_LENGTH(p_route_name) > 100 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'route_name|ชื่อเส้นทางยาวได้ไม่เกิน 100 ตัวอักษร';
  END IF;

  -- แยกรายการจุดจอดลงตารางชั่วคราว พร้อมตรวจทีละลำดับ
  DROP TEMPORARY TABLE IF EXISTS tmp_route_stops;
  CREATE TEMPORARY TABLE tmp_route_stops (stop_order INT PRIMARY KEY, stop_id VARCHAR(10), travel_minutes INT);
  SET v_count = IF(p_stops = '', 0, CHAR_LENGTH(p_stops) - CHAR_LENGTH(REPLACE(p_stops, ',', '')) + 1);
  IF v_count < 2 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'stops|เส้นทางต้องมีอย่างน้อย 2 จุดจอด';
  END IF;
  WHILE v_i <= v_count DO
    SET v_token = TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(p_stops, ',', v_i), ',', -1));
    SET v_stop = SUBSTRING_INDEX(v_token, ':', 1);
    SET v_min = IF(v_i = 1, '0', IF(LOCATE(':', v_token) > 0, TRIM(SUBSTRING_INDEX(v_token, ':', -1)), ''));
    IF NOT EXISTS (SELECT 1 FROM stops WHERE stop_id = v_stop) THEN
      SET v_msg = CONCAT('stops|ลำดับ ', v_i, ': กรุณาเลือกจุดจอด');
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;
    IF v_i > 1 AND v_stop = v_prev THEN
      SET v_msg = CONCAT('stops|ลำดับ ', v_i, ': จุดจอดติดกันต้องไม่ซ้ำกัน');
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;
    IF v_i > 1 AND (mut_is_int(v_min) = 0 OR CAST(v_min AS SIGNED) <= 0) THEN
      SET v_msg = CONCAT('stops|ลำดับ ', v_i, ': เวลาเดินทางต้องเป็นจำนวนเต็มมากกว่า 0 นาที');
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;
    INSERT INTO tmp_route_stops VALUES (v_i, v_stop, CAST(v_min AS SIGNED));
    SET v_seq = CONCAT(v_seq, v_stop, ',');
    SET v_prev = v_stop;
    SET v_i = v_i + 1;
  END WHILE;

  -- รายการจองที่ยังใช้งานของเส้นทางนี้ต้องยังมีจุดขึ้นก่อนจุดลงในลำดับใหม่
  IF NOT mut_blank(p_id) THEN
    SET v_broken = (
      SELECT COUNT(*) FROM (
        SELECT DISTINCT bi.board_stop_id, bi.alight_stop_id
          FROM booking_items bi JOIN trips t ON t.trip_id = bi.trip_id
         WHERE t.route_id = p_id AND t.status IN ('เปิด', 'กำลังเดินทาง') AND bi.status = 'ยืนยัน'
      ) u
       WHERE LOCATE(CONCAT(',', u.board_stop_id, ','), v_seq) = 0
          OR LOCATE(CONCAT(',', u.alight_stop_id, ','), v_seq, LOCATE(CONCAT(',', u.board_stop_id, ','), v_seq) + 1) = 0);
    IF v_broken > 0 THEN
      SET v_msg = CONCAT('stops|บันทึกไม่ได้ — มีรายการจองของรอบที่ยังเปิดใช้ช่วงจุดจอดที่ถูกตัดออก (', v_broken, ' ช่วง)');
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;

    -- เวลาเดินทางรวมยาวขึ้น → รอบ/ตารางเวลาของเส้นทางนี้จบช้าลง อาจชนงานถัดไปของรถ/คนขับเดียวกัน
    SET v_total = (SELECT SUM(travel_minutes) FROM tmp_route_stops);
    IF v_total > (SELECT total_minutes FROM v_route_totals WHERE route_id = p_id) THEN
      SET v_msg = (
        SELECT CONCAT('stops|เวลารวมใหม่ ', v_total, ' นาที ทำให้รอบ ', t.trip_id, ' วันที่ ',
                      DATE_FORMAT(t.trip_date, '%d/%m/%Y'), ' ', TIME_FORMAT(t.depart_time, '%H:%i'), ' ชนกับรอบ ', o.trip_id,
                      IF(o.vehicle_id = t.vehicle_id, ' (รถคันเดียวกัน)', ' (คนขับเดียวกัน)'))
          FROM trips t
          JOIN trips o ON o.trip_id <> t.trip_id AND o.status <> 'ยกเลิก'
                      AND (o.vehicle_id = t.vehicle_id OR o.driver_id = t.driver_id)
                      AND o.trip_date BETWEEN t.trip_date - INTERVAL 1 DAY AND t.trip_date + INTERVAL 1 DAY
          JOIN v_route_totals ort ON ort.route_id = o.route_id
         WHERE t.route_id = p_id AND t.trip_date >= CURDATE() AND t.status IN ('เปิด', 'กำลังเดินทาง')
           AND TIMESTAMP(o.trip_date, o.depart_time) < TIMESTAMP(t.trip_date, t.depart_time) + INTERVAL v_total MINUTE
           AND TIMESTAMP(t.trip_date, t.depart_time)
               < TIMESTAMP(o.trip_date, o.depart_time) + INTERVAL IF(o.route_id = p_id, v_total, ort.total_minutes) MINUTE
         ORDER BY t.trip_date, t.depart_time
         LIMIT 1);
      IF v_msg IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
      END IF;
      SET v_msg = (
        SELECT CONCAT('stops|เวลารวมใหม่ ', v_total, ' นาที ทำให้ตารางเวลา ', s.schedule_id, ' (',
                      TIME_FORMAT(s.depart_time, '%H:%i'), ') ชนกับตารางเวลา ', o.schedule_id,
                      IF(o.vehicle_id = s.vehicle_id, ' (รถคันเดียวกัน)', ' (คนขับเดียวกัน)'))
          FROM trip_schedules s
          JOIN trip_schedules o ON o.schedule_id <> s.schedule_id AND o.active = 1
                               AND (o.vehicle_id = s.vehicle_id OR o.driver_id = s.driver_id)
                               AND mut_days_overlap(o.run_days, s.run_days) = 1
          JOIN v_route_totals ort ON ort.route_id = o.route_id
         WHERE s.route_id = p_id AND s.active = 1
           AND TIME_TO_SEC(o.depart_time) DIV 60 < TIME_TO_SEC(s.depart_time) DIV 60 + v_total
           AND TIME_TO_SEC(s.depart_time) DIV 60 < TIME_TO_SEC(o.depart_time) DIV 60 + IF(o.route_id = p_id, v_total, ort.total_minutes)
         ORDER BY s.depart_time
         LIMIT 1);
      IF v_msg IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
      END IF;
    END IF;
  END IF;

  START TRANSACTION;
  IF mut_blank(p_id) THEN
    SET v_id = mut_fmt_id('R', (SELECT COALESCE(MAX(CAST(SUBSTRING(route_id, 2) AS UNSIGNED)), 0) + 1
                                  FROM routes WHERE route_id LIKE 'R%'), 3);
    INSERT INTO routes (route_id, route_name) VALUES (v_id, p_route_name);
    SET v_msg = CONCAT('เพิ่มเส้นทาง ', v_id, ' เรียบร้อยแล้ว');
  ELSE
    SET v_id = p_id;
    UPDATE routes SET route_name = p_route_name WHERE route_id = v_id;
    DELETE FROM route_stops WHERE route_id = v_id;
    SET v_msg = CONCAT('บันทึกเส้นทาง ', v_id, ' เรียบร้อยแล้ว');
  END IF;
  INSERT INTO route_stops (route_id, stop_order, stop_id, travel_minutes)
    SELECT v_id, stop_order, stop_id, travel_minutes FROM tmp_route_stops ORDER BY stop_order;
  COMMIT;
  DROP TEMPORARY TABLE IF EXISTS tmp_route_stops;
  SELECT v_id AS id, v_msg AS message;
END$$

DROP PROCEDURE IF EXISTS api_routes_delete$$
CREATE PROCEDURE api_routes_delete(IN p_uid VARCHAR(10), IN p_id VARCHAR(10))
BEGIN
  DECLARE v_n INT;
  DECLARE v_msg VARCHAR(200);
  CALL sp_require(p_uid, 'SC05', 'delete');
  SET v_n = (SELECT COUNT(*) FROM trips WHERE route_id = p_id);
  IF v_n > 0 THEN
    SET v_msg = CONCAT('ลบไม่ได้ เนื่องจากเส้นทางนี้ถูกใช้ใน ', v_n, ' รอบการเดินรถ');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;
  DELETE FROM routes WHERE route_id = p_id;   -- route_stops / trip_schedules ลบตาม (CASCADE)
  SELECT CONCAT('ลบเส้นทาง ', p_id, ' เรียบร้อยแล้ว') AS message;
END$$

DROP PROCEDURE IF EXISTS api_trips_list$$
-- p_date ว่าง = ทุกวัน (หน้าเว็บส่งวันนี้เป็นค่าเริ่มต้น) — แสดงไม่เกิน 500 รอบ
-- p_q = ค้นรหัสรอบ (บางส่วนได้) — มีค่าแล้วไม่กรองวันที่ เพราะรหัสรอบไม่ซ้ำกันอยู่แล้ว
CREATE PROCEDURE api_trips_list(IN p_uid VARCHAR(10), IN p_date VARCHAR(20), IN p_route VARCHAR(10),
                                IN p_driver VARCHAR(10), IN p_vehicle VARCHAR(10), IN p_status VARCHAR(30),
                                IN p_q VARCHAR(30))
BEGIN
  CALL sp_require(p_uid, 'SC06', '');
  SELECT * FROM v_trip_details
   WHERE (mut_blank(p_q) OR UPPER(trip_id) LIKE CONCAT('%', UPPER(TRIM(p_q)), '%'))
     AND (NOT mut_blank(p_q) OR mut_is_date(p_date) = 0 OR trip_date = p_date)
     AND (mut_blank(p_route) OR route_id = p_route)
     AND (mut_blank(p_driver) OR driver_id = p_driver)
     AND (mut_blank(p_vehicle) OR vehicle_id = p_vehicle)
     AND (mut_blank(p_status) OR status = p_status)
   ORDER BY trip_date DESC, depart_time
   LIMIT 500;
END$$

DROP PROCEDURE IF EXISTS api_trips_form$$
-- ฟอร์มรอบ: ชุดที่ 1 = รอบ (ว่างถ้าเพิ่มใหม่) / ชุดที่ 2 = เส้นทาง
--           ชุดที่ 3 = รถที่พร้อมใช้งาน (+ คันเดิมของรอบ) / ชุดที่ 4 = คนขับ (+ คนเดิมของรอบ)
CREATE PROCEDURE api_trips_form(IN p_uid VARCHAR(10), IN p_id VARCHAR(10))
BEGIN
  DECLARE v_vehicle VARCHAR(10) DEFAULT '-';
  DECLARE v_driver VARCHAR(10) DEFAULT '-';
  CALL sp_require(p_uid, 'SC06', IF(mut_blank(p_id), 'add', 'edit'));
  IF NOT mut_blank(p_id) THEN
    IF NOT EXISTS (SELECT 1 FROM trips WHERE trip_id = p_id) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบรอบการเดินรถ';
    END IF;
    SELECT vehicle_id, driver_id INTO v_vehicle, v_driver FROM trips WHERE trip_id = p_id;
  END IF;
  SELECT * FROM v_trip_details WHERE trip_id = p_id;
  SELECT route_id, route_name, total_minutes FROM v_route_totals ORDER BY route_id;
  SELECT v.vehicle_id, v.plate_no, v.status, vt.type_name, vt.seat_count
    FROM vehicles v JOIN vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id
   WHERE v.status = 'พร้อมใช้งาน' OR v.vehicle_id = v_vehicle
   ORDER BY v.plate_no;
  SELECT u.user_id, u.name, p.position_name
    FROM employees e JOIN users u ON u.user_id = e.user_id JOIN positions p ON p.position_id = e.position_id
   WHERE e.position_id IN (SELECT position_id FROM permissions WHERE screen_id = 'SC12') OR e.user_id = v_driver
   ORDER BY u.name;
END$$

DROP PROCEDURE IF EXISTS api_trips_save$$
-- เพิ่ม/แก้ไขรอบ + Conflict Validation (รถ/คนขับชนเวลา) — trigger ในตาราง trips เป็นด่านสุดท้าย
CREATE PROCEDURE api_trips_save(IN p_uid VARCHAR(10), IN p_id VARCHAR(10), IN p_route_id VARCHAR(10),
                                IN p_trip_date VARCHAR(20), IN p_depart_time VARCHAR(10), IN p_vehicle_id VARCHAR(10),
                                IN p_driver_id VARCHAR(10), IN p_status VARCHAR(30))
BEGIN
  DECLARE v_new INT DEFAULT mut_blank(p_id);
  DECLARE v_id VARCHAR(10);
  DECLARE v_date DATE;
  DECLARE v_time TIME;
  DECLARE v_status VARCHAR(30);
  DECLARE v_old_vehicle VARCHAR(10);
  DECLARE v_old_driver VARCHAR(10);
  DECLARE v_old_route VARCHAR(10);
  DECLARE v_old_sched VARCHAR(10);
  DECLARE v_booked INT DEFAULT 0;
  DECLARE v_vstatus VARCHAR(30);
  DECLARE v_vseats INT;
  DECLARE v_minutes INT;
  DECLARE v_conflict VARCHAR(255);
  DECLARE v_msg VARCHAR(255);

  CALL sp_require(p_uid, 'SC06', IF(v_new, 'add', 'edit'));
  IF NOT v_new THEN
    IF NOT EXISTS (SELECT 1 FROM trips WHERE trip_id = p_id) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบรอบการเดินรถ';
    END IF;
    SELECT t.vehicle_id, t.driver_id, t.route_id, t.schedule_id, s.booked_seats
      INTO v_old_vehicle, v_old_driver, v_old_route, v_old_sched, v_booked
      FROM trips t JOIN v_trip_seats s ON s.trip_id = t.trip_id WHERE t.trip_id = p_id;
  END IF;
  SET v_status = IF(v_new, 'เปิด', p_status);
  SET v_vstatus = (SELECT status FROM vehicles WHERE vehicle_id = p_vehicle_id);
  SET v_vseats = (SELECT vt.seat_count FROM vehicles v JOIN vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id
                   WHERE v.vehicle_id = p_vehicle_id);

  IF NOT EXISTS (SELECT 1 FROM routes WHERE route_id = p_route_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'route_id|กรุณาเลือกเส้นทาง';
  ELSEIF mut_is_date(p_trip_date) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'trip_date|กรุณาเลือกวันที่เดินรถ';
  ELSEIF v_new AND STR_TO_DATE(p_trip_date, '%Y-%m-%d') < CURDATE() THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'trip_date|ไม่สามารถจัดรอบย้อนหลังได้';
  ELSEIF COALESCE(p_depart_time, '') NOT REGEXP '^[0-9]{2}:[0-9]{2}(:[0-9]{2})?$' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'depart_time|กรุณาระบุเวลาออก';
  ELSEIF v_vstatus IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'vehicle_id|กรุณาเลือกรถที่พร้อมใช้งาน';
  ELSEIF v_vstatus <> 'พร้อมใช้งาน' AND (v_new OR p_vehicle_id <> v_old_vehicle) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'vehicle_id|รถคันนี้ไม่อยู่ในสถานะพร้อมใช้งาน';
  ELSEIF NOT EXISTS (SELECT 1 FROM employees e WHERE e.user_id = p_driver_id
                        AND (e.position_id IN (SELECT position_id FROM permissions WHERE screen_id = 'SC12')
                             OR e.user_id = COALESCE(v_old_driver, '-'))) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'driver_id|กรุณาเลือกคนขับ';
  ELSEIF COALESCE(v_status, '') NOT IN ('เปิด', 'กำลังเดินทาง', 'เสร็จสิ้น', 'ยกเลิก') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'status|กรุณาเลือกสถานะรอบ';
  ELSEIF NOT v_new AND p_route_id <> v_old_route AND v_booked > 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'route_id|เปลี่ยนเส้นทางไม่ได้ เนื่องจากรอบนี้มีการจองแล้ว';
  ELSEIF NOT v_new AND v_vseats < v_booked THEN
    SET v_msg = CONCAT('vehicle_id|รถคันนี้มี ', v_vseats, ' ที่นั่ง น้อยกว่าที่จองแล้ว ', v_booked, ' ที่นั่ง');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;

  SET v_date = STR_TO_DATE(p_trip_date, '%Y-%m-%d');
  SET v_time = CAST(CONCAT(LEFT(p_depart_time, 5), ':00') AS TIME);

  -- Conflict Validation: รอบอื่นที่ใช้รถ/คนขับเดียวกันและช่วงเวลาทับกัน
  IF v_status <> 'ยกเลิก' THEN
    SET v_minutes = COALESCE((SELECT total_minutes FROM v_route_totals WHERE route_id = p_route_id), 0);
    SET v_conflict = (
      SELECT CONCAT(trip_id, ' (', TIME_FORMAT(depart_time, '%H:%i'), '–', TIME_FORMAT(end_at, '%H:%i'), ')')
        FROM v_trip_details
       WHERE trip_date = v_date AND status <> 'ยกเลิก' AND trip_id <> COALESCE(NULLIF(p_id, ''), '-')
         AND vehicle_id = p_vehicle_id
         AND TIMESTAMP(trip_date, depart_time) < TIMESTAMP(v_date, v_time) + INTERVAL v_minutes MINUTE
         AND TIMESTAMP(v_date, v_time) < end_at
       LIMIT 1);
    IF v_conflict IS NOT NULL THEN
      SET v_msg = CONCAT('vehicle_id|ไม่สามารถจัดรอบนี้ได้ เนื่องจากรถถูกมอบหมายในรอบ ', v_conflict);
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;
    SET v_conflict = (
      SELECT CONCAT(trip_id, ' (', TIME_FORMAT(depart_time, '%H:%i'), '–', TIME_FORMAT(end_at, '%H:%i'), ')')
        FROM v_trip_details
       WHERE trip_date = v_date AND status <> 'ยกเลิก' AND trip_id <> COALESCE(NULLIF(p_id, ''), '-')
         AND driver_id = p_driver_id
         AND TIMESTAMP(trip_date, depart_time) < TIMESTAMP(v_date, v_time) + INTERVAL v_minutes MINUTE
         AND TIMESTAMP(v_date, v_time) < end_at
       LIMIT 1);
    IF v_conflict IS NOT NULL THEN
      SET v_msg = CONCAT('driver_id|ไม่สามารถจัดรอบนี้ได้ เนื่องจากคนขับมีงานรอบ ', v_conflict);
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;

    -- ตารางเวลาที่ยังไม่ได้สร้างรอบของวันนั้น (sp_ensure_trips สร้างล่วงหน้าแค่ 8 วัน) ที่ใช้รถ/คนขับเดียวกันและเวลาทับกัน
    IF v_date >= CURDATE() THEN
      SET v_msg = (
        SELECT CONCAT(IF(s.vehicle_id = p_vehicle_id, 'vehicle_id|ไม่สามารถจัดรอบนี้ได้ เนื่องจากรถถูกใช้ในตารางเวลา ',
                                                      'driver_id|ไม่สามารถจัดรอบนี้ได้ เนื่องจากคนขับมีงานในตารางเวลา '),
                      s.schedule_id, ' ', rt.route_name, ' ', TIME_FORMAT(s.depart_time, '%H:%i'), '–',
                      mut_time_add(s.depart_time, rt.total_minutes))
        FROM trip_schedules s JOIN v_route_totals rt ON rt.route_id = s.route_id
       WHERE s.active = 1 AND s.schedule_id <> COALESCE(v_old_sched, '-')
         AND NOT (s.route_id = p_route_id AND s.depart_time = v_time)   -- รอบเดียวกัน: sp_ensure_trips ไม่สร้างซ้ำอยู่แล้ว
         AND (s.vehicle_id = p_vehicle_id OR s.driver_id = p_driver_id)
         AND mut_runs_on(s.run_days, v_date) = 1
         AND NOT EXISTS (SELECT 1 FROM trips t
                          WHERE t.trip_date = v_date
                            AND (t.schedule_id = s.schedule_id OR (t.route_id = s.route_id AND t.depart_time = s.depart_time)))
         AND TIME_TO_SEC(s.depart_time) DIV 60 < TIME_TO_SEC(v_time) DIV 60 + v_minutes
         AND TIME_TO_SEC(v_time) DIV 60 < TIME_TO_SEC(s.depart_time) DIV 60 + rt.total_minutes
       ORDER BY s.vehicle_id = p_vehicle_id DESC
       LIMIT 1);
      IF v_msg IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
      END IF;
    END IF;
  END IF;

  IF v_new THEN
    SET v_id = mut_fmt_id('TR', (SELECT COALESCE(MAX(CAST(SUBSTRING(trip_id, 3) AS UNSIGNED)), 0) + 1
                                   FROM trips WHERE trip_id LIKE 'TR%'), 3);
    INSERT INTO trips (trip_id, trip_date, depart_time, status, vehicle_id, route_id, driver_id)
    VALUES (v_id, v_date, v_time, 'เปิด', p_vehicle_id, p_route_id, p_driver_id);
    SET v_msg = CONCAT('เพิ่มรอบ ', v_id, ' (', DATE_FORMAT(v_date, '%d/%m/%Y'), ' ', TIME_FORMAT(v_time, '%H:%i'), ') เรียบร้อยแล้ว');
  ELSE
    SET v_id = p_id;
    UPDATE trips SET trip_date = v_date, depart_time = v_time, status = v_status, vehicle_id = p_vehicle_id,
                     route_id = p_route_id, driver_id = p_driver_id
     WHERE trip_id = p_id;
    SET v_msg = CONCAT('บันทึกรอบ ', v_id, ' เรียบร้อยแล้ว');
  END IF;
  SELECT v_id AS id, v_date AS trip_date, v_msg AS message;
END$$

DROP PROCEDURE IF EXISTS api_trips_delete$$
CREATE PROCEDURE api_trips_delete(IN p_uid VARCHAR(10), IN p_id VARCHAR(10))
BEGIN
  DECLARE v_n INT;
  DECLARE v_msg VARCHAR(200);
  CALL sp_require(p_uid, 'SC06', 'delete');
  SET v_n = (SELECT COUNT(*) FROM booking_items WHERE trip_id = p_id);
  IF v_n > 0 THEN
    SET v_msg = CONCAT('ลบไม่ได้ เนื่องจากรอบ ', p_id, ' มีรายการจอง ', v_n, ' รายการ — เปลี่ยนสถานะรอบเป็น "ยกเลิก" แทน');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;
  DELETE FROM trips WHERE trip_id = p_id;
  SELECT CONCAT('ลบรอบ ', p_id, ' เรียบร้อยแล้ว') AS message;
END$$


-- =====================================================================
-- 11) หลังบ้าน: การจอง (SC02)
-- =====================================================================

DROP PROCEDURE IF EXISTS api_bookings_list$$
-- p_status: ยืนยัน (ยังไม่ Check-in) / Check-in แล้ว / ยกเลิก / No Show — แสดงไม่เกิน 500 รายการ
CREATE PROCEDURE api_bookings_list(IN p_uid VARCHAR(10), IN p_q VARCHAR(100), IN p_from VARCHAR(20), IN p_to VARCHAR(20),
                                   IN p_status VARCHAR(30), IN p_route VARCHAR(10), IN p_trip VARCHAR(10))
BEGIN
  CALL sp_require(p_uid, 'SC02', '');
  SELECT * FROM v_item_details t
   WHERE (mut_is_date(p_from) = 0 OR t.trip_date >= p_from)
     AND (mut_is_date(p_to) = 0 OR t.trip_date <= p_to)
     AND (mut_blank(p_route) OR t.route_id = p_route)
     AND (mut_blank(p_trip) OR t.trip_id = p_trip)
     AND (mut_blank(p_status) OR t.display_status = p_status)
     AND (mut_blank(p_q) OR t.booking_id LIKE CONCAT('%', TRIM(p_q), '%') OR t.booking_item_id LIKE CONCAT('%', TRIM(p_q), '%')
          OR t.passenger_name LIKE CONCAT('%', TRIM(p_q), '%') OR t.qr_code = TRIM(p_q))
   ORDER BY t.booked_at DESC, t.booking_item_id DESC
   LIMIT 500;
  SELECT route_id, route_name FROM routes ORDER BY route_id;
END$$

DROP PROCEDURE IF EXISTS api_bookings_get$$
-- ชุดที่ 1 = การจอง + ผู้จอง / ชุดที่ 2 = รายการจอง
CREATE PROCEDURE api_bookings_get(IN p_uid VARCHAR(10), IN p_id VARCHAR(10))
BEGIN
  CALL sp_require(p_uid, 'SC02', '');
  IF NOT EXISTS (SELECT 1 FROM bookings WHERE booking_id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบการจอง';
  END IF;
  SELECT b.booking_id, b.booked_at, u.user_id, u.name, u.email, u.username, d.department_name
    FROM bookings b JOIN users u ON u.user_id = b.user_id JOIN departments d ON d.department_id = u.department_id
   WHERE b.booking_id = p_id;
  SELECT * FROM v_item_details WHERE booking_id = p_id ORDER BY booking_item_id;
END$$

DROP PROCEDURE IF EXISTS api_bookings_cancel_item$$
-- ยกเลิกรายการจองโดยเจ้าหน้าที่ (ไม่ตรวจเจ้าของ)
CREATE PROCEDURE api_bookings_cancel_item(IN p_uid VARCHAR(10), IN p_item VARCHAR(10))
BEGIN
  CALL sp_require(p_uid, 'SC02', 'edit');
  CALL sp_cancel_booking_item(p_item, NULL);
  SELECT CONCAT('ยกเลิกรายการจอง ', p_item, ' แล้ว — คืนที่นั่งให้รอบเรียบร้อย') AS message;
END$$

DROP PROCEDURE IF EXISTS api_bookings_set_status$$
-- เปลี่ยนสถานะรายการจอง (trigger ตรวจที่นั่งเมื่อเปิดรายการที่ยกเลิกกลับมา)
CREATE PROCEDURE api_bookings_set_status(IN p_uid VARCHAR(10), IN p_item VARCHAR(10), IN p_status VARCHAR(30))
BEGIN
  CALL sp_require(p_uid, 'SC02', 'edit');
  IF NOT EXISTS (SELECT 1 FROM booking_items WHERE booking_item_id = p_item) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '!notfound|ไม่พบรายการจอง';
  END IF;
  IF COALESCE(p_status, '') NOT IN ('ยืนยัน', 'ยกเลิก', 'No Show') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'สถานะไม่ถูกต้อง';
  END IF;
  UPDATE booking_items SET status = p_status WHERE booking_item_id = p_item;
  SELECT CONCAT('เปลี่ยนสถานะรายการ ', p_item, ' เป็น ', p_status, ' แล้ว') AS message;
END$$

DROP PROCEDURE IF EXISTS api_bookings_delete$$
CREATE PROCEDURE api_bookings_delete(IN p_uid VARCHAR(10), IN p_id VARCHAR(10))
BEGIN
  CALL sp_require(p_uid, 'SC02', 'delete');
  DELETE FROM bookings WHERE booking_id = p_id;   -- รายการจองลบตาม (CASCADE)
  SELECT CONCAT('ลบการจอง ', p_id, ' เรียบร้อยแล้ว') AS message;
END$$

DELIMITER ;


-- =====================================================================
-- 12) รายงาน 1–7 (SC11)
--     ชุดที่ 1 = ค่าที่ใช้ออกรายงาน (ปี ค.ศ. / ช่วงวันที่) / ชุดถัดไป = ข้อมูลของรายงาน
--     หน้าเว็บ (public/js/pages/admin-reports.js) คำนวณผลรวม/การ์ด/กราฟ จากข้อมูลชุดนี้
-- =====================================================================
DELIMITER $$

DROP PROCEDURE IF EXISTS api_report$$
CREATE PROCEDURE api_report(IN p_uid VARCHAR(10), IN p_report VARCHAR(5), IN p_year VARCHAR(10),
                            IN p_from VARCHAR(20), IN p_to VARCHAR(20))
BEGIN
  DECLARE v_year INT;
  DECLARE v_from DATE;
  DECLARE v_to DATE;
  DECLARE v_tmp DATE;
  CALL sp_require(p_uid, 'SC11', '');

  -- ปีรับได้ทั้ง พ.ศ. (2568) และ ค.ศ. (2025) / ค่าเริ่มต้น = ปีนี้, ช่วงวันที่ = เดือนนี้
  SET v_year = IF(mut_is_int(p_year) AND CAST(p_year AS SIGNED) > 0, CAST(p_year AS SIGNED), YEAR(CURDATE()));
  IF v_year > 2400 THEN
    SET v_year = v_year - 543;
  END IF;
  SET v_from = IF(mut_is_date(p_from), STR_TO_DATE(p_from, '%Y-%m-%d'), CURDATE() - INTERVAL (DAY(CURDATE()) - 1) DAY);
  SET v_to = IF(mut_is_date(p_to), STR_TO_DATE(p_to, '%Y-%m-%d'), LAST_DAY(CURDATE()));
  IF v_from > v_to THEN
    SET v_tmp = v_from; SET v_from = v_to; SET v_to = v_tmp;
  END IF;
  SELECT v_year AS year_ad, v_from AS date_from, v_to AS date_to;

  CASE COALESCE(p_report, '1')
  -- รายงาน 1: จำนวนคนขึ้น–ลงรถรายปี แยกจุดจอด × เดือน (เฉพาะที่ Check-in)
  WHEN '1' THEN
    SELECT k.type, s.stop_id, s.stop_name,
           SUM(IF(x.m = 1, x.n, 0)) AS m1,  SUM(IF(x.m = 2, x.n, 0)) AS m2,  SUM(IF(x.m = 3, x.n, 0)) AS m3,
           SUM(IF(x.m = 4, x.n, 0)) AS m4,  SUM(IF(x.m = 5, x.n, 0)) AS m5,  SUM(IF(x.m = 6, x.n, 0)) AS m6,
           SUM(IF(x.m = 7, x.n, 0)) AS m7,  SUM(IF(x.m = 8, x.n, 0)) AS m8,  SUM(IF(x.m = 9, x.n, 0)) AS m9,
           SUM(IF(x.m = 10, x.n, 0)) AS m10, SUM(IF(x.m = 11, x.n, 0)) AS m11, SUM(IF(x.m = 12, x.n, 0)) AS m12,
           COALESCE(SUM(x.n), 0) AS total
      FROM (SELECT 1 AS sort, 'ขึ้นรถ' AS type UNION ALL SELECT 2, 'ลงรถ') k
     CROSS JOIN stops s
      LEFT JOIN (
        SELECT 1 AS sort, MONTH(t.trip_date) AS m, bi.board_stop_id AS stop_id, SUM(bi.seats) AS n
          FROM booking_items bi JOIN trips t ON t.trip_id = bi.trip_id
         WHERE bi.checkin_at IS NOT NULL AND YEAR(t.trip_date) = v_year
         GROUP BY MONTH(t.trip_date), bi.board_stop_id
        UNION ALL
        SELECT 2, MONTH(t.trip_date), bi.alight_stop_id, SUM(bi.seats)
          FROM booking_items bi JOIN trips t ON t.trip_id = bi.trip_id
         WHERE bi.checkin_at IS NOT NULL AND YEAR(t.trip_date) = v_year
         GROUP BY MONTH(t.trip_date), bi.alight_stop_id
      ) x ON x.sort = k.sort AND x.stop_id = s.stop_id
     GROUP BY k.sort, k.type, s.stop_id, s.stop_name
     ORDER BY k.sort, s.stop_id;

  -- รายงาน 2: สถิติการจองรายปี (ครบ 12 เดือน)
  WHEN '2' THEN
    SELECT mo.month_no,
           COALESCE(d.bookings, 0) AS bookings, COALESCE(d.booking_items, 0) AS booking_items,
           COALESCE(d.booked_seats, 0) AS booked_seats, COALESCE(d.cancelled, 0) AS cancelled,
           COALESCE(d.checked_in, 0) AS checked_in, COALESCE(d.no_show, 0) AS no_show
      FROM (SELECT 1 AS month_no UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6
            UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10 UNION ALL SELECT 11 UNION ALL SELECT 12) mo
      LEFT JOIN (
        SELECT MONTH(t.trip_date) AS month_no,
               COUNT(DISTINCT bi.booking_id)                                  AS bookings,
               COUNT(*)                                                       AS booking_items,
               SUM(CASE WHEN bi.status <> 'ยกเลิก' THEN bi.seats ELSE 0 END)  AS booked_seats,
               SUM(CASE WHEN bi.status = 'ยกเลิก' THEN 1 ELSE 0 END)          AS cancelled,
               SUM(CASE WHEN bi.checkin_at IS NOT NULL THEN 1 ELSE 0 END)    AS checked_in,
               SUM(CASE WHEN bi.status = 'No Show' THEN 1 ELSE 0 END)        AS no_show
          FROM booking_items bi JOIN trips t ON t.trip_id = bi.trip_id
         WHERE YEAR(t.trip_date) = v_year
         GROUP BY MONTH(t.trip_date)
      ) d ON d.month_no = mo.month_no
     ORDER BY mo.month_no;

  -- รายงาน 3: พฤติกรรมผู้ใช้ตามช่วงวันที่
  WHEN '3' THEN
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

  -- รายงาน 4: ผู้ใช้บริการจริงแต่ละเส้นทาง รวมตามวันในสัปดาห์ (ชุดที่ 2 = เส้นทาง / ชุดที่ 3 = ข้อมูล)
  WHEN '4' THEN
    SELECT route_id, route_name FROM routes ORDER BY route_id;
    SELECT DAYOFWEEK(t.trip_date) AS dow_no, t.route_id, SUM(bi.seats) AS passengers
      FROM booking_items bi JOIN trips t ON t.trip_id = bi.trip_id
     WHERE bi.checkin_at IS NOT NULL AND t.trip_date BETWEEN v_from AND v_to
     GROUP BY DAYOFWEEK(t.trip_date), t.route_id;

  -- รายงาน 5: การใช้บริการแต่ละจุดจอดตามรอบเวลา
  WHEN '5' THEN
    SELECT ts.stop_name, TIME(ts.arrive_at) AS pass_time,
           COALESCE(SUM(CASE WHEN bi.board_order  = ts.stop_order THEN bi.seats END), 0) AS boarding,
           COALESCE(SUM(CASE WHEN bi.alight_order = ts.stop_order THEN bi.seats END), 0) AS alighting
      FROM v_trip_stop_times ts
      LEFT JOIN v_booking_item_segments bi
             ON bi.trip_id = ts.trip_id AND bi.checkin_at IS NOT NULL
            AND (bi.board_order = ts.stop_order OR bi.alight_order = ts.stop_order)
     WHERE ts.trip_date BETWEEN v_from AND v_to
     GROUP BY ts.stop_name, TIME(ts.arrive_at)
     ORDER BY ts.stop_name, TIME(ts.arrive_at);

  -- รายงาน 6: การมอบหมายงานคนขับ ก่อน/หลัง 17:00 (ไม่นับรอบที่ยกเลิก)
  WHEN '6' THEN
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
    SELECT vt.vehicle_type_id, vt.type_name, v.plate_no, COUNT(t.trip_id) AS trips
      FROM vehicle_types vt
      JOIN vehicles v   ON v.vehicle_type_id = vt.vehicle_type_id
      LEFT JOIN trips t ON t.vehicle_id = v.vehicle_id
                       AND t.trip_date BETWEEN v_from AND v_to AND t.status <> 'ยกเลิก'
     GROUP BY vt.vehicle_type_id, vt.type_name, v.plate_no
     ORDER BY vt.vehicle_type_id, v.plate_no;

  ELSE
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ไม่พบรายงานนี้';
  END CASE;
END$$

DELIMITER ;
