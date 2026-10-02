// 10.10 เส้นทาง → CALL api_routes_list (ลบ → CALL api_routes_delete)
MUT.page(async ({ can }) => {
  const { esc } = MUT;
  const q = MUT.params();
  document.getElementById('q').value = q.q || '';
  document.getElementById('add-btn').hidden = !can('SC05', 'add');
  const [rows] = await MUT.api('routes_list', q);
  const box = document.getElementById('rows');
  if (!rows.length) {
    box.innerHTML = '<div class="card empty"><strong>ไม่พบเส้นทาง</strong></div>';
    return;
  }
  const link = (r) => `/admin/route?id=${encodeURIComponent(r.route_id)}`;
  box.innerHTML = `<div class="table-wrap"><table class="table">
      <thead><tr><th>รหัสเส้นทาง</th><th>ชื่อเส้นทาง</th><th class="right">จำนวนจุดจอด</th><th class="right">เวลารวม</th><th class="right">จำนวนรอบ</th><th class="right">จัดการ</th></tr></thead>
      <tbody>${rows.map((r, i) => `<tr>
        <td class="mono">${esc(r.route_id)}</td><td><a href="${link(r)}">${esc(r.route_name)}</a></td>
        <td class="right">${r.stop_count}</td><td class="right">${r.total_minutes} นาที</td><td class="right">${r.trip_count}</td>
        <td class="actions">
          <a class="btn btn-sm btn-ghost" href="${link(r)}">ดู</a>
          ${can('SC05', 'edit') ? `<a class="btn btn-sm" href="/admin/route-form?id=${encodeURIComponent(r.route_id)}">แก้ไข</a>` : ''}
          ${can('SC05', 'delete') ? `<button class="btn btn-sm" style="color:var(--danger)" type="button" data-delete="${i}">ลบ</button>` : ''}
        </td>
      </tr>`).join('')}</tbody>
    </table></div>`;

  box.addEventListener('click', async (e) => {
    const btn = e.target.closest('[data-delete]');
    if (!btn) return;
    const r = rows[Number(btn.dataset.delete)];
    const ok = await MUT.confirmBox({
      title: `ลบเส้นทาง ${r.route_id}?`, message: `${r.route_name} และลำดับจุดจอดทั้งหมด\nการลบไม่สามารถย้อนกลับได้`, ok: 'ลบ',
    });
    if (!ok) return;
    try {
      const [[res]] = await MUT.api('routes_delete', { id: r.route_id });
      MUT.go(location.href, 'success', res.message);
    } catch (err) {
      MUT.flash('error', err.message);
    }
  });
});
