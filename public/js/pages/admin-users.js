// 10.2 ผู้ใช้งาน / พนักงาน → CALL api_lookups / api_users_list (ลบ → CALL api_users_delete)
MUT.page(async ({ can }) => {
  const { esc, options } = MUT;
  const q = MUT.params();
  const [, , , , departments, positions] = await MUT.api('lookups');
  document.getElementById('q').value = q.q || '';
  document.getElementById('department').innerHTML = options(departments, 'department_id', 'department_name', q.department, 'ทั้งหมด');
  document.getElementById('position').innerHTML = options(positions, 'position_id', 'position_name', q.position, 'ทั้งหมด');
  document.getElementById('type').value = q.type || '';
  document.getElementById('add-btn').hidden = !can('SC07', 'add');

  const [rows] = await MUT.api('users_list', q);
  const box = document.getElementById('rows');
  if (!rows.length) {
    box.innerHTML = '<div class="card empty"><strong>ไม่พบผู้ใช้งาน</strong></div>';
    return;
  }
  box.innerHTML = `<div class="table-wrap"><table class="table">
      <thead><tr><th>รหัส</th><th>ชื่อ</th><th>email</th><th>username</th><th>แผนก</th><th>ตำแหน่ง</th><th>เบอร์โทร</th><th class="right">จัดการ</th></tr></thead>
      <tbody>${rows.map((u, i) => `<tr>
        <td class="mono">${esc(u.user_id)}</td><td>${esc(u.name)}</td><td>${esc(u.email)}</td><td>${esc(u.username)}</td>
        <td>${esc(u.department_name)}</td><td>${esc(u.position_name || '—')}</td><td class="nowrap">${esc(u.phone || '—')}</td>
        <td class="actions">
          ${can('SC07', 'edit') ? `<a class="btn btn-sm" href="/admin/user-form?id=${encodeURIComponent(u.user_id)}">แก้ไข</a>` : ''}
          ${can('SC07', 'delete') ? `<button class="btn btn-sm" style="color:var(--danger)" type="button" data-delete="${i}">ลบ</button>` : ''}
        </td>
      </tr>`).join('')}</tbody>
    </table></div>
    <p class="small muted mt-2">ทั้งหมด ${rows.length} คน</p>`;

  box.addEventListener('click', async (e) => {
    const btn = e.target.closest('[data-delete]');
    if (!btn) return;
    const u = rows[Number(btn.dataset.delete)];
    const ok = await MUT.confirmBox({
      title: `ลบผู้ใช้งาน ${u.user_id}?`, message: `${u.name} (${u.username})\nการลบไม่สามารถย้อนกลับได้`, ok: 'ลบ',
    });
    if (!ok) return;
    try {
      const [[r]] = await MUT.api('users_delete', { id: u.user_id });
      MUT.go(location.href, 'success', r.message);
    } catch (err) {
      MUT.flash('error', err.message);
    }
  });
});
