// รายละเอียดเส้นทาง + Route diagram → CALL api_routes_get
MUT.page(async ({ can }) => {
  const { esc } = MUT;
  const [[route], stops] = await MUT.api('routes_get', { id: MUT.param('id') });
  document.title = `เส้นทาง ${route.route_name} · BusBuddy`;
  document.getElementById('route-view').innerHTML = `
    <div class="page-bar">
      <div>
        <h1>${esc(route.route_name)}</h1>
        <div class="muted"><span class="mono">${esc(route.route_id)}</span> · ${route.stop_count} จุดจอด · เวลารวม <b>${route.total_minutes} นาที</b>
          · ใช้ใน ${route.trip_total} รอบ (เปิดอยู่ ${route.trip_open})</div>
      </div>
      ${can('SC05', 'edit') ? `<a class="btn btn-primary" href="/admin/route-form?id=${encodeURIComponent(route.route_id)}">แก้ไขเส้นทาง</a>` : ''}
    </div>
    <div class="grid-2" style="align-items:start">
      <div class="card">
        <h2 class="card-title">Route diagram</h2>
        <ol class="route">${stops.map((s) => `
          <li class="in-seg">
            <span class="t">+${s.cum_minutes}</span><span class="dot" aria-hidden="true"></span>
            <span><span class="name">${esc(s.stop_name)}</span>
              <div class="sub">ลำดับ ${s.stop_order} · ${s.stop_order === 1 ? 'ต้นทาง' : `จากจุดก่อนหน้า ${s.travel_minutes} นาที`}</div></span>
          </li>`).join('')}</ol>
      </div>
      <div class="table-wrap"><table class="table">
        <thead><tr><th class="right">ลำดับ</th><th>จุดจอด</th><th class="right">เวลาจากจุดก่อนหน้า</th><th class="right">สะสม</th></tr></thead>
        <tbody>${stops.map((s) => `<tr><td class="right">${s.stop_order}</td><td><span class="mono muted">${esc(s.stop_id)}</span> ${esc(s.stop_name)}</td>
          <td class="right">${s.travel_minutes} นาที</td><td class="right">${s.cum_minutes} นาที</td></tr>`).join('')}</tbody>
        <tfoot><tr><td></td><td>เวลารวม</td><td class="right">${route.total_minutes} นาที</td><td></td></tr></tfoot>
      </table></div>
    </div>`;
});
