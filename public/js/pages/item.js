// 8.3 รายละเอียดรายการจอง + QR Code → CALL api_item / api_cancel
MUT.page(async () => {
  const { esc, fmtDate, fmtTime, fmtDateTime, badge, icon } = MUT;
  const [[item]] = await MUT.api('item', { item: MUT.param('id') });
  const isNew = !!MUT.param('new');
  const cancelled = item.status === 'ยกเลิก';
  document.title = `รายการจอง ${item.booking_item_id} · MUT Shuttle`;
  const qr = await QRCode.toDataURL(item.qr_code, { width: 440, margin: 1 });

  document.getElementById('item-view').innerHTML = `
    ${isNew ? `<div class="success-head">
        <div class="check-circle">${icon('check')}</div>
        <h1 class="mb-0">จองสำเร็จ</h1><p class="muted">แสดง QR Code นี้ให้คนขับสแกนเมื่อขึ้นรถ</p>
      </div>` : `<a class="back-link no-print" href="/my">${icon('back')} การจองของฉัน</a>
      <div class="page-head row-between"><h1 class="mb-0">QR Code การจอง</h1>${badge(item.display_status)}</div>`}
    <div class="card center">
      <div class="qr-box ${cancelled ? 'cancelled' : ''}"><img src="${qr}" alt="QR Code รหัส ${esc(item.qr_code)}" width="220" height="220"></div>
      <div class="qr-code-text">รหัส QR: ${esc(item.qr_code)}</div>
      <div class="muted small">รหัสการจอง <span class="mono">${esc(item.booking_id)}</span> · รายการจอง <span class="mono">${esc(item.booking_item_id)}</span></div>
    </div>
    <div class="card">
      <dl class="dl">
        <dt>สถานะการจอง</dt><dd>${badge(item.display_status)}</dd>
        <dt>เส้นทาง</dt><dd>${esc(item.route_name)}</dd>
        <dt>วันที่เดินรถ</dt><dd>${fmtDate(item.trip_date)}</dd>
        <dt>เวลาออก</dt><dd>${fmtTime(item.depart_time)}</dd>
        <dt>จุดขึ้น</dt><dd>${esc(item.board_stop)} (ถึง ${fmtTime(item.board_at)})</dd>
        <dt>จุดลง</dt><dd>${esc(item.alight_stop)} (ถึง ${fmtTime(item.alight_at)})</dd>
        <dt>รถ</dt><dd>${esc(item.plate_no)} (${esc(item.type_name)})</dd>
        <dt>จำนวนที่นั่ง</dt><dd>${item.seats}</dd>
        <dt>วันที่และเวลาจอง</dt><dd>${fmtDateTime(item.booked_at)}</dd>
        ${item.checkin_at ? `<dt>Check-in</dt><dd>${fmtDateTime(item.checkin_at)}</dd>` : ''}
      </dl>
    </div>
    <div class="stack mt-4 no-print">
      ${cancelled ? '' : `<div class="btn-row">
          <a class="btn grow" href="${qr}" download="${esc(item.booking_item_id)}-QR.png">บันทึก QR</a>
          <button class="btn grow" type="button" onclick="window.print()">พิมพ์ QR</button>
        </div>`}
      <a class="btn btn-primary btn-block" href="/my">การจองของฉัน</a>
      <a class="btn btn-ghost btn-block" href="/">กลับหน้าหลัก</a>
      ${Number(item.can_cancel) ? '<button class="btn btn-block" style="color:var(--danger)" type="button" id="cancel-btn">ยกเลิกการจอง</button>' : ''}
    </div>`;

  const cancelBtn = document.getElementById('cancel-btn');
  if (cancelBtn) cancelBtn.addEventListener('click', () => MyBooking.cancel(item, '/my?tab=cancelled'));
});
