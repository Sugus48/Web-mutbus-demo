-- =====================================================================
--  MUT Shuttle Bus System — Database Schema สำหรับ Oracle 19c
--  แปลงจาก mut_shuttle.sql (MySQL) — ตาราง/กฎทางธุรกิจ/ข้อมูลตัวอย่างเหมือนกัน
--
--  วิธีใช้:  SQL Developer → เปิดไฟล์นี้ → Run Script (F5)
--           หรือ  npm run db:init  (เมื่อ DB_CLIENT=oracle ใน .env)
--
--  ความต่างจากฉบับ MySQL
--  - ENUM → VARCHAR2 + CHECK, TIME → VARCHAR2(8) 'HH24:MI:SS', DATETIME → DATE
--  - ไม่มี VIEW (บัญชีไม่มีสิทธิ์ CREATE VIEW) — procedure ใช้ subquery/ฟังก์ชันแทน view
--  - trigger ตรวจชนเวลา/ที่นั่งใช้ COMPOUND TRIGGER (เลี่ยง mutating table)
--  - procedure ที่คืนผลลัพธ์ใช้ OUT SYS_REFCURSOR
--  - ส่วนที่ 0 ลบเฉพาะ object ของระบบนี้ (ตามชื่อ) ไม่แตะตารางอื่นในบัญชี
-- =====================================================================

-- =====================================================================
-- 0) ลบ object เดิมของระบบนี้ (ถ้ามี)
-- =====================================================================
BEGIN
  FOR t IN (SELECT table_name FROM user_tables WHERE table_name IN (
      'BOOKING_ITEMS', 'BOOKINGS', 'TRIPS', 'TRIP_SCHEDULES', 'ROUTE_STOPS', 'STOPS', 'ROUTES', 'VEHICLES',
      'VEHICLE_TYPES', 'PERMISSIONS', 'EMPLOYEES', 'USERS', 'SCREENS', 'POSITIONS', 'DEPARTMENTS')) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
  END LOOP;
  FOR o IN (SELECT object_name, object_type FROM user_objects
             WHERE object_type IN ('FUNCTION', 'PROCEDURE') AND object_name IN (
               'MUT_TS', 'MUT_ROUTE_MINUTES', 'MUT_SEGMENT_REMAINING', 'SP_SEARCH_TRIPS', 'SP_CREATE_BOOKING', 'SP_CANCEL_BOOKING_ITEM',
               'SP_START_TRIP', 'SP_CHECKIN', 'SP_CLOSE_TRIP')) LOOP
    EXECUTE IMMEDIATE 'DROP ' || o.object_type || ' ' || o.object_name;
  END LOOP;
END;
/

-- =====================================================================
-- 1) ตาราง (Tables)
-- =====================================================================

-- 1. แผนก
CREATE TABLE departments (
  department_id   VARCHAR2(10 CHAR)  NOT NULL,
  department_name VARCHAR2(100 CHAR) NOT NULL,
  CONSTRAINT pk_departments PRIMARY KEY (department_id)
);

-- 4. ตำแหน่ง
CREATE TABLE positions (
  position_id   VARCHAR2(10 CHAR)  NOT NULL,
  position_name VARCHAR2(100 CHAR) NOT NULL,
  department_id VARCHAR2(10 CHAR),                      -- แผนกของตำแหน่ง — NULL = ใช้ได้ทุกแผนก
  CONSTRAINT pk_positions PRIMARY KEY (position_id),
  CONSTRAINT fk_positions_department FOREIGN KEY (department_id) REFERENCES departments (department_id)
);

-- 6. หน้าจอ
CREATE TABLE screens (
  screen_id   VARCHAR2(10 CHAR)  NOT NULL,
  screen_name VARCHAR2(100 CHAR) NOT NULL,
  CONSTRAINT pk_screens PRIMARY KEY (screen_id)
);

-- 2. ผู้ใช้งาน
CREATE TABLE users (
  user_id       VARCHAR2(10 CHAR)  NOT NULL,
  name          VARCHAR2(100 CHAR) NOT NULL,
  email         VARCHAR2(150 CHAR) NOT NULL,
  username      VARCHAR2(50 CHAR)  NOT NULL,
  password_hash VARCHAR2(255 CHAR) NOT NULL,
  department_id VARCHAR2(10 CHAR)  NOT NULL,
  CONSTRAINT pk_users PRIMARY KEY (user_id),
  CONSTRAINT uq_users_email UNIQUE (email),
  CONSTRAINT uq_users_username UNIQUE (username),
  CONSTRAINT fk_users_department FOREIGN KEY (department_id) REFERENCES departments (department_id)
);

-- 3 + 5. พนักงาน (Subclass ของ ผู้ใช้งาน) + ตำแหน่ง
CREATE TABLE employees (
  user_id     VARCHAR2(10 CHAR) NOT NULL,
  phone       VARCHAR2(20 CHAR) NOT NULL,
  position_id VARCHAR2(10 CHAR) NOT NULL,
  CONSTRAINT pk_employees PRIMARY KEY (user_id),
  CONSTRAINT fk_employees_user     FOREIGN KEY (user_id)     REFERENCES users (user_id) ON DELETE CASCADE,
  CONSTRAINT fk_employees_position FOREIGN KEY (position_id) REFERENCES positions (position_id)
);

-- 7. สิทธิ์ (มีแถว = เข้าถึงหน้าจอได้)
CREATE TABLE permissions (
  permission_id VARCHAR2(10 CHAR) NOT NULL,
  can_add       NUMBER(1) DEFAULT 0 NOT NULL,
  can_edit      NUMBER(1) DEFAULT 0 NOT NULL,
  can_delete    NUMBER(1) DEFAULT 0 NOT NULL,
  position_id   VARCHAR2(10 CHAR) NOT NULL,
  screen_id     VARCHAR2(10 CHAR) NOT NULL,
  CONSTRAINT pk_permissions PRIMARY KEY (permission_id),
  CONSTRAINT uq_perm_position_screen UNIQUE (position_id, screen_id),
  CONSTRAINT fk_perm_position FOREIGN KEY (position_id) REFERENCES positions (position_id) ON DELETE CASCADE,
  CONSTRAINT fk_perm_screen   FOREIGN KEY (screen_id)   REFERENCES screens (screen_id) ON DELETE CASCADE,
  CONSTRAINT ck_perm_flags CHECK (can_add IN (0, 1) AND can_edit IN (0, 1) AND can_delete IN (0, 1))
);

-- 8. ประเภทรถ
CREATE TABLE vehicle_types (
  vehicle_type_id VARCHAR2(10 CHAR)  NOT NULL,
  type_name       VARCHAR2(50 CHAR)  NOT NULL,
  description     VARCHAR2(255 CHAR),
  seat_count      NUMBER(4)          NOT NULL,
  CONSTRAINT pk_vehicle_types PRIMARY KEY (vehicle_type_id),
  CONSTRAINT ck_vtype_seats CHECK (seat_count > 0)
);

-- 9. รถ
CREATE TABLE vehicles (
  vehicle_id      VARCHAR2(10 CHAR) NOT NULL,
  plate_no        VARCHAR2(20 CHAR) NOT NULL,
  status          VARCHAR2(20 CHAR) DEFAULT 'พร้อมใช้งาน' NOT NULL,
  vehicle_type_id VARCHAR2(10 CHAR) NOT NULL,
  CONSTRAINT pk_vehicles PRIMARY KEY (vehicle_id),
  CONSTRAINT uq_vehicles_plate UNIQUE (plate_no),
  CONSTRAINT fk_vehicles_type FOREIGN KEY (vehicle_type_id) REFERENCES vehicle_types (vehicle_type_id),
  CONSTRAINT ck_vehicles_status CHECK (status IN ('พร้อมใช้งาน', 'ซ่อมบำรุง', 'ไม่พร้อมใช้งาน'))
);

-- 10. เส้นทาง (เวลารวม = Derived)
CREATE TABLE routes (
  route_id   VARCHAR2(10 CHAR)  NOT NULL,
  route_name VARCHAR2(100 CHAR) NOT NULL,
  CONSTRAINT pk_routes PRIMARY KEY (route_id)
);

-- 12. จุดจอด
CREATE TABLE stops (
  stop_id   VARCHAR2(10 CHAR)  NOT NULL,
  stop_name VARCHAR2(150 CHAR) NOT NULL,
  CONSTRAINT pk_stops PRIMARY KEY (stop_id)
);

-- 13. เส้นทาง_จุดจอด — PK = (รหัสเส้นทาง, ลำดับจุดจอด) เพราะผ่านจุดจอดเดิมซ้ำได้
CREATE TABLE route_stops (
  route_id       VARCHAR2(10 CHAR) NOT NULL,
  stop_order     NUMBER(4)         NOT NULL,
  stop_id        VARCHAR2(10 CHAR) NOT NULL,
  travel_minutes NUMBER(4) DEFAULT 0 NOT NULL,
  CONSTRAINT pk_route_stops PRIMARY KEY (route_id, stop_order),
  CONSTRAINT fk_rs_route FOREIGN KEY (route_id) REFERENCES routes (route_id) ON DELETE CASCADE,
  CONSTRAINT fk_rs_stop  FOREIGN KEY (stop_id)  REFERENCES stops (stop_id),
  CONSTRAINT ck_rs_order   CHECK (stop_order >= 1),
  CONSTRAINT ck_rs_minutes CHECK (travel_minutes >= 0)
);
CREATE INDEX ix_route_stops_stop ON route_stops (stop_id);

-- 16. ตารางเวลาเดินรถประจำ — ระบบสร้างรอบการเดินรถของแต่ละวันล่วงหน้าจากตารางนี้ (procedure sp_ensure_trips ใน api_procedures_oracle.sql)
--     "รอบที่" = ลำดับเวลาออกภายในเส้นทาง (ไม่ได้เก็บ)
CREATE TABLE trip_schedules (
  schedule_id VARCHAR2(10 CHAR) NOT NULL,
  route_id    VARCHAR2(10 CHAR) NOT NULL,
  depart_time VARCHAR2(8 CHAR)  NOT NULL,              -- 'HH24:MI:SS'
  vehicle_id  VARCHAR2(10 CHAR) NOT NULL,
  driver_id   VARCHAR2(10 CHAR) NOT NULL,
  run_days    VARCHAR2(7 CHAR) DEFAULT '12345' NOT NULL, -- วันที่วิ่ง 0=อาทิตย์ … 6=เสาร์ ('12345' = จันทร์–ศุกร์)
  active      NUMBER(1) DEFAULT 1 NOT NULL,            -- 1 = ใช้งาน / 0 = หยุดใช้งาน
  CONSTRAINT pk_trip_schedules PRIMARY KEY (schedule_id),
  CONSTRAINT uq_sched_route_time UNIQUE (route_id, depart_time),
  CONSTRAINT fk_sched_route   FOREIGN KEY (route_id)   REFERENCES routes (route_id) ON DELETE CASCADE,
  CONSTRAINT fk_sched_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicles (vehicle_id),
  CONSTRAINT fk_sched_driver  FOREIGN KEY (driver_id)  REFERENCES employees (user_id),
  CONSTRAINT ck_sched_days CHECK (REGEXP_LIKE(run_days, '^[0-6]+$')),
  CONSTRAINT ck_sched_active CHECK (active IN (0, 1)),
  CONSTRAINT ck_sched_time CHECK (REGEXP_LIKE(depart_time, '^([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$'))
);

-- 11. รอบการเดินรถ
CREATE TABLE trips (
  trip_id     VARCHAR2(10 CHAR) NOT NULL,
  trip_date   DATE              NOT NULL,
  depart_time VARCHAR2(8 CHAR)  NOT NULL,              -- 'HH24:MI:SS'
  status      VARCHAR2(20 CHAR) DEFAULT 'เปิด' NOT NULL,
  seat_count  NUMBER(4) DEFAULT 0 NOT NULL,           -- Derived: trigger ดึงจากประเภทรถ
  vehicle_id  VARCHAR2(10 CHAR) NOT NULL,
  route_id    VARCHAR2(10 CHAR) NOT NULL,
  driver_id   VARCHAR2(10 CHAR) NOT NULL,              -- คนขับ = รหัสผู้ใช้งานของพนักงาน
  schedule_id VARCHAR2(10 CHAR),                       -- สร้างจากตารางเวลาใด (NULL = จัดรอบเอง)
  CONSTRAINT pk_trips PRIMARY KEY (trip_id),
  CONSTRAINT fk_trips_vehicle  FOREIGN KEY (vehicle_id)  REFERENCES vehicles (vehicle_id),
  CONSTRAINT fk_trips_route    FOREIGN KEY (route_id)    REFERENCES routes (route_id),
  CONSTRAINT fk_trips_driver   FOREIGN KEY (driver_id)   REFERENCES employees (user_id),
  CONSTRAINT fk_trips_schedule FOREIGN KEY (schedule_id) REFERENCES trip_schedules (schedule_id) ON DELETE SET NULL,
  CONSTRAINT ck_trips_status CHECK (status IN ('เปิด', 'กำลังเดินทาง', 'เสร็จสิ้น', 'ยกเลิก')),
  CONSTRAINT ck_trips_time CHECK (REGEXP_LIKE(depart_time, '^([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$')),
  CONSTRAINT ck_trips_date CHECK (trip_date = TRUNC(trip_date))
);
CREATE INDEX ix_trips_date ON trips (trip_date, depart_time);
CREATE INDEX ix_trips_schedule ON trips (schedule_id, trip_date);

-- 14. การจอง
CREATE TABLE bookings (
  booking_id VARCHAR2(10 CHAR) NOT NULL,
  booked_at  DATE DEFAULT SYSDATE NOT NULL,
  user_id    VARCHAR2(10 CHAR) NOT NULL,
  CONSTRAINT pk_bookings PRIMARY KEY (booking_id),
  CONSTRAINT fk_bookings_user FOREIGN KEY (user_id) REFERENCES users (user_id)
);

-- 15. รายการจอง
CREATE TABLE booking_items (
  booking_item_id VARCHAR2(10 CHAR) NOT NULL,
  qr_code         VARCHAR2(64 CHAR) NOT NULL,
  status          VARCHAR2(20 CHAR) DEFAULT 'ยืนยัน' NOT NULL,
  seats           NUMBER(2)         NOT NULL,
  checkin_at      DATE,
  booking_id      VARCHAR2(10 CHAR) NOT NULL,
  trip_id         VARCHAR2(10 CHAR) NOT NULL,
  board_stop_id   VARCHAR2(10 CHAR) NOT NULL,
  alight_stop_id  VARCHAR2(10 CHAR) NOT NULL,
  CONSTRAINT pk_booking_items PRIMARY KEY (booking_item_id),
  CONSTRAINT uq_items_qr UNIQUE (qr_code),
  CONSTRAINT fk_items_booking FOREIGN KEY (booking_id)     REFERENCES bookings (booking_id) ON DELETE CASCADE,
  CONSTRAINT fk_items_trip    FOREIGN KEY (trip_id)        REFERENCES trips (trip_id),
  CONSTRAINT fk_items_board   FOREIGN KEY (board_stop_id)  REFERENCES stops (stop_id),
  CONSTRAINT fk_items_alight  FOREIGN KEY (alight_stop_id) REFERENCES stops (stop_id),
  CONSTRAINT ck_items_status CHECK (status IN ('ยืนยัน', 'ยกเลิก', 'No Show')),
  CONSTRAINT ck_items_seats CHECK (seats BETWEEN 1 AND 4),
  CONSTRAINT ck_items_stops CHECK (board_stop_id <> alight_stop_id)
);
CREATE INDEX ix_items_trip ON booking_items (trip_id, status);

COMMENT ON TABLE departments   IS 'แผนก';
COMMENT ON TABLE positions     IS 'ตำแหน่ง';
COMMENT ON TABLE screens       IS 'หน้าจอ';
COMMENT ON TABLE users         IS 'ผู้ใช้งาน (Superclass)';
COMMENT ON TABLE employees     IS 'พนักงาน';
COMMENT ON TABLE permissions   IS 'สิทธิ์';
COMMENT ON TABLE vehicle_types IS 'ประเภทรถ';
COMMENT ON TABLE vehicles      IS 'รถ';
COMMENT ON TABLE routes        IS 'เส้นทาง';
COMMENT ON TABLE stops         IS 'จุดจอด';
COMMENT ON TABLE route_stops   IS 'เส้นทาง_จุดจอด';
COMMENT ON TABLE trip_schedules IS 'ตารางเวลาเดินรถประจำ';
COMMENT ON TABLE trips         IS 'รอบการเดินรถ';
COMMENT ON TABLE bookings      IS 'การจอง';
COMMENT ON TABLE booking_items IS 'รายการจอง';


-- =====================================================================
-- 2) ฟังก์ชันช่วย (ค่าที่คำนวณได้)
-- =====================================================================

-- วันที่ + เวลา 'HH24:MI:SS' → DATE (เทียบ TIMESTAMP(date, time) ของ MySQL)
CREATE OR REPLACE FUNCTION mut_ts(p_date IN DATE, p_time IN VARCHAR2) RETURN DATE DETERMINISTIC IS
BEGIN
  RETURN TRUNC(p_date)
       + (TO_NUMBER(SUBSTR(p_time, 1, 2)) * 3600
          + TO_NUMBER(SUBSTR(p_time, 4, 2)) * 60
          + NVL(TO_NUMBER(SUBSTR(p_time, 7, 2)), 0)) / 86400;
END;
/

-- เวลารวมของเส้นทาง (นาที) = Σ เวลาเดินทางจากจุดก่อนหน้า
CREATE OR REPLACE FUNCTION mut_route_minutes(p_route IN VARCHAR2) RETURN NUMBER IS
  v NUMBER;
BEGIN
  SELECT NVL(SUM(travel_minutes), 0) INTO v FROM route_stops WHERE route_id = p_route;
  RETURN v;
END;
/

-- ที่นั่งว่างในช่วงจุดขึ้น → จุดลงของรอบ = ความจุ − จำนวนคนบนรถสูงสุดในช่วงนั้น
-- ผู้โดยสารครองที่นั่งตั้งแต่จุดขึ้นถึงก่อนจุดลง — ลงแล้วที่นั่งว่างให้คนที่ขึ้นหลังจากนั้นจองต่อได้
-- p_exclude = รายการจองที่ไม่นับ หรือ NULL
CREATE OR REPLACE FUNCTION mut_segment_remaining(
  p_trip IN VARCHAR2, p_board IN VARCHAR2, p_alight IN VARCHAR2, p_exclude IN VARCHAR2) RETURN NUMBER IS
  v_route trips.route_id%TYPE;
  v_seats NUMBER;
  v_from  NUMBER;
  v_to    NUMBER;
  v_max   NUMBER;
BEGIN
  SELECT route_id, seat_count INTO v_route, v_seats FROM trips WHERE trip_id = p_trip;
  SELECT MIN(stop_order) INTO v_from FROM route_stops WHERE route_id = v_route AND stop_id = p_board;
  SELECT MIN(stop_order) INTO v_to FROM route_stops
   WHERE route_id = v_route AND stop_id = p_alight AND stop_order > v_from;
  IF v_from IS NULL OR v_to IS NULL THEN
    RETURN 0;
  END IF;

  -- จำนวนคนบนรถในแต่ละช่วง (ลำดับ k → k+1) ที่อยู่ในช่วงที่จอง แล้วเอาช่วงที่แน่นที่สุด
  SELECT NVL(MAX(occ), 0) INTO v_max
    FROM (SELECT rs.stop_order, SUM(sg.seats) AS occ
            FROM route_stops rs
            JOIN (SELECT bi.seats,
                         (SELECT MIN(a.stop_order) FROM route_stops a
                           WHERE a.route_id = v_route AND a.stop_id = bi.board_stop_id) AS board_order,
                         (SELECT MIN(b.stop_order) FROM route_stops b
                           WHERE b.route_id = v_route AND b.stop_id = bi.alight_stop_id
                             AND b.stop_order > (SELECT MIN(a2.stop_order) FROM route_stops a2
                                                  WHERE a2.route_id = v_route AND a2.stop_id = bi.board_stop_id)) AS alight_order
                    FROM booking_items bi
                   WHERE bi.trip_id = p_trip AND bi.status <> 'ยกเลิก'
                     AND (p_exclude IS NULL OR bi.booking_item_id <> p_exclude)) sg
              ON sg.board_order <= rs.stop_order AND sg.alight_order > rs.stop_order
           WHERE rs.route_id = v_route AND rs.stop_order >= v_from AND rs.stop_order < v_to
           GROUP BY rs.stop_order);
  RETURN v_seats - v_max;
EXCEPTION
  WHEN NO_DATA_FOUND THEN RETURN 0;
END;
/


-- =====================================================================
-- 3) Triggers — บังคับกฎทางธุรกิจที่ระดับฐานข้อมูล
-- =====================================================================

-- ผู้ใช้งาน: พิมพ์รหัสผ่านตรงๆ ได้ (เช่นกรอกใน SQL Developer) — แปลงเป็น SHA-256 hex ให้
-- ค่าที่เป็น bcrypt ($2…) หรือ SHA-256 hex อยู่แล้วจะไม่ถูกแตะ
CREATE OR REPLACE TRIGGER trg_users_password
BEFORE INSERT OR UPDATE OF password_hash ON users
FOR EACH ROW
BEGIN
  IF :NEW.password_hash NOT LIKE '$2%' AND NOT REGEXP_LIKE(:NEW.password_hash, '^[0-9a-fA-F]{64}$') THEN
    SELECT LOWER(RAWTOHEX(STANDARD_HASH(:NEW.password_hash, 'SHA256'))) INTO :NEW.password_hash FROM dual;
  END IF;
END;
/

-- รอบการเดินรถ: ดึงจำนวนที่นั่งจากประเภทรถ + รถต้องพร้อมใช้งาน
CREATE OR REPLACE TRIGGER trg_trips_bi
BEFORE INSERT OR UPDATE OF vehicle_id ON trips
FOR EACH ROW
DECLARE
  v_status vehicles.status%TYPE;
BEGIN
  SELECT vt.seat_count, v.status INTO :NEW.seat_count, v_status
    FROM vehicles v JOIN vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id
   WHERE v.vehicle_id = :NEW.vehicle_id;
  IF INSERTING AND :NEW.status <> 'ยกเลิก' AND v_status <> 'พร้อมใช้งาน' THEN
    RAISE_APPLICATION_ERROR(-20001, 'รถคันนี้ไม่อยู่ในสถานะพร้อมใช้งาน');
  END IF;
END;
/

-- รอบการเดินรถ: ตรวจรถ/คนขับชนเวลา (ตรวจหลังจบคำสั่งเพื่อเลี่ยง mutating table)
CREATE OR REPLACE TRIGGER trg_trips_conflict
FOR INSERT OR UPDATE ON trips
COMPOUND TRIGGER
  TYPE t_ids IS TABLE OF VARCHAR2(10);
  g_ids t_ids := t_ids();

  AFTER EACH ROW IS
  BEGIN
    IF :NEW.status <> 'ยกเลิก' AND (INSERTING
        OR :NEW.trip_date <> :OLD.trip_date OR :NEW.depart_time <> :OLD.depart_time
        OR :NEW.vehicle_id <> :OLD.vehicle_id OR :NEW.driver_id <> :OLD.driver_id
        OR :NEW.route_id <> :OLD.route_id OR :OLD.status = 'ยกเลิก') THEN
      g_ids.EXTEND;
      g_ids(g_ids.COUNT) := :NEW.trip_id;
    END IF;
  END AFTER EACH ROW;

  AFTER STATEMENT IS
    v_conflict VARCHAR2(10);
    v_kind     VARCHAR2(10);
  BEGIN
    FOR i IN 1 .. g_ids.COUNT LOOP
      v_conflict := NULL;
      FOR c IN (
        SELECT o.trip_id, CASE WHEN o.vehicle_id = n.vehicle_id THEN 'vehicle' ELSE 'driver' END AS kind
          FROM trips n JOIN trips o
            ON o.trip_id <> n.trip_id AND o.trip_date = n.trip_date AND o.status <> 'ยกเลิก'
           AND (o.vehicle_id = n.vehicle_id OR o.driver_id = n.driver_id)
         WHERE n.trip_id = g_ids(i)
           AND mut_ts(o.trip_date, o.depart_time) < mut_ts(n.trip_date, n.depart_time) + mut_route_minutes(n.route_id) / 1440
           AND mut_ts(n.trip_date, n.depart_time) < mut_ts(o.trip_date, o.depart_time) + mut_route_minutes(o.route_id) / 1440
         ORDER BY 2 DESC
         FETCH FIRST 1 ROWS ONLY) LOOP
        v_conflict := c.trip_id;
        v_kind := c.kind;
      END LOOP;
      IF v_conflict IS NOT NULL THEN
        g_ids.DELETE;
        IF v_kind = 'vehicle' THEN
          RAISE_APPLICATION_ERROR(-20001, 'ไม่สามารถจัดรอบนี้ได้ เนื่องจากรถถูกมอบหมายในรอบ ' || v_conflict || ' ช่วงเวลาเดียวกัน');
        ELSE
          RAISE_APPLICATION_ERROR(-20001, 'ไม่สามารถจัดรอบนี้ได้ เนื่องจากคนขับมีงานรอบ ' || v_conflict || ' ในช่วงเวลาเดียวกัน');
        END IF;
      END IF;
    END LOOP;
    g_ids.DELETE;
  END AFTER STATEMENT;
END trg_trips_conflict;
/

-- รายการจอง: จุดขึ้นต้องอยู่ก่อนจุดลงในเส้นทางของรอบ
CREATE OR REPLACE TRIGGER trg_items_bi
BEFORE INSERT ON booking_items
FOR EACH ROW
DECLARE
  v_ok NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_ok
    FROM trips t
    JOIN route_stops a ON a.route_id = t.route_id AND a.stop_id = :NEW.board_stop_id
    JOIN route_stops b ON b.route_id = t.route_id AND b.stop_id = :NEW.alight_stop_id AND b.stop_order > a.stop_order
   WHERE t.trip_id = :NEW.trip_id;
  IF v_ok = 0 THEN
    RAISE_APPLICATION_ERROR(-20001, 'จุดขึ้น/จุดลงไม่อยู่ในเส้นทางของรอบนี้ หรือจุดลงอยู่ก่อนจุดขึ้น');
  END IF;
END;
/

-- รายการจอง: ที่นั่งต้องพอเฉพาะช่วงจุดขึ้น → จุดลงที่จอง (ตรวจหลังจบคำสั่งเพื่อเลี่ยง mutating table)
CREATE OR REPLACE TRIGGER trg_items_seats
FOR INSERT OR UPDATE ON booking_items
COMPOUND TRIGGER
  TYPE t_ids IS TABLE OF VARCHAR2(10);
  g_ids t_ids := t_ids();

  AFTER EACH ROW IS
  BEGIN
    IF :NEW.status <> 'ยกเลิก' AND (INSERTING OR :OLD.status = 'ยกเลิก'
        OR :NEW.seats > :OLD.seats OR :NEW.trip_id <> :OLD.trip_id
        OR :NEW.board_stop_id <> :OLD.board_stop_id OR :NEW.alight_stop_id <> :OLD.alight_stop_id) THEN
      g_ids.EXTEND;
      g_ids(g_ids.COUNT) := :NEW.booking_item_id;
    END IF;
  END AFTER EACH ROW;

  AFTER STATEMENT IS
    v_over NUMBER;
  BEGIN
    -- แถวใหม่อยู่ในตารางแล้ว: ช่วงที่จองต้องไม่เกินความจุ (ที่นั่งว่างต้องไม่ติดลบ)
    FOR i IN 1 .. g_ids.COUNT LOOP
      SELECT COUNT(*) INTO v_over
        FROM booking_items bi
       WHERE bi.booking_item_id = g_ids(i)
         AND mut_segment_remaining(bi.trip_id, bi.board_stop_id, bi.alight_stop_id, NULL) < 0;
      IF v_over > 0 THEN
        g_ids.DELETE;
        RAISE_APPLICATION_ERROR(-20001, 'ที่นั่งว่างไม่พอในช่วงจุดขึ้น–จุดลงนี้');
      END IF;
    END LOOP;
    g_ids.DELETE;
  END AFTER STATEMENT;
END trg_items_seats;
/


-- =====================================================================
-- 4) Stored Procedures — ใช้จากแอปพลิเคชัน
-- =====================================================================

-- ค้นหารอบที่จองได้ (ซ่อนรอบที่รถจะถึงจุดขึ้นในอีกไม่ถึง 20 นาที)
-- ที่นั่งคงเหลือ = ที่นั่งว่างเฉพาะช่วงจุดขึ้น → จุดลงที่ค้นหา
CREATE OR REPLACE PROCEDURE sp_search_trips(
  p_date IN DATE, p_board IN VARCHAR2, p_alight IN VARCHAR2, p_rc OUT SYS_REFCURSOR) IS
BEGIN
  OPEN p_rc FOR
    WITH st AS (
      SELECT rs.route_id, rs.stop_order, rs.stop_id,
             SUM(rs.travel_minutes) OVER (PARTITION BY rs.route_id ORDER BY rs.stop_order
                                          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_minutes
        FROM route_stops rs
    )
    SELECT t.trip_id, t.trip_date, t.depart_time, r.route_name,
           vt.type_name || ' ' || v.plate_no AS vehicle,
           mut_ts(t.trip_date, t.depart_time) + b.cum_minutes / 1440 AS board_at,
           mut_ts(t.trip_date, t.depart_time) + a.cum_minutes / 1440 AS alight_at,
           t.seat_count,
           mut_segment_remaining(t.trip_id, p_board, p_alight, NULL)           AS remaining_seats,
           LEAST(4, mut_segment_remaining(t.trip_id, p_board, p_alight, NULL)) AS max_selectable
      FROM trips t
      JOIN routes r         ON r.route_id = t.route_id
      JOIN vehicles v       ON v.vehicle_id = t.vehicle_id
      JOIN vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id
      JOIN st b             ON b.route_id = t.route_id AND b.stop_id = p_board
      JOIN st a             ON a.route_id = t.route_id AND a.stop_id = p_alight
     WHERE t.trip_date = TRUNC(p_date)
       AND t.status = 'เปิด'
       AND b.stop_order = (SELECT MIN(x.stop_order) FROM route_stops x WHERE x.route_id = t.route_id AND x.stop_id = p_board)
       AND a.stop_order = (SELECT MIN(y.stop_order) FROM route_stops y
                            WHERE y.route_id = t.route_id AND y.stop_id = p_alight AND y.stop_order > b.stop_order)
       AND mut_ts(t.trip_date, t.depart_time) + b.cum_minutes / 1440 >= SYSDATE + 20 / 1440
     ORDER BY t.depart_time;
END;
/

-- สร้างการจอง 1 รายการ (การจอง + รายการจอง + QR Code)
-- ถ้าเกิด error ทุกอย่างในการเรียกครั้งนั้นถูก rollback อัตโนมัติ
CREATE OR REPLACE PROCEDURE sp_create_booking(
  p_user IN VARCHAR2, p_trip IN VARCHAR2, p_board IN VARCHAR2, p_alight IN VARCHAR2, p_seats IN NUMBER,
  p_booking_id OUT VARCHAR2, p_item_id OUT VARCHAR2, p_qr OUT VARCHAR2) IS
  v_status   trips.status%TYPE;
  v_board_at DATE;
  v_n        NUMBER;
BEGIN
  IF p_seats < 1 OR p_seats > 4 THEN
    RAISE_APPLICATION_ERROR(-20001, 'จองได้ 1–4 ที่นั่งต่อรายการ');
  END IF;

  BEGIN
    SELECT status INTO v_status FROM trips WHERE trip_id = p_trip FOR UPDATE;   -- ล็อกรอบกันจองชนกัน
  EXCEPTION WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20001, 'ไม่พบรอบการเดินรถ');
  END;
  IF v_status <> 'เปิด' THEN
    RAISE_APPLICATION_ERROR(-20001, 'รอบนี้ไม่เปิดให้จอง');
  END IF;

  SELECT MIN(mut_ts(t.trip_date, t.depart_time)
             + (SELECT SUM(x.travel_minutes) FROM route_stops x
                 WHERE x.route_id = rs.route_id AND x.stop_order <= rs.stop_order) / 1440)
    INTO v_board_at
    FROM trips t JOIN route_stops rs ON rs.route_id = t.route_id
   WHERE t.trip_id = p_trip AND rs.stop_id = p_board;
  IF v_board_at IS NULL OR v_board_at < SYSDATE + 20 / 1440 THEN
    RAISE_APPLICATION_ERROR(-20001, 'ต้องจองก่อนรถถึงจุดขึ้นอย่างน้อย 20 นาที');
  END IF;

  SELECT NVL(MAX(TO_NUMBER(SUBSTR(booking_id, 2))), 0) + 1 INTO v_n
    FROM bookings WHERE REGEXP_LIKE(booking_id, '^B[0-9]+$');
  p_booking_id := 'B' || LPAD(v_n, GREATEST(3, LENGTH(TO_CHAR(v_n))), '0');  -- LPAD ตัดเลขที่ยาวเกิน จึงต้องขยายความยาว
  INSERT INTO bookings (booking_id, booked_at, user_id) VALUES (p_booking_id, SYSDATE, p_user);

  SELECT NVL(MAX(TO_NUMBER(SUBSTR(booking_item_id, 3))), 0) + 1 INTO v_n
    FROM booking_items WHERE REGEXP_LIKE(booking_item_id, '^BD[0-9]+$');
  p_item_id := 'BD' || LPAD(v_n, GREATEST(3, LENGTH(TO_CHAR(v_n))), '0');
  p_qr := 'QR-' || p_item_id || '-' || SUBSTR(RAWTOHEX(SYS_GUID()), 1, 8);

  -- trigger ตรวจลำดับจุดขึ้น–ลง และที่นั่งว่าง
  INSERT INTO booking_items (booking_item_id, qr_code, status, seats, booking_id, trip_id, board_stop_id, alight_stop_id)
  VALUES (p_item_id, p_qr, 'ยืนยัน', p_seats, p_booking_id, p_trip, p_board, p_alight);
END;
/

-- ยกเลิกรายการจอง (ที่นั่งคืนอัตโนมัติ เพราะการนับที่นั่งไม่นับสถานะยกเลิก)
CREATE OR REPLACE PROCEDURE sp_cancel_booking_item(p_item IN VARCHAR2, p_user IN VARCHAR2) IS
  v_owner   bookings.user_id%TYPE;
  v_status  booking_items.status%TYPE;
  v_checkin DATE;
BEGIN
  BEGIN
    SELECT b.user_id, bi.status, bi.checkin_at INTO v_owner, v_status, v_checkin
      FROM booking_items bi JOIN bookings b ON b.booking_id = bi.booking_id
     WHERE bi.booking_item_id = p_item;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20001, 'ไม่พบรายการจอง');
  END;
  IF p_user IS NOT NULL AND v_owner <> p_user THEN
    RAISE_APPLICATION_ERROR(-20001, 'ไม่สามารถยกเลิกรายการจองของผู้อื่นได้');
  END IF;
  IF v_status <> 'ยืนยัน' OR v_checkin IS NOT NULL THEN
    RAISE_APPLICATION_ERROR(-20001, 'รายการนี้ยกเลิกไม่ได้ (ยกเลิกแล้ว / Check-in แล้ว / No Show)');
  END IF;
  UPDATE booking_items SET status = 'ยกเลิก' WHERE booking_item_id = p_item;
END;
/

-- คนขับเริ่มการเดินทาง
CREATE OR REPLACE PROCEDURE sp_start_trip(p_trip IN VARCHAR2, p_driver IN VARCHAR2) IS
  v_n NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_n FROM trips WHERE trip_id = p_trip AND driver_id = p_driver AND status = 'เปิด';
  IF v_n = 0 THEN
    RAISE_APPLICATION_ERROR(-20001, 'เริ่มรอบนี้ไม่ได้ (ไม่ใช่รอบของคนขับ หรือสถานะไม่ใช่ เปิด)');
  END IF;
  UPDATE trips SET status = 'กำลังเดินทาง' WHERE trip_id = p_trip;
END;
/

-- สแกน QR Check-in
CREATE OR REPLACE PROCEDURE sp_checkin(p_qr IN VARCHAR2, p_trip IN VARCHAR2, p_rc OUT SYS_REFCURSOR) IS
  v_trip_status trips.status%TYPE;
  v_item        booking_items.booking_item_id%TYPE;
  v_trip        booking_items.trip_id%TYPE;
  v_status      booking_items.status%TYPE;
  v_checkin     DATE;
BEGIN
  SELECT MAX(status) INTO v_trip_status FROM trips WHERE trip_id = p_trip;
  IF v_trip_status <> 'กำลังเดินทาง' THEN
    RAISE_APPLICATION_ERROR(-20001, 'กรุณาเริ่มการเดินทางก่อนสแกน QR');
  END IF;

  BEGIN
    SELECT booking_item_id, trip_id, status, checkin_at INTO v_item, v_trip, v_status, v_checkin
      FROM booking_items WHERE qr_code = p_qr;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20001, 'ไม่พบ QR Code นี้ในระบบ');
  END;

  IF v_trip <> p_trip THEN
    RAISE_APPLICATION_ERROR(-20001, 'QR Code นี้ไม่ตรงกับรอบการเดินทาง ไม่สามารถขึ้นรถได้');
  ELSIF v_status = 'ยกเลิก' THEN
    RAISE_APPLICATION_ERROR(-20001, 'รายการจองนี้ถูกยกเลิกแล้ว');
  ELSIF v_checkin IS NOT NULL THEN
    RAISE_APPLICATION_ERROR(-20001, 'รายการจองนี้ Check-in แล้วเมื่อ ' || TO_CHAR(v_checkin, 'HH24:MI'));
  END IF;

  UPDATE booking_items SET checkin_at = SYSDATE WHERE booking_item_id = v_item;

  OPEN p_rc FOR
    SELECT bi.booking_item_id, u.name AS passenger_name, bi.seats, s.stop_name AS alight_stop,
           'Check-in สำเร็จ' AS result
      FROM booking_items bi
      JOIN bookings b ON b.booking_id = bi.booking_id
      JOIN users u    ON u.user_id = b.user_id
      JOIN stops s    ON s.stop_id = bi.alight_stop_id
     WHERE bi.booking_item_id = v_item;
END;
/

-- ปิดงาน: รายการที่ไม่ได้ Check-in → No Show และสรุปผล
CREATE OR REPLACE PROCEDURE sp_close_trip(p_trip IN VARCHAR2, p_summary OUT SYS_REFCURSOR, p_no_shows OUT SYS_REFCURSOR) IS
  v_status trips.status%TYPE;
BEGIN
  SELECT MAX(status) INTO v_status FROM trips WHERE trip_id = p_trip;
  IF v_status IS NULL OR v_status <> 'กำลังเดินทาง' THEN
    RAISE_APPLICATION_ERROR(-20001, 'ปิดงานได้เฉพาะรอบที่กำลังเดินทาง');
  END IF;

  UPDATE booking_items SET status = 'No Show'
   WHERE trip_id = p_trip AND status = 'ยืนยัน' AND checkin_at IS NULL;
  UPDATE trips SET status = 'เสร็จสิ้น' WHERE trip_id = p_trip;

  OPEN p_summary FOR
    SELECT p_trip AS trip_id,
           NVL(SUM(CASE WHEN checkin_at IS NOT NULL THEN seats END), 0) AS actual_passengers,
           NVL(SUM(CASE WHEN status = 'No Show' THEN 1 ELSE 0 END), 0) AS no_show_items
      FROM booking_items WHERE trip_id = p_trip;

  OPEN p_no_shows FOR
    SELECT bi.booking_item_id, u.name, bi.seats
      FROM booking_items bi JOIN bookings b ON b.booking_id = bi.booking_id JOIN users u ON u.user_id = b.user_id
     WHERE bi.trip_id = p_trip AND bi.status = 'No Show';
END;
/


-- =====================================================================
-- 5) ข้อมูลตัวอย่าง (Seed) — จาก Mapping + จุดจอด/เวลาจากเอกสาร MINI
-- =====================================================================

INSERT INTO departments VALUES ('D001', 'ฝ่ายบุคคล');
INSERT INTO departments VALUES ('D002', 'ฝ่ายปฏิบัติการ');
-- D003 = ผู้ใช้บริการที่ Login มาจอง (ไม่ใช่พนักงาน)
INSERT INTO departments VALUES ('D003', 'นักศึกษา');

INSERT INTO positions (position_id, position_name, department_id) VALUES ('P01', 'Admin', 'D001');
INSERT INTO positions (position_id, position_name, department_id) VALUES ('P02', 'พนักงาน', 'D002');

INSERT INTO screens VALUES ('SC01', 'จัดการรถ');
INSERT INTO screens VALUES ('SC02', 'จัดการการจอง');
INSERT INTO screens VALUES ('SC03', 'จัดการประเภทรถ');
INSERT INTO screens VALUES ('SC04', 'จัดการจุดจอด');
INSERT INTO screens VALUES ('SC05', 'จัดการเส้นทาง');
INSERT INTO screens VALUES ('SC06', 'จัดการรอบการเดินรถ');
INSERT INTO screens VALUES ('SC07', 'จัดการผู้ใช้งาน/พนักงาน');
INSERT INTO screens VALUES ('SC08', 'จัดการแผนก');
INSERT INTO screens VALUES ('SC09', 'จัดการตำแหน่ง');
INSERT INTO screens VALUES ('SC10', 'จัดการหน้าจอและสิทธิ์');
INSERT INTO screens VALUES ('SC11', 'รายงาน');
INSERT INTO screens VALUES ('SC12', 'งานคนขับ');

-- password ตัวอย่าง = '1234' (SHA-256 hex)
-- U001 = ผู้ดูแลระบบ / U002–U004 = คนขับตามเอกสาร MINI
INSERT INTO users VALUES ('U001', 'ผู้ดูแลระบบ', 'admin@mail.com', 'admin', LOWER(RAWTOHEX(STANDARD_HASH('1234', 'SHA256'))), 'D001');
INSERT INTO users VALUES ('U002', 'สมชาย ใจดี', 'somchai@mail.com', 'somchai', LOWER(RAWTOHEX(STANDARD_HASH('1234', 'SHA256'))), 'D002');
INSERT INTO users VALUES ('U003', 'สมหญิง ใจรัก', 'somying@mail.com', 'somying', LOWER(RAWTOHEX(STANDARD_HASH('1234', 'SHA256'))), 'D002');
INSERT INTO users VALUES ('U004', 'สมควร ใจงาม', 'somkuan@mail.com', 'somkuan', LOWER(RAWTOHEX(STANDARD_HASH('1234', 'SHA256'))), 'D002');

INSERT INTO employees VALUES ('U001', '0811111111', 'P01');
INSERT INTO employees VALUES ('U002', '0822222222', 'P02');
INSERT INTO employees VALUES ('U003', '0833333333', 'P02');
INSERT INTO employees VALUES ('U004', '0844444444', 'P02');

-- PR001, PR002 ตาม Mapping / PR003–PR013 = Admin เข้าถึงทุกหน้าจอ
INSERT INTO permissions VALUES ('PR001', 1, 1, 1, 'P01', 'SC01');
INSERT INTO permissions VALUES ('PR002', 0, 0, 0, 'P02', 'SC01');
INSERT INTO permissions VALUES ('PR003', 1, 1, 1, 'P01', 'SC02');
INSERT INTO permissions VALUES ('PR004', 1, 1, 1, 'P01', 'SC03');
INSERT INTO permissions VALUES ('PR005', 1, 1, 1, 'P01', 'SC04');
INSERT INTO permissions VALUES ('PR006', 1, 1, 1, 'P01', 'SC05');
INSERT INTO permissions VALUES ('PR007', 1, 1, 1, 'P01', 'SC06');
INSERT INTO permissions VALUES ('PR008', 1, 1, 1, 'P01', 'SC07');
INSERT INTO permissions VALUES ('PR009', 1, 1, 1, 'P01', 'SC08');
INSERT INTO permissions VALUES ('PR010', 1, 1, 1, 'P01', 'SC09');
INSERT INTO permissions VALUES ('PR011', 1, 1, 1, 'P01', 'SC10');
INSERT INTO permissions VALUES ('PR012', 1, 1, 1, 'P01', 'SC11');
INSERT INTO permissions VALUES ('PR013', 0, 1, 0, 'P02', 'SC12');

-- ประเภทรถ/รถตามเอกสาร MINI
INSERT INTO vehicle_types VALUES ('T01', 'รถตู้', 'รถโดยสารขนาดเล็ก', 9);
INSERT INTO vehicle_types VALUES ('T02', 'รถบัส', 'รถโดยสารขนาดใหญ่', 20);

INSERT INTO vehicles VALUES ('V001', 'สย 2591', 'พร้อมใช้งาน', 'T01');
INSERT INTO vehicles VALUES ('V002', 'บก 1130', 'พร้อมใช้งาน', 'T02');
INSERT INTO vehicles VALUES ('V003', 'สย 2599', 'พร้อมใช้งาน', 'T01');

INSERT INTO routes VALUES ('R001', 'เส้นทาง 1');
INSERT INTO routes VALUES ('R002', 'เส้นทาง 2');
INSERT INTO routes VALUES ('R003', 'เส้นทาง 3');

-- จุดจอดตามเอกสาร MINI
INSERT INTO stops VALUES ('S001', 'มหาวิทยาลัยเทคโนโลยีมหานคร');
INSERT INTO stops VALUES ('S002', 'โลตัสหนองจอก');
INSERT INTO stops VALUES ('S003', 'โรงพยาบาลหนองจอก');
INSERT INTO stops VALUES ('S004', 'Big C หนองจอก');
INSERT INTO stops VALUES ('S005', 'สวนสาธารณหนองจอก');
INSERT INTO stops VALUES ('S006', 'ร้านส้มตำป้านาง');

-- ลำดับจุดจอดและเวลาเดินทางตามเอกสาร MINI
-- เส้นทาง 1 = 30 นาที / เส้นทาง 2 = 13 นาที / เส้นทาง 3 = 15 นาที (เอกสารเขียน 12 แต่ 5+3+5+2 = 15)
INSERT INTO route_stops (route_id, stop_order, stop_id, travel_minutes) VALUES ('R001', 1, 'S001', 0);
INSERT INTO route_stops (route_id, stop_order, stop_id, travel_minutes) VALUES ('R001', 2, 'S002', 5);
INSERT INTO route_stops (route_id, stop_order, stop_id, travel_minutes) VALUES ('R001', 3, 'S003', 3);
INSERT INTO route_stops (route_id, stop_order, stop_id, travel_minutes) VALUES ('R001', 4, 'S004', 6);
INSERT INTO route_stops (route_id, stop_order, stop_id, travel_minutes) VALUES ('R001', 5, 'S003', 3);
INSERT INTO route_stops (route_id, stop_order, stop_id, travel_minutes) VALUES ('R001', 6, 'S002', 3);
INSERT INTO route_stops (route_id, stop_order, stop_id, travel_minutes) VALUES ('R001', 7, 'S001', 10);
INSERT INTO route_stops (route_id, stop_order, stop_id, travel_minutes) VALUES ('R002', 1, 'S001', 0);
INSERT INTO route_stops (route_id, stop_order, stop_id, travel_minutes) VALUES ('R002', 2, 'S002', 5);
INSERT INTO route_stops (route_id, stop_order, stop_id, travel_minutes) VALUES ('R002', 3, 'S005', 3);
INSERT INTO route_stops (route_id, stop_order, stop_id, travel_minutes) VALUES ('R002', 4, 'S006', 5);
INSERT INTO route_stops (route_id, stop_order, stop_id, travel_minutes) VALUES ('R003', 1, 'S004', 0);
INSERT INTO route_stops (route_id, stop_order, stop_id, travel_minutes) VALUES ('R003', 2, 'S002', 5);
INSERT INTO route_stops (route_id, stop_order, stop_id, travel_minutes) VALUES ('R003', 3, 'S005', 3);
INSERT INTO route_stops (route_id, stop_order, stop_id, travel_minutes) VALUES ('R003', 4, 'S006', 5);
INSERT INTO route_stops (route_id, stop_order, stop_id, travel_minutes) VALUES ('R003', 5, 'S001', 2);

-- ตารางเวลาเดินรถประจำตามเอกสาร MINI — วิ่งเฉพาะวันทำการ (จันทร์–ศุกร์) รอบของแต่ละวันถูกสร้างอัตโนมัติจากตารางนี้
INSERT INTO trip_schedules (schedule_id, route_id, depart_time, vehicle_id, driver_id, run_days, active) VALUES ('TS001', 'R001', '09:30:00', 'V001', 'U002', '12345', 1);
INSERT INTO trip_schedules (schedule_id, route_id, depart_time, vehicle_id, driver_id, run_days, active) VALUES ('TS002', 'R001', '11:00:00', 'V001', 'U003', '12345', 1);
INSERT INTO trip_schedules (schedule_id, route_id, depart_time, vehicle_id, driver_id, run_days, active) VALUES ('TS003', 'R001', '13:00:00', 'V002', 'U002', '12345', 1);
INSERT INTO trip_schedules (schedule_id, route_id, depart_time, vehicle_id, driver_id, run_days, active) VALUES ('TS004', 'R001', '15:00:00', 'V002', 'U002', '12345', 1);
INSERT INTO trip_schedules (schedule_id, route_id, depart_time, vehicle_id, driver_id, run_days, active) VALUES ('TS005', 'R002', '09:30:00', 'V003', 'U004', '12345', 1);
INSERT INTO trip_schedules (schedule_id, route_id, depart_time, vehicle_id, driver_id, run_days, active) VALUES ('TS006', 'R002', '11:00:00', 'V003', 'U004', '12345', 1);
INSERT INTO trip_schedules (schedule_id, route_id, depart_time, vehicle_id, driver_id, run_days, active) VALUES ('TS007', 'R002', '13:00:00', 'V003', 'U003', '12345', 1);
INSERT INTO trip_schedules (schedule_id, route_id, depart_time, vehicle_id, driver_id, run_days, active) VALUES ('TS008', 'R002', '15:00:00', 'V003', 'U003', '12345', 1);
-- เส้นทาง 3: เอกสารไม่ได้กำหนดเวลา — จัดจากรถ/คนขับที่ว่าง ไม่ชนรอบเส้นทาง 1–2
INSERT INTO trip_schedules (schedule_id, route_id, depart_time, vehicle_id, driver_id, run_days, active) VALUES ('TS009', 'R003', '09:30:00', 'V002', 'U003', '12345', 1);
INSERT INTO trip_schedules (schedule_id, route_id, depart_time, vehicle_id, driver_id, run_days, active) VALUES ('TS010', 'R003', '11:00:00', 'V002', 'U002', '12345', 1);
INSERT INTO trip_schedules (schedule_id, route_id, depart_time, vehicle_id, driver_id, run_days, active) VALUES ('TS011', 'R003', '13:00:00', 'V001', 'U004', '12345', 1);
INSERT INTO trip_schedules (schedule_id, route_id, depart_time, vehicle_id, driver_id, run_days, active) VALUES ('TS012', 'R003', '15:00:00', 'V001', 'U004', '12345', 1);

COMMIT;


-- =====================================================================
-- 6) ตัวอย่างการเรียกใช้ใน SQL Developer
-- =====================================================================
-- VARIABLE rc REFCURSOR
-- EXEC sp_search_trips(DATE '2026-09-24', 'S002', 'S004', :rc)
-- PRINT rc
--
-- VARIABLE b VARCHAR2(10)
-- VARIABLE i VARCHAR2(10)
-- VARIABLE q VARCHAR2(64)
-- EXEC sp_create_booking('U001', 'TR002', 'S002', 'S004', 2, :b, :i, :q)
-- PRINT b i q
--
-- EXEC sp_cancel_booking_item('BD002', 'U002')
-- EXEC sp_start_trip('TR002', 'U002')
