// โปรไฟล์ → CALL api_profile / api_change_password
MUT.page(async () => {
  const { esc } = MUT;
  // ข้อมูลของผู้ที่ login อยู่เท่านั้น (api_profile ใช้ uid จาก session) — หน้านี้แสดงอย่างเดียว
  const [[p]] = await MUT.api('profile');
  // ตำแหน่ง/เบอร์โทร แสดงเฉพาะพนักงาน
  document.getElementById('profile').innerHTML = `
    <dt>รหัสผู้ใช้งาน</dt><dd class="mono">${esc(p.user_id)}</dd>
    <dt>ชื่อ</dt><dd>${esc(p.name)}</dd>
    <dt>Email</dt><dd>${esc(p.email)}</dd>
    <dt>Username</dt><dd>${esc(p.username)}</dd>
    <dt>แผนก</dt><dd>${esc(p.department_name)}</dd>
    ${p.position_name ? `<dt>ตำแหน่ง</dt><dd>${esc(p.position_name)}</dd><dt>เบอร์โทร</dt><dd>${esc(p.phone)}</dd>` : ''}`;

  // เปลี่ยน password: หลังบ้านตรวจ password เดิม + ความยาว + ยืนยันตรงกัน → สำเร็จ = ล้างฟอร์ม อยู่หน้าเดิม
  const form = document.getElementById('password-form');
  MUT.bindForm(form, async (data) => {
    const [[r]] = await MUT.api('change_password', data);
    form.reset();
    MUT.flash('success', r.message);
  });
});
