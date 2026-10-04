import { useMemo } from "react";
import BookingStatusBadge from "../../components/booking/BookingStatusBadge";

const dateFormatter = new Intl.DateTimeFormat("en-LK", { weekday: "long", day: "numeric", month: "long", year: "numeric", timeZone: "UTC" });
const timeFormatter = new Intl.DateTimeFormat("en-LK", { hour: "numeric", minute: "2-digit", timeZone: "UTC" });
const scheduledStatuses = new Set(["Pending", "AIRecommended", "AwaitingApproval", "Confirmed", "Rescheduled"]);

function today() { const now = new Date(); return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`; }
function formatDate(value) { return dateFormatter.format(new Date(`${String(value).slice(0, 10)}T00:00:00Z`)); }
function formatTime(value) { if (!/^\d{2}:\d{2}/.test(value || "")) return "Not set"; const [hours, minutes] = value.split(":").map(Number); return timeFormatter.format(new Date(Date.UTC(2000, 0, 1, hours, minutes))); }
function formatName(value, fallback) { const trimmed = typeof value === "string" ? value.trim() : ""; return trimmed || fallback; }

export default function StudioSchedule({ bookings, isLoading, error, onRetry }) {
  const groupedBookings = useMemo(() => {
    const dates = new Map();
    bookings.filter((booking) => scheduledStatuses.has(booking.status) && String(booking.bookingDate).slice(0, 10) >= today()).sort((first, second) => `${first.bookingDate}${first.startTime}`.localeCompare(`${second.bookingDate}${second.startTime}`)).forEach((booking) => {
      const key = String(booking.bookingDate).slice(0, 10);
      dates.set(key, [...(dates.get(key) || []), booking]);
    });
    return [...dates.entries()];
  }, [bookings]);

  const calendarDays = groupedBookings.slice(0, 7);

  return <>
    <section className="studio-route-heading booking-route-heading"><div><p className="studio-kicker">STUDIO SCHEDULE</p><h1>Schedule</h1><p>See upcoming booking activity grouped by shoot date.</p></div><button className="dashboard-primary-button" type="button" onClick={() => window.location.assign("/studio/bookings")}>Manage bookings</button></section>
    {isLoading ? <section className="booking-state"><span className="dashboard-loading-pulse" /> Loading schedule…</section> : error ? <section className="booking-state booking-error"><strong>Unable to load the schedule.</strong><p>{error}</p><button className="dashboard-primary-button" type="button" onClick={onRetry}>Retry</button></section> : !calendarDays.length ? <section className="booking-state"><strong>No upcoming bookings.</strong><p>Upcoming pending and scheduled bookings will appear here.</p></section> : <section className="schedule-calendar"><div className="schedule-calendar-header"><span>Upcoming bookings</span><strong>{calendarDays.reduce((total, [, items]) => total + items.length, 0)} total</strong></div><div className="schedule-calendar-grid">{calendarDays.map(([date, items]) => <article key={date} className="schedule-day-card"><header><div><small>{new Intl.DateTimeFormat("en-LK", { weekday: "short", timeZone: "UTC" }).format(new Date(`${String(date).slice(0, 10)}T00:00:00Z`))}</small><strong>{new Intl.DateTimeFormat("en-LK", { day: "numeric", month: "short", timeZone: "UTC" }).format(new Date(`${String(date).slice(0, 10)}T00:00:00Z`))}</strong></div><span>{items.length}</span></header><div className="schedule-day-items">{items.map((booking) => <button className="schedule-booking-card" type="button" key={booking.id} onClick={() => window.location.assign(`/studio/bookings/${booking.id}`)}><div className="schedule-slot-top"><time>{formatTime(booking.startTime)}</time><BookingStatusBadge status={booking.status} /></div><strong>{formatName(booking.customerName, `Customer #${booking.customerId}`)}</strong><small>{formatName(booking.packageName, `Package #${booking.packageId}`)}</small><small>{booking.location || "Location not provided"}</small></button>)}</div></article>)}</div></section>}
  </>;
}
