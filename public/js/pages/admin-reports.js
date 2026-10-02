// 11. รายงาน 1–7 → CALL api_report(ปี, ช่วงวันที่)
// SQL คืนข้อมูลที่สรุปแล้ว — ไฟล์นี้จัดเป็นการ์ดสรุป + กราฟ (Chart.js) + ตาราง + Export CSV
MUT.page(async () => {
  const { esc, fmtDate, fmtTime, fmtNum, DAY_NAMES } = MUT;
  const MONTHS = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
  const num = (v) => Number(v || 0);
  const sum = (rows, k) => rows.reduce((n, r) => n + num(r[k]), 0);
  const right = (key, label) => ({ key, label, align: 'right' });

  // แต่ละรายงาน: ตัวกรอง (year / range) + build(ชุดข้อมูลจาก SQL, ค่าที่ใช้) → { note, cards, columns, rows, totals, charts }
  const REPORTS = {
    1: {
      title: 'เปรียบเทียบจำนวนคนขึ้น–ลงรถรายปี', filter: 'year',
      build([data], { year_ad: year }) {
        const rows = [];
        const section = (type) => {
          const list = data.filter((r) => r.type === type).map((r) => {
            const row = { type, stop_name: r.stop_name, total: num(r.total) };
            MONTHS.forEach((_, i) => { row[`m${i + 1}`] = num(r[`m${i + 1}`]); });
            return row;
          });
          const subtotal = { type, stop_name: `รวม${type}`, _subtotal: true, total: sum(list, 'total') };
          MONTHS.forEach((_, i) => { subtotal[`m${i + 1}`] = sum(list, `m${i + 1}`); });
          rows.push(...list, subtotal);
          return { list, subtotal };
        };
        const board = section('ขึ้นรถ');
        const alight = section('ลงรถ');
        const busiest = [...board.list].sort((a, b) => b.total - a.total)[0];
        const chartOf = (label, list) => ({
          title: `จำนวนผู้โดยสาร ${label} รายเดือน ปี ${year + 543} (ทุกสถานี)`,
          labels: MONTHS,
          datasets: list.map((r) => ({ label: r.stop_name, data: MONTHS.map((_, i) => r[`m${i + 1}`]) })),
        });
        return {
          note: 'นับเฉพาะผู้โดยสารที่ Check-in แล้ว (หน่วย: คน/ที่นั่ง) จัดกลุ่มตามเดือนของวันที่เดินรถ',
          cards: [['ขึ้นรถทั้งปี', board.subtotal.total], ['ลงรถทั้งปี', alight.subtotal.total],
            ['จุดขึ้นรถมากที่สุด', busiest && busiest.total ? busiest.stop_name : '-']],
          columns: [{ key: 'type', label: 'ประเภท' }, { key: 'stop_name', label: 'จุดจอด' },
            ...MONTHS.map((m, i) => right(`m${i + 1}`, m)), right('total', 'รวมทั้งปี')],
          rows,
          charts: [chartOf('ขึ้น', board.list), chartOf('ลง', alight.list)],
        };
      },
    },
    2: {
      title: 'สถิติการจองรายปี', filter: 'year',
      build([data]) {
        const keys = ['bookings', 'booking_items', 'booked_seats', 'cancelled', 'checked_in', 'no_show'];
        const rows = data.map((r) => ({ month: MONTHS[r.month_no - 1], ...Object.fromEntries(keys.map((k) => [k, num(r[k])])) }));
        const totals = { month: 'รวมทั้งปี', ...Object.fromEntries(keys.map((k) => [k, sum(rows, k)])) };
        return {
          note: 'จัดกลุ่มตามเดือนของวันที่เดินรถ',
          cards: [['การจอง', totals.bookings], ['รายการจอง', totals.booking_items], ['ที่นั่งที่จอง', totals.booked_seats],
            ['ยกเลิก', totals.cancelled], ['Check-in', totals.checked_in], ['No Show', totals.no_show]],
          columns: [{ key: 'month', label: 'เดือน' }, right('bookings', 'การจอง'), right('booking_items', 'รายการจอง'),
            right('booked_seats', 'ที่นั่งที่จอง'), right('cancelled', 'ยกเลิก'), right('checked_in', 'Check-in'), right('no_show', 'No Show')],
          rows, totals,
          chart: { labels: MONTHS, datasets: [{ label: 'ที่นั่งที่จอง', data: rows.map((r) => r.booked_seats) }] },
        };
      },
    },
    3: {
      title: 'พฤติกรรมผู้ใช้ตามช่วงวันที่', filter: 'range',
      build([rows]) {
        const top = rows.slice(0, 10);
        return {
          note: 'จำนวนรายการจองแยกตามผู้ใช้ (จองทั้งหมด / ขึ้นรถจริง / ยกเลิก / No Show)',
          cards: [['ผู้ใช้ที่จอง', rows.length], ['จองทั้งหมด', sum(rows, 'total_items')], ['ขึ้นรถจริง', sum(rows, 'boarded')],
            ['ยกเลิก', sum(rows, 'cancelled')], ['No Show', sum(rows, 'no_show')]],
          columns: [{ key: 'user_id', label: 'รหัส' }, { key: 'name', label: 'ชื่อ' }, right('total_items', 'จองทั้งหมด'),
            right('boarded', 'ขึ้นรถจริง'), right('cancelled', 'ยกเลิก'), right('no_show', 'No Show')],
          rows,
          totals: { name: 'รวม', total_items: sum(rows, 'total_items'), boarded: sum(rows, 'boarded'),
            cancelled: sum(rows, 'cancelled'), no_show: sum(rows, 'no_show') },
          chart: { labels: top.map((r) => r.name), caption: 'ผู้ใช้ 10 อันดับแรก',
            datasets: [{ label: 'จองทั้งหมด', data: top.map((r) => num(r.total_items)) }, { label: 'ขึ้นรถจริง', data: top.map((r) => num(r.boarded)) }] },
        };
      },
    },
    4: {
      title: 'สรุปยอดผู้ใช้แต่ละเส้นทางรายวัน', filter: 'range',
      build([routes, data]) {
        const order = [2, 3, 4, 5, 6, 7, 1]; // จันทร์ → อาทิตย์ (DAYOFWEEK: 1 = อาทิตย์)
        const rows = order.map((dow) => {
          const r = { day: DAY_NAMES[dow - 1], total: 0 };
          for (const rt of routes) {
            const v = num((data.find((d) => Number(d.dow_no) === dow && d.route_id === rt.route_id) || {}).passengers);
            r[rt.route_id] = v;
            r.total += v;
          }
          return r;
        });
        const totals = { day: 'รวม', total: sum(rows, 'total') };
        routes.forEach((rt) => { totals[rt.route_id] = sum(rows, rt.route_id); });
        return {
          note: 'ผู้ใช้บริการจริง (Check-in) รวมตามวันในสัปดาห์ — วันเดียวกันในช่วงที่เลือกถูกรวมกัน',
          cards: [['ผู้ใช้บริการรวม', totals.total], ...routes.slice(0, 4).map((rt) => [rt.route_name, totals[rt.route_id]])],
          columns: [{ key: 'day', label: 'วัน' }, ...routes.map((rt) => right(rt.route_id, rt.route_name)), right('total', 'รวมทั้งวัน')],
          rows, totals,
          chart: { labels: rows.map((r) => r.day), datasets: routes.slice(0, 8).map((rt) => ({ label: rt.route_name, data: rows.map((r) => r[rt.route_id]) })) },
        };
      },
    },
    5: {
      title: 'การใช้บริการแต่ละจุดจอดตามรอบเวลา', filter: 'range',
      build([data]) {
        const rows = data.map((r) => ({ stop_name: r.stop_name, pass_time: fmtTime(r.pass_time), boarding: num(r.boarding), alighting: num(r.alighting) }));
        const byStop = [];
        for (const r of rows) {
          let s = byStop.find((x) => x.stop_name === r.stop_name);
          if (!s) byStop.push((s = { stop_name: r.stop_name, boarding: 0, alighting: 0 }));
          s.boarding += r.boarding;
          s.alighting += r.alighting;
        }
        return {
          note: 'เรียงตามจุดจอด แล้วตามเวลาที่รถผ่าน (นับเฉพาะผู้ที่ Check-in)',
          cards: [['ขึ้นรถรวม', sum(rows, 'boarding')], ['ลงรถรวม', sum(rows, 'alighting')], ['จำนวนรอบเวลา×จุดจอด', rows.length]],
          columns: [{ key: 'stop_name', label: 'จุดจอด' }, { key: 'pass_time', label: 'เวลาที่รถผ่าน' }, right('boarding', 'ขึ้นรถ'), right('alighting', 'ลงรถ')],
          rows,
          totals: { stop_name: 'รวม', boarding: sum(rows, 'boarding'), alighting: sum(rows, 'alighting') },
          chart: { labels: byStop.map((s) => s.stop_name), caption: 'รวมทุกรอบเวลาของแต่ละจุดจอด',
            datasets: [{ label: 'ขึ้นรถ', data: byStop.map((s) => s.boarding) }, { label: 'ลงรถ', data: byStop.map((s) => s.alighting) }] },
        };
      },
    },
    6: {
      title: 'สรุปการมอบหมายงานคนขับ', filter: 'range',
      build([rows]) {
        return {
          note: 'แบ่งตามเวลาออกของรอบ ก่อน 17:00 / ตั้งแต่ 17:00 (ไม่นับรอบที่ยกเลิก)',
          cards: [['คนขับ', rows.length], ['รอบทั้งหมด', sum(rows, 'total_trips')], ['ก่อน 17:00', sum(rows, 'before_1700')], ['หลัง 17:00', sum(rows, 'after_1700')]],
          columns: [{ key: 'user_id', label: 'รหัส' }, { key: 'name', label: 'คนขับ' }, right('before_1700', 'ก่อน 17:00'),
            right('after_1700', 'หลัง 17:00'), right('total_trips', 'รวม')],
          rows,
          totals: { name: 'รวม', before_1700: sum(rows, 'before_1700'), after_1700: sum(rows, 'after_1700'), total_trips: sum(rows, 'total_trips') },
          chart: { labels: rows.map((r) => r.name),
            datasets: [{ label: 'ก่อน 17:00', data: rows.map((r) => num(r.before_1700)) }, { label: 'หลัง 17:00', data: rows.map((r) => num(r.after_1700)) }] },
        };
      },
    },
    7: {
      title: 'จำนวนการมอบหมายงานให้รถแต่ละประเภท', filter: 'range',
      build([data]) {
        const rows = [];
        const types = [...new Set(data.map((d) => d.type_name))];
        for (const type of types) {
          const list = data.filter((d) => d.type_name === type);
          list.forEach((d) => rows.push({ type_name: d.type_name, plate_no: d.plate_no, trips: num(d.trips) }));
          rows.push({ type_name: `รวม${type}`, plate_no: '', trips: sum(list, 'trips'), _subtotal: true });
        }
        const detail = rows.filter((r) => !r._subtotal);
        return {
          note: 'จำนวนรอบที่รถแต่ละคันได้รับมอบหมาย (ไม่นับรอบที่ยกเลิก)',
          cards: [['รอบทั้งหมด', sum(detail, 'trips')], ...types.slice(0, 4).map((t) => [t, sum(detail.filter((r) => r.type_name === t), 'trips')])],
          columns: [{ key: 'type_name', label: 'ประเภทรถ' }, { key: 'plate_no', label: 'ทะเบียน' }, right('trips', 'จำนวนรอบ')],
          rows,
          totals: { type_name: 'รวมทั้งหมด', trips: sum(detail, 'trips') },
          chart: { labels: detail.map((r) => `${r.plate_no} (${r.type_name})`), datasets: [{ label: 'จำนวนรอบ', data: detail.map((r) => r.trips) }] },
        };
      },
    },
  };

  const q = MUT.params();
  const id = REPORTS[q.r] ? Number(q.r) : 1;
  const report = REPORTS[id];
  const [[p], ...sets] = await MUT.api('report', { report: String(id), year: q.year, from: q.from, to: q.to });
  const result = report.build(sets, p);

  // หัวข้อ เมนู ตัวกรอง
  document.title = `รายงาน ${id} · BusBuddy`;
  document.getElementById('report-title').textContent = `รายงาน ${id}: ${report.title}`;
  document.getElementById('report-menu').innerHTML = Object.entries(REPORTS).map(([k, r]) =>
    `<a class="chip" href="/admin/reports?r=${k}" ${Number(k) === id ? 'aria-current="page"' : ''}>${k}. ${esc(r.title)}</a>`).join('');
  const form = document.getElementById('filter-form');
  form.r.value = id;
  form.year.value = p.year_ad + 543;
  form.from.value = p.date_from;
  form.to.value = p.date_to;
  form.querySelectorAll('[data-filter]').forEach((el) => {
    el.hidden = el.dataset.filter !== report.filter;
    el.querySelectorAll('input').forEach((i) => { i.disabled = el.hidden; });
  });
  const period = report.filter === 'year' ? `ปี ${p.year_ad + 543}` : `${fmtDate(p.date_from)} – ${fmtDate(p.date_to)}`;
  document.getElementById('report-note').textContent = `${result.note} · ${period}`;

  // การ์ดสรุป
  document.getElementById('cards').innerHTML = result.cards.map(([label, value]) =>
    `<div class="kpi"><div class="k-label">${esc(label)}</div><div class="k-value">${esc(fmtNum(value))}</div></div>`).join('');

  // ตาราง
  const cell = (c, v) => `<td class="${c.align || ''}">${esc(v ?? '')}</td>`;
  document.getElementById('report-table').innerHTML = `
    <caption class="sr-only">ตาราง${esc(report.title)}</caption>
    <thead><tr>${result.columns.map((c) => `<th class="${c.align || ''}" scope="col">${esc(c.label)}</th>`).join('')}</tr></thead>
    <tbody>${result.rows.length ? result.rows.map((r) => `<tr ${r._subtotal ? 'style="font-weight:700;background:var(--surface-2)"' : ''}>${
      result.columns.map((c) => cell(c, r[c.key])).join('')}</tr>`).join('')
      : `<tr><td colspan="${result.columns.length}" class="center muted">ไม่มีข้อมูล</td></tr>`}</tbody>
    ${result.totals ? `<tfoot><tr>${result.columns.map((c) => cell(c, result.totals[c.key])).join('')}</tr></tfoot>` : ''}`;

  // Export CSV (BOM ให้ Excel อ่านภาษาไทยได้)
  const csvBtn = document.getElementById('csv-btn');
  csvBtn.disabled = false;
  csvBtn.addEventListener('click', () => {
    const csvEsc = (v) => `"${String(v ?? '').replace(/"/g, '""')}"`;
    const lines = [result.columns.map((c) => csvEsc(c.label)).join(',')];
    for (const r of [...result.rows, ...(result.totals ? [result.totals] : [])]) lines.push(result.columns.map((c) => csvEsc(r[c.key])).join(','));
    const blob = new Blob([`﻿${lines.join('\r\n')}`], { type: 'text/csv;charset=utf-8' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `report-${id}-${report.filter === 'year' ? p.year_ad : `${p.date_from}_${p.date_to}`}.csv`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  });

  // กราฟ
  const charts = result.charts || [{ ...result.chart, title: report.title }];
  const hasData = charts.some((c) => c.datasets.some((d) => d.data.some((v) => v > 0)));
  document.getElementById('charts').innerHTML = charts.map((c, i) => `
    <div class="card mb-4">
      <h2 class="card-title">${esc(c.title)}${c.caption ? ` <span class="muted small">— ${esc(c.caption)}</span>` : ''}</h2>
      ${hasData ? `<div class="chart-box"><canvas id="chart-${i}" role="img" aria-label="กราฟ ${esc(c.title)} (ข้อมูลเดียวกับตารางด้านล่าง)"></canvas></div>`
                : '<div class="empty"><strong>ไม่มีข้อมูลในช่วงที่เลือก</strong>ลองเปลี่ยนปีหรือช่วงวันที่</div>'}
    </div>`).join('');
  if (!hasData || typeof Chart === 'undefined') return;

  // ลำดับสี categorical คงที่ (ไม่วนสี)
  const SERIES = ['#2a78d6', '#eb6834', '#1baf7a', '#eda100', '#e87ba4', '#008300', '#4a3aa7', '#e34948'];
  Chart.defaults.font.family = getComputedStyle(document.documentElement).getPropertyValue('--font');
  Chart.defaults.color = '#52514e';
  charts.forEach((chart, n) => new Chart(document.getElementById(`chart-${n}`), {
    type: 'bar',
    data: {
      labels: chart.labels,
      datasets: chart.datasets.map((d, i) => ({
        ...d, backgroundColor: SERIES[i % SERIES.length], borderRadius: 4, borderSkipped: 'bottom', maxBarThickness: 36,
        borderColor: '#ffffff', borderWidth: 1,
      })),
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      interaction: { mode: 'index', intersect: false },
      plugins: {
        legend: { display: chart.datasets.length > 1, position: 'top', align: 'start', labels: { boxWidth: 12, boxHeight: 12, useBorderRadius: true, borderRadius: 3 } },
        tooltip: { backgroundColor: '#0b0b0b', padding: 10, boxPadding: 4 },
      },
      scales: {
        x: { grid: { display: false }, ticks: { color: '#52514e' } },
        y: { beginAtZero: true, grid: { color: '#eceae6' }, border: { display: false }, ticks: { precision: 0, color: '#898781' } },
      },
    },
  }));
});
