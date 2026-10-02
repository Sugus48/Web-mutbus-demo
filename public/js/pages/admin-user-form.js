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
  else form.password.required = true;
  for (const k of ['name', 'email', 'username', 'phone']) form[k].value = v[k] || '';
  document.getElementById('department_id').innerHTML = options(departments, 'department_id', 'department_name', v.department_id, '— เลือกแผนก —');
  document.getElementById('position_id').innerHTML = options(positions, 'position_id', 'position_name', v.position_id, '— เลือกตำแหน่ง —');

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
