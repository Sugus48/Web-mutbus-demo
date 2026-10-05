// เพิ่ม/แก้ไขรอบการเดินรถ → CALL api_trips_form / api_trips_save (ตรวจรถ/คนขับชนเวลาใน SQL)
MUT.page(async ({ me }) => {
  const { esc, options } = MUT;
  const id = MUT.param('id');
  const isNew = !id;
  const [[trip], routes, vehicles, drivers] = await MUT.api('trips_form', { id });
  const v = trip || { trip_date: MUT.param('date') || me.today, route_id: MUT.param('route') };
  const form = document.getElementById('trip-form');
  document.getElementById('form-title').textContent = isNew ? 'เพิ่มรอบการเดินรถ' : `แก้ไขรอบ ${id}`;
  document.title = `${isNew ? 'เพิ่ม' : 'แก้ไข'}รอบการเดินรถ · BusBuddy`;
  if (trip && Number(trip.booked_seats) > 0) {
    document.getElementById('booked-note').innerHTML = `<div class="alert alert-info">รอบนี้มีการจองแล้ว ${esc(trip.booked_seats)} ที่นั่ง</div>`;
  }

  form.route_id.innerHTML = options(routes, 'route_id', (r) => `${r.route_name} (${r.total_minutes} นาที)`, v.route_id, '— เลือกเส้นทาง —');
  form.vehicle_id.innerHTML = options(vehicles, 'vehicle_id',
    (x) => `${x.plate_no} · ${x.type_name}${x.status !== 'พร้อมใช้งาน' ? ` (${x.status})` : ''}`, v.vehicle_id, '— เลือกรถ —');
  form.driver_id.innerHTML = options(drivers, 'user_id', (x) => `${x.name} (${x.position_name}${x.status && x.status !== 'ใช้งาน' ? ` · ${x.status}` : ''})`, v.driver_id, '— เลือกคนขับ —');
  form.trip_date.value = v.trip_date || '';
  if (isNew) form.trip_date.min = me.today;
  form.depart_time.value = v.depart_time ? String(v.depart_time).slice(0, 5) : '';
  if (!isNew) {
    document.getElementById('status-field').hidden = false;
    form.status.value = v.status;
  } else {
    form.status.disabled = true; // รอบใหม่ = เปิด เสมอ
  }

  // จำนวนที่นั่งตามรถ + ช่วงเวลาของรอบตามเวลารวมของเส้นทาง
  const seats = document.getElementById('seat_count');
  const hint = document.getElementById('end-hint');
  function sync() {
    const car = vehicles.find((x) => x.vehicle_id === form.vehicle_id.value);
    seats.value = car ? `${car.seat_count} ที่นั่ง` : '';
    const r = routes.find((x) => x.route_id === form.route_id.value);
    hint.textContent = r && form.depart_time.value
      ? `ช่วงเวลาของรอบ ${form.depart_time.value}–${MUT.addMinutes(form.depart_time.value, r.total_minutes)}` : '';
  }
  [form.route_id, form.depart_time, form.vehicle_id].forEach((el) => el.addEventListener('input', sync));
  sync();

  MUT.bindForm(form, async (data) => {
    const [[r]] = await MUT.api('trips_save', { ...data, id });
    MUT.go(`/admin/trips?date=${r.trip_date}`, 'success', r.message);
  });
});
