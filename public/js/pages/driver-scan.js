// 9.3 สแกน QR (Check-in) → CALL api_driver_scan / api_driver_checkin
//
// Check-in ได้ 2 ทาง: สแกนด้วยกล้อง หรือพิมพ์รหัส QR ในช่อง (กล้องใช้ไม่ได้/ไม่มีเน็ต)
// ทั้งสองทางเรียก checkin() ตัวเดียวกัน — หลังบ้านเป็นคนตัดสินว่าขึ้นรถได้ไหม
// (QR ไม่มีในระบบ / ไม่ใช่รอบนี้ / ถูกยกเลิก / Check-in ไปแล้ว → ไม่อนุญาต)
MUT.page(async () => {
  const { esc, fmtTime } = MUT;
  const id = MUT.param('id');
  const [[trip], [counts]] = await MUT.api('driver_scan', { trip: id });
  document.getElementById('back-link').href = `/driver/trip?id=${encodeURIComponent(trip.trip_id)}`;
  document.getElementById('trip-info').textContent = `${fmtTime(trip.depart_time)} · ${trip.route_name} · ${trip.plate_no}`;
  // ตัวนับ "Check-in แล้ว / จองทั้งหมด" — อัปเดตหลังสแกนสำเร็จทุกครั้ง
  const countEl = document.getElementById('checkin-count');
  const showCounts = (c) => { countEl.textContent = `${c.checked_in} / ${c.booked}`; };
  showCounts(counts);

  // สแกนได้เฉพาะรอบที่ "กำลังเดินทาง" — สถานะอื่นแสดงเหตุผลแทนพื้นที่สแกน
  if (trip.status !== 'กำลังเดินทาง') {
    document.getElementById('scan-blocked').innerHTML = `<div class="alert alert-warning">${
      trip.status === 'เปิด' ? 'กรุณาเริ่มการเดินทางก่อนสแกน QR' : `รอบนี้สถานะ ${esc(trip.status)} แล้ว ไม่สามารถสแกนได้`}</div>`;
    return;
  }
  document.getElementById('scan-area').hidden = false;

  // กล่องผลลัพธ์ตัวใหญ่ เขียว/แดง ให้คนขับเห็นชัด (role="alert" = screen reader อ่านทันที)
  const resultBox = document.getElementById('scan-result');
  const showResult = (ok, msg, qr) => {
    resultBox.innerHTML = `<div class="scan-result ${ok ? 'ok' : 'err'}" role="alert">
        <div class="big">${ok ? '✓ อนุญาตให้ขึ้นรถ' : '✗ ไม่อนุญาตให้ขึ้นรถ'}</div>
        <div>${esc(msg)}</div>${qr ? `<div class="small mono mt-2">QR: ${esc(qr)}</div>` : ''}
      </div>`;
  };

  // ตรวจ QR กับหลังบ้าน: สำเร็จ → ชื่อผู้โดยสาร/จำนวนที่นั่ง/จุดลง + ล้างช่อง / ไม่ผ่าน → ข้อความจากหลังบ้าน
  // ไม่ใช้ bindForm เพราะผลต้องแสดงในกล่องผลลัพธ์ ไม่ใช่ใต้ช่องกรอก
  const form = document.getElementById('checkin-form');
  const input = document.getElementById('qr');
  async function checkin(qr) {
    try {
      const [[r], [c]] = await MUT.api('driver_checkin', { trip: trip.trip_id, qr });
      showResult(true, `Check-in สำเร็จ — ${r.passenger_name} ${r.seats} ที่นั่ง (ลงที่ ${r.alight_stop})`);
      showCounts(c);
      input.value = '';
    } catch (err) {
      if (!(err instanceof MUT.ApiError)) throw err;
      showResult(false, err.message, qr);
    }
  }
  // กรอกรหัสเอง: ปิดปุ่มระหว่างตรวจ แล้ว focus กลับช่องกรอก พร้อมกรอกคนถัดไป
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const btn = form.querySelector('[type=submit]');
    btn.disabled = true;
    await checkin(input.value.trim());
    btn.disabled = false;
    input.focus();
  });

  // กล้องสแกน (html5-qrcode) — สแกนได้แล้วตรวจทันที และสแกนคนถัดไปต่อได้
  // running = กล้องเปิดอยู่ / busy = กำลังตรวจ QR (กล้องอ่านได้หลายครั้งต่อวินาที — ไม่ส่งซ้ำระหว่างรอ)
  // facingMode environment = กล้องหลังของมือถือ
  const btn = document.getElementById('cam-btn');
  const status = document.getElementById('cam-status');
  let scanner = null;
  let running = false;
  let busy = false;
  async function start() {
    if (typeof Html5Qrcode === 'undefined') {
      status.textContent = 'โหลดตัวสแกนไม่ได้ (ไม่มีอินเทอร์เน็ต) — กรอกรหัส QR แทน';
      return;
    }
    scanner = scanner || new Html5Qrcode('reader');
    try {
      await scanner.start({ facingMode: 'environment' }, { fps: 10, qrbox: 220 }, async (text) => {
        if (busy) return;
        busy = true;
        status.textContent = 'กำลังตรวจสอบ...';
        await checkin(text);
        status.textContent = 'กำลังสแกน... หัน QR Code ของคนถัดไปเข้ากล้อง';
        setTimeout(() => { busy = false; }, 1500); // กันสแกน QR เดิมซ้ำทันที
      });
      running = true;
      btn.textContent = 'ปิดกล้อง';
      status.textContent = 'กำลังสแกน... หัน QR Code เข้ากล้อง';
    } catch (e) {
      status.textContent = 'เปิดกล้องไม่ได้ (ไม่ได้รับอนุญาต หรือไม่มีกล้อง) — กรอกรหัส QR แทน';
    }
  }
  async function stop() {
    if (scanner && running) await scanner.stop();
    running = false;
    btn.innerHTML = `${MUT.icon('qr')} เปิดกล้องสแกน`;
    status.textContent = 'ปิดกล้องแล้ว';
  }
  btn.addEventListener('click', () => (running ? stop() : start()));
});
