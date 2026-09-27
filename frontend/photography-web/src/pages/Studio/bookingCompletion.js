export function bookingEndTimestamp(booking) {
  const date = booking?.bookingDate;
  const time = booking?.endTime;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date || "") ||
      !/^(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d(?:\.\d{1,7})?)?$/.test(time || "")) return NaN;
  // Asia/Colombo uses UTC+05:30 for scheduled bookings. Never use the browser's zone.
  // Round sub-millisecond precision up so the UI cannot enable completion early.
  const [whole, fraction = ""] = time.split(".");
  const seconds = whole.length === 5 ? `${whole}:00` : whole;
  return Date.parse(`${date}T${seconds}+05:30`) + Math.ceil(Number(`0.${fraction || "0"}`) * 1000);
}

export function canCompleteBooking(booking, now = Date.now()) {
  return booking?.status === "Confirmed" && now > bookingEndTimestamp(booking);
}

export function completionAvailabilityMessage(booking) {
  const end = bookingEndTimestamp(booking);
  if (!Number.isFinite(end)) return "Scheduled end time unavailable.";
  return `Available after ${new Intl.DateTimeFormat("en-LK", {
    timeZone: "Asia/Colombo", day: "numeric", month: "short", year: "numeric",
    hour: "numeric", minute: "2-digit", hour12: true,
  }).format(new Date(end))} (Asia/Colombo)`;
}
