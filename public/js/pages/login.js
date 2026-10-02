// เข้าสู่ระบบ → CALL sp_login (ผ่าน /api/login)
MUT.page(() => {
  const form = document.getElementById('login-form');
  if (MUT.param('out')) MUT.flash('success', 'ออกจากระบบเรียบร้อยแล้ว');
  MUT.bindForm(form, async (data) => {
    const res = await MUT.post('/api/login', { ...data, next: MUT.param('next') });
    location.href = res.redirect;
  });
});
