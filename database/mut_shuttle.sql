-- =====================================================================
--  MUT Shuttle Bus System — Database Schema (MySQL 8.0+ / MariaDB 10.5+)
--  อ้างอิง: ER Diagram + Mapping + ข้อมูลจุดจอด/เวลาจากเอกสาร MINI PROJECT
--  วิธีใช้: รันทั้งไฟล์ใน phpMyAdmin (แท็บ SQL) หรือ
--          mysql -u root -p < mut_shuttle.sql
-- =====================================================================

DROP DATABASE IF EXISTS mut_shuttle;
CREATE DATABASE mut_shuttle CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE mut_shuttle;

-- =====================================================================
-- 1) ตาราง (Tables)
-- =====================================================================

-- 1. แผนก
CREATE TABLE departments (
  department_id   VARCHAR(10)  NOT NULL,               -- รหัสแผนก (PK)
  department_name VARCHAR(100) NOT NULL,               -- ชื่อแผนก
  PRIMARY KEY (department_id)
) ENGINE=InnoDB COMMENT='แผนก';

-- 4. ตำแหน่ง
CREATE TABLE positions (
  position_id   VARCHAR(10)  NOT NULL,                 -- รหัสตำแหน่ง (PK)
  position_name VARCHAR(100) NOT NULL,                 -- ชื่อตำแหน่ง
  department_id VARCHAR(10)  NULL,                     -- แผนกของตำแหน่ง (FK) — NULL = ใช้ได้ทุกแผนก
  PRIMARY KEY (position_id),
  CONSTRAINT fk_positions_department FOREIGN KEY (department_id) REFERENCES departments (department_id)
) ENGINE=InnoDB COMMENT='ตำแหน่ง';

-- 6. หน้าจอ
CREATE TABLE screens (
  screen_id   VARCHAR(10)  NOT NULL,                   -- รหัสหน้าจอ (PK)
  screen_name VARCHAR(100) NOT NULL,                   -- ชื่อหน้าจอ
  PRIMARY KEY (screen_id)
) ENGINE=InnoDB COMMENT='หน้าจอ';

-- 2. ผู้ใช้งาน
CREATE TABLE users (
  user_id       VARCHAR(10)  NOT NULL,                 -- รหัสผู้ใช้งาน (PK)
  name          VARCHAR(100) NOT NULL,                 -- ชื่อ
  email         VARCHAR(150) NOT NULL,
  username      VARCHAR(50)  NOT NULL,
  password_hash VARCHAR(255) NOT NULL,                 -- เก็บเป็น hash เท่านั้น
  department_id VARCHAR(10)  NOT NULL,                 -- รหัสแผนก (FK)
  PRIMARY KEY (user_id),
  UNIQUE KEY uq_users_email (email),
  UNIQUE KEY uq_users_username (username),
  CONSTRAINT fk_users_department FOREIGN KEY (department_id) REFERENCES departments (department_id)
) ENGINE=InnoDB COMMENT='ผู้ใช้งาน (Superclass)';

-- 3 + 5. พนักงาน (Subclass ของ ผู้ใช้งาน) + ตำแหน่ง
CREATE TABLE employees (
  user_id     VARCHAR(10) NOT NULL,                    -- รหัสผู้ใช้งาน (PK, FK)
  phone       VARCHAR(20) NOT NULL,                    -- เบอร์โทร
  position_id VARCHAR(10) NOT NULL,                    -- รหัสตำแหน่ง (FK)
  PRIMARY KEY (user_id),
  CONSTRAINT fk_employees_user     FOREIGN KEY (user_id)     REFERENCES users (user_id) ON DELETE CASCADE,
  CONSTRAINT fk_employees_position FOREIGN KEY (position_id) REFERENCES positions (position_id)
) ENGINE=InnoDB COMMENT='พนักงาน';

-- 7. สิทธิ์ (Weak entity ของ ตำแหน่ง)
--    มีแถว = เข้าถึงหน้าจอนั้นได้ / can_add, can_edit, can_delete = 0/1
CREATE TABLE permissions (
  permission_id VARCHAR(10) NOT NULL,                  -- รหัสสิทธิ์ (PK)
  can_add       TINYINT(1)  NOT NULL DEFAULT 0,        -- เพิ่ม
  can_edit      TINYINT(1)  NOT NULL DEFAULT 0,        -- แก้ไข
  can_delete    TINYINT(1)  NOT NULL DEFAULT 0,        -- ลบ
  position_id   VARCHAR(10) NOT NULL,                  -- รหัสตำแหน่ง (FK)
  screen_id     VARCHAR(10) NOT NULL,                  -- รหัสหน้าจอ (FK)
  PRIMARY KEY (permission_id),
  UNIQUE KEY uq_perm_position_screen (position_id, screen_id),
  CONSTRAINT fk_perm_position FOREIGN KEY (position_id) REFERENCES positions (position_id) ON DELETE CASCADE,
  CONSTRAINT fk_perm_screen   FOREIGN KEY (screen_id)   REFERENCES screens (screen_id)     ON DELETE CASCADE,
  CONSTRAINT ck_perm_flags CHECK (can_add IN (0,1) AND can_edit IN (0,1) AND can_delete IN (0,1))
) ENGINE=InnoDB COMMENT='สิทธิ์';

-- 8. ประเภทรถ
CREATE TABLE vehicle_types (
  vehicle_type_id VARCHAR(10)  NOT NULL,               -- รหัสประเภทรถ (PK)
  type_name       VARCHAR(50)  NOT NULL,               -- ชื่อประเภทรถ
  description     VARCHAR(255) NULL,                   -- รายละเอียด
  seat_count      INT          NOT NULL,               -- จำนวนที่นั่ง
  PRIMARY KEY (vehicle_type_id),
  CONSTRAINT ck_vtype_seats CHECK (seat_count > 0)
) ENGINE=InnoDB COMMENT='ประเภทรถ';

-- 9. รถ
CREATE TABLE vehicles (
  vehicle_id      VARCHAR(10) NOT NULL,                -- รหัสรถ (PK)
  plate_no        VARCHAR(20) NOT NULL,                -- ทะเบียนรถ (UNIQUE)
  status          ENUM('พร้อมใช้งาน','ซ่อมบำรุง','ไม่พร้อมใช้งาน') NOT NULL DEFAULT 'พร้อมใช้งาน',
  vehicle_type_id VARCHAR(10) NOT NULL,                -- รหัสประเภทรถ (FK)
  PRIMARY KEY (vehicle_id),
  UNIQUE KEY uq_vehicles_plate (plate_no),
  CONSTRAINT fk_vehicles_type FOREIGN KEY (vehicle_type_id) REFERENCES vehicle_types (vehicle_type_id)
) ENGINE=InnoDB COMMENT='รถ';

-- 10. เส้นทาง  (เวลารวม = Derived → ดู view v_route_totals)
CREATE TABLE routes (
  route_id   VARCHAR(10)  NOT NULL,                    -- รหัสเส้นทาง (PK)
  route_name VARCHAR(100) NOT NULL,                    -- ชื่อเส้นทาง
  PRIMARY KEY (route_id)
) ENGINE=InnoDB COMMENT='เส้นทาง';

-- 12. จุดจอด
CREATE TABLE stops (
  stop_id   VARCHAR(10)  NOT NULL,                     -- รหัสจุดจอด (PK)
  stop_name VARCHAR(150) NOT NULL,                     -- ชื่อจุดจอด
  PRIMARY KEY (stop_id)
) ENGINE=InnoDB COMMENT='จุดจอด';

-- 13. เส้นทาง_จุดจอด (Weak entity ของ เส้นทาง)
--     PK = (รหัสเส้นทาง, ลำดับจุดจอด) เพราะเส้นทางผ่านจุดจอดเดิมซ้ำได้
CREATE TABLE route_stops (
  route_id       VARCHAR(10) NOT NULL,                 -- รหัสเส้นทาง (PK, FK)
  stop_order     INT         NOT NULL,                 -- ลำดับจุดจอด (partial key)
  stop_id        VARCHAR(10) NOT NULL,                 -- รหัสจุดจอด (FK)
  travel_minutes INT         NOT NULL DEFAULT 0,       -- เวลาเดินทางจากจุดก่อนหน้า (นาที)
  PRIMARY KEY (route_id, stop_order),
  KEY ix_route_stops_stop (stop_id),
  CONSTRAINT fk_rs_route FOREIGN KEY (route_id) REFERENCES routes (route_id) ON DELETE CASCADE,
  CONSTRAINT fk_rs_stop  FOREIGN KEY (stop_id)  REFERENCES stops (stop_id),
  CONSTRAINT ck_rs_order   CHECK (stop_order >= 1),
  CONSTRAINT ck_rs_minutes CHECK (travel_minutes >= 0)
) ENGINE=InnoDB COMMENT='เส้นทาง_จุดจอด';

-- 16. ตารางเวลาเดินรถประจำ — ระบบสร้างรอบการเดินรถของแต่ละวันล่วงหน้าจากตารางนี้ (procedure sp_ensure_trips ใน api_procedures.sql)
--     "รอบที่" = ลำดับเวลาออกภายในเส้นทาง (ไม่ได้เก็บ)
CREATE TABLE trip_schedules (
  schedule_id VARCHAR(10) NOT NULL,                    -- รหัสตารางเวลา (PK)
  route_id    VARCHAR(10) NOT NULL,                    -- รหัสเส้นทาง (FK)
  depart_time TIME        NOT NULL,                    -- เวลาออก
  vehicle_id  VARCHAR(10) NOT NULL,                    -- รหัสรถ (FK)
  driver_id   VARCHAR(10) NOT NULL,                    -- คนขับ (FK)
  run_days    VARCHAR(7)  NOT NULL DEFAULT '12345',    -- วันที่วิ่ง 0=อาทิตย์ … 6=เสาร์ ('12345' = จันทร์–ศุกร์)
  active      TINYINT(1)  NOT NULL DEFAULT 1,          -- 1 = ใช้งาน / 0 = หยุดใช้งาน
  PRIMARY KEY (schedule_id),
  UNIQUE KEY uq_sched_route_time (route_id, depart_time),
  CONSTRAINT fk_sched_route   FOREIGN KEY (route_id)   REFERENCES routes (route_id) ON DELETE CASCADE,
  CONSTRAINT fk_sched_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicles (vehicle_id),
  CONSTRAINT fk_sched_driver  FOREIGN KEY (driver_id)  REFERENCES employees (user_id),
  CONSTRAINT ck_sched_days CHECK (run_days REGEXP '^[0-6]+$'),
  CONSTRAINT ck_sched_active CHECK (active IN (0,1))
) ENGINE=InnoDB COMMENT='ตารางเวลาเดินรถประจำ';

-- 11. รอบการเดินรถ
CREATE TABLE trips (
  trip_id     VARCHAR(10) NOT NULL,                    -- รหัสรอบการเดินรถ (PK)
  trip_date   DATE        NOT NULL,                    -- วันที่เดินรถ
  depart_time TIME        NOT NULL,                    -- เวลาออก
  status      ENUM('เปิด','กำลังเดินทาง','เสร็จสิ้น','ยกเลิก') NOT NULL DEFAULT 'เปิด',  -- สถานะรอบ
  seat_count  INT         NOT NULL DEFAULT 0,          -- จำนวนที่นั่ง (Derived: trigger ดึงจากประเภทรถ)
  vehicle_id  VARCHAR(10) NOT NULL,                    -- รหัสรถ (FK)
  route_id    VARCHAR(10) NOT NULL,                    -- รหัสเส้นทาง (FK)
  driver_id   VARCHAR(10) NOT NULL,                    -- คนขับ = รหัสผู้ใช้งานของพนักงาน (FK) ตาม ER
  schedule_id VARCHAR(10) NULL,                        -- สร้างจากตารางเวลาใด (FK, NULL = จัดรอบเอง)
  PRIMARY KEY (trip_id),
  KEY ix_trips_date (trip_date, depart_time),
  KEY ix_trips_schedule (schedule_id, trip_date),
  CONSTRAINT fk_trips_vehicle  FOREIGN KEY (vehicle_id)  REFERENCES vehicles (vehicle_id),
  CONSTRAINT fk_trips_route    FOREIGN KEY (route_id)    REFERENCES routes (route_id),
  CONSTRAINT fk_trips_driver   FOREIGN KEY (driver_id)   REFERENCES employees (user_id),
  CONSTRAINT fk_trips_schedule FOREIGN KEY (schedule_id) REFERENCES trip_schedules (schedule_id) ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='รอบการเดินรถ';

-- 14. การจอง
CREATE TABLE bookings (
  booking_id VARCHAR(10) NOT NULL,                     -- รหัสการจอง (PK)
  booked_at  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,  -- วันที่และเวลาจอง
  user_id    VARCHAR(10) NOT NULL,                     -- รหัสผู้ใช้งาน (FK)
  PRIMARY KEY (booking_id),
  CONSTRAINT fk_bookings_user FOREIGN KEY (user_id) REFERENCES users (user_id)
) ENGINE=InnoDB COMMENT='การจอง';

-- 15. รายการจอง (Weak entity ของ การจอง)
CREATE TABLE booking_items (
  booking_item_id VARCHAR(10) NOT NULL,                -- รหัสรายการจอง (PK)
  qr_code         VARCHAR(64) NOT NULL,                -- QR Code (UNIQUE)
  status          ENUM('ยืนยัน','ยกเลิก','No Show') NOT NULL DEFAULT 'ยืนยัน',  -- สถานะการจอง
  seats           INT         NOT NULL,                -- จำนวนที่นั่งจอง (1–4)
  checkin_at      DATETIME    NULL,                    -- วันและเวลา Check-in
  booking_id      VARCHAR(10) NOT NULL,                -- รหัสการจอง (FK)
  trip_id         VARCHAR(10) NOT NULL,                -- รหัสรอบการเดินรถ (FK)
  board_stop_id   VARCHAR(10) NOT NULL,                -- รหัสจุดจอดขึ้น (FK)
  alight_stop_id  VARCHAR(10) NOT NULL,                -- รหัสจุดจอดลง (FK)
  PRIMARY KEY (booking_item_id),
  UNIQUE KEY uq_items_qr (qr_code),
  KEY ix_items_trip (trip_id, status),
  CONSTRAINT fk_items_booking FOREIGN KEY (booking_id)     REFERENCES bookings (booking_id) ON DELETE CASCADE,
  CONSTRAINT fk_items_trip    FOREIGN KEY (trip_id)        REFERENCES trips (trip_id),
  CONSTRAINT fk_items_board   FOREIGN KEY (board_stop_id)  REFERENCES stops (stop_id),
  CONSTRAINT fk_items_alight  FOREIGN KEY (alight_stop_id) REFERENCES stops (stop_id),
  CONSTRAINT ck_items_seats CHECK (seats BETWEEN 1 AND 4),
  CONSTRAINT ck_items_stops CHECK (board_stop_id <> alight_stop_id)
) ENGINE=InnoDB COMMENT='รายการจอง';


-- =====================================================================
-- 2) Views — ค่าที่คำนวณได้ (Derived)
-- =====================================================================

-- เวลารวมของเส้นทาง
CREATE VIEW v_route_totals AS
SELECT r.route_id, r.route_name,
       COUNT(rs.stop_order)                 AS stop_count,
       COALESCE(SUM(rs.travel_minutes), 0)  AS total_minutes
FROM routes r
LEFT JOIN route_stops rs ON rs.route_id = r.route_id
GROUP BY r.route_id, r.route_name;

-- เวลาสะสมถึงแต่ละลำดับจุดจอด
CREATE VIEW v_route_stop_times AS
SELECT rs.route_id, rs.stop_order, rs.stop_id, s.stop_name, rs.travel_minutes,
       SUM(rs.travel_minutes) OVER (PARTITION BY rs.route_id ORDER BY rs.stop_order
                                    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_minutes
FROM route_stops rs
JOIN stops s ON s.stop_id = rs.stop_id;

-- เวลาที่รถแต่ละรอบถึงแต่ละจุดจอด
CREATE VIEW v_trip_stop_times AS
SELECT t.trip_id, t.trip_date, t.depart_time, t.route_id,
       st.stop_order, st.stop_id, st.stop_name, st.cum_minutes,
       TIMESTAMP(t.trip_date, t.depart_time) + INTERVAL st.cum_minutes MINUTE AS arrive_at
FROM trips t
JOIN v_route_stop_times st ON st.route_id = t.route_id;

-- ที่นั่งคงเหลือต่อรอบ (ไม่นับรายการที่ยกเลิก)
CREATE VIEW v_trip_seats AS
SELECT t.trip_id, t.seat_count,
       COALESCE(SUM(CASE WHEN bi.status <> 'ยกเลิก' THEN bi.seats END), 0)               AS booked_seats,
       t.seat_count - COALESCE(SUM(CASE WHEN bi.status <> 'ยกเลิก' THEN bi.seats END), 0) AS remaining_seats
FROM trips t
LEFT JOIN booking_items bi ON bi.trip_id = t.trip_id
GROUP BY t.trip_id, t.seat_count;

-- ลำดับจุดขึ้น/ลงของรายการจอง (จุดขึ้น = ลำดับแรกที่ตรง, จุดลง = ลำดับแรกหลังจุดขึ้น)
CREATE VIEW v_booking_item_segments AS
SELECT bi.booking_item_id, bi.booking_id, bi.trip_id, bi.status, bi.seats, bi.checkin_at,
       bi.board_stop_id, bi.alight_stop_id, t.route_id,
       (SELECT MIN(a.stop_order) FROM route_stops a
         WHERE a.route_id = t.route_id AND a.stop_id = bi.board_stop_id) AS board_order,
       (SELECT MIN(b.stop_order) FROM route_stops b
         WHERE b.route_id = t.route_id AND b.stop_id = bi.alight_stop_id
           AND b.stop_order > (SELECT MIN(a2.stop_order) FROM route_stops a2
                                WHERE a2.route_id = t.route_id AND a2.stop_id = bi.board_stop_id)) AS alight_order
FROM booking_items bi
JOIN trips t ON t.trip_id = bi.trip_id;

-- รายการจองพร้อมเวลาถึงจุดขึ้น/จุดลง
CREATE VIEW v_booking_item_times AS
SELECT sg.*, u.user_id, u.name AS passenger_name,
       tb.arrive_at AS board_at, ta.arrive_at AS alight_at
FROM v_booking_item_segments sg
JOIN bookings b          ON b.booking_id = sg.booking_id
JOIN users u             ON u.user_id = b.user_id
JOIN v_trip_stop_times tb ON tb.trip_id = sg.trip_id AND tb.stop_order = sg.board_order
LEFT JOIN v_trip_stop_times ta ON ta.trip_id = sg.trip_id AND ta.stop_order = sg.alight_order;


-- =====================================================================
-- 3) Triggers — บังคับกฎทางธุรกิจที่ระดับฐานข้อมูล
-- =====================================================================
DELIMITER $$

-- ที่นั่งว่างในช่วงจุดขึ้น → จุดลงของรอบ = ความจุ − จำนวนคนบนรถสูงสุดในช่วงนั้น
-- ผู้โดยสารครองที่นั่งตั้งแต่จุดขึ้นถึงก่อนจุดลง — ลงแล้วที่นั่งว่างให้คนที่ขึ้นหลังจากนั้นจองต่อได้
-- p_exclude = รายการจองที่ไม่นับ (ใช้ตอนแก้ไขรายการเดิม) หรือ NULL
CREATE FUNCTION mut_segment_remaining(p_trip VARCHAR(10), p_board VARCHAR(10), p_alight VARCHAR(10), p_exclude VARCHAR(10))
RETURNS INT
READS SQL DATA
BEGIN
  DECLARE v_route VARCHAR(10);
  DECLARE v_seats INT;
  DECLARE v_from INT;
  DECLARE v_to INT;
  DECLARE v_max INT DEFAULT 0;

  SELECT route_id, seat_count INTO v_route, v_seats FROM trips WHERE trip_id = p_trip;
  SELECT MIN(stop_order) INTO v_from FROM route_stops WHERE route_id = v_route AND stop_id = p_board;
  SELECT MIN(stop_order) INTO v_to FROM route_stops
   WHERE route_id = v_route AND stop_id = p_alight AND stop_order > v_from;
  IF v_seats IS NULL OR v_from IS NULL OR v_to IS NULL THEN
    RETURN 0;
  END IF;

  -- จำนวนคนบนรถในแต่ละช่วง (ลำดับ k → k+1) ที่อยู่ในช่วงที่จอง แล้วเอาช่วงที่แน่นที่สุด
  SELECT COALESCE(MAX(x.occ), 0) INTO v_max
  FROM (SELECT rs.stop_order, SUM(sg.seats) AS occ
          FROM route_stops rs
          JOIN v_booking_item_segments sg
            ON sg.trip_id = p_trip AND sg.status <> 'ยกเลิก'
           AND sg.board_order <= rs.stop_order AND sg.alight_order > rs.stop_order
           AND (p_exclude IS NULL OR sg.booking_item_id <> p_exclude)
         WHERE rs.route_id = v_route AND rs.stop_order >= v_from AND rs.stop_order < v_to
         GROUP BY rs.stop_order) x;
  RETURN v_seats - v_max;
END$$

-- รอบการเดินรถ: ดึงจำนวนที่นั่งจากประเภทรถ + ตรวจรถ/คนขับชนเวลา
CREATE TRIGGER trg_trips_bi BEFORE INSERT ON trips
FOR EACH ROW
BEGIN
  DECLARE v_msg VARCHAR(255);
  DECLARE v_total INT DEFAULT 0;
  DECLARE v_conflict VARCHAR(10);

  SET NEW.seat_count = (SELECT vt.seat_count
    FROM vehicles v JOIN vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id
    WHERE v.vehicle_id = NEW.vehicle_id);

  IF NEW.status <> 'ยกเลิก' THEN
    IF (SELECT status FROM vehicles WHERE vehicle_id = NEW.vehicle_id) <> 'พร้อมใช้งาน' THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'รถคันนี้ไม่อยู่ในสถานะพร้อมใช้งาน';
    END IF;

    SELECT COALESCE(SUM(travel_minutes), 0) INTO v_total FROM route_stops WHERE route_id = NEW.route_id;

    SET v_conflict = NULL;
    SELECT t.trip_id INTO v_conflict
    FROM trips t
    WHERE t.trip_date = NEW.trip_date AND t.status <> 'ยกเลิก' AND t.vehicle_id = NEW.vehicle_id
      AND TIMESTAMP(t.trip_date, t.depart_time) <
          TIMESTAMP(NEW.trip_date, NEW.depart_time) + INTERVAL v_total MINUTE
      AND TIMESTAMP(NEW.trip_date, NEW.depart_time) <
          TIMESTAMP(t.trip_date, t.depart_time)
          + INTERVAL (SELECT COALESCE(SUM(x.travel_minutes), 0) FROM route_stops x WHERE x.route_id = t.route_id) MINUTE
    LIMIT 1;
    IF v_conflict IS NOT NULL THEN
      SET v_msg = CONCAT('ไม่สามารถจัดรอบนี้ได้ เนื่องจากรถถูกมอบหมายในรอบ ', v_conflict, ' ช่วงเวลาเดียวกัน');
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;

    SET v_conflict = NULL;
    SELECT t.trip_id INTO v_conflict
    FROM trips t
    WHERE t.trip_date = NEW.trip_date AND t.status <> 'ยกเลิก' AND t.driver_id = NEW.driver_id
      AND TIMESTAMP(t.trip_date, t.depart_time) <
          TIMESTAMP(NEW.trip_date, NEW.depart_time) + INTERVAL v_total MINUTE
      AND TIMESTAMP(NEW.trip_date, NEW.depart_time) <
          TIMESTAMP(t.trip_date, t.depart_time)
          + INTERVAL (SELECT COALESCE(SUM(x.travel_minutes), 0) FROM route_stops x WHERE x.route_id = t.route_id) MINUTE
    LIMIT 1;
    IF v_conflict IS NOT NULL THEN
      SET v_msg = CONCAT('ไม่สามารถจัดรอบนี้ได้ เนื่องจากคนขับมีงานรอบ ', v_conflict, ' ในช่วงเวลาเดียวกัน');
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;
  END IF;
END$$

CREATE TRIGGER trg_trips_bu BEFORE UPDATE ON trips
FOR EACH ROW
BEGIN
  DECLARE v_msg VARCHAR(255);
  DECLARE v_total INT DEFAULT 0;
  DECLARE v_conflict VARCHAR(10);

  IF NEW.vehicle_id <> OLD.vehicle_id THEN
    SET NEW.seat_count = (SELECT vt.seat_count
      FROM vehicles v JOIN vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id
      WHERE v.vehicle_id = NEW.vehicle_id);
  END IF;

  -- ตรวจชนเวลาเฉพาะเมื่อเปลี่ยน วัน/เวลา/รถ/คนขับ/เส้นทาง หรือเปิดรอบที่ยกเลิกกลับมา
  IF NEW.status <> 'ยกเลิก' AND (NEW.trip_date <> OLD.trip_date OR NEW.depart_time <> OLD.depart_time
      OR NEW.vehicle_id <> OLD.vehicle_id OR NEW.driver_id <> OLD.driver_id
      OR NEW.route_id <> OLD.route_id OR OLD.status = 'ยกเลิก') THEN

    SELECT COALESCE(SUM(travel_minutes), 0) INTO v_total FROM route_stops WHERE route_id = NEW.route_id;

    SET v_conflict = NULL;
    SELECT t.trip_id INTO v_conflict
    FROM trips t
    WHERE t.trip_id <> NEW.trip_id AND t.trip_date = NEW.trip_date AND t.status <> 'ยกเลิก'
      AND (t.vehicle_id = NEW.vehicle_id OR t.driver_id = NEW.driver_id)
      AND TIMESTAMP(t.trip_date, t.depart_time) <
          TIMESTAMP(NEW.trip_date, NEW.depart_time) + INTERVAL v_total MINUTE
      AND TIMESTAMP(NEW.trip_date, NEW.depart_time) <
          TIMESTAMP(t.trip_date, t.depart_time)
          + INTERVAL (SELECT COALESCE(SUM(x.travel_minutes), 0) FROM route_stops x WHERE x.route_id = t.route_id) MINUTE
    LIMIT 1;
    IF v_conflict IS NOT NULL THEN
      SET v_msg = CONCAT('ไม่สามารถจัดรอบนี้ได้ เนื่องจากรถหรือคนขับชนกับรอบ ', v_conflict);
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;
  END IF;
END$$

-- รายการจอง: จุดขึ้นต้องอยู่ก่อนจุดลงในเส้นทาง + ที่นั่งต้องพอในช่วงที่จอง
CREATE TRIGGER trg_items_bi BEFORE INSERT ON booking_items
FOR EACH ROW
BEGIN
  DECLARE v_ok INT DEFAULT 0;

  SELECT COUNT(*) INTO v_ok
  FROM trips t
  JOIN route_stops a ON a.route_id = t.route_id AND a.stop_id = NEW.board_stop_id
  JOIN route_stops b ON b.route_id = t.route_id AND b.stop_id = NEW.alight_stop_id AND b.stop_order > a.stop_order
  WHERE t.trip_id = NEW.trip_id;
  IF v_ok = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'จุดขึ้น/จุดลงไม่อยู่ในเส้นทางของรอบนี้ หรือจุดลงอยู่ก่อนจุดขึ้น';
  END IF;

  -- ที่นั่งต้องพอเฉพาะช่วงจุดขึ้น → จุดลงที่จอง
  IF NEW.status <> 'ยกเลิก'
     AND NEW.seats > mut_segment_remaining(NEW.trip_id, NEW.board_stop_id, NEW.alight_stop_id, NULL) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ที่นั่งว่างไม่พอในช่วงจุดขึ้น–จุดลงนี้';
  END IF;
END$$

CREATE TRIGGER trg_items_bu BEFORE UPDATE ON booking_items
FOR EACH ROW
BEGIN
  IF NEW.status <> 'ยกเลิก'
     AND (OLD.status = 'ยกเลิก' OR NEW.seats > OLD.seats OR NEW.trip_id <> OLD.trip_id
          OR NEW.board_stop_id <> OLD.board_stop_id OR NEW.alight_stop_id <> OLD.alight_stop_id)
     AND NEW.seats > mut_segment_remaining(NEW.trip_id, NEW.board_stop_id, NEW.alight_stop_id, OLD.booking_item_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ที่นั่งว่างไม่พอในช่วงจุดขึ้น–จุดลงนี้';
  END IF;
END$$


-- =====================================================================
-- 4) Stored Procedures — ใช้จากแอปพลิเคชัน
-- =====================================================================

-- ค้นหารอบที่จองได้ (ซ่อนรอบที่รถจะถึงจุดขึ้นในอีกไม่ถึง 20 นาที)
-- ที่นั่งคงเหลือ = ที่นั่งว่างเฉพาะช่วงจุดขึ้น → จุดลงที่ค้นหา
CREATE PROCEDURE sp_search_trips(IN p_date DATE, IN p_board VARCHAR(10), IN p_alight VARCHAR(10))
BEGIN
  SELECT t.trip_id, t.trip_date, t.depart_time, r.route_name,
         CONCAT(vt.type_name, ' ', v.plate_no) AS vehicle,
         tb.arrive_at AS board_at, ta.arrive_at AS alight_at,
         t.seat_count,
         mut_segment_remaining(t.trip_id, p_board, p_alight, NULL)           AS remaining_seats,
         LEAST(4, mut_segment_remaining(t.trip_id, p_board, p_alight, NULL)) AS max_selectable
  FROM trips t
  JOIN routes r         ON r.route_id = t.route_id
  JOIN vehicles v       ON v.vehicle_id = t.vehicle_id
  JOIN vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id
  JOIN v_trip_stop_times tb ON tb.trip_id = t.trip_id AND tb.stop_id = p_board
       AND tb.stop_order = (SELECT MIN(a.stop_order) FROM route_stops a
                             WHERE a.route_id = t.route_id AND a.stop_id = p_board)
  JOIN v_trip_stop_times ta ON ta.trip_id = t.trip_id AND ta.stop_id = p_alight
       AND ta.stop_order = (SELECT MIN(b.stop_order) FROM route_stops b
                             WHERE b.route_id = t.route_id AND b.stop_id = p_alight AND b.stop_order > tb.stop_order)
  WHERE t.trip_date = p_date
    AND t.status = 'เปิด'
    AND tb.arrive_at >= NOW() + INTERVAL 20 MINUTE
  ORDER BY t.depart_time;
END$$

-- สร้างการจอง 1 รายการ (การจอง + รายการจอง + QR Code) แบบ transaction
CREATE PROCEDURE sp_create_booking(
  IN  p_user   VARCHAR(10),
  IN  p_trip   VARCHAR(10),
  IN  p_board  VARCHAR(10),
  IN  p_alight VARCHAR(10),
  IN  p_seats  INT,
  OUT p_booking_id VARCHAR(10),
  OUT p_item_id    VARCHAR(10),
  OUT p_qr         VARCHAR(64))
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE v_board_at DATETIME;
  DECLARE v_n INT;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  IF p_seats < 1 OR p_seats > 4 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'จองได้ 1–4 ที่นั่งต่อรายการ';
  END IF;

  START TRANSACTION;
    SELECT status INTO v_status FROM trips WHERE trip_id = p_trip FOR UPDATE;   -- ล็อกรอบกันจองชนกัน
    IF v_status IS NULL THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ไม่พบรอบการเดินรถ';
    END IF;
    IF v_status <> 'เปิด' THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'รอบนี้ไม่เปิดให้จอง';
    END IF;

    SELECT MIN(arrive_at) INTO v_board_at
    FROM v_trip_stop_times WHERE trip_id = p_trip AND stop_id = p_board;
    IF v_board_at IS NULL OR v_board_at < NOW() + INTERVAL 20 MINUTE THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ต้องจองก่อนรถถึงจุดขึ้นอย่างน้อย 20 นาที';
    END IF;

    SELECT COALESCE(MAX(CAST(SUBSTRING(booking_id, 2) AS UNSIGNED)), 0) + 1 INTO v_n FROM bookings;
    SET p_booking_id = CONCAT('B', LPAD(v_n, GREATEST(3, CHAR_LENGTH(v_n)), '0'));  -- LPAD ตัดเลขที่ยาวเกิน จึงต้องขยายความยาว
    INSERT INTO bookings (booking_id, booked_at, user_id) VALUES (p_booking_id, NOW(), p_user);

    SELECT COALESCE(MAX(CAST(SUBSTRING(booking_item_id, 3) AS UNSIGNED)), 0) + 1 INTO v_n FROM booking_items;
    SET p_item_id = CONCAT('BD', LPAD(v_n, GREATEST(3, CHAR_LENGTH(v_n)), '0'));
    SET p_qr = CONCAT('QR-', p_item_id, '-', UPPER(LEFT(REPLACE(UUID(), '-', ''), 8)));

    -- trigger trg_items_bi ตรวจลำดับจุดขึ้น–ลง และที่นั่งว่าง
    INSERT INTO booking_items (booking_item_id, qr_code, status, seats, booking_id, trip_id, board_stop_id, alight_stop_id)
    VALUES (p_item_id, p_qr, 'ยืนยัน', p_seats, p_booking_id, p_trip, p_board, p_alight);
  COMMIT;
END$$

-- ยกเลิกรายการจอง (ที่นั่งคืนอัตโนมัติ เพราะ v_trip_seats ไม่นับสถานะยกเลิก)
CREATE PROCEDURE sp_cancel_booking_item(IN p_item VARCHAR(10), IN p_user VARCHAR(10))
BEGIN
  DECLARE v_owner VARCHAR(10);
  DECLARE v_status VARCHAR(20);
  DECLARE v_checkin DATETIME;

  SELECT b.user_id, bi.status, bi.checkin_at INTO v_owner, v_status, v_checkin
  FROM booking_items bi JOIN bookings b ON b.booking_id = bi.booking_id
  WHERE bi.booking_item_id = p_item;

  IF v_owner IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ไม่พบรายการจอง';
  END IF;
  IF p_user IS NOT NULL AND v_owner <> p_user THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ไม่สามารถยกเลิกรายการจองของผู้อื่นได้';
  END IF;
  IF v_status <> 'ยืนยัน' OR v_checkin IS NOT NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'รายการนี้ยกเลิกไม่ได้ (ยกเลิกแล้ว / Check-in แล้ว / No Show)';
  END IF;

  UPDATE booking_items SET status = 'ยกเลิก' WHERE booking_item_id = p_item;
END$$

-- คนขับเริ่มการเดินทาง
CREATE PROCEDURE sp_start_trip(IN p_trip VARCHAR(10), IN p_driver VARCHAR(10))
BEGIN
  IF (SELECT COUNT(*) FROM trips WHERE trip_id = p_trip AND driver_id = p_driver AND status = 'เปิด') = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'เริ่มรอบนี้ไม่ได้ (ไม่ใช่รอบของคนขับ หรือสถานะไม่ใช่ เปิด)';
  END IF;
  UPDATE trips SET status = 'กำลังเดินทาง' WHERE trip_id = p_trip;
END$$

-- สแกน QR Check-in
CREATE PROCEDURE sp_checkin(IN p_qr VARCHAR(64), IN p_trip VARCHAR(10))
BEGIN
  DECLARE v_item VARCHAR(10);
  DECLARE v_trip VARCHAR(10);
  DECLARE v_status VARCHAR(20);
  DECLARE v_checkin DATETIME;
  DECLARE v_msg VARCHAR(255);

  IF (SELECT status FROM trips WHERE trip_id = p_trip) <> 'กำลังเดินทาง' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'กรุณาเริ่มการเดินทางก่อนสแกน QR';
  END IF;

  SELECT booking_item_id, trip_id, status, checkin_at INTO v_item, v_trip, v_status, v_checkin
  FROM booking_items WHERE qr_code = p_qr;

  IF v_item IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ไม่พบ QR Code นี้ในระบบ';
  ELSEIF v_trip <> p_trip THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'QR Code นี้ไม่ตรงกับรอบการเดินทาง ไม่สามารถขึ้นรถได้';
  ELSEIF v_status = 'ยกเลิก' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'รายการจองนี้ถูกยกเลิกแล้ว';
  ELSEIF v_checkin IS NOT NULL THEN
    SET v_msg = CONCAT('รายการจองนี้ Check-in แล้วเมื่อ ', DATE_FORMAT(v_checkin, '%H:%i'));
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;

  UPDATE booking_items SET checkin_at = NOW() WHERE booking_item_id = v_item;

  SELECT t.booking_item_id, t.passenger_name, t.seats, s.stop_name AS alight_stop, 'Check-in สำเร็จ' AS result
  FROM v_booking_item_times t JOIN stops s ON s.stop_id = t.alight_stop_id
  WHERE t.booking_item_id = v_item;
END$$

-- ปิดงาน: รายการที่ไม่ได้ Check-in → No Show และสรุปผล
CREATE PROCEDURE sp_close_trip(IN p_trip VARCHAR(10))
BEGIN
  IF (SELECT status FROM trips WHERE trip_id = p_trip) <> 'กำลังเดินทาง' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ปิดงานได้เฉพาะรอบที่กำลังเดินทาง';
  END IF;

  START TRANSACTION;
    UPDATE booking_items SET status = 'No Show'
    WHERE trip_id = p_trip AND status = 'ยืนยัน' AND checkin_at IS NULL;
    UPDATE trips SET status = 'เสร็จสิ้น' WHERE trip_id = p_trip;
  COMMIT;

  SELECT p_trip AS trip_id,
         COALESCE(SUM(CASE WHEN checkin_at IS NOT NULL THEN seats END), 0) AS actual_passengers,
         SUM(status = 'No Show')                                           AS no_show_items
  FROM booking_items WHERE trip_id = p_trip;

  SELECT bi.booking_item_id, u.name, bi.seats
  FROM booking_items bi JOIN bookings b ON b.booking_id = bi.booking_id JOIN users u ON u.user_id = b.user_id
  WHERE bi.trip_id = p_trip AND bi.status = 'No Show';
END$$

DELIMITER ;


-- =====================================================================
-- 5) ข้อมูลตัวอย่าง (Seed) — จาก Mapping + จุดจอด/เวลาจากเอกสาร MINI
-- =====================================================================

-- D003 = ผู้ใช้บริการที่ Login มาจอง (ไม่ใช่พนักงาน)
INSERT INTO departments VALUES
  ('D001', 'ฝ่ายบุคคล'),
  ('D002', 'ฝ่ายปฏิบัติการ'),
  ('D003', 'นักศึกษา');

INSERT INTO positions (position_id, position_name, department_id) VALUES
  ('P01', 'Admin', 'D001'),
  ('P02', 'พนักงาน', 'D002');

INSERT INTO screens VALUES
  ('SC01', 'จัดการรถ'),
  ('SC02', 'จัดการการจอง'),
  ('SC03', 'จัดการประเภทรถ'),
  ('SC04', 'จัดการจุดจอด'),
  ('SC05', 'จัดการเส้นทาง'),
  ('SC06', 'จัดการรอบการเดินรถ'),
  ('SC07', 'จัดการผู้ใช้งาน/พนักงาน'),
  ('SC08', 'จัดการแผนก'),
  ('SC09', 'จัดการตำแหน่ง'),
  ('SC10', 'จัดการหน้าจอและสิทธิ์'),
  ('SC11', 'รายงาน'),
  ('SC12', 'งานคนขับ');

-- password ตัวอย่าง = '1234' (ในระบบจริงให้ hash ด้วย bcrypt/argon2 ที่ฝั่งแอป)
-- U001 = ผู้ดูแลระบบ / U002–U004 = คนขับตามเอกสาร MINI
INSERT INTO users VALUES
  ('U001', 'ผู้ดูแลระบบ', 'admin@mail.com',   'admin',   SHA2('1234', 256), 'D001'),
  ('U002', 'สมชาย ใจดี',  'somchai@mail.com', 'somchai', SHA2('1234', 256), 'D002'),
  ('U003', 'สมหญิง ใจรัก', 'somying@mail.com', 'somying', SHA2('1234', 256), 'D002'),
  ('U004', 'สมควร ใจงาม', 'somkuan@mail.com', 'somkuan', SHA2('1234', 256), 'D002');

INSERT INTO employees VALUES
  ('U001', '0811111111', 'P01'),
  ('U002', '0822222222', 'P02'),
  ('U003', '0833333333', 'P02'),
  ('U004', '0844444444', 'P02');

-- PR001, PR002 ตาม Mapping / PR003–PR013 = Admin เข้าถึงทุกหน้าจอ
INSERT INTO permissions VALUES
  ('PR001', 1, 1, 1, 'P01', 'SC01'),
  ('PR002', 0, 0, 0, 'P02', 'SC01'),
  ('PR003', 1, 1, 1, 'P01', 'SC02'),
  ('PR004', 1, 1, 1, 'P01', 'SC03'),
  ('PR005', 1, 1, 1, 'P01', 'SC04'),
  ('PR006', 1, 1, 1, 'P01', 'SC05'),
  ('PR007', 1, 1, 1, 'P01', 'SC06'),
  ('PR008', 1, 1, 1, 'P01', 'SC07'),
  ('PR009', 1, 1, 1, 'P01', 'SC08'),
  ('PR010', 1, 1, 1, 'P01', 'SC09'),
  ('PR011', 1, 1, 1, 'P01', 'SC10'),
  ('PR012', 1, 1, 1, 'P01', 'SC11'),
  ('PR013', 0, 1, 0, 'P02', 'SC12');

-- ประเภทรถ/รถตามเอกสาร MINI
INSERT INTO vehicle_types VALUES
  ('T01', 'รถตู้', 'รถโดยสารขนาดเล็ก', 9),
  ('T02', 'รถบัส', 'รถโดยสารขนาดใหญ่', 20);

INSERT INTO vehicles VALUES
  ('V001', 'สย 2591', 'พร้อมใช้งาน', 'T01'),
  ('V002', 'บก 1130', 'พร้อมใช้งาน', 'T02'),
  ('V003', 'สย 2599', 'พร้อมใช้งาน', 'T01');

INSERT INTO routes VALUES
  ('R001', 'เส้นทาง 1'),
  ('R002', 'เส้นทาง 2'),
  ('R003', 'เส้นทาง 3');

-- จุดจอดตามเอกสาร MINI
INSERT INTO stops VALUES
  ('S001', 'มหาวิทยาลัยเทคโนโลยีมหานคร'),
  ('S002', 'โลตัสหนองจอก'),
  ('S003', 'โรงพยาบาลหนองจอก'),
  ('S004', 'Big C หนองจอก'),
  ('S005', 'สวนสาธารณหนองจอก'),
  ('S006', 'ร้านส้มตำป้านาง');

-- ลำดับจุดจอดและเวลาเดินทางตามเอกสาร MINI
-- เส้นทาง 1 = 30 นาที / เส้นทาง 2 = 13 นาที / เส้นทาง 3 = 15 นาที (เอกสารเขียน 12 แต่ 5+3+5+2 = 15)
INSERT INTO route_stops (route_id, stop_order, stop_id, travel_minutes) VALUES
  ('R001', 1, 'S001', 0),
  ('R001', 2, 'S002', 5),
  ('R001', 3, 'S003', 3),
  ('R001', 4, 'S004', 6),
  ('R001', 5, 'S003', 3),
  ('R001', 6, 'S002', 3),
  ('R001', 7, 'S001', 10),
  ('R002', 1, 'S001', 0),
  ('R002', 2, 'S002', 5),
  ('R002', 3, 'S005', 3),
  ('R002', 4, 'S006', 5),
  ('R003', 1, 'S004', 0),
  ('R003', 2, 'S002', 5),
  ('R003', 3, 'S005', 3),
  ('R003', 4, 'S006', 5),
  ('R003', 5, 'S001', 2);

-- ตารางเวลาเดินรถประจำตามเอกสาร MINI — วิ่งเฉพาะวันทำการ (จันทร์–ศุกร์) รอบของแต่ละวันถูกสร้างอัตโนมัติจากตารางนี้
INSERT INTO trip_schedules (schedule_id, route_id, depart_time, vehicle_id, driver_id, run_days, active) VALUES
  ('TS001', 'R001', '09:30:00', 'V001', 'U002', '12345', 1),
  ('TS002', 'R001', '11:00:00', 'V001', 'U003', '12345', 1),
  ('TS003', 'R001', '13:00:00', 'V002', 'U002', '12345', 1),
  ('TS004', 'R001', '15:00:00', 'V002', 'U002', '12345', 1),
  ('TS005', 'R002', '09:30:00', 'V003', 'U004', '12345', 1),
  ('TS006', 'R002', '11:00:00', 'V003', 'U004', '12345', 1),
  ('TS007', 'R002', '13:00:00', 'V003', 'U003', '12345', 1),
  ('TS008', 'R002', '15:00:00', 'V003', 'U003', '12345', 1),
  -- เส้นทาง 3: เอกสารไม่ได้กำหนดเวลา — จัดจากรถ/คนขับที่ว่าง ไม่ชนรอบเส้นทาง 1–2
  ('TS009', 'R003', '09:30:00', 'V002', 'U003', '12345', 1),
  ('TS010', 'R003', '11:00:00', 'V002', 'U002', '12345', 1),
  ('TS011', 'R003', '13:00:00', 'V001', 'U004', '12345', 1),
  ('TS012', 'R003', '15:00:00', 'V001', 'U004', '12345', 1);


-- =====================================================================
-- 6) Query ตัวอย่างสำหรับหน้าจอ
-- =====================================================================

-- 6.1 Login: ดึงผู้ใช้ + ตำแหน่ง (ตรวจ password ด้วย procedure sp_login)
-- SELECT u.user_id, u.name, u.password_hash, e.position_id
-- FROM users u LEFT JOIN employees e ON e.user_id = u.user_id
-- WHERE u.username = 'somchai';

-- 6.2 เมนูตามสิทธิ์ของผู้ใช้ที่ login
-- SELECT s.screen_id, s.screen_name, p.can_add, p.can_edit, p.can_delete
-- FROM employees e
-- JOIN permissions p ON p.position_id = e.position_id
-- JOIN screens s     ON s.screen_id = p.screen_id
-- WHERE e.user_id = 'U001'
-- ORDER BY s.screen_id;

-- 6.3 ค้นหารอบ / จอง / ยกเลิก
-- CALL sp_search_trips('2026-09-24', 'S002', 'S004');
-- CALL sp_create_booking('U001', 'TR002', 'S002', 'S004', 2, @b, @i, @qr);  SELECT @b, @i, @qr;
-- CALL sp_cancel_booking_item('BD002', 'U002');

-- 6.4 การจองของฉัน (แยกกลุ่ม กำลังจะถึง / เสร็จแล้ว / ยกเลิก)
-- SELECT t.booking_id, t.booking_item_id, t.board_at, t.alight_at, t.seats, t.status, t.checkin_at,
--        sb.stop_name AS board_stop, sa.stop_name AS alight_stop,
--        CASE WHEN t.status = 'ยกเลิก' THEN 'ยกเลิก'
--             WHEN t.checkin_at IS NOT NULL OR t.status = 'No Show' THEN 'เสร็จแล้ว'
--             ELSE 'กำลังจะถึง' END AS tab
-- FROM v_booking_item_times t
-- JOIN stops sb ON sb.stop_id = t.board_stop_id
-- JOIN stops sa ON sa.stop_id = t.alight_stop_id
-- WHERE t.user_id = 'U001'
-- ORDER BY t.board_at DESC;

-- 6.5 คนขับ: งานวันนี้
-- SELECT t.trip_id, t.depart_time, r.route_name, v.plate_no, s.booked_seats, s.seat_count, t.status
-- FROM trips t JOIN routes r ON r.route_id = t.route_id JOIN vehicles v ON v.vehicle_id = t.vehicle_id
-- JOIN v_trip_seats s ON s.trip_id = t.trip_id
-- WHERE t.driver_id = 'U002' AND t.trip_date = CURDATE()
-- ORDER BY t.depart_time;

-- 6.6 คนขับ: ผู้โดยสารขึ้น/ลงตามจุดจอด
-- SELECT ts.stop_order, ts.stop_name, ts.arrive_at,
--        COALESCE(SUM(CASE WHEN bi.board_order  = ts.stop_order THEN bi.seats END), 0) AS boarding,
--        COALESCE(SUM(CASE WHEN bi.alight_order = ts.stop_order THEN bi.seats END), 0) AS alighting,
--        GROUP_CONCAT(CASE WHEN bi.board_order = ts.stop_order THEN CONCAT(bi.passenger_name, ' (', bi.seats, ')') END
--                     SEPARATOR ', ') AS boarding_names
-- FROM v_trip_stop_times ts
-- LEFT JOIN v_booking_item_times bi
--        ON bi.trip_id = ts.trip_id AND bi.status <> 'ยกเลิก'
--       AND (bi.board_order = ts.stop_order OR bi.alight_order = ts.stop_order)
-- WHERE ts.trip_id = 'TR001'
-- GROUP BY ts.stop_order, ts.stop_name, ts.arrive_at
-- ORDER BY ts.stop_order;

-- 6.7 คนขับ: เริ่มงาน / สแกน / ปิดงาน
-- CALL sp_start_trip('TR002', 'U002');
-- CALL sp_checkin('QR002', 'TR002');
-- CALL sp_close_trip('TR002');


-- =====================================================================
-- 7) รายงาน 1–7
-- =====================================================================

-- รายงาน 1: เปรียบเทียบจำนวนคนขึ้นรถและลงรถรายปี (นับเฉพาะที่ Check-in)
-- SET @year = 2026;
-- SELECT s.stop_id, s.stop_name,
--        COALESCE(SUM(CASE WHEN bi.board_stop_id  = s.stop_id THEN bi.seats END), 0) AS boarded,
--        COALESCE(SUM(CASE WHEN bi.alight_stop_id = s.stop_id THEN bi.seats END), 0) AS alighted
-- FROM stops s
-- LEFT JOIN (booking_items bi JOIN trips t ON t.trip_id = bi.trip_id)
--        ON (bi.board_stop_id = s.stop_id OR bi.alight_stop_id = s.stop_id)
--       AND bi.checkin_at IS NOT NULL AND YEAR(t.trip_date) = @year
-- GROUP BY s.stop_id, s.stop_name
-- ORDER BY s.stop_id;

-- รายงาน 2: สถิติการจองรายปี (แยกเดือน)
-- SET @year = 2026;
-- SELECT MONTH(t.trip_date)                                   AS month_no,
--        COUNT(DISTINCT bi.booking_id)                        AS bookings,
--        COUNT(*)                                             AS booking_items,
--        SUM(CASE WHEN bi.status <> 'ยกเลิก' THEN bi.seats ELSE 0 END) AS booked_seats,
--        SUM(bi.status = 'ยกเลิก')                            AS cancelled,
--        SUM(bi.checkin_at IS NOT NULL)                       AS checked_in,
--        SUM(bi.status = 'No Show')                           AS no_show
-- FROM booking_items bi JOIN trips t ON t.trip_id = bi.trip_id
-- WHERE YEAR(t.trip_date) = @year
-- GROUP BY MONTH(t.trip_date) WITH ROLLUP;

-- รายงาน 3: พฤติกรรมผู้ใช้ตามช่วงวันที่
-- SET @from = '2026-09-01', @to = '2026-09-30';
-- SELECT u.user_id, u.name,
--        COUNT(*)                       AS total_items,
--        SUM(bi.checkin_at IS NOT NULL) AS boarded,
--        SUM(bi.status = 'ยกเลิก')      AS cancelled,
--        SUM(bi.status = 'No Show')     AS no_show
-- FROM booking_items bi
-- JOIN bookings b ON b.booking_id = bi.booking_id
-- JOIN users u    ON u.user_id = b.user_id
-- JOIN trips t    ON t.trip_id = bi.trip_id
-- WHERE t.trip_date BETWEEN @from AND @to
-- GROUP BY u.user_id, u.name WITH ROLLUP;

-- รายงาน 4: สรุปยอดผู้ใช้แต่ละเส้นทางรายวัน (รวมวันเดียวกันในสัปดาห์)
-- SET @from = '2026-09-01', @to = '2026-09-30';
-- SELECT DAYOFWEEK(t.trip_date) AS dow_no,
--        ELT(DAYOFWEEK(t.trip_date), 'อาทิตย์','จันทร์','อังคาร','พุธ','พฤหัสบดี','ศุกร์','เสาร์') AS day_name,
--        r.route_name,
--        SUM(bi.seats) AS passengers
-- FROM booking_items bi
-- JOIN trips t  ON t.trip_id = bi.trip_id
-- JOIN routes r ON r.route_id = t.route_id
-- WHERE bi.checkin_at IS NOT NULL AND t.trip_date BETWEEN @from AND @to
-- GROUP BY dow_no, day_name, r.route_name
-- ORDER BY dow_no, r.route_name;

-- รายงาน 5: การใช้บริการแต่ละจุดจอดตามรอบเวลา (เรียงจุดจอด แล้วตามเวลา)
-- SET @from = '2026-09-01', @to = '2026-09-30';
-- SELECT ts.stop_name, TIME(ts.arrive_at) AS pass_time,
--        COALESCE(SUM(CASE WHEN bi.board_order  = ts.stop_order THEN bi.seats END), 0) AS boarding,
--        COALESCE(SUM(CASE WHEN bi.alight_order = ts.stop_order THEN bi.seats END), 0) AS alighting
-- FROM v_trip_stop_times ts
-- LEFT JOIN v_booking_item_segments bi
--        ON bi.trip_id = ts.trip_id AND bi.checkin_at IS NOT NULL
--       AND (bi.board_order = ts.stop_order OR bi.alight_order = ts.stop_order)
-- WHERE ts.trip_date BETWEEN @from AND @to
-- GROUP BY ts.stop_name, TIME(ts.arrive_at)
-- ORDER BY ts.stop_name, pass_time;

-- รายงาน 6: สรุปการมอบหมายงานคนขับ ก่อน/หลัง 17:00
-- SET @from = '2026-09-01', @to = '2026-09-30';
-- SELECT u.user_id, u.name,
--        COUNT(*)                            AS total_trips,
--        SUM(t.depart_time <  '17:00:00')    AS before_1700,
--        SUM(t.depart_time >= '17:00:00')    AS after_1700
-- FROM trips t JOIN users u ON u.user_id = t.driver_id
-- WHERE t.trip_date BETWEEN @from AND @to AND t.status <> 'ยกเลิก'
-- GROUP BY u.user_id, u.name
-- ORDER BY total_trips DESC;

-- รายงาน 7: จำนวนการมอบหมายงานให้รถแต่ละประเภท (ประเภทรถ → ทะเบียน → จำนวนรอบ)
-- SET @from = '2026-09-01', @to = '2026-09-30';
-- SELECT vt.type_name, v.plate_no, COUNT(t.trip_id) AS trips
-- FROM vehicle_types vt
-- JOIN vehicles v   ON v.vehicle_type_id = vt.vehicle_type_id
-- LEFT JOIN trips t ON t.vehicle_id = v.vehicle_id
--                  AND t.trip_date BETWEEN @from AND @to AND t.status <> 'ยกเลิก'
-- GROUP BY vt.type_name, v.plate_no WITH ROLLUP;
