// 10.2 ผู้ใช้งาน / พนักงาน → CALL api_lookups / api_users_list (ลบ → CALL api_users_delete)
//
// ลำดับการทำงาน
//   1. อ่านตัวกรองจาก URL (?q=&department=&position=&type=&status=) แล้วเติมกลับลงฟอร์ม
//      — ฟอร์มค้นหาเป็น GET ธรรมดา กดค้นหา = โหลดหน้าใหม่พร้อมตัวกรองใน URL
//   2. ส่งตัวกรองชุดเดียวกันไป api_users_list แล้ววาดตาราง
//   3. ปุ่ม เพิ่ม/แก้ไข/ลบ แสดงตามสิทธิ์ SC07 ของตำแหน่ง (ฝั่ง server ตรวจซ้ำทุกครั้ง)
MUT.page(async ({ can }) => {
  const { esc, options } = MUT;
  const q = MUT.params();   // ตัวกรองทั้งหมดจาก URL
  // api_lookups คืนหลายชุดข้อมูล — ชุดที่ 5 = แผนก, ชุดที่ 6 = ตำแหน่ง
  const [, , , , departments, positions] = await MUT.api('lookups');
  document.getElementById('q').value = q.q || '';
  document.getElementById('department').innerHTML = options(departments, 'department_id', 'department_name', q.department, 'ทั้งหมด');
  document.getElementById('position').innerHTML = options(positions, 'position_id', 'position_name', q.position, 'ทั้งหมด');
  document.getElementById('type').value = q.type || '';       // employee / user / ว่าง = ทั้งหมด
  document.getElementById('status').value = q.status || '';   // ว่าง = ซ่อนบัญชีที่ลาออก
  document.getElementById('add-btn').hidden = !can('SC07', 'add');

  // ---------- ตาราง ----------
  const [rows] = await MUT.api('users_list', q);
  const box = document.getElementById('rows');
  if (!rows.length) {
    box.innerHTML = '<div class="card empty"><strong>ไม่พบผู้ใช้งาน</strong></div>';
    return;
  }
  // ทุกค่าที่มาจากฐานข้อมูลผ่าน esc() กัน HTML injection
  // ปุ่มลบเก็บแค่ลำดับแถว (data-delete) แล้วไปหาข้อมูลจาก rows ตอนกด
  box.innerHTML = `<div class="table-wrap"><table class="table">
      <thead><tr><th>รหัส</th><th>ชื่อ</th><th>email</th><th>username</th><th>แผนก</th><th>ตำแหน่ง</th><th>เบอร์โทร</th><th>สถานะ</th><th class="right">จัดการ</th></tr></thead>
      <tbody>${rows.map((u, i) => `<tr>
        <td class="mono">${esc(u.user_id)}</td><td>${esc(u.name)}</td><td>${esc(u.email)}</td><td>${esc(u.username)}</td>
        <td>${esc(u.department_name)}</td><td>${Number(u.is_employee) ? esc(u.position_name || '—') : '<span class="muted">ผู้ใช้ทั่วไป</span>'}</td><td class="nowrap">${esc(u.phone || '—')}</td><td>${MUT.badge(u.status)}</td>
        <td class="actions">
          ${can('SC07', 'edit') ? `<a class="btn btn-sm" href="/admin/user-form?id=${encodeURIComponent(u.user_id)}">แก้ไข</a>` : ''}
          ${can('SC07', 'delete') ? `<button class="btn btn-sm" style="color:var(--danger)" type="button" data-delete="${i}">ลบ</button>` : ''}
        </td>
      </tr>`).join('')}</tbody>
    </table></div>
    <p class="small muted mt-2">ทั้งหมด ${rows.length} คน</p>`;

  // ---------- ลบ ----------
  // ผูก click ครั้งเดียวที่กล่องตาราง (event delegation) แทนการผูกทุกปุ่ม
  // หลังบ้านไม่ให้ลบ: บัญชีตัวเอง / บัญชีที่สิทธิ์สูงกว่า / มีประวัติการจอง / เป็นคนขับในรอบหรือตารางเวลา
  // → ข้อความ error แสดงเป็นแถบแจ้งเตือนด้านบน (กรณีนี้ควรเปลี่ยนสถานะเป็น "ลาออก" แทน)
  box.addEventListener('click', async (e) => {
    const btn = e.target.closest('[data-delete]');
    if (!btn) return;
    const u = rows[Number(btn.dataset.delete)];
    const ok = await MUT.confirmBox({
      title: `ลบผู้ใช้งาน ${u.user_id}?`, message: `${u.name} (${u.username})\nการลบไม่สามารถย้อนกลับได้`, ok: 'ลบ',
    });
    if (!ok) return;
    try {
      const [[r]] = await MUT.api('users_delete', { id: u.user_id });
      MUT.go(location.href, 'success', r.message);   // โหลดหน้าเดิม (ตัวกรองเดิม) พร้อมข้อความสำเร็จ
    } catch (err) {
      MUT.flash('error', err.message);
    }
  });
});
