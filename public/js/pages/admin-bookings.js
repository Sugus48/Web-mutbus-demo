// 10.12 การจอง → CALL api_bookings_list
MUT.page(async () => {
  const { esc, fmtDate, fmtTime, fmtDateTime, badge, options } = MUT;
  const q = MUT.params();
  const [rows, routes] = await MUT.api('bookings_list', q);
  const form = document.getElementById('filter-form');
  for (const k of ['q', 'from', 'to', 'status', 'trip']) form[k].value = q[k] || '';
  form.route.innerHTML = options(routes, 'route_id', 'route_name', q.route, 'ทั้งหมด');
  if (q.trip) {
    document.getElementById('trip-filter-note').innerHTML =
      `เฉพาะรอบ <span class="mono">${esc(q.trip)}</span> · <a href="/admin/bookings">ดูทั้งหมด</a>`;
  }

  const box = document.getElementById('rows');
  if (!rows.length) {
    box.innerHTML = '<div class="card empty"><strong>ไม่พบรายการจอง</strong></div>';
    return;
  }
  const link = (i) => `/admin/booking?id=${encodeURIComponent(i.booking_id)}`;
  box.innerHTML = `<div class="table-wrap"><table class="table">
      <thead><tr><th>การจอง</th><th>รายการจอง</th><th>ผู้จอง</th><th>วันที่และเวลาจอง</th><th>รอบ</th><th>จุดขึ้น → จุดลง</th><th class="right">ที่นั่ง</th><th>สถานะ</th><th>Check-in</th><th class="right">จัดการ</th></tr></thead>
      <tbody>${rows.map((i) => `<tr>
        <td class="mono"><a href="${link(i)}">${esc(i.booking_id)}</a></td><td class="mono">${esc(i.booking_item_id)}</td>
        <td class="nowrap">${esc(i.passenger_name)}</td><td class="nowrap">${fmtDateTime(i.booked_at)}</td>
        <td class="nowrap">${fmtDate(i.trip_date)} ${fmtTime(i.depart_time)}<br><span class="small muted">${esc(i.route_name)} · ${esc(i.trip_id)}</span></td>
        <td>${esc(i.board_stop)} → ${esc(i.alight_stop)}</td><td class="right">${i.seats}</td>
        <td>${badge(i.display_status)}</td><td class="nowrap">${i.checkin_at ? fmtTime(i.checkin_at) : '—'}</td>
        <td class="actions"><a class="btn btn-sm" href="${link(i)}">รายละเอียด</a></td>
      </tr>`).join('')}</tbody>
    </table></div>
    <p class="small muted mt-2">ทั้งหมด ${rows.length} รายการ</p>`;
});
