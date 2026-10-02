-- =====================================================================
--  ข้อมูลตัวอย่างเพิ่มเติมสำหรับทดลองใช้งาน (รันหลัง mut_shuttle.sql)
--  - รอบรถของแต่ละวันสร้างอัตโนมัติจากตารางเวลาเดินรถ (trip_schedules) เมื่อเปิดเว็บ
--  - ไฟล์นี้เพิ่มรอบที่เสร็จสิ้นแล้วในอดีต + รอบพรุ่งนี้ 2 รอบ พร้อมการจอง เพื่อให้หน้าจอ/รายงานมีข้อมูล
--  ทุกบัญชี password = 1234
-- =====================================================================
USE mut_shuttle;

-- มานี = นักศึกษา (ผู้ใช้บริการ ไม่ใช่พนักงาน)
INSERT INTO users VALUES
  ('U005', 'มานี มีนา', 'manee@mail.com', 'manee', SHA2('1234', 256), 'D003');

-- รอบในอดีต (เสร็จสิ้นแล้ว) ตามตารางเวลาเดินรถ
INSERT INTO trips (trip_id, trip_date, depart_time, status, vehicle_id, route_id, driver_id, schedule_id) VALUES
  ('TR001', CURDATE() - INTERVAL 3 DAY, '09:30:00', 'เสร็จสิ้น', 'V001', 'R001', 'U002', 'TS001'),
  ('TR002', CURDATE() - INTERVAL 3 DAY, '11:00:00', 'เสร็จสิ้น', 'V003', 'R002', 'U004', 'TS006'),
  ('TR003', CURDATE() - INTERVAL 2 DAY, '13:00:00', 'เสร็จสิ้น', 'V002', 'R001', 'U002', 'TS003'),
  ('TR004', CURDATE() - INTERVAL 1 DAY, '15:00:00', 'เสร็จสิ้น', 'V003', 'R002', 'U003', 'TS008');

-- รอบพรุ่งนี้ที่มีการจองแล้ว (รอบอื่นของพรุ่งนี้ระบบสร้างเองจากตารางเวลา)
INSERT INTO trips (trip_id, trip_date, depart_time, status, vehicle_id, route_id, driver_id, schedule_id) VALUES
  ('TR005', CURDATE() + INTERVAL 1 DAY, '11:00:00', 'เปิด', 'V001', 'R001', 'U003', 'TS002'),
  ('TR006', CURDATE() + INTERVAL 1 DAY, '09:30:00', 'เปิด', 'V003', 'R002', 'U004', 'TS005');

INSERT INTO bookings VALUES
  ('B001', NOW() - INTERVAL 5 DAY, 'U005'),
  ('B002', NOW() - INTERVAL 5 DAY, 'U001'),
  ('B003', NOW() - INTERVAL 4 DAY, 'U005'),
  ('B004', NOW() - INTERVAL 3 DAY, 'U001'),
  ('B005', NOW() - INTERVAL 2 DAY, 'U005'),
  ('B006', NOW() - INTERVAL 1 HOUR, 'U005'),
  ('B007', NOW() - INTERVAL 30 MINUTE, 'U001');

INSERT INTO booking_items
  (booking_item_id, qr_code, status, seats, checkin_at, booking_id, trip_id, board_stop_id, alight_stop_id) VALUES
  ('BD001', 'QR-BD001-DEMO0001', 'ยืนยัน',  2, TIMESTAMP(CURDATE() - INTERVAL 3 DAY, '09:35:00'), 'B001', 'TR001', 'S002', 'S004'),
  ('BD002', 'QR-BD002-DEMO0002', 'No Show', 1, NULL,                                             'B002', 'TR001', 'S001', 'S003'),
  ('BD003', 'QR-BD003-DEMO0003', 'ยืนยัน',  1, TIMESTAMP(CURDATE() - INTERVAL 3 DAY, '11:00:00'), 'B003', 'TR002', 'S001', 'S006'),
  ('BD004', 'QR-BD004-DEMO0004', 'ยืนยัน',  3, TIMESTAMP(CURDATE() - INTERVAL 2 DAY, '13:14:00'), 'B004', 'TR003', 'S004', 'S001'),
  ('BD005', 'QR-BD005-DEMO0005', 'ยกเลิก',  1, NULL,                                             'B005', 'TR004', 'S002', 'S005'),
  ('BD006', 'QR-BD006-DEMO0006', 'ยืนยัน',  2, NULL,                                             'B006', 'TR005', 'S002', 'S004'),
  ('BD007', 'QR-BD007-DEMO0007', 'ยืนยัน',  1, NULL,                                             'B007', 'TR006', 'S001', 'S006');
