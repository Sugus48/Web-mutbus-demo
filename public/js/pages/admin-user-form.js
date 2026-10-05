// เพิ่ม/แก้ไขผู้ใช้งาน → CALL api_lookups / api_users_get / api_users_save
MUT.page(async ({ can }) => {
  const { options } = MUT;
  const id = MUT.param('id');
  const isNew = !id;
  if (!can('SC07', isNew ? 'add' : 'edit')) throw new MUT.ApiError(403, 'ตำแหน่งของคุณไม่มีสิทธิ์ใช้งานส่วนนี้');
  const [, , , , departments, positions] = await MUT.api('lookups');
  const v = isNew ? {} : (await MUT.api('users_get', { id }))[0][0];

  const form = document.getElementById('user-form');
  document.getElementById('form-title').textContent = isNew ? 'เพิ่มผู้ใช้งาน' : `แก้ไขผู้ใช้งาน ${id}`;
  document.title = `${isNew ? 'เพิ่ม' : 'แก้ไข'}ผู้ใช้งาน · BusBuddy`;
  if (!isNew) document.getElementById('password-label').textContent = 'Password (เว้นว่างถ้าไม่เปลี่ยน)';
  // ยืนยัน password: บังคับเมื่อเพิ่มใหม่ หรือเมื่อกรอก password ใหม่ตอนแก้ไข (api_users_save ตรวจซ้ำอีกชั้น)
  const syncConfirm = () => {
    form.password.required = isNew;
    form.confirm.required = isNew || form.password.value !== '';
  };
  form.password.addEventListener('input', syncConfirm);
  syncConfirm();
  for (const k of ['name', 'email', 'username', 'phone']) form[k].value = v[k] || '';
  const depSelect = document.getElementById('department_id');
  const posSelect = document.getElementById('position_id');
  depSelect.innerHTML = options(departments, 'department_id', 'department_name', v.department_id, '— เลือกแผนก —');

  // ตำแหน่งแสดงตามแผนกที่เลือก (ตำแหน่งที่ไม่ระบุแผนก = ใช้ได้ทุกแผนก)
  const syncPositions = (selected) => {
    const dep = depSelect.value;
    const list = dep ? positions.filter((p) => !p.department_id || p.department_id === dep) : [];
    const placeholder = !dep ? '— เลือกแผนกก่อน —' : list.length ? '— เลือกตำแหน่ง —' : '— แผนกนี้ยังไม่มีตำแหน่ง —';
    posSelect.innerHTML = options(list, 'position_id', 'position_name', selected, placeholder);
    posSelect.disabled = !list.length;
  };
  depSelect.addEventListener('change', () => syncPositions(posSelect.value));   // ตำแหน่งเดิมไม่อยู่ในแผนกใหม่ → ล้าง
  syncPositions(v.position_id);

  const toggle = document.getElementById('is_employee');
  const box = document.getElementById('employee-fields');
  toggle.checked = !!Number(v.is_employee);
  const sync = () => { box.hidden = !toggle.checked; };
  toggle.addEventListener('change', sync);
  sync();

  MUT.bindForm(form, async (data) => {
    const [[r]] = await MUT.api('users_save', { ...data, id });
    MUT.go('/admin/users', 'success', r.message);
  });
});
