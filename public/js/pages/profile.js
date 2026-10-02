// โปรไฟล์ → CALL api_profile / api_change_password
MUT.page(async () => {
  const { esc } = MUT;
  const [[p]] = await MUT.api('profile');
  document.getElementById('profile').innerHTML = `
    <dt>รหัสผู้ใช้งาน</dt><dd class="mono">${esc(p.user_id)}</dd>
    <dt>ชื่อ</dt><dd>${esc(p.name)}</dd>
    <dt>Email</dt><dd>${esc(p.email)}</dd>
    <dt>Username</dt><dd>${esc(p.username)}</dd>
    <dt>แผนก</dt><dd>${esc(p.department_name)}</dd>
    ${p.position_name ? `<dt>ตำแหน่ง</dt><dd>${esc(p.position_name)}</dd><dt>เบอร์โทร</dt><dd>${esc(p.phone)}</dd>` : ''}`;

  const form = document.getElementById('password-form');
  MUT.bindForm(form, async (data) => {
    const [[r]] = await MUT.api('change_password', data);
    form.reset();
    MUT.flash('success', r.message);
  });
});
