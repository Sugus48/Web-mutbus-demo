// สมัครสมาชิก → CALL sp_register (ผ่าน /api/register)
MUT.page(() => {
  MUT.bindForm(document.getElementById('register-form'), async (data) => {
    const res = await MUT.post('/api/register', data);
    MUT.go(res.redirect, 'success', res.message);
  });
});
