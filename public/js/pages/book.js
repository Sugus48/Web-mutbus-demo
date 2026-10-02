// 8.1 เลือกจำนวนที่นั่ง → CALL api_trip
MUT.page(async () => {
  const { qs } = MUT;
  const ctx = await TripCtx.load();
  const { trip, board, alight } = ctx;
  const back = '/trip' + qs({ id: trip.trip_id, board, alight });
  document.getElementById('back-link').href = back;
  if (trip.blocked) return MUT.go(back, 'error', trip.blocked);

  document.getElementById('trip-summary').innerHTML = TripCtx.summaryCard(ctx);
  const form = document.getElementById('seats-form');
  const input = document.getElementById('seats');
  const max = Number(trip.max_seats);
  input.max = max;
  input.value = Math.min(Math.max(1, Number(MUT.param('seats')) || 1), max);
  document.getElementById('seats-hint').textContent =
    `ที่นั่งคงเหลือในช่วงนี้ ${trip.seg_remaining} ที่ · เลือกได้สูงสุด ${max} ที่นั่ง (ไม่เกิน 4 ที่นั่งต่อรายการจอง)`;
  form.hidden = false;

  const minus = form.querySelector('[data-step="-1"]');
  const plus = form.querySelector('[data-step="1"]');
  const sync = () => { const v = Number(input.value); minus.disabled = v <= 1; plus.disabled = v >= max; };
  form.querySelectorAll('[data-step]').forEach((b) => b.addEventListener('click', () => {
    input.value = Math.min(max, Math.max(1, Number(input.value || 1) + Number(b.dataset.step)));
    sync();
  }));
  input.addEventListener('input', sync);
  sync();

  form.addEventListener('submit', (e) => {
    e.preventDefault();
    const seats = Number(input.value);
    if (!(seats >= 1 && seats <= max)) return MUT.flash('error', `เลือกได้ 1–${max} ที่นั่ง`);
    location.href = '/book-confirm' + qs({ id: trip.trip_id, board, alight, seats });
  });
});
