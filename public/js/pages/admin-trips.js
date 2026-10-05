// 10.11 รอบการเดินรถ → CALL api_lookups / api_trips_list (ลบ → CALL api_trips_delete)
MUT.page(async ({ me, can, hasScreen }) => {
  const { esc, fmtDate, fmtTime, badge, options, qs } = MUT;
  const q = MUT.params();
  if (!location.search) q.date = me.today; // ค่าเริ่มต้น = รอบวันนี้
  const [, routes, vehicles, drivers] = await MUT.api('lookups');
  const form = document.getElementById('filter-form');
  form.q.value = q.q || '';
  form.driver_name.value = q.driver_name || '';
  form.date.value = q.q ? '' : (q.date || '');   // ค้นรหัสรอบ = ค้นทุกวัน (api_trips_list ไม่กรองวันที่)
  form.route.innerHTML = options(routes, 'route_id', 'route_name', q.route, 'ทั้งหมด');
  // ตัวกรองแสดงคนขับทุกสถานะ (ดูรอบย้อนหลังของคนที่ลาออกได้)
  form.driver.innerHTML = options(drivers, 'user_id', (d) => (d.status === 'ใช้งาน' ? d.name : `${d.name} (${d.status})`), q.driver, 'ทั้งหมด');
  form.vehicle.innerHTML = options(vehicles, 'vehicle_id', 'plate_no', q.vehicle, 'ทั้งหมด');
  form.status.value = q.status || '';
  const add = document.getElementById('add-btn');
  add.hidden = !can('SC06', 'add');
  add.href = '/admin/trip-form' + qs({ date: q.date });

  const [rows] = await MUT.api('trips_list', q);
  const box = document.getElementById('rows');
  if (!rows.length) {
    box.innerHTML = q.q
      ? `<div class="card empty"><strong>ไม่พบรอบรหัส "${esc(q.q)}"</strong>ตรวจสอบรหัสรอบ หรือล้างตัวกรองอื่น</div>`
      : '<div class="card empty"><strong>ไม่พบรอบการเดินรถ</strong>ลองเปลี่ยนตัวกรอง</div>';
    return;
  }
  box.innerHTML = `<div class="table-wrap"><table class="table">
      <thead><tr><th>รหัสรอบ</th><th>วันที่เดินรถ</th><th>เวลาออก</th><th>ถึงปลายทาง</th><th>เส้นทาง</th><th>คนขับ</th><th>รถ</th><th class="right">จองแล้ว</th><th>สถานะ</th><th class="right">จัดการ</th></tr></thead>
      <tbody>${rows.map((t, i) => `<tr>
        <td class="mono">${esc(t.trip_id)}</td><td class="nowrap">${fmtDate(t.trip_date)}</td>
        <td><b>${fmtTime(t.depart_time)}</b></td><td>${fmtTime(t.end_at)}</td>
        <td class="nowrap">${esc(t.route_name)}</td><td class="nowrap">${esc(t.driver_name)}</td>
        <td class="nowrap">${esc(t.plate_no)} <span class="muted small">(${esc(t.type_name)})</span></td>
        <td class="right nowrap">${t.booked_seats} / ${t.seat_count}</td><td>${badge(t.status)}</td>
        <td class="actions">
          ${hasScreen('SC02') ? `<a class="btn btn-sm btn-ghost" href="/admin/bookings?trip=${encodeURIComponent(t.trip_id)}">การจอง</a>` : ''}
          ${can('SC06', 'edit') ? `<a class="btn btn-sm" href="/admin/trip-form?id=${encodeURIComponent(t.trip_id)}">แก้ไข</a>` : ''}
          ${can('SC06', 'delete') ? `<button class="btn btn-sm" style="color:var(--danger)" type="button" data-delete="${i}">ลบ</button>` : ''}
        </td>
      </tr>`).join('')}</tbody>
    </table></div>
    <p class="small muted mt-2">ทั้งหมด ${rows.length} รอบ</p>`;

  box.addEventListener('click', async (e) => {
    const btn = e.target.closest('[data-delete]');
    if (!btn) return;
    const t = rows[Number(btn.dataset.delete)];
    const ok = await MUT.confirmBox({
      title: `ลบรอบ ${t.trip_id}?`,
      message: `${fmtDate(t.trip_date)} ${fmtTime(t.depart_time)} ${t.route_name}\nการลบไม่สามารถย้อนกลับได้`, ok: 'ลบ',
    });
    if (!ok) return;
    try {
      const [[r]] = await MUT.api('trips_delete', { id: t.trip_id });
      MUT.go(location.href, 'success', r.message);
    } catch (err) {
      MUT.flash('error', err.message);
    }
  });
});
