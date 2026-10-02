// 9.5 ประวัติรอบที่ขับ → CALL api_driver_history
MUT.page(async () => {
  const { esc, fmtDate, fmtTime, badge } = MUT;
  const [trips] = await MUT.api('driver_history');
  document.getElementById('history').innerHTML = !trips.length
    ? '<div class="card empty"><strong>ยังไม่มีประวัติ</strong></div>'
    : `<div class="table-wrap"><table class="table">
        <thead><tr><th>วันที่</th><th>เวลาออก</th><th>เส้นทาง</th><th>รถ</th><th class="right">จอง</th><th class="right">ผู้ใช้จริง</th><th class="right">No Show</th><th>สถานะ</th></tr></thead>
        <tbody>${trips.map((t) => `<tr>
          <td class="nowrap"><a href="/driver/trip?id=${encodeURIComponent(t.trip_id)}">${fmtDate(t.trip_date)}</a></td>
          <td>${fmtTime(t.depart_time)}</td><td class="nowrap">${esc(t.route_name)}</td><td class="nowrap">${esc(t.plate_no)}</td>
          <td class="right">${t.booked}</td><td class="right">${t.actual}</td><td class="right">${t.no_show}</td><td>${badge(t.status)}</td>
        </tr>`).join('')}</tbody>
      </table></div>`;
});
