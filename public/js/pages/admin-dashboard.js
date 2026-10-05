// 10.1 Dashboard → CALL api_dashboard
MUT.page(async ({ hasScreen }) => {
  const { esc, fmtDate, fmtTime, fmtDateTime, badge } = MUT;
  const [[k], trips, latest] = await MUT.api('dashboard');
  document.getElementById('today-info').textContent = `ข้อมูลวันที่ ${fmtDate(k.today)}`;
  const kpi = (label, value, style = '') => `<div class="kpi"><div class="k-label">${label}</div><div class="k-value" ${style}>${value}</div></div>`;
  document.getElementById('kpis').innerHTML = [
    kpi('รายการจองวันนี้', k.items_today),
    kpi('รอบรถวันนี้', k.trips_today),
    kpi('ที่นั่งที่ถูกจองวันนี้', k.seats_today),
    kpi('ผู้ใช้บริการจริง (Check-in)', k.checkin_today, 'style="color:var(--success)"'),
    kpi('No Show', k.noshow_today, 'style="color:var(--warning)"'),
    kpi('รถพร้อมใช้งาน', `${k.vehicles_ready}<span class="small muted"> / ${k.vehicles_total}</span>`),
  ].join('');

  // รอบวันนี้ / รายการจองล่าสุด แสดงเฉพาะผู้มีสิทธิ์หน้าจอนั้น (api_dashboard คืนชุดว่างให้ผู้ไม่มีสิทธิ์)
  document.getElementById('trips-section').hidden = !hasScreen('SC06');
  document.getElementById('latest-section').hidden = !hasScreen('SC02');
  document.getElementById('trips-link').href = `/admin/trips?date=${k.today}`;

  document.getElementById('today-trips').innerHTML = !trips.length
    ? '<div class="card empty"><strong>วันนี้ยังไม่มีรอบการเดินรถ</strong></div>'
    : `<div class="table-wrap"><table class="table">
        <thead><tr><th>เวลา</th><th>เส้นทาง</th><th>คนขับ</th><th>รถ</th><th class="right">จองแล้ว</th><th>สถานะ</th></tr></thead>
        <tbody>${trips.map((t) => `<tr>
          <td class="nowrap"><b>${fmtTime(t.depart_time)}</b>–${fmtTime(t.end_at)}</td>
          <td>${esc(t.route_name)}</td><td>${esc(t.driver_name)}</td>
          <td class="nowrap">${esc(t.plate_no)} <span class="muted small">(${esc(t.type_name)})</span></td>
          <td class="right">${t.booked_seats} / ${t.seat_count}</td><td>${badge(t.status)}</td>
        </tr>`).join('')}</tbody></table></div>`;

  document.getElementById('latest').innerHTML = !latest.length
    ? '<div class="card empty"><strong>ยังไม่มีการจอง</strong></div>'
    : `<div class="table-wrap"><table class="table">
        <thead><tr><th>รายการจอง</th><th>ผู้จอง</th><th>วันที่จอง</th><th>รอบ</th><th>จุดขึ้น → จุดลง</th><th class="right">ที่นั่ง</th><th>สถานะ</th></tr></thead>
        <tbody>${latest.map((i) => `<tr>
          <td class="mono">${esc(i.booking_item_id)}</td><td>${esc(i.passenger_name)}</td>
          <td class="nowrap">${fmtDateTime(i.booked_at)}</td><td class="nowrap">${fmtDate(i.trip_date)} ${fmtTime(i.depart_time)}</td>
          <td>${esc(i.board_stop)} → ${esc(i.alight_stop)}</td><td class="right">${i.seats}</td><td>${badge(i.display_status)}</td>
        </tr>`).join('')}</tbody></table></div>`;
});
