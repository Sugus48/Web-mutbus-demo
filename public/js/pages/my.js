// 8.4 การจองของฉัน → CALL api_my (ยกเลิก → CALL api_cancel)
MUT.page(async () => {
  const { esc, fmtDate, fmtTime, fmtDateTime, badge, icon } = MUT;
  const TABS = [
    { key: 'upcoming', label: 'กำลังจะถึง' },
    { key: 'done', label: 'เสร็จแล้ว' },
    { key: 'cancelled', label: 'ยกเลิก' },
  ];
  const tab = TABS.some((t) => t.key === MUT.param('tab')) ? MUT.param('tab') : 'upcoming';
  const [rows] = await MUT.api('my');
  const count = (k) => rows.filter((r) => r.tab === k).length;

  document.getElementById('tabs').innerHTML = TABS.map((t) =>
    `<a href="/my?tab=${t.key}" ${t.key === tab ? 'aria-current="page"' : ''}>${t.label} (${count(t.key)})</a>`).join('');

  let items = rows.filter((r) => r.tab === tab);
  if (tab === 'upcoming') items = items.reverse(); // ใกล้ที่สุดก่อน
  const box = document.getElementById('items');
  if (!items.length) {
    box.innerHTML = `<div class="card empty"><strong>ไม่มีรายการ</strong>${tab === 'upcoming' ? 'ยังไม่มีการจองที่กำลังจะถึง <a href="/search">ค้นหารอบรถ</a>' : ''}</div>`;
    return;
  }
  box.innerHTML = items.map((i, n) => {
    const tripCancelled = i.tab === 'cancelled' && i.status !== 'ยกเลิก';
    return `<article class="card trip-card">
      <div class="row-between"><strong>${esc(i.route_name)}</strong>${badge(tripCancelled ? 'ยกเลิก' : i.display_status)}</div>
      <div class="muted small"><span class="mono">${esc(i.booking_id)}</span> / <span class="mono">${esc(i.booking_item_id)}</span> · ${fmtDate(i.trip_date)}</div>
      <div class="times"><span class="time">${fmtTime(i.board_at)}</span><span class="arrow" aria-hidden="true"></span><span class="time">${fmtTime(i.alight_at)}</span></div>
      <div class="stop-names"><span>${esc(i.board_stop)}</span><span class="right">${esc(i.alight_stop)}</span></div>
      <div class="meta">
        <span>${i.seats} ที่นั่ง</span><span>${esc(i.plate_no)} (${esc(i.type_name)})</span>
        ${i.checkin_at ? `<span>Check-in ${fmtDateTime(i.checkin_at)}</span>` : ''}
        ${tripCancelled ? '<span>รอบนี้ถูกยกเลิก</span>' : ''}
      </div>
      <div class="foot"><span></span><span class="btn-row">
        ${Number(i.can_cancel) ? `<button class="btn btn-sm" style="color:var(--danger)" type="button" data-cancel="${n}">ยกเลิก</button>` : ''}
        <a class="btn btn-sm btn-primary" href="/item?id=${encodeURIComponent(i.booking_item_id)}">${icon('qr')} ดู QR</a>
      </span></div>
    </article>`;
  }).join('');

  box.addEventListener('click', (e) => {
    const btn = e.target.closest('[data-cancel]');
    if (btn) MyBooking.cancel(items[Number(btn.dataset.cancel)], '/my?tab=cancelled');
  });
});
