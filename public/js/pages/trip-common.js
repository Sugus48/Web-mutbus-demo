// ใช้ร่วมกันในหน้า รายละเอียดรอบ / เลือกที่นั่ง / ยืนยันการจอง → CALL api_trip
window.TripCtx = {
  async load() {
    const { id, board, alight } = MUT.params();
    const [[trip], stops] = await MUT.api('trip', { trip: id, board, alight });
    const seg = {
      board: stops.find((s) => s.stop_order === trip.board_order) || null,
      alight: stops.find((s) => s.stop_order === trip.alight_order) || null,
    };
    return { trip, stops, seg, board, alight };
  },
  // การ์ดสรุปรอบ + ช่วงที่เลือก
  summaryCard({ trip, seg }) {
    const { esc, fmtDate, fmtTime } = MUT;
    return `<div class="card trip-card">
      <strong>${esc(trip.route_name)}</strong>
      <div class="muted small">${fmtDate(trip.trip_date)} · รถออก ${fmtTime(trip.depart_time)} · ${esc(trip.plate_no)} (${esc(trip.type_name)})</div>
      <div class="times"><span class="time">${fmtTime(seg.board.arrive_at)}</span><span class="arrow" aria-hidden="true"></span><span class="time">${fmtTime(seg.alight.arrive_at)}</span></div>
      <div class="stop-names"><span>${esc(seg.board.stop_name)}</span><span class="right">${esc(seg.alight.stop_name)}</span></div>
    </div>`;
  },
};
