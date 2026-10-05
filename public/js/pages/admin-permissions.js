// 10.6 สิทธิ์ตามตำแหน่ง (Permission Matrix) → CALL api_permissions / api_permissions_save
// ?position=user = บทบาทคงที่ "ผู้ใช้ทั่วไป / นักศึกษา" (บัญชีที่สมัครเอง ไม่มีตำแหน่ง) — แสดงอย่างเดียว ไม่เรียก save
const GENERAL_ROLE = 'user';

// สิ่งที่บัญชีไม่มีตำแหน่งทำได้/ไม่ได้ — ตรงกับ procedure ฝั่งผู้ใช้บริการ (ไม่ตรวจสิทธิ์หน้าจอ แต่ดูได้เฉพาะข้อมูลของตัวเอง)
const GENERAL_ACCESS = [
  ['ค้นหารอบรถ และดูรายละเอียดรอบ', true],
  ['จองที่นั่ง (ครั้งละไม่เกิน 4 ที่นั่ง)', true],
  ['การจองของฉัน / QR Code ขึ้นรถ / ยกเลิกการจองของตัวเอง', true],
  ['โปรไฟล์ และเปลี่ยน password', true],
  ['หลังบ้านทุกหน้าจอ (SC01–SC11)', false],
  ['งานคนขับ (SC12)', false],
  ['ดูหรือแก้ไขการจองของผู้อื่น', false],
];

MUT.page(async ({ hasScreen }) => {
  const { esc, options } = MUT;
  const general = MUT.param('position') === GENERAL_ROLE;
  const [positions, [position], screens] = await MUT.api('permissions', { position: general ? null : MUT.param('position') });
  const select = document.getElementById('position');
  const form = document.getElementById('matrix-form');
  select.innerHTML = `<optgroup label="บทบาทพื้นฐาน">
      <option value="${GENERAL_ROLE}" ${general ? 'selected' : ''}>ผู้ใช้ทั่วไป / นักศึกษา (สมัครเอง)</option>
    </optgroup>
    <optgroup label="ตำแหน่งพนักงาน">${options(positions, 'position_id', (p) => `${p.position_name} (${p.position_id})`,
      general ? null : position?.position_id)}</optgroup>`;
  select.addEventListener('change', () => { location.href = `/admin/permissions?position=${encodeURIComponent(select.value)}`; });

  if (general) {
    form.hidden = true;
    document.getElementById('general-role').hidden = false;
    document.getElementById('general-rows').innerHTML = GENERAL_ACCESS.map(([label, ok]) => `<tr>
      <th scope="row" style="background:none;color:var(--text);font-weight:500">${esc(label)}</th>
      <td>${ok ? '<span class="badge badge-success">ได้</span>' : '<span class="badge badge-neutral">ไม่ได้</span>'}</td>
    </tr>`).join('');
    document.getElementById('general-users-link').hidden = !hasScreen('SC07');
    return;
  }
  if (!position) {
    form.innerHTML = '<div class="card empty"><strong>ยังไม่มีตำแหน่ง</strong>เพิ่มตำแหน่งก่อนกำหนดสิทธิ์</div>';
    return;
  }

  const editable = !!Number(position.editable);
  document.getElementById('matrix-caption').textContent = `สิทธิ์ของตำแหน่ง ${position.position_name}`;
  document.getElementById('reset-btn').href = `/admin/permissions?position=${encodeURIComponent(position.position_id)}`;
  document.getElementById('matrix-actions').hidden = !editable;
  document.getElementById('readonly-note').hidden = editable;

  const FLAGS = [['add', 'can_add', 'เพิ่ม'], ['edit', 'can_edit', 'แก้ไข'], ['delete', 'can_delete', 'ลบ']];
  // งานคนขับ (SC12) ระบบตรวจแค่ "เข้าถึง" — มีสิทธิ์นี้ = เป็นคนขับ (ไม่มีปุ่มเพิ่ม/แก้ไข/ลบ)
  const ACCESS_ONLY = ['SC12'];
  const tbody = document.getElementById('matrix');
  tbody.innerHTML = screens.map((s) => {
    const on = !!Number(s.has_access);
    const accessOnly = ACCESS_ONLY.includes(s.screen_id);
    return `<tr data-screen="${esc(s.screen_id)}">
      <th scope="row" style="background:none;color:var(--text);font-weight:500"><span class="mono muted">${esc(s.screen_id)}</span> ${esc(s.screen_name)}</th>
      <td><input class="check" type="checkbox" data-flag="access" ${on ? 'checked' : ''} ${editable ? '' : 'disabled'} aria-label="เข้าถึง ${esc(s.screen_name)}"></td>
      ${FLAGS.map(([k, col, label]) => (accessOnly ? '<td class="muted" title="หน้าจอนี้ใช้เฉพาะสิทธิ์เข้าถึง">—</td>'
        : `<td><input class="check" type="checkbox" data-flag="${k}" ${on && Number(s[col]) ? 'checked' : ''}
        ${editable && on ? '' : 'disabled'} aria-label="${label} ${esc(s.screen_name)}"></td>`)).join('')}
    </tr>`;
  }).join('');

  // ตำแหน่งที่เข้าถึง SC12 = คนขับ → แสดงคำอธิบาย (อัปเดตตามการติ๊ก)
  const driverAccess = tbody.querySelector('tr[data-screen="SC12"] [data-flag=access]');
  const driverNote = document.getElementById('driver-note');
  const syncDriverNote = () => { driverNote.hidden = !driverAccess?.checked; };
  driverAccess?.addEventListener('change', syncDriverNote);
  syncDriverNote();

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
      const bit = (k) => (row.querySelector(`[data-flag=${k}]`)?.checked ? '1' : '0');
      return `${row.dataset.screen}=${bit('access')}${bit('add')}${bit('edit')}${bit('delete')}`;
    }).join(';');
    const [[r]] = await MUT.api('permissions_save', { position: position.position_id, matrix });
    MUT.go(location.href, 'success', r.message);
  });
});
