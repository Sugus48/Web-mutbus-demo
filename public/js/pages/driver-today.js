// 9.1 งานวันนี้ + งานที่จะถึงใน 7 วัน → CALL api_driver_today
MUT.page(async ({ me }) => {
  const { esc, fmtDate, fmtTime, badge } = MUT;
  const [trips, upcoming] = await MUT.api('driver_today');
  document.getElementById('today-info').textContent = `${fmtDate(me.today)} · ${trips.length} รอบ`;
  const SUB = { 'เปิด': 'รอเริ่มงาน', 'กำลังเดินทาง': 'กำลังเดินทาง', 'เสร็จสิ้น': 'ปิดงานแล้ว', 'ยกเลิก': 'รอบถูกยกเลิก' };
  const link = (t) => `/driver/trip?id=${encodeURIComponent(t.trip_id)}`;

  document.getElementById('today-trips').innerHTML = !trips.length
    ? `<div class="card empty"><strong>วันนี้ไม่มีรอบที่ได้รับมอบหมาย</strong>${upcoming.length ? 'ดูงานที่จะถึงด้านล่าง' : 'ดูรอบที่ผ่านมาได้ที่เมนูประวัติ'}</div>`
    : trips.map((t) => `
      <a class="card card-link trip-card" href="${link(t)}">
        <div class="row-between">
          <span class="row"><span class="time" style="font-size:1.4rem;font-weight:700">${fmtTime(t.depart_time)}</span> <strong>${esc(t.route_name)}</strong></span>
          ${badge(t.status)}
        </div>
        <div class="meta">
          <span>รถ: ${esc(t.plate_no)} (${esc(t.type_name)})</span>
          <span>จองแล้ว <b>${t.booked_seats}</b> / ${t.seat_count} ที่นั่ง</span>
          <span>ถึงปลายทาง ${fmtTime(t.end_at)}</span>
        </div>
        <div class="small muted mt-2">สถานะรอบ: ${esc(t.status)} (${SUB[t.status] || ''})</div>
      </a>`).join('');

  if (!upcoming.length) return;
  let lastDate = null;
  document.getElementById('upcoming-trips').innerHTML = '<h2 class="section-title mt-4">งานที่จะถึง (7 วัน)</h2>' + upcoming.map((t) => {
    const head = t.trip_date !== lastDate ? `<h3 class="small muted mt-2 mb-0">${fmtDate(t.trip_date)}</h3>` : '';
    lastDate = t.trip_date;
    return `${head}<a class="card card-link trip-card" href="${link(t)}">
        <div class="row-between">
          <span class="row"><span class="time" style="font-weight:700">${fmtTime(t.depart_time)}</span> <strong>${esc(t.route_name)}</strong></span>
          <span class="small muted">จองแล้ว <b>${t.booked_seats}</b> / ${t.seat_count}</span>
        </div>
        <div class="meta"><span>รถ: ${esc(t.plate_no)} (${esc(t.type_name)})</span><span>ถึงปลายทาง ${fmtTime(t.end_at)}</span></div>
      </a>`;
  }).join('');
});
