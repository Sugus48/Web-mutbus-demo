// 7.2 ค้นหารอบรถ → CALL api_search_form / api_search
MUT.page(async () => {
  const { esc, fmtDate, fmtTime, badge, qs, options } = MUT;
  const form = document.getElementById('search-form');
  const board = document.getElementById('board');
  const alight = document.getElementById('alight');
  const date = document.getElementById('date');
  const results = document.getElementById('results');

  const [stops, routeStops, [range]] = await MUT.api('search_form');
  const q = MUT.params();
  board.innerHTML = options(stops, 'stop_id', 'stop_name', q.board, '— เลือกจุดขึ้น —');
  alight.innerHTML = options(stops, 'stop_id', 'stop_name', q.alight, '— เลือกจุดลง —');
  date.min = range.min_date;
  date.max = range.max_date;
  date.value = q.date || range.min_date;
  const stopName = (id) => (stops.find((s) => s.stop_id === id) || {}).stop_name || id;

  // จำกัดตัวเลือกจุดลงให้อยู่หลังจุดขึ้นในเส้นทางใดเส้นทางหนึ่ง
  const sequences = {};
  routeStops.forEach((r) => (sequences[r.route_id] ||= []).push(r.stop_id));
  function limitAlight() {
    const allowed = new Set();
    Object.values(sequences).forEach((seq) => {
      const i = seq.indexOf(board.value);
      if (i >= 0) seq.slice(i + 1).forEach((s) => { if (s !== board.value) allowed.add(s); });
    });
    [...alight.options].forEach((o) => { if (o.value) o.disabled = !!board.value && !allowed.has(o.value); });
    if (alight.selectedOptions[0] && alight.selectedOptions[0].disabled) alight.value = '';
  }
  board.addEventListener('change', limitAlight);
  limitAlight();

  async function search(data) {
    const [rows] = await MUT.api('search', data);
    const day = MUT.dayName(data.date);
    const link = qs({ board: data.board, alight: data.alight });
    results.innerHTML = `
      <section class="section">
        <h2 class="section-title">รอบรถวัน${day}ที่ ${fmtDate(data.date)} (${rows.length} รอบ)</h2>
        ${rows.length ? '' : `<div class="card empty"><strong>ไม่พบรอบรถที่ตรงกับเงื่อนไข</strong>${
          ['เสาร์', 'อาทิตย์'].includes(day) ? `รถให้บริการเฉพาะวันทำการ — วัน${day}อาจไม่มีรอบ ลองเลือกวันจันทร์–ศุกร์` : 'ลองเปลี่ยนวันที่หรือจุดขึ้น–ลงแล้วค้นหาอีกครั้ง'}</div>`}
        ${rows.map((r) => {
          const full = r.remaining_seats <= 0;
          return `<article class="card trip-card">
            <div class="row-between"><strong>${esc(r.route_name)}</strong>${full ? badge('ที่นั่งเต็ม') : badge('เปิด')}</div>
            <div class="muted small">${fmtDate(r.trip_date)} · รถออก ${fmtTime(r.depart_time)}</div>
            <div class="times"><span class="time">${fmtTime(r.board_at)}</span><span class="arrow" aria-hidden="true"></span><span class="time">${fmtTime(r.alight_at)}</span></div>
            <div class="stop-names"><span>${esc(stopName(data.board))}</span><span class="right">${esc(stopName(data.alight))}</span></div>
            <div class="meta"><span>${esc(r.vehicle)}</span></div>
            <div class="foot">
              <span class="seats-left">เหลือ <b>${r.remaining_seats}</b> / ${r.seat_count} ที่นั่ง</span>
              <span class="btn-row">
                <a class="btn btn-sm" href="/trip${qs({ id: r.trip_id, board: data.board, alight: data.alight })}">ดูรายละเอียด</a>
                ${full ? '<button class="btn btn-sm btn-primary" disabled>จอง</button>'
                       : `<a class="btn btn-sm btn-primary" href="/book${qs({ id: r.trip_id })}${link.replace('?', '&')}">จอง</a>`}
              </span>
            </div>
          </article>`;
        }).join('')}
      </section>`;
  }

  MUT.bindForm(form, async (data) => {
    history.replaceState(null, '', '/search' + qs(data));
    try {
      await search(data);
    } catch (err) {
      results.innerHTML = '';
      throw err;
    }
  });
  if (q.board !== undefined) form.requestSubmit(); // กลับมาจากหน้ารายละเอียด → ค้นหาเดิมอีกครั้ง
});
