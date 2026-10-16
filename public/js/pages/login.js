// เข้าสู่ระบบ → CALL sp_login (ผ่าน /api/login)
MUT.page(() => {
  const form = document.getElementById('login-form');
  if (MUT.param('out')) MUT.flash('success', 'ออกจากระบบเรียบร้อยแล้ว');   // มาจากปุ่มออกจากระบบ (/login?out=1)
  // ?next= = หน้าที่ผู้ใช้จะเข้าก่อนถูกพามา login — server.js ตรวจว่าเป็นหน้าในเว็บนี้ก่อนพากลับ
  // ไม่มี next → ไปหน้าแรกตามบทบาท (ผู้โดยสาร / คนขับ / หลังบ้าน) ที่ sp_login คืนมา
  MUT.bindForm(form, async (data) => {
    const res = await MUT.post('/api/login', { ...data, next: MUT.param('next') });
    location.href = res.redirect;
  });
});
