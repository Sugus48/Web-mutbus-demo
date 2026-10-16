// สมัครสมาชิก → CALL sp_register (ผ่าน /api/register)
// บัญชีที่สมัครเองเป็นผู้ใช้ทั่วไป (ไม่มีตำแหน่ง) — สำเร็จแล้ว server login ให้ทันที แล้วพาไปหน้าแรกพร้อมข้อความต้อนรับ
// error ของแต่ละช่อง (เช่น username ซ้ำ) แสดงใต้ช่องนั้นผ่าน bindForm
MUT.page(() => {
  MUT.bindForm(document.getElementById('register-form'), async (data) => {
    const res = await MUT.post('/api/register', data);
    MUT.go(res.redirect, 'success', res.message);
  });
});
