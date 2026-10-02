// 9.4 ปิดงาน → CALL api_driver_close_info แล้ว CALL api_driver_close
MUT.page(async () => {
  const { esc, fmtDate, fmtTime } = MUT;
  const id = MUT.param('id');
  const back = `/driver/trip?id=${encodeURIComponent(id)}`;
  document.getElementById('back-link').href = back;
  let data;
  try {
    data = await MUT.api('driver_close_info', { trip: id });
  } catch (err) {
    if (err.status === 400) return MUT.go(back, 'error', err.message);
    throw err;
  }
  const [[trip], [counts], noShows] = data;
  document.getElementById('trip-info').textContent =
    `${fmtDate(trip.trip_date)} · ${fmtTime(trip.depart_time)} · ${trip.route_name} · ${trip.plate_no}`;
  document.getElementById('k-checked').textContent = counts.checked_in;
  document.getElementById('k-noshow').textContent = noShows.length;
  document.getElementById('noshow-list').innerHTML = !noShows.length
    ? '<div class="card empty"><strong>ผู้โดยสารทุกคน Check-in แล้ว</strong></div>'
    : `<div class="table-wrap"><table class="table">
        <thead><tr><th>รายการจอง</th><th>ชื่อ</th><th>จุดขึ้น</th><th class="right">ที่นั่ง</th></tr></thead>
        <tbody>${noShows.map((n) => `<tr><td class="mono">${esc(n.booking_item_id)}</td><td>${esc(n.passenger_name)}</td>
          <td>${fmtTime(n.board_at)} ${esc(n.board_stop)}</td><td class="right">${n.seats}</td></tr>`).join('')}</tbody>
      </table></div>`;

  const btn = document.getElementById('close-btn');
  btn.disabled = false;
  btn.addEventListener('click', async () => {
    const ok = await MUT.confirmBox({
      title: `ยืนยันปิดงานรอบ ${fmtTime(trip.depart_time)}?`,
      message: `ผู้ใช้บริการจริง ${counts.checked_in} คน\nNo Show ${noShows.length} รายการ\nสถานะรอบจะเปลี่ยนเป็น เสร็จสิ้น และแก้ไขไม่ได้`,
      ok: 'ยืนยันปิดงาน',
    });
    if (!ok) return;
    try {
      const [[summary]] = await MUT.api('driver_close', { trip: trip.trip_id });
      MUT.go(back, 'success', `ปิดงานแล้ว — ผู้ใช้บริการจริง ${summary.actual_passengers} คน, No Show ${summary.no_show_items || 0} รายการ`);
    } catch (err) {
      MUT.flash('error', err.message);
    }
  });
});
