// 9.3 สแกน QR (Check-in) → CALL api_driver_scan / api_driver_checkin
MUT.page(async () => {
  const { esc, fmtTime } = MUT;
  const id = MUT.param('id');
  const [[trip], [counts]] = await MUT.api('driver_scan', { trip: id });
  document.getElementById('back-link').href = `/driver/trip?id=${encodeURIComponent(trip.trip_id)}`;
  document.getElementById('trip-info').textContent = `${fmtTime(trip.depart_time)} · ${trip.route_name} · ${trip.plate_no}`;
  const countEl = document.getElementById('checkin-count');
  const showCounts = (c) => { countEl.textContent = `${c.checked_in} / ${c.booked}`; };
  showCounts(counts);

  if (trip.status !== 'กำลังเดินทาง') {
    document.getElementById('scan-blocked').innerHTML = `<div class="alert alert-warning">${
      trip.status === 'เปิด' ? 'กรุณาเริ่มการเดินทางก่อนสแกน QR' : `รอบนี้สถานะ ${esc(trip.status)} แล้ว ไม่สามารถสแกนได้`}</div>`;
    return;
  }
  document.getElementById('scan-area').hidden = false;

  const resultBox = document.getElementById('scan-result');
  const showResult = (ok, msg, qr) => {
    resultBox.innerHTML = `<div class="scan-result ${ok ? 'ok' : 'err'}" role="alert">
        <div class="big">${ok ? '✓ อนุญาตให้ขึ้นรถ' : '✗ ไม่อนุญาตให้ขึ้นรถ'}</div>
        <div>${esc(msg)}</div>${qr ? `<div class="small mono mt-2">QR: ${esc(qr)}</div>` : ''}
      </div>`;
  };

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
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const btn = form.querySelector('[type=submit]');
    btn.disabled = true;
    await checkin(input.value.trim());
    btn.disabled = false;
    input.focus();
  });

  // กล้องสแกน (html5-qrcode) — สแกนได้แล้วตรวจทันที และสแกนคนถัดไปต่อได้
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
