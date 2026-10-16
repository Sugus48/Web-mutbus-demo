// 7.1 หน้าหลัก → CALL api_home
MUT.page(async ({ me }) => {
  const { esc, fmtDate, fmtTime, badge, icon } = MUT;
  document.getElementById('user-name').textContent = me.name;   // textContent = ไม่ตีความเป็น HTML จึงไม่ต้อง esc
  // api_home: ชุดที่ 1 = การเดินทางครั้งถัดไป (ไม่มี = แถวว่าง), ชุดที่ 2 = จำนวนการจองที่กำลังจะถึง
  const [[next], [count]] = await MUT.api('home');
  document.getElementById('upcoming-count').textContent = count.n;
  // มีการเดินทางถัดไป → การ์ดสรุป + ปุ่มไปหน้า QR / ไม่มี → ข้อความชวนค้นหารอบรถ
  document.getElementById('next-trip').innerHTML = next ? `
    <article class="card trip-card">
      <div class="row-between"><strong>${esc(next.route_name)}</strong>${badge(next.display_status)}</div>
      <div class="muted small">${fmtDate(next.trip_date)} · รถออก ${fmtTime(next.depart_time)}</div>
      <div class="times">
        <span class="time">${fmtTime(next.board_at)}</span><span class="arrow" aria-hidden="true"></span><span class="time">${fmtTime(next.alight_at)}</span>
      </div>
      <div class="stop-names"><span>${esc(next.board_stop)}</span><span class="right">${esc(next.alight_stop)}</span></div>
      <div class="meta">
        <span>${esc(next.type_name)} ${esc(next.plate_no)}</span><span>${next.seats} ที่นั่ง</span>
        <span class="mono">${esc(next.booking_item_id)}</span>
      </div>
      <div class="foot">
        <span class="small muted">แสดง QR Code ให้คนขับสแกนตอนขึ้นรถ</span>
        <a class="btn btn-primary btn-sm" href="/item?id=${encodeURIComponent(next.booking_item_id)}">${icon('qr')} ดู QR</a>
      </div>
    </article>` : `
    <div class="card empty"><strong>ยังไม่มีการเดินทางที่กำลังจะถึง</strong>เริ่มค้นหารอบรถแล้วจองที่นั่งได้เลย</div>`;
});
