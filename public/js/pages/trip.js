// 7.3 รายละเอียดรอบ + Route diagram → CALL api_trip
MUT.page(async () => {
  const { esc, fmtDate, fmtTime, badge, qs } = MUT;
  const ctx = await TripCtx.load();
  const { trip, stops, seg, board, alight } = ctx;
  document.title = `รอบ ${trip.trip_id} · BusBuddy`;
  document.getElementById('back-link').href = '/search' + qs({ board, alight, date: trip.trip_date });

  const b = seg.board && seg.board.stop_order;
  const a = seg.alight && seg.alight.stop_order;
  const route = stops.map((s) => {
    const cls = [];
    if (b && a && s.stop_order >= b && s.stop_order <= a) cls.push('in-seg');
    if (s.stop_order === b) cls.push('board');
    if (s.stop_order === a) cls.push('alight', 'seg-end');
    return `<li class="${cls.join(' ')}">
      <span class="t">${fmtTime(s.arrive_at)}</span><span class="dot" aria-hidden="true"></span>
      <span>
        <span class="name">${esc(s.stop_name)}</span>
        ${s.stop_order === b ? '<span class="tag">ขึ้น</span>' : ''}${s.stop_order === a ? '<span class="tag">ลง</span>' : ''}
        <div class="sub">ลำดับ ${s.stop_order}${s.stop_order > 1 ? ` · +${s.cum_minutes} นาทีจากต้นทาง` : ' · ต้นทาง'}</div>
      </span>
    </li>`;
  }).join('');

  document.getElementById('trip-view').innerHTML = `
    <div class="page-head row-between">
      <div><h1>${esc(trip.route_name)}</h1><div class="muted">${fmtDate(trip.trip_date)} · รถออก ${fmtTime(trip.depart_time)}</div></div>
      ${badge(trip.status)}
    </div>
    <div class="card">
      <dl class="dl">
        <dt>รหัสรอบ</dt><dd class="mono">${esc(trip.trip_id)}</dd>
        <dt>รถ</dt><dd>${esc(trip.plate_no)} (${esc(trip.type_name)})</dd>
        <dt>ที่นั่งคงเหลือ</dt><dd>${trip.seg_remaining} / ${trip.seat_count}${seg.board && seg.alight ? ' <span class="muted small">(ช่วงที่เลือก)</span>' : ''}</dd>
        <dt>เวลารวมของเส้นทาง</dt><dd>${trip.total_minutes} นาที</dd>
        ${seg.board && seg.alight ? `<dt>ช่วงที่เลือก</dt><dd>${esc(seg.board.stop_name)} ${fmtTime(seg.board.arrive_at)} → ${esc(seg.alight.stop_name)} ${fmtTime(seg.alight.arrive_at)}</dd>` : ''}
      </dl>
    </div>
    <section class="section">
      <h2 class="section-title">เส้นทางและเวลาถึงแต่ละจุดจอด</h2>
      <div class="card"><ol class="route">${route}</ol></div>
    </section>
    <div class="section">
      ${trip.blocked
        ? `<div class="alert alert-warning">${esc(trip.blocked)}</div><button class="btn btn-primary btn-block" disabled>จองรอบนี้</button>`
        : `<a class="btn btn-primary btn-block" href="/book${qs({ id: trip.trip_id, board, alight })}">จองรอบนี้</a>`}
    </div>`;
});
