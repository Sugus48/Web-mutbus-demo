// 10.6 สิทธิ์ตามตำแหน่ง (Permission Matrix) → CALL api_permissions / api_permissions_save
MUT.page(async () => {
  const { esc, options } = MUT;
  const [positions, [position], screens] = await MUT.api('permissions', { position: MUT.param('position') });
  const select = document.getElementById('position');
  const form = document.getElementById('matrix-form');
  if (!position) {
    form.innerHTML = '<div class="card empty"><strong>ยังไม่มีตำแหน่ง</strong>เพิ่มตำแหน่งก่อนกำหนดสิทธิ์</div>';
    return;
  }
  select.innerHTML = options(positions, 'position_id', (p) => `${p.position_name} (${p.position_id})`, position.position_id);
  select.addEventListener('change', () => { location.href = `/admin/permissions?position=${encodeURIComponent(select.value)}`; });

  const editable = !!Number(position.editable);
  document.getElementById('matrix-caption').textContent = `สิทธิ์ของตำแหน่ง ${position.position_name}`;
  document.getElementById('reset-btn').href = `/admin/permissions?position=${encodeURIComponent(position.position_id)}`;
  document.getElementById('matrix-actions').hidden = !editable;
  document.getElementById('readonly-note').hidden = editable;

  const FLAGS = [['add', 'can_add', 'เพิ่ม'], ['edit', 'can_edit', 'แก้ไข'], ['delete', 'can_delete', 'ลบ']];
  const tbody = document.getElementById('matrix');
  tbody.innerHTML = screens.map((s) => {
    const on = !!Number(s.has_access);
    return `<tr data-screen="${esc(s.screen_id)}">
      <th scope="row" style="background:none;color:var(--text);font-weight:500"><span class="mono muted">${esc(s.screen_id)}</span> ${esc(s.screen_name)}</th>
      <td><input class="check" type="checkbox" data-flag="access" ${on ? 'checked' : ''} ${editable ? '' : 'disabled'} aria-label="เข้าถึง ${esc(s.screen_name)}"></td>
      ${FLAGS.map(([k, col, label]) => `<td><input class="check" type="checkbox" data-flag="${k}" ${on && Number(s[col]) ? 'checked' : ''}
        ${editable && on ? '' : 'disabled'} aria-label="${label} ${esc(s.screen_name)}"></td>`).join('')}
    </tr>`;
  }).join('');

  // ปิด "เข้าถึง" → ล้างและ disable เพิ่ม/แก้ไข/ลบ
  tbody.querySelectorAll('tr').forEach((row) => {
    const access = row.querySelector('[data-flag=access]');
    if (access.disabled) return;
    const flags = row.querySelectorAll('[data-flag]:not([data-flag=access])');
    const sync = () => flags.forEach((f) => { f.disabled = !access.checked; if (!access.checked) f.checked = false; });
    access.addEventListener('change', sync);
    sync();
  });

  // ส่งเป็นข้อความ 'SC01=1111;SC02=1000' (เข้าถึง เพิ่ม แก้ไข ลบ)
  MUT.bindForm(form, async () => {
    const matrix = [...tbody.querySelectorAll('tr')].map((row) => {
      const bit = (k) => (row.querySelector(`[data-flag=${k}]`).checked ? '1' : '0');
      return `${row.dataset.screen}=${bit('access')}${bit('add')}${bit('edit')}${bit('delete')}`;
    }).join(';');
    const [[r]] = await MUT.api('permissions_save', { position: position.position_id, matrix });
    MUT.go(location.href, 'success', r.message);
  });
});
