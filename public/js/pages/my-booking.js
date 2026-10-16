// ยกเลิกรายการจอง (ใช้ทั้งหน้านี้และหน้าการจองของฉัน)
// ถามยืนยัน → api_cancel (หลังบ้านตรวจว่าเป็นรายการของผู้ใช้เองและยังยกเลิกได้) → ไปหน้า nextUrl พร้อมข้อความ
// ยกเลิกไม่สำเร็จ → แสดง error ด้านบน อยู่หน้าเดิม
window.MyBooking = {
  async cancel(item, nextUrl) {
    const ok = await MUT.confirmBox({
      title: `ยืนยันการยกเลิกรายการจอง ${item.booking_item_id}?`,
      message: `ที่นั่ง ${item.seats} ที่จะถูกคืนให้รอบ ${MUT.fmtTime(item.depart_time)} ${item.route_name}`,
      ok: 'ยืนยันการยกเลิก',
    });
    if (!ok) return;
    try {
      const [[r]] = await MUT.api('cancel', { item: item.booking_item_id });
      MUT.go(nextUrl, 'success', r.message);
    } catch (err) {
      MUT.flash('error', err.message);
    }
  },
};
