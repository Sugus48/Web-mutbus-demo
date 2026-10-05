// BusBuddy — โค้ดกลางของหน้าเว็บทุกหน้า
// - api(): เรียกหลังบ้าน (stored procedure api_*) ผ่าน server.js
// - ฟังก์ชันจัดรูปแบบ, Badge, ไอคอน, Flash message, กล่องยืนยัน
// - วาง layout (แถบบน/เมนูล่าง/เมนูข้างหลังบ้าน) ตาม <body data-layout="user|driver|admin|auth">
// - page(fn): เริ่มหน้า — โหลดผู้ใช้ที่ login แล้วเรียก fn({ me, can, hasScreen })
(function () {
  'use strict';

  // ---------- เรียกหลังบ้าน ----------
  class ApiError extends Error {
    constructor(status, message, field) {
      super(message);
      this.status = status;
      this.field = field || null;
    }
  }

  async function post(url, data) {
    let res;
    try {
      res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'same-origin',
        body: JSON.stringify(data || {}),
      });
    } catch (e) {
      throw new ApiError(0, 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ — ตรวจสอบว่ารัน npm start อยู่');
    }
    let body = {};
    try { body = await res.json(); } catch (e) { /* ไม่ใช่ JSON */ }
    if (res.status === 401 && body.login) {
      setFlash('error', body.error || 'กรุณาเข้าสู่ระบบก่อนใช้งาน');
      location.href = '/login?next=' + encodeURIComponent(location.pathname + location.search);
      return new Promise(() => {}); // หยุดรอระหว่างเปลี่ยนหน้า
    }
    if (!res.ok) throw new ApiError(res.status, body.error || 'เกิดข้อผิดพลาดของระบบ', body.field);
    return body;
  }

  // เรียก procedure api_<name> — คืนค่าเป็น array ของ result set: [[แถว...], [แถว...]]
  async function api(name, data) {
    const body = await post('/api/' + name, data);
    return body.sets || [];
  }

  // ---------- จัดรูปแบบ ----------
  const pad2 = (n) => String(n).padStart(2, '0');
  const DAY_NAMES = ['อาทิตย์', 'จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์'];

  function esc(s) {
    return String(s ?? '')
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }
  // '2026-09-24' หรือ '2026-09-24 09:30:00' → '24/09/2026'
  function fmtDate(v) {
    if (!v) return '-';
    const m = String(v).match(/^(\d{4})-(\d{2})-(\d{2})/);
    return m ? `${m[3]}/${m[2]}/${m[1]}` : String(v);
  }
  // '09:30:00' หรือ '2026-09-24 09:30:00' → '09:30'
  function fmtTime(v) {
    if (!v) return '-';
    const m = String(v).match(/(\d{2}):(\d{2})(?::\d{2})?$/);
    return m ? `${m[1]}:${m[2]}` : String(v);
  }
  const fmtDateTime = (v) => (v ? `${fmtDate(v)} ${fmtTime(v)}` : '-');
  const fmtNum = (v) => (typeof v === 'number' ? v.toLocaleString('th-TH') : v);

  // เพิ่มนาทีให้เวลา 'HH:MM' → 'HH:MM'
  function addMinutes(time, minutes) {
    const [h, m] = String(time).split(':').map(Number);
    const total = h * 60 + m + Number(minutes || 0);
    return `${pad2(Math.floor(total / 60) % 24)}:${pad2(total % 60)}`;
  }
  const dayName = (date) => DAY_NAMES[new Date(`${String(date).slice(0, 10)}T00:00:00`).getDay()];

  // สถานะ → สี Badge (ข้อความแสดงคู่กับสีเสมอ)
  const BADGE = {
    'ยืนยัน': 'success', 'Check-in แล้ว': 'success', 'ยกเลิก': 'danger', 'No Show': 'warning',
    'เปิด': 'info', 'กำลังเดินทาง': 'accent', 'เสร็จสิ้น': 'neutral',
    'พร้อมใช้งาน': 'success', 'ซ่อมบำรุง': 'warning', 'ไม่พร้อมใช้งาน': 'danger',
    'ที่นั่งเต็ม': 'danger', 'ใช้งาน': 'success', 'หยุดใช้งาน': 'neutral',
  };
  const badge = (status) => `<span class="badge badge-${BADGE[status] || 'neutral'}">${esc(status)}</span>`;

  // query string: qs({ a: 1, b: '' }) → '?a=1'
  function qs(obj) {
    const p = new URLSearchParams();
    for (const [k, v] of Object.entries(obj || {})) {
      if (v !== undefined && v !== null && v !== '') p.set(k, v);
    }
    const s = p.toString();
    return s ? `?${s}` : '';
  }
  const param = (name) => new URLSearchParams(location.search).get(name) || '';
  const params = () => Object.fromEntries(new URLSearchParams(location.search));

  // ---------- ไอคอน ----------
  const ICONS = {
    home: '<path d="M3 10.5 12 3l9 7.5V21a1 1 0 0 1-1 1h-5v-7h-6v7H4a1 1 0 0 1-1-1z"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
    ticket: '<path d="M3 8a2 2 0 0 0 2-2h14a2 2 0 0 0 2 2v2a2 2 0 0 0 0 4v2a2 2 0 0 0-2 2H5a2 2 0 0 0-2-2v-2a2 2 0 0 0 0-4z"/><path d="M13 7v10" stroke-dasharray="2 2"/>',
    user: '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
    bus: '<rect x="4" y="3" width="16" height="15" rx="3"/><path d="M4 11h16M8 18v3M16 18v3"/><circle cx="8" cy="14.5" r="1"/><circle cx="16" cy="14.5" r="1"/>',
    qr: '<rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><path d="M14 14h3v3h-3zM20 14v7M14 20h3"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    check: '<path d="m5 12 5 5L20 7"/>',
    back: '<path d="m15 18-6-6 6-6"/>',
    menu: '<path d="M4 6h16M4 12h16M4 18h16"/>',
    close: '<path d="M18 6 6 18M6 6l12 12"/>',
    logout: '<path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4M10 17l5-5-5-5M15 12H3"/>',
    steering: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="2"/><path d="M3.5 10h6M14.5 10h6M12 14v7"/>',
  };
  const icon = (name) => `<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name] || ''}</svg>`;

  // ---------- Flash message (ข้อความแจ้งผลที่แสดงในหน้าถัดไป) ----------
  function setFlash(type, msg) {
    try { sessionStorage.setItem('mut-flash', JSON.stringify({ type, msg })); } catch (e) { /* ignore */ }
  }
  function takeFlash() {
    try {
      const v = sessionStorage.getItem('mut-flash');
      sessionStorage.removeItem('mut-flash');
      return v ? JSON.parse(v) : null;
    } catch (e) { return null; }
  }
  // แสดงข้อความด้านบนของหน้า (type: success / error / warning / info)
  function flash(type, msg) {
    const main = document.getElementById('main');
    if (!main) return;
    let box = document.getElementById('flash');
    if (!box) {
      box = document.createElement('div');
      box.id = 'flash';
      main.prepend(box);
    }
    box.innerHTML = msg ? `<div class="alert alert-${esc(type)}" role="${type === 'error' ? 'alert' : 'status'}">${esc(msg)}</div>` : '';
    if (msg) box.scrollIntoView({ block: 'nearest' });
  }
  // ไปหน้าอื่นพร้อมข้อความ
  function go(url, type, msg) {
    if (msg) setFlash(type, msg);
    location.href = url;
  }

  // ---------- กล่องยืนยัน ----------
  function confirmBox({ title = 'ยืนยันการทำรายการ', message = '', ok = 'ยืนยัน', tone = 'danger' } = {}) {
    let dialog = document.getElementById('confirm-dialog');
    if (!dialog) {
      dialog = document.createElement('dialog');
      dialog.className = 'modal';
      dialog.id = 'confirm-dialog';
      dialog.setAttribute('aria-labelledby', 'confirm-title');
      dialog.innerHTML = `<form method="dialog">
          <div class="modal-body"><h2 id="confirm-title" data-title></h2><p data-message style="white-space:pre-line"></p></div>
          <div class="modal-foot"><button class="btn" value="cancel">กลับ</button><button class="btn" value="ok" data-ok></button></div>
        </form>`;
      document.body.appendChild(dialog);
    }
    dialog.querySelector('[data-title]').textContent = title;
    dialog.querySelector('[data-message]').textContent = message;
    const okBtn = dialog.querySelector('[data-ok]');
    okBtn.textContent = ok;
    okBtn.className = 'btn ' + (tone === 'primary' ? 'btn-primary' : 'btn-danger');
    dialog.returnValue = '';
    dialog.showModal();
    return new Promise((resolve) => {
      dialog.addEventListener('close', () => resolve(dialog.returnValue === 'ok'), { once: true });
    });
  }

  // ---------- ฟอร์ม ----------
  // อ่านค่าฟอร์มเป็น object (checkbox ที่ไม่ติ๊ก = '0')
  function formData(form) {
    const data = {};
    for (const el of form.elements) {
      if (!el.name || el.disabled) continue;
      if (el.type === 'checkbox') data[el.name] = el.checked ? (el.value || '1') : '0';
      else if (el.type === 'radio') { if (el.checked) data[el.name] = el.value; } else data[el.name] = el.value;
    }
    return data;
  }
  function clearErrors(form) {
    form.querySelectorAll('.is-invalid').forEach((el) => { el.classList.remove('is-invalid'); el.removeAttribute('aria-invalid'); });
    form.querySelectorAll('.error-text[data-auto]').forEach((el) => el.remove());
    const top = form.querySelector('[data-form-error]');
    if (top) top.innerHTML = '';
  }
  // แสดง error ใต้ช่องที่ผิด (ไม่พบช่อง → แสดงด้านบนของฟอร์ม)
  function showError(form, err) {
    const input = err.field && form.querySelector(`[name="${err.field}"]`);
    const anchor = err.field && form.querySelector(`[data-error-for="${err.field}"]`);
    if (input || anchor) {
      const target = anchor || input;
      if (input) { input.classList.add('is-invalid'); input.setAttribute('aria-invalid', 'true'); }
      const span = document.createElement('span');
      span.className = 'error-text';
      span.dataset.auto = '1';
      span.textContent = err.message;
      const field = target.closest('.field') || target.parentElement;
      field.appendChild(span);
      (input || target).focus?.();
      return;
    }
    const top = form.querySelector('[data-form-error]');
    if (top) top.innerHTML = `<div class="alert alert-error" role="alert">${esc(err.message)}</div>`;
    else flash('error', err.message);
  }
  // ผูกฟอร์ม: submit → onSubmit(data) พร้อมสถานะกำลังส่ง + แสดง error จากหลังบ้าน
  function bindForm(form, onSubmit) {
    // แก้ช่องที่ผิดแล้ว → ซ่อน error ของช่องนั้นทันที (ไม่ค้างจนกว่าจะกดบันทึกใหม่)
    form.addEventListener('input', (e) => {
      const el = e.target;
      if (!el.classList || !el.classList.contains('is-invalid')) return;
      el.classList.remove('is-invalid');
      el.removeAttribute('aria-invalid');
      el.closest('.field')?.querySelector('.error-text[data-auto]')?.remove();
    });
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      clearErrors(form);
      const btn = form.querySelector('[type=submit]');
      const label = btn && btn.innerHTML;
      if (btn) { btn.disabled = true; if (btn.dataset.loading) btn.textContent = btn.dataset.loading; }
      try {
        await onSubmit(formData(form), form);
      } catch (err) {
        if (!(err instanceof ApiError)) throw err;
        showError(form, err);
      } finally {
        if (btn) { btn.disabled = false; btn.innerHTML = label; }
      }
    });
  }
  // ตัวเลือก <option>
  const options = (rows, value, label, selected, placeholder) =>
    (placeholder !== undefined ? `<option value="">${esc(placeholder)}</option>` : '')
    + rows.map((r) => {
      const v = typeof value === 'function' ? value(r) : r[value];
      const l = typeof label === 'function' ? label(r) : r[label];
      return `<option value="${esc(v)}" ${String(v) === String(selected ?? '') ? 'selected' : ''}>${esc(l)}</option>`;
    }).join('');

  // ปุ่มแสดง/ซ่อนรหัสผ่าน
  document.addEventListener('click', (e) => {
    const btn = e.target.closest('[data-toggle-password]');
    if (!btn) return;
    const input = document.getElementById(btn.dataset.togglePassword);
    const show = input.type === 'password';
    input.type = show ? 'text' : 'password';
    btn.textContent = show ? 'ซ่อน' : 'แสดง';
    btn.setAttribute('aria-pressed', show ? 'true' : 'false');
  });

  // ---------- Layout ----------
  const ADMIN_MENU = [
    { group: 'ข้อมูลหลัก', items: [
      { label: 'ผู้ใช้งาน / พนักงาน', href: '/admin/users', screen: 'SC07', match: ['/admin/user'] },
      { label: 'แผนก', href: '/admin/departments', screen: 'SC08' },
      { label: 'ตำแหน่ง', href: '/admin/positions', screen: 'SC09' },
    ] },
    { group: 'สิทธิ์', items: [
      { label: 'หน้าจอ', href: '/admin/screens', screen: 'SC10' },
      { label: 'สิทธิ์ตามตำแหน่ง', href: '/admin/permissions', screen: 'SC10' },
    ] },
    { group: 'การเดินรถ', items: [
      { label: 'ประเภทรถ', href: '/admin/vehicle-types', screen: 'SC03' },
      { label: 'รถ', href: '/admin/vehicles', screen: 'SC01' },
      { label: 'จุดจอด', href: '/admin/stops', screen: 'SC04' },
      { label: 'เส้นทาง', href: '/admin/routes', screen: 'SC05', match: ['/admin/route'] },
      { label: 'ตารางเวลาเดินรถ', href: '/admin/schedules', screen: 'SC06' },
      { label: 'รอบการเดินรถ', href: '/admin/trips', screen: 'SC06', match: ['/admin/trip'] },
    ] },
    { group: 'การจอง', items: [{ label: 'การจอง', href: '/admin/bookings', screen: 'SC02', match: ['/admin/booking'] }] },
    { group: 'รายงาน', items: [{ label: 'รายงาน', href: '/admin/reports', screen: 'SC11' }] },
  ];

  const path = location.pathname.replace(/\.html$/, '').replace(/\/index$/, '/');
  const current = (cond) => (cond ? 'aria-current="page"' : '');

  // โลโก้ BusBuddy (public/img/) — ใส่ favicon ให้ทุกหน้าจากที่นี่ที่เดียว
  const LOGO = '<img class="brand-logo" src="/img/logo-64.png" alt="" width="32" height="32">';
  document.head.insertAdjacentHTML('beforeend',
    '<link rel="icon" type="image/png" href="/img/favicon.png"><link rel="apple-touch-icon" href="/img/apple-touch-icon.png">');

  function tabbar(label, tabs) {
    return `<nav class="tabbar" aria-label="${label}"><div class="tabbar-inner">${tabs.map((t) =>
      `<a href="${t.href}" ${current(t.match)}>${icon(t.icon)}<span>${t.label}</span></a>`).join('')}</div></nav>`;
  }

  function layoutUser(me) {
    const header = `<header class="topbar"><div class="topbar-inner">
        <a class="brand" href="/">${LOGO} BusBuddy</a><span class="spacer"></span>
        ${me.is_driver ? '<a class="switch-link" href="/driver/">งานคนขับ</a>' : ''}
        ${me.has_admin ? '<a class="switch-link" href="/admin/">หลังบ้าน</a>' : ''}
      </div></header>`;
    const nav = tabbar('เมนูหลัก', [
      { href: '/', label: 'หน้าหลัก', icon: 'home', match: path === '/' },
      { href: '/search', label: 'จองรถ', icon: 'search', match: /^\/(search|trip|book)/.test(path) },
      { href: '/my', label: 'การจองของฉัน', icon: 'ticket', match: /^\/(my|item)/.test(path) },
      { href: '/profile', label: 'โปรไฟล์', icon: 'user', match: path.startsWith('/profile') },
    ]);
    const main = document.getElementById('main');
    main.insertAdjacentHTML('beforebegin', header);
    main.insertAdjacentHTML('afterend', nav);
  }

  // คนขับ: แสดงชื่อผู้ login (กันใช้เครื่องร่วมกันแล้วกดงานผิดบัญชี) + สลับโหมด/ออกจากระบบที่หัวหน้า
  function layoutDriver(me) {
    const header = `<header class="topbar"><div class="topbar-inner">
        <a class="brand" href="/driver/">${LOGO}<span class="brand-text">
          <span class="brand-name">BusBuddy <span class="role-tag">คนขับ</span></span>
          <span class="brand-who">${esc(me.name)}</span>
        </span></a><span class="spacer"></span>
        <a class="switch-link" href="/"><span class="hide-xs">โหมด</span>ผู้โดยสาร</a>
        ${me.has_admin ? '<a class="switch-link" href="/admin/">หลังบ้าน</a>' : ''}
        <button class="topbar-icon" type="button" data-logout aria-label="ออกจากระบบ" title="ออกจากระบบ">${icon('logout')}</button>
      </div></header>`;
    const nav = tabbar('เมนูคนขับ', [
      { href: '/driver/', label: 'งานวันนี้', icon: 'steering', match: path === '/driver/' || /^\/driver\/(trip|scan|close)/.test(path) },
      { href: '/driver/history', label: 'ประวัติ', icon: 'clock', match: path.startsWith('/driver/history') },
      { href: '/profile', label: 'โปรไฟล์', icon: 'user', match: path.startsWith('/profile') },
    ]);
    const main = document.getElementById('main');
    main.insertAdjacentHTML('beforebegin', header);
    main.insertAdjacentHTML('afterend', nav);
  }

  function layoutAdmin(me, perms) {
    const menu = ADMIN_MENU.map((g) => {
      const items = g.items.filter((i) => perms[i.screen]);
      if (!items.length) return '';
      return `<div class="group">${g.group}</div>` + items.map((i) => {
        const on = path === i.href || path.startsWith(i.href + '/') || (i.match || []).some((m) => path.startsWith(m));
        return `<a class="nav" href="${i.href}" ${current(on)}>${i.label}</a>`;
      }).join('');
    }).join('');
    const main = document.getElementById('main');
    const root = document.createElement('div');
    root.className = 'admin';
    root.innerHTML = `
      <aside class="sidebar" id="admin-sidebar" aria-label="เมนูหลังบ้าน">
        <div class="sidebar-head">
          <a class="brand" href="/admin/">${LOGO} BusBuddy</a>
          <button class="sidebar-close" type="button" aria-label="ปิดเมนู">${icon('close')}</button>
        </div>
        <a class="nav" href="/admin/" ${current(path === '/admin/')}>Dashboard</a>
        ${menu}
      </aside>
      <div class="sidebar-backdrop" aria-hidden="true"></div>
      <div class="admin-main">
        <header class="admin-top">
          <button class="btn btn-sm menu-toggle" type="button" aria-expanded="false" aria-controls="admin-sidebar" aria-label="เปิดเมนู">${icon('menu')}</button>
          <span class="who">เข้าสู่ระบบเป็น <b>${esc(me.name)}</b></span>
          <span class="grow"></span>
          <a class="btn btn-sm btn-ghost" href="/">โหมดผู้โดยสาร</a>
          ${me.is_driver ? '<a class="btn btn-sm btn-ghost" href="/driver/">งานคนขับ</a>' : ''}
          <button class="btn btn-sm" type="button" data-logout>${icon('logout')} <span class="btn-label">ออกจากระบบ</span></button>
        </header>
      </div>`;
    main.replaceWith(root);
    main.classList.add('admin-content');
    root.querySelector('.admin-main').appendChild(main);

    // ปุ่มเปิด/ปิด sidebar บนจอเล็ก (ปิดได้ด้วยปุ่มกากบาท, แตะพื้นหลัง หรือกด Esc)
    const toggle = root.querySelector('.menu-toggle');
    const closeBtn = root.querySelector('.sidebar-close');
    const setOpen = (open) => {
      root.classList.toggle('menu-open', open);
      toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
      document.body.style.overflow = open ? 'hidden' : '';
      (open ? closeBtn : toggle).focus();
    };
    toggle.addEventListener('click', () => setOpen(!root.classList.contains('menu-open')));
    closeBtn.addEventListener('click', () => setOpen(false));
    root.querySelector('.sidebar-backdrop').addEventListener('click', () => setOpen(false));
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && root.classList.contains('menu-open')) setOpen(false); });
  }

  function layoutAuth() {
    const main = document.getElementById('main');
    const wrap = document.createElement('div');
    wrap.className = 'auth-wrap';
    wrap.innerHTML = `<div class="auth-card">
        <div class="auth-brand"><div class="logo"><img src="/img/logo.png" alt="" width="100" height="100"></div><h1>BusBuddy</h1><p>ระบบจองรถรับส่งและบริหารการเดินรถ</p></div>
      </div>`;
    main.replaceWith(wrap);
    main.classList.add('card');
    wrap.querySelector('.auth-card').appendChild(main);
  }

  // ออกจากระบบ
  async function logout() {
    const body = await post('/api/logout');
    location.href = body.redirect || '/login';
  }
  document.addEventListener('click', (e) => { if (e.target.closest('[data-logout]')) logout(); });

  // ---------- หน้าแสดงข้อผิดพลาด ----------
  function errorView(err) {
    const main = document.getElementById('main');
    const views = {
      403: ['ไม่มีสิทธิ์เข้าถึง (Access Denied)', err.message || 'ตำแหน่งของคุณไม่มีสิทธิ์ใช้งานหน้านี้ หากต้องการใช้งานกรุณาติดต่อผู้ดูแลระบบ'],
      404: ['ไม่พบหน้าที่ต้องการ', err.message || 'ลิงก์อาจไม่ถูกต้อง หรือข้อมูลถูกลบไปแล้ว'],
    };
    const [title, msg] = views[err.status] || ['เกิดข้อผิดพลาด', err.message];
    main.innerHTML = `<div class="card center" style="margin-top:var(--s5)">
        <h2>${esc(title)}</h2><p class="muted">${esc(msg)}</p>
        <div class="btn-row" style="justify-content:center">
          <a class="btn" href="javascript:history.back()">ย้อนกลับ</a>
          <a class="btn btn-primary" href="/">กลับหน้าหลัก</a>
        </div></div>`;
    document.title = `${title} · BusBuddy`;
  }

  // ---------- เริ่มหน้า ----------
  // page(async (ctx) => {...}) — ctx = { me, perms, can(screen, action), hasScreen(screen) }
  // หน้า auth (login/register) ไม่ต้อง login
  // โหมดล่าสุด (ผู้โดยสาร/คนขับ) — หน้าโปรไฟล์ใช้ร่วมกัน จึงแสดงตามโหมดที่มาจาก ไม่ให้แถบเมนูคนขับหายไป
  const MODE_KEY = 'mut-mode';
  const readMode = () => { try { return sessionStorage.getItem(MODE_KEY); } catch (e) { return null; } };
  const saveMode = (m) => { try { sessionStorage.setItem(MODE_KEY, m); } catch (e) { /* ignore */ } };

  async function page(fn) {
    let kind = document.body.dataset.layout || 'user';
    const main = document.getElementById('main');
    main.setAttribute('aria-busy', 'true');
    // <a data-icon="search"> → ใส่ไอคอนหน้าข้อความ
    document.querySelectorAll('[data-icon]').forEach((el) => el.insertAdjacentHTML('afterbegin', `${icon(el.dataset.icon)} `));
    try {
      let ctx = {};
      if (kind === 'auth') {
        layoutAuth();
      } else {
        const [[me], permRows] = await api('me');
        if (!me) { await logout(); return; }
        const perms = {};
        for (const r of permRows) perms[r.screen_id] = { add: !!r.can_add, edit: !!r.can_edit, delete: !!r.can_delete };
        me.is_driver = !!Number(me.is_driver);
        me.has_admin = !!Number(me.has_admin);
        ctx = {
          me, perms,
          hasScreen: (s) => !!perms[s],
          can: (s, action) => !!(perms[s] && perms[s][action]),
        };
        if (kind === 'user' && path.startsWith('/profile') && me.is_driver && readMode() === 'driver') kind = 'driver';
        if (kind === 'driver' || kind === 'user') saveMode(kind);
        if (kind === 'driver') layoutDriver(me);
        else if (kind === 'admin') layoutAdmin(me, perms);
        else layoutUser(me);
      }
      const f = takeFlash();
      if (f) flash(f.type, f.msg);
      await fn(ctx);
    } catch (err) {
      if (!(err instanceof ApiError)) { console.error(err); err = new ApiError(500, 'เกิดข้อผิดพลาดในหน้าเว็บ'); }
      errorView(err);
    } finally {
      main.removeAttribute('aria-busy');
    }
  }

  window.MUT = {
    api, post, ApiError, page, go, flash, setFlash, confirmBox, bindForm, formData, clearErrors, showError, options,
    esc, fmtDate, fmtTime, fmtDateTime, fmtNum, addMinutes, dayName, DAY_NAMES, badge, qs, param, params, icon, errorView,
  };
})();
