// 8.2 ยืนยันการจอง → CALL api_trip แล้ว CALL api_book
MUT.page(async () => {
  const { esc, fmtDate, fmtTime, qs } = MUT;
  const ctx = await TripCtx.load();
  const { trip, seg, board, alight } = ctx;
  const seats = Number(MUT.param('seats'));
  const back = '/book' + qs({ id: trip.trip_id, board, alight, seats });
  document.getElementById('back-btn').href = back;
  // ตรวจซ้ำก่อนแสดง (URL แก้เองได้ / ที่นั่งอาจหมดระหว่างนั้น) → ไม่ผ่าน = กลับหน้าเลือกที่นั่ง
  if (trip.blocked || !(seats >= 1 && seats <= trip.max_seats)) {
    return MUT.go(back, 'error', trip.blocked || `เลือกได้ 1–${trip.max_seats} ที่นั่ง`);
  }

  document.getElementById('summary').innerHTML = `
    <dt>เส้นทาง</dt><dd>${esc(trip.route_name)}</dd>
    <dt>วันที่เดินรถ</dt><dd>${fmtDate(trip.trip_date)}</dd>
    <dt>เวลาออก</dt><dd>${fmtTime(trip.depart_time)}</dd>
    <dt>จุดขึ้น</dt><dd>${esc(seg.board.stop_name)} (ถึง ${fmtTime(seg.board.arrive_at)})</dd>
    <dt>จุดลง</dt><dd>${esc(seg.alight.stop_name)} (ถึง ${fmtTime(seg.alight.arrive_at)})</dd>
    <dt>รถ</dt><dd>${esc(trip.plate_no)} (${esc(trip.type_name)})</dd>
    <dt>จำนวนที่นั่ง</dt><dd>${seats}</dd>`;

  // ปุ่มยืนยันปิดไว้ใน HTML จนกว่าข้อมูลจะโหลดครบ (กันกดก่อนเห็นสรุป)
  // api_book → sp_create_booking ล็อกรอบแล้วตรวจที่นั่ง/เวลาอีกครั้งในฐานข้อมูล (กันจองเกินเมื่อกดพร้อมกัน)
  // สำเร็จ → หน้า QR ของรายการที่เพิ่งจอง (?new=1 = แสดงหัว "จองสำเร็จ")
  const form = document.getElementById('confirm-form');
  form.querySelector('[type=submit]').disabled = false;
  MUT.bindForm(form, async () => {
    const [[out]] = await MUT.api('book', { trip: trip.trip_id, board, alight, seats });
    location.href = '/item' + qs({ id: out.item_id, new: 1 });
  });
});
