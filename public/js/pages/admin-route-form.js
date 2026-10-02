// เพิ่ม/แก้ไขเส้นทาง + ลำดับจุดจอด → CALL api_lookups / api_routes_get / api_routes_save
MUT.page(async ({ can }) => {
  const id = MUT.param('id');
  const isNew = !id;
  if (!can('SC05', isNew ? 'add' : 'edit')) throw new MUT.ApiError(403, 'ตำแหน่งของคุณไม่มีสิทธิ์ใช้งานส่วนนี้');
  const allStops = (await MUT.api('lookups'))[6];
  let route = { route_name: '' };
  let rows = [{ stop_id: '', travel_minutes: 0 }, { stop_id: '', travel_minutes: '' }];
  if (!isNew) {
    const [[r], stops] = await MUT.api('routes_get', { id });
    route = r;
    rows = stops.map((s) => ({ stop_id: s.stop_id, travel_minutes: s.travel_minutes }));
  }
  const back = isNew ? '/admin/routes' : `/admin/route?id=${encodeURIComponent(id)}`;
  document.getElementById('back-link').href = back;
  document.getElementById('cancel-btn').href = back;
  document.getElementById('form-title').textContent = isNew ? 'เพิ่มเส้นทาง' : `แก้ไขเส้นทาง ${id}`;
  document.getElementById('edit-note').hidden = isNew;
  const form = document.getElementById('route-form');
  form.route_name.value = route.route_name;

  const box = document.getElementById('rows');
  const tpl = document.getElementById('row-template');
  const total = document.getElementById('total');
  const rowEls = () => [...box.querySelectorAll('.repeat-row')];
  function addRow(r) {
    const el = tpl.content.firstElementChild.cloneNode(true);
    el.querySelector('select').innerHTML = MUT.options(allStops, 'stop_id', 'stop_name', r.stop_id, '— เลือกจุดจอด —');
    el.querySelector('[name=minutes]').value = r.travel_minutes;
    box.appendChild(el);
    return el;
  }
  function refresh() {
    let sum = 0;
    rowEls().forEach((row, i) => {
      row.querySelector('.order').textContent = i + 1;
      const m = row.querySelector('[name=minutes]');
      m.readOnly = i === 0; // ลำดับ 1 = 0 นาที และล็อกไว้
      if (i === 0) m.value = 0;
      sum += Number(m.value) || 0;
      row.querySelector('[data-remove]').disabled = rowEls().length <= 2;
    });
    total.value = sum;
  }
  rows.forEach(addRow);

  document.getElementById('add-row').addEventListener('click', () => {
    const el = addRow({ stop_id: '', travel_minutes: '' });
    refresh();
    el.querySelector('select').focus();
  });
  box.addEventListener('click', (e) => {
    const row = e.target.closest('.repeat-row');
    if (!row) return;
    if (e.target.closest('[data-remove]') && rowEls().length > 2) row.remove();
    const mv = e.target.closest('[data-move]');
    if (mv) {
      if (mv.dataset.move === '-1' && row.previousElementSibling) box.insertBefore(row, row.previousElementSibling);
      if (mv.dataset.move === '1' && row.nextElementSibling) box.insertBefore(row.nextElementSibling, row);
      mv.focus();
    }
    refresh();
  });
  box.addEventListener('input', refresh);

  // ลากเพื่อเรียงลำดับ
  let dragging = null;
  box.addEventListener('dragstart', (e) => { dragging = e.target.closest('.repeat-row'); dragging.classList.add('dragging'); });
  box.addEventListener('dragend', () => { dragging.classList.remove('dragging'); dragging = null; refresh(); });
  box.addEventListener('dragover', (e) => {
    e.preventDefault();
    const over = e.target.closest('.repeat-row');
    if (!over || over === dragging) return;
    const after = e.clientY > over.getBoundingClientRect().top + over.offsetHeight / 2;
    box.insertBefore(dragging, after ? over.nextSibling : over);
  });
  refresh();

  // ส่งลำดับจุดจอดเป็นข้อความ 'S001:0,S002:5,...'
  MUT.bindForm(form, async () => {
    const stops = rowEls().map((row, i) =>
      `${row.querySelector('select').value}:${i === 0 ? 0 : row.querySelector('[name=minutes]').value}`).join(',');
    const [[r]] = await MUT.api('routes_save', { id, route_name: form.route_name.value, stops });
    MUT.go(`/admin/route?id=${encodeURIComponent(r.id)}`, 'success', r.message);
  });
});
