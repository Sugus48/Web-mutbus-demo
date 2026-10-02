// หน้าจัดการข้อมูลหลักแบบมาตรฐาน: ค้นหา/กรอง + ตาราง + เพิ่ม/แก้ไข/ลบ (ตามสิทธิ์)
// แต่ละหน้า (admin/departments.html ฯลฯ) ระบุ data-resource แล้วใช้การตั้งค่าใน RESOURCES ด้านล่าง
//   รายการ → CALL api_<api>_list   ฟอร์มแก้ไข → CALL api_<api>_get
//   บันทึก → CALL api_<api>_save   ลบ → CALL api_<api>_delete
// URL: ?new=1 = ฟอร์มเพิ่ม / ?edit=<รหัส> = ฟอร์มแก้ไข / อื่นๆ = รายการ (+ ค่าตัวกรอง)
(function () {
  const { esc, fmtTime, badge } = MUT;

  const VEHICLE_STATUS = ['พร้อมใช้งาน', 'ซ่อมบำรุง', 'ไม่พร้อมใช้งาน'].map((s) => ({ value: s, label: s }));
  const RUN_DAYS = [
    { value: '12345', label: 'จันทร์–ศุกร์ (วันทำการ)' },
    { value: '123456', label: 'จันทร์–เสาร์' },
    { value: '0123456', label: 'ทุกวัน' },
    { value: '06', label: 'เสาร์–อาทิตย์' },
  ];
  const ACTIVE = [{ value: '1', label: 'ใช้งาน' }, { value: '0', label: 'หยุดใช้งาน' }];
  const runDaysLabel = (v) => (RUN_DAYS.find((o) => o.value === String(v)) || { label: v }).label;

  // ตัวเลือกจาก api_lookups (lk = { types, routes, vehicles, drivers, ... })
  const typeOptions = (lk) => lk.types.map((t) => ({ value: t.vehicle_type_id, label: `${t.type_name} (${t.seat_count} ที่นั่ง)` }));
  const routeOptions = (lk) => lk.routes.map((r) => ({ value: r.route_id, label: `${r.route_name} (${r.total_minutes} นาที)` }));
  const vehicleOptions = (lk) => lk.vehicles.map((v) => ({
    value: v.vehicle_id,
    label: `${v.plate_no} ${v.type_name} ${v.seat_count} ที่นั่ง${v.status === 'พร้อมใช้งาน' ? '' : ` (${v.status})`}`,
  }));
  const driverOptions = (lk) => lk.drivers.map((u) => ({ value: u.user_id, label: u.name }));

  const RESOURCES = {
    // 10.3 แผนก
    departments: {
      title: 'แผนก', screen: 'SC08', api: 'departments', pk: 'department_id', search: true,
      columns: [
        { key: 'department_id', label: 'รหัสแผนก' },
        { key: 'department_name', label: 'ชื่อแผนก' },
        { key: 'user_count', label: 'จำนวนผู้ใช้งาน', align: 'right' },
      ],
      fields: [{ name: 'department_name', label: 'ชื่อแผนก', type: 'text', required: true, max: 100 }],
      nameOf: (r) => r.department_name,
    },
    // 10.4 ตำแหน่ง
    positions: {
      title: 'ตำแหน่ง', screen: 'SC09', api: 'positions', pk: 'position_id', search: true,
      columns: [
        { key: 'position_id', label: 'รหัสตำแหน่ง' },
        { key: 'position_name', label: 'ชื่อตำแหน่ง' },
        { key: 'employee_count', label: 'จำนวนพนักงาน', align: 'right' },
        { key: 'screen_count', label: 'หน้าจอที่เข้าถึงได้', align: 'right' },
      ],
      fields: [{ name: 'position_name', label: 'ชื่อตำแหน่ง', type: 'text', required: true, max: 100 }],
      rowLinks: [{ label: 'กำหนดสิทธิ์', href: (r) => `/admin/permissions?position=${encodeURIComponent(r.position_id)}`, screen: 'SC10' }],
      nameOf: (r) => r.position_name,
      deleteWarning: 'สิทธิ์ทั้งหมดของตำแหน่งนี้จะถูกลบด้วย',
    },
    // 10.5 หน้าจอ
    screens: {
      title: 'หน้าจอ', screen: 'SC10', api: 'screens', pk: 'screen_id', search: true,
      note: 'หน้าจอ SC01–SC12 ผูกกับเมนูของระบบ (แก้ชื่อได้ แต่ลบไม่ได้)',
      columns: [
        { key: 'screen_id', label: 'รหัสหน้าจอ' },
        { key: 'screen_name', label: 'ชื่อหน้าจอ' },
        { key: 'position_count', label: 'จำนวนตำแหน่งที่เข้าถึงได้', align: 'right' },
      ],
      fields: [{ name: 'screen_name', label: 'ชื่อหน้าจอ', type: 'text', required: true, max: 100 }],
      nameOf: (r) => r.screen_name,
      deleteWarning: 'สิทธิ์ของหน้าจอนี้ในทุกตำแหน่งจะถูกลบด้วย',
    },
    // 10.7 ประเภทรถ
    'vehicle-types': {
      title: 'ประเภทรถ', screen: 'SC03', api: 'vehicle_types', pk: 'vehicle_type_id', search: true,
      columns: [
        { key: 'vehicle_type_id', label: 'รหัสประเภทรถ' },
        { key: 'type_name', label: 'ชื่อประเภทรถ' },
        { key: 'description', label: 'รายละเอียด' },
        { key: 'seat_count', label: 'จำนวนที่นั่ง', align: 'right' },
        { key: 'vehicle_count', label: 'จำนวนรถ', align: 'right' },
      ],
      fields: [
        { name: 'type_name', label: 'ชื่อประเภทรถ', type: 'text', required: true, max: 50 },
        { name: 'description', label: 'รายละเอียด', type: 'textarea', max: 255 },
        { name: 'seat_count', label: 'จำนวนที่นั่ง', type: 'number', required: true, min: 1,
          hint: 'เมื่อแก้ไข รอบที่ยังเปิดจองของรถประเภทนี้จะใช้จำนวนที่นั่งใหม่' },
      ],
      nameOf: (r) => r.type_name,
    },
    // 10.8 รถ
    vehicles: {
      title: 'รถ', screen: 'SC01', api: 'vehicles', pk: 'vehicle_id', search: true,
      filters: [
        { name: 'vehicle_type_id', label: 'ประเภทรถ', options: typeOptions },
        { name: 'status', label: 'สถานะ', options: () => VEHICLE_STATUS },
      ],
      columns: [
        { key: 'vehicle_id', label: 'รหัสรถ' },
        { key: 'plate_no', label: 'ทะเบียนรถ' },
        { key: 'type_name', label: 'ประเภทรถ' },
        { key: 'seat_count', label: 'จำนวนที่นั่ง', align: 'right' },
        { key: 'status', label: 'สถานะ', badge: true },
      ],
      fields: [
        { name: 'plate_no', label: 'ทะเบียนรถ', type: 'text', required: true, max: 20 },
        { name: 'vehicle_type_id', label: 'ประเภทรถ', type: 'select', required: true, options: typeOptions,
          hint: 'จำนวนที่นั่งของรถมาจากประเภทรถ' },
        { name: 'status', label: 'สถานะ', type: 'select', required: true, options: () => VEHICLE_STATUS,
          hint: 'เฉพาะรถ "พร้อมใช้งาน" ที่เลือกได้ตอนจัดรอบการเดินรถ' },
      ],
      nameOf: (r) => `ทะเบียน ${r.plate_no}`,
    },
    // 10.9 จุดจอด
    stops: {
      title: 'จุดจอด', screen: 'SC04', api: 'stops', pk: 'stop_id', search: true,
      note: 'ห้ามลบจุดจอดที่ถูกใช้ในเส้นทางหรือรายการจอง',
      columns: [
        { key: 'stop_id', label: 'รหัสจุดจอด' },
        { key: 'stop_name', label: 'ชื่อจุดจอด' },
        { key: 'route_count', label: 'ใช้ในเส้นทาง', align: 'right' },
        { key: 'item_count', label: 'ใช้ในรายการจอง', align: 'right' },
      ],
      fields: [{ name: 'stop_name', label: 'ชื่อจุดจอด', type: 'text', required: true, max: 150 }],
      nameOf: (r) => r.stop_name,
    },
    // ตารางเวลาเดินรถประจำ — ระบบสร้างรอบของแต่ละวันล่วงหน้าจากตารางนี้
    schedules: {
      title: 'ตารางเวลาเดินรถ', screen: 'SC06', api: 'schedules', pk: 'schedule_id', search: false,
      note: 'ระบบสร้างรอบการเดินรถล่วงหน้า 7 วันจากตารางนี้ เฉพาะวันที่ตรงกับวันที่วิ่ง — แก้ไขแล้วรอบที่ยังไม่มีคนจองจะเปลี่ยนตาม ส่วนรอบที่มีการจองแล้วแก้ได้ที่หน้ารอบการเดินรถ',
      filters: [
        { name: 'route_id', label: 'เส้นทาง', options: routeOptions },
        { name: 'driver_id', label: 'คนขับ', options: driverOptions },
      ],
      columns: [
        { key: 'schedule_id', label: 'รหัส' },
        { key: 'route_name', label: 'เส้นทาง' },
        { key: 'round_no', label: 'รอบที่', align: 'right' },
        { key: 'depart_time', label: 'เวลา', fmt: (r) => fmtTime(r.depart_time) },
        { key: 'run_days', label: 'วันที่วิ่ง', fmt: (r) => runDaysLabel(r.run_days) },
        { key: 'driver_name', label: 'คนขับ' },
        { key: 'plate_no', label: 'รถ', fmt: (r) => `${r.plate_no} ${r.type_name} ${r.seat_count} ที่นั่ง` },
        { key: 'active_label', label: 'สถานะ', badge: true },
      ],
      fields: [
        { name: 'route_id', label: 'เส้นทาง', type: 'select', required: true, options: routeOptions },
        { name: 'depart_time', label: 'เวลาออก', type: 'time', required: true },
        { name: 'run_days', label: 'วันที่วิ่ง', type: 'select', required: true, options: () => RUN_DAYS },
        { name: 'driver_id', label: 'คนขับ', type: 'select', required: true, options: driverOptions },
        { name: 'vehicle_id', label: 'รถ', type: 'select', required: true, options: vehicleOptions,
          hint: 'รถที่ไม่อยู่ในสถานะพร้อมใช้งาน ระบบจะข้ามไม่สร้างรอบให้' },
        { name: 'active', label: 'สถานะ', type: 'select', required: true, options: () => ACTIVE,
          hint: 'หยุดใช้งาน = ไม่สร้างรอบใหม่ และลบรอบล่วงหน้าที่ยังไม่มีคนจอง' },
      ],
      nameOf: (r) => `${r.route_name} ${fmtTime(r.depart_time)}`,
      deleteWarning: 'รอบล่วงหน้าที่ยังไม่มีคนจองจะถูกลบด้วย',
    },
  };

  // api_lookups คืน 8 ชุดตามลำดับ
  async function loadLookups() {
    const [types, routes, vehicles, drivers, departments, positions, stops, screens] = await MUT.api('lookups');
    return { types, routes, vehicles, drivers, departments, positions, stops, screens };
  }
  const needsLookups = (cfg) => (cfg.filters || []).length > 0 || cfg.fields.some((f) => f.type === 'select');

  MUT.page(async ({ can, hasScreen }) => {
    const listView = document.getElementById('list-view');
    const cfg = RESOURCES[listView.dataset.resource];
    const base = location.pathname.replace(/\.html$/, '');
    const q = MUT.params();
    const lk = needsLookups(cfg) ? await loadLookups() : {};
    document.title = `${cfg.title} · MUT Shuttle`;

    if (q.new || q.edit) await showForm(q.edit || null);
    else await showList();

    // ---------- รายการ ----------
    async function showList() {
      const filters = (cfg.filters || []).map((f) => ({ ...f, opts: f.options(lk) }));
      const rowsData = await MUT.api(`${cfg.api}_list`, q).then((s) => s[0]);
      listView.hidden = false;
      listView.querySelector('[data-title]').textContent = cfg.title;
      listView.querySelector('[data-note]').textContent = cfg.note || '';
      const addBtn = document.getElementById('add-btn');
      if (can(cfg.screen, 'add')) {
        addBtn.hidden = false;
        addBtn.href = `${base}?new=1`;
        addBtn.textContent = `+ เพิ่ม${cfg.title}`;
      }

      document.getElementById('filter-form').innerHTML = `
        ${cfg.search ? `<div class="field wide"><label for="q">ค้นหา</label>
          <input class="input" id="q" name="q" value="${esc(q.q || '')}" placeholder="รหัส หรือชื่อ"></div>` : ''}
        ${filters.map((f) => `<div class="field"><label for="f-${f.name}">${esc(f.label)}</label>
          <select class="input" id="f-${f.name}" name="${f.name}">${MUT.options(f.opts, 'value', 'label', q[f.name], 'ทั้งหมด')}</select></div>`).join('')}
        <div class="btn-row"><button class="btn" type="submit">ค้นหา</button><a class="btn btn-ghost" href="${base}">ล้าง</a></div>`;

      const showActions = can(cfg.screen, 'edit') || can(cfg.screen, 'delete') || (cfg.rowLinks || []).length;
      const box = document.getElementById('rows');
      if (!rowsData.length) {
        box.innerHTML = `<div class="card empty"><strong>ไม่พบข้อมูล</strong>${q.q ? 'ลองเปลี่ยนคำค้นหา' : ''}</div>`;
        return;
      }
      box.innerHTML = `<div class="table-wrap"><table class="table">
          <thead><tr>${cfg.columns.map((c) => `<th class="${c.align || ''}">${esc(c.label)}</th>`).join('')}
            ${showActions ? '<th class="right">จัดการ</th>' : ''}</tr></thead>
          <tbody>${rowsData.map((r, i) => `<tr>
            ${cfg.columns.map((c) => `<td class="${c.align || ''} ${c.key === cfg.pk ? 'mono' : ''}">${
              c.badge ? badge(r[c.key]) : esc(c.fmt ? c.fmt(r) : (r[c.key] ?? '-'))}</td>`).join('')}
            ${showActions ? `<td class="actions">
              ${(cfg.rowLinks || []).filter((l) => !l.screen || hasScreen(l.screen)).map((l) =>
                `<a class="btn btn-sm btn-ghost" href="${esc(l.href(r))}">${esc(l.label)}</a>`).join('')}
              ${can(cfg.screen, 'edit') ? `<a class="btn btn-sm" href="${base}?edit=${encodeURIComponent(r[cfg.pk])}">แก้ไข</a>` : ''}
              ${can(cfg.screen, 'delete') ? `<button class="btn btn-sm" style="color:var(--danger)" type="button" data-delete="${i}">ลบ</button>` : ''}
            </td>` : ''}
          </tr>`).join('')}</tbody>
        </table></div>
        <p class="small muted mt-2">ทั้งหมด ${rowsData.length} รายการ</p>`;

      box.addEventListener('click', async (e) => {
        const btn = e.target.closest('[data-delete]');
        if (!btn) return;
        const r = rowsData[Number(btn.dataset.delete)];
        const id = r[cfg.pk];
        const ok = await MUT.confirmBox({
          title: `ลบ${cfg.title} ${id}?`,
          message: `${cfg.nameOf ? cfg.nameOf(r) : ''}${cfg.deleteWarning ? `\n${cfg.deleteWarning}` : ''}\nการลบไม่สามารถย้อนกลับได้`,
          ok: 'ลบ',
        });
        if (!ok) return;
        try {
          const [[res]] = await MUT.api(`${cfg.api}_delete`, { id });
          MUT.go(location.href, 'success', res.message);
        } catch (err) {
          MUT.flash('error', err.message);
        }
      });
    }

    // ---------- ฟอร์มเพิ่ม/แก้ไข ----------
    async function showForm(id) {
      const isNew = !id;
      if (!can(cfg.screen, isNew ? 'add' : 'edit')) throw new MUT.ApiError(403, 'ตำแหน่งของคุณไม่มีสิทธิ์ใช้งานส่วนนี้');
      const values = isNew ? {} : (await MUT.api(`${cfg.api}_get`, { id }))[0][0];
      const view = document.getElementById('form-view');
      view.hidden = false;
      const back = document.getElementById('form-back');
      back.href = base;
      back.insertAdjacentText('beforeend', cfg.title);
      document.getElementById('form-cancel').href = base;
      document.getElementById('form-title').textContent = `${isNew ? 'เพิ่ม' : 'แก้ไข'}${cfg.title}${isNew ? '' : ` ${id}`}`;
      document.title = `${isNew ? 'เพิ่ม' : 'แก้ไข'}${cfg.title} · MUT Shuttle`;

      document.getElementById('form-fields').innerHTML = `
        <div class="field"><label>รหัส</label><input class="input mono" value="${esc(isNew ? 'สร้างอัตโนมัติ' : id)}" readonly></div>
        ${cfg.fields.map((f) => {
          const v = values[f.name] ?? '';
          const req = f.required ? 'required' : '';
          let input;
          if (f.type === 'select') {
            input = `<select class="input" id="${f.name}" name="${f.name}" ${req}>${MUT.options(f.options(lk), 'value', 'label', v, `— เลือก${f.label} —`)}</select>`;
          } else if (f.type === 'textarea') {
            input = `<textarea class="input" id="${f.name}" name="${f.name}" ${f.max ? `maxlength="${f.max}"` : ''}>${esc(v)}</textarea>`;
          } else if (f.type === 'time') {
            input = `<input class="input" id="${f.name}" name="${f.name}" type="time" value="${esc(String(v).slice(0, 5))}" ${req}>`;
          } else {
            input = `<input class="input" id="${f.name}" name="${f.name}" value="${esc(v)}" type="${f.type === 'number' ? 'number' : 'text'}"
              ${f.min !== undefined ? `min="${f.min}"` : ''} ${f.max ? `maxlength="${f.max}"` : ''} ${req}>`;
          }
          return `<div class="field">
            <label for="${f.name}">${esc(f.label)}${f.required ? '' : ' (ไม่บังคับ)'}</label>
            ${input}${f.hint ? `<span class="hint">${esc(f.hint)}</span>` : ''}
          </div>`;
        }).join('')}`;

      MUT.bindForm(document.getElementById('edit-form'), async (data) => {
        const [[res]] = await MUT.api(`${cfg.api}_save`, { ...data, id: id || '' });
        MUT.go(base, 'success', res.message);
      });
    }
  });
})();
