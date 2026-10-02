// 9.2 รายละเอียดรอบ + ผู้โดยสารตามจุดจอด → CALL api_driver_trip (เริ่มการเดินทาง → CALL api_driver_start)
MUT.page(async () => {
  const { esc, fmtDate, fmtTime, badge, icon } = MUT;
  const id = MUT.param('id');
  const [[trip], [counts], rows] = await MUT.api('driver_trip', { trip: id });
  document.title = `รอบ ${trip.trip_id} · BusBuddy`;
  document.getElementById('back-link').href = trip.trip_date >= trip.today ? '/driver/' : '/driver/history';

  // จัดกลุ่มผู้โดยสารตามจุดจอด
  const stops = [];
  for (const r of rows) {
    let s = stops[stops.length - 1];
    if (!s || s.stop_order !== r.stop_order) {
      s = { stop_order: r.stop_order, stop_name: r.stop_name, arrive_at: r.arrive_at, up: [], down: [] };
      stops.push(s);
    }
    if (!r.booking_item_id) continue;
    if (Number(r.is_up)) s.up.push(r);
    if (Number(r.is_down)) s.down.push(r);
  }
  const seats = (list) => list.reduce((n, p) => n + Number(p.seats), 0);
  const done = trip.status === 'เสร็จสิ้น';
  const q = `?id=${encodeURIComponent(trip.trip_id)}`;

  let actions = '';
  if (trip.status === 'เปิด' && trip.trip_date > trip.today) {
    actions = `<div class="alert alert-info">รอบล่วงหน้า — กดเริ่มการเดินทางและสแกน QR ได้ในวันที่ ${fmtDate(trip.trip_date)}</div>`;
  } else if (trip.status === 'เปิด') {
    actions = `<button class="btn btn-primary btn-block" type="button" id="start-btn">${icon('steering')} เริ่มการเดินทาง</button>`;
  } else if (trip.status === 'กำลังเดินทาง') {
    actions = `<a class="btn btn-primary btn-block" href="/driver/scan${q}">${icon('qr')} สแกน QR</a>
               <a class="btn btn-block" href="/driver/close${q}">ปิดงาน</a>`;
  }

  document.getElementById('trip-view').innerHTML = `
    <div class="page-head row-between">
      <div>
        <h1 class="mb-0">${fmtTime(trip.depart_time)} · ${esc(trip.route_name)}</h1>
        <div class="muted">${fmtDate(trip.trip_date)} · ${esc(trip.plate_no)} (${esc(trip.type_name)}) · <span class="mono">${esc(trip.trip_id)}</span></div>
      </div>
      ${badge(trip.status)}
    </div>
    <div class="kpis" style="grid-template-columns:repeat(3,1fr);margin-bottom:var(--s4)">
      <div class="kpi"><div class="k-label">จองแล้ว</div><div class="k-value">${counts.booked}<span class="small muted">/${trip.seat_count}</span></div></div>
      <div class="kpi"><div class="k-label">Check-in</div><div class="k-value" style="color:var(--success)">${counts.checked_in}</div></div>
      <div class="kpi"><div class="k-label">${done ? 'No Show' : 'รอขึ้นรถ'}</div><div class="k-value">${done ? counts.no_show : counts.waiting}</div></div>
    </div>
    <div class="stack mb-4">${actions}</div>
    <h2 class="section-title">ผู้โดยสารตามจุดจอด</h2>
    <div class="card">
      ${stops.map((s) => `
        <div class="stop-block">
          <div class="head"><span class="mono">${fmtTime(s.arrive_at)}</span> <span>${esc(s.stop_name)}</span></div>
          <div class="io"><span class="up">ขึ้น ${seats(s.up)} คน</span>${s.up.length ? ' — ' + esc(s.up.map((p) =>
            `${p.passenger_name} (${p.seats})${p.checkin_at ? ' ✓' : p.status === 'No Show' ? ' ✗' : ''}`).join(', ')) : ''}</div>
          <div class="io"><span class="down">ลง ${seats(s.down)} คน</span>${s.down.length ? ' — ' + esc(s.down.map((p) => `${p.passenger_name} (${p.seats})`).join(', ')) : ''}</div>
        </div>`).join('')}
      <p class="small muted mb-0">✓ = Check-in แล้ว · ✗ = No Show</p>
    </div>`;

  const start = document.getElementById('start-btn');
  if (start) {
    start.addEventListener('click', async () => {
      const ok = await MUT.confirmBox({
        title: `เริ่มการเดินทางรอบ ${fmtTime(trip.depart_time)}?`,
        message: 'สถานะรอบจะเปลี่ยนเป็น กำลังเดินทาง และเริ่มสแกน QR ได้',
        ok: 'เริ่มการเดินทาง', tone: 'primary',
      });
      if (!ok) return;
      try {
        const [[r]] = await MUT.api('driver_start', { trip: trip.trip_id });
        MUT.go(location.href, 'success', r.message);
      } catch (err) {
        MUT.flash('error', err.message);
      }
    });
  }
});
