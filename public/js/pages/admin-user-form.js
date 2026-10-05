// เพิ่ม/แก้ไขผู้ใช้งาน → CALL api_lookups / api_users_get / api_users_save

// สถานะบัญชีที่เลือกได้ตามประเภท + คำอธิบาย (api_users_save ตรวจซ้ำอีกชั้น)
const STATUS_EMPLOYEE = ['ใช้งาน', 'ลาพัก', 'ระงับชั่วคราว', 'ลาออก'];
const STATUS_USER = ['ใช้งาน', 'ระงับชั่วคราว'];   // นักศึกษาที่จบแล้วยังใช้งานได้ตามปกติ
const STATUS_HINT = {
  'ใช้งาน': 'ใช้งานได้ตามปกติ',
  'ลาพัก': 'ยังเข้าสู่ระบบได้ แต่จะไม่ถูกเลือกเป็นคนขับในรอบ/ตารางเวลาใหม่',
  'ระงับชั่วคราว': 'เข้าสู่ระบบและจองไม่ได้ — การจองที่ยังไม่เดินทางจะถูกยกเลิก (เปลี่ยนกลับเป็น "ใช้งาน" ได้)',
  'ลาออก': 'เข้าสู่ระบบไม่ได้ ประวัติยังอยู่ครบ — การจองที่ยังไม่เดินทางจะถูกยกเลิก',
};

MUT.page(async ({ me, can }) => {
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

  // สถานะบัญชี: ตัวเลือกเปลี่ยนตามพนักงาน/ผู้ใช้ทั่วไป — แก้สถานะของตัวเองไม่ได้ (ช่อง disabled จะไม่ถูกส่ง = คงเดิม)
  const statusSelect = document.getElementById('status');
  const statusHint = document.getElementById('status-hint');
  const isSelf = !isNew && id === me.user_id;
  const syncStatus = (selected) => {
    const list = toggle.checked ? STATUS_EMPLOYEE : STATUS_USER;
    const value = list.includes(selected) ? selected : 'ใช้งาน';
    statusSelect.innerHTML = options(list.map((s) => ({ s })), 's', 's', value);
    statusHint.textContent = isSelf ? 'เปลี่ยนสถานะบัญชีของตัวเองไม่ได้' : STATUS_HINT[value];
  };
  statusSelect.disabled = isSelf;
  statusSelect.addEventListener('change', () => { statusHint.textContent = STATUS_HINT[statusSelect.value]; });
  syncStatus(v.status || 'ใช้งาน');

  const sync = () => { box.hidden = !toggle.checked; };
  toggle.addEventListener('change', () => { sync(); syncStatus(statusSelect.value); });
  sync();

  MUT.bindForm(form, async (data) => {
    const [[r]] = await MUT.api('users_save', { ...data, id });
    MUT.go('/admin/users', 'success', r.message);
  });
});
