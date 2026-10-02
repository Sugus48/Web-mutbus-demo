// รายละเอียดการจอง → CALL api_bookings_get
// ยกเลิกรายการ → api_bookings_cancel_item / เปลี่ยนสถานะ → api_bookings_set_status / ลบการจอง → api_bookings_delete
MUT.page(async ({ can }) => {
  const { esc, fmtDate, fmtTime, fmtDateTime, badge } = MUT;
  const [[b], items] = await MUT.api('bookings_get', { id: MUT.param('id') });
  document.title = `การจอง ${b.booking_id} · MUT Shuttle`;
  const editable = can('SC02', 'edit');
  const qrs = await Promise.all(items.map((i) => QRCode.toDataURL(i.qr_code, { width: 240, margin: 1 })));
  const STATUSES = ['ยืนยัน', 'ยกเลิก', 'No Show'];

  const view = document.getElementById('booking-view');
  view.innerHTML = `
    <div class="page-bar">
      <div><h1>การจอง <span class="mono">${esc(b.booking_id)}</span></h1><div class="muted">จองเมื่อ ${fmtDateTime(b.booked_at)}</div></div>
      ${can('SC02', 'delete') ? '<button class="btn btn-danger" type="button" id="delete-btn">ลบการจอง</button>' : ''}
    </div>
    <div class="card">
      <h2 class="card-title">ผู้จอง</h2>
      <dl class="dl">
        <dt>รหัสผู้ใช้งาน</dt><dd class="mono">${esc(b.user_id)}</dd><dt>ชื่อ</dt><dd>${esc(b.name)}</dd>
        <dt>Email</dt><dd>${esc(b.email)}</dd><dt>Username</dt><dd>${esc(b.username)}</dd><dt>แผนก</dt><dd>${esc(b.department_name)}</dd>
      </dl>
    </div>
    <h2 class="section-title mt-5">รายการจอง (${items.length})</h2>
    ${items.map((i, n) => `
      <div class="card">
        <div class="row" style="align-items:flex-start;gap:var(--s5)">
          <div class="center">
            <div class="qr-box ${i.status === 'ยกเลิก' ? 'cancelled' : ''}" style="padding:var(--s2)">
              <img src="${qrs[n]}" alt="QR Code รหัส ${esc(i.qr_code)}" style="width:140px;height:140px">
            </div>
            <div class="small mono mt-2">${esc(i.qr_code)}</div>
          </div>
          <div class="grow">
            <div class="row-between mb-2"><strong class="mono">${esc(i.booking_item_id)}</strong>${badge(i.display_status)}</div>
            <dl class="dl">
              <dt>รอบ</dt><dd><span class="mono">${esc(i.trip_id)}</span> · ${fmtDate(i.trip_date)} ${fmtTime(i.depart_time)} · ${esc(i.route_name)} ${badge(i.trip_status)}</dd>
              <dt>รถ</dt><dd>${esc(i.plate_no)} (${esc(i.type_name)})</dd>
              <dt>จุดขึ้น</dt><dd>${esc(i.board_stop)} (ถึง ${fmtTime(i.board_at)})</dd>
              <dt>จุดลง</dt><dd>${esc(i.alight_stop)} (ถึง ${fmtTime(i.alight_at)})</dd>
              <dt>จำนวนที่นั่ง</dt><dd>${i.seats}</dd>
              <dt>Check-in</dt><dd>${i.checkin_at ? fmtDateTime(i.checkin_at) : '—'}</dd>
            </dl>
            ${editable ? `<div class="btn-row mt-4">
              ${i.status === 'ยืนยัน' && !i.checkin_at ? `<button class="btn btn-sm" style="color:var(--danger)" type="button" data-cancel="${n}">ยกเลิกรายการ</button>` : ''}
              <span class="row" style="gap:var(--s2)">
                <label class="sr-only" for="st-${n}">เปลี่ยนสถานะ</label>
                <select class="input" id="st-${n}" style="min-height:34px;width:auto">${STATUSES.map((s) => `<option ${s === i.status ? 'selected' : ''}>${s}</option>`).join('')}</select>
                <button class="btn btn-sm" type="button" data-status="${n}">เปลี่ยนสถานะ</button>
              </span>
            </div>` : ''}
          </div>
        </div>
      </div>`).join('')}`;

  const run = async (name, data, next) => {
    try {
      const [[r]] = await MUT.api(name, data);
      MUT.go(next || location.href, 'success', r.message);
    } catch (err) {
      MUT.flash('error', err.message);
    }
  };
  view.addEventListener('click', async (e) => {
    const cancel = e.target.closest('[data-cancel]');
    const status = e.target.closest('[data-status]');
    if (cancel) {
      const i = items[Number(cancel.dataset.cancel)];
      const ok = await MUT.confirmBox({
        title: `ยกเลิกรายการจอง ${i.booking_item_id}?`,
        message: `ที่นั่ง ${i.seats} ที่จะถูกคืนให้รอบ ${fmtTime(i.depart_time)} ${i.route_name}`, ok: 'ยืนยันการยกเลิก',
      });
      if (ok) run('bookings_cancel_item', { item: i.booking_item_id });
    } else if (status) {
      const n = Number(status.dataset.status);
      run('bookings_set_status', { item: items[n].booking_item_id, status: document.getElementById(`st-${n}`).value });
    } else if (e.target.closest('#delete-btn')) {
      const ok = await MUT.confirmBox({
        title: `ลบการจอง ${b.booking_id}?`,
        message: `รายการจองทั้งหมด ${items.length} รายการภายใต้การจองนี้จะถูกลบด้วย\nการลบไม่สามารถย้อนกลับได้`, ok: 'ลบ',
      });
      if (ok) run('bookings_delete', { id: b.booking_id }, '/admin/bookings');
    }
  });
});
