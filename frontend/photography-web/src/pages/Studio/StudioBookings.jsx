import { useMemo, useState } from "react";
import BookingStatusBadge from "../../components/booking/BookingStatusBadge";

const statusFilters = ["All", "Pending", "AIRecommended", "AwaitingApproval", "Confirmed", "Rejected", "Cancelled", "Rescheduled", "Completed"];

const dateFormatter = new Intl.DateTimeFormat("en-LK", { day: "2-digit", month: "short", year: "numeric", timeZone: "UTC" });
const timeFormatter = new Intl.DateTimeFormat("en-LK", { hour: "numeric", minute: "2-digit", timeZone: "UTC" });

function formatDate(value) {
  if (!value) return "Not set";
  return dateFormatter.format(new Date(`${String(value).slice(0, 10)}T00:00:00Z`));
}

function formatTime(value) {
  if (!/^\d{2}:\d{2}/.test(value || "")) return "Not set";
  const [hours, minutes] = value.split(":").map(Number);
  return timeFormatter.format(new Date(Date.UTC(2000, 0, 1, hours, minutes)));
}

function readableStatus(status) {
  return status === "AIRecommended" ? "AI Recommended" : status === "AwaitingApproval" ? "Awaiting Approval" : status;
}

export default function StudioBookings({ bookings, isLoading, error, onRetry }) {
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState("All");
  const [date, setDate] = useState("");
  const [sort, setSort] = useState("newest");

  const visibleBookings = useMemo(() => {
    const searchTerm = search.trim().toLowerCase();
    return [...bookings]
      .filter((booking) => status === "All" || booking.status === status)
      .filter((booking) => !date || String(booking.bookingDate).slice(0, 10) === date)
      .filter((booking) => !searchTerm || [booking.id, booking.customerId, booking.studioId, booking.packageId, booking.location].some((value) => String(value ?? "").toLowerCase().includes(searchTerm)))
      .sort((first, second) => {
        const firstValue = `${first.bookingDate || ""}T${first.startTime || ""}`;
        const secondValue = `${second.bookingDate || ""}T${second.startTime || ""}`;
        return sort === "newest" ? secondValue.localeCompare(firstValue) : firstValue.localeCompare(secondValue);
      });
  }, [bookings, date, search, sort, status]);

  return <>
    <section className="studio-route-heading booking-route-heading"><div><p className="studio-kicker">BOOKING MANAGEMENT</p><h1>Bookings</h1><p>Review customer booking requests, current statuses, and shoot details.</p></div><button className="dashboard-primary-button" type="button" onClick={() => window.location.assign("/studio/schedule")}>View Schedule</button></section>
    <section className="booking-controls" aria-label="Booking filters">
      <label className="booking-search"><span aria-hidden="true">⌕</span><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search booking, customer, package or location" /></label>
      <label><span>Status</span><select value={status} onChange={(event) => setStatus(event.target.value)}>{statusFilters.map((item) => <option value={item} key={item}>{item === "All" ? "All statuses" : readableStatus(item)}</option>)}</select></label>
      <label><span>Date</span><input type="date" value={date} onChange={(event) => setDate(event.target.value)} /></label>
      <label><span>Sort</span><select value={sort} onChange={(event) => setSort(event.target.value)}><option value="newest">Newest first</option><option value="oldest">Oldest first</option></select></label>
    </section>
    {isLoading ? <section className="booking-state"><span className="dashboard-loading-pulse" /> Loading bookings…</section> : error ? <section className="booking-state booking-error"><strong>Unable to load bookings.</strong><p>{error}</p><button type="button" className="dashboard-primary-button" onClick={onRetry}>Retry</button></section> : !visibleBookings.length ? <section className="booking-state"><strong>No bookings found.</strong><p>{bookings.length ? "Try changing your filters." : "Booking requests will appear here when they are created."}</p></section> : <section className="booking-table-card">
      <div className="booking-table-summary"><strong>{visibleBookings.length} booking{visibleBookings.length === 1 ? "" : "s"}</strong><span>Showing real-time booking data</span></div>
      <div className="booking-table-scroll"><table><thead><tr><th>Booking</th><th>Customer</th><th>Date & time</th><th>Location</th><th>Status</th><th>Created</th><th><span className="sr-only">Actions</span></th></tr></thead><tbody>{visibleBookings.map((booking) => <tr key={booking.id}><td><strong>#{booking.id}</strong><small>Package #{booking.packageId} · Studio #{booking.studioId}</small></td><td>Customer #{booking.customerId}</td><td><strong>{formatDate(booking.bookingDate)}</strong><small>{formatTime(booking.startTime)} – {formatTime(booking.endTime)}</small></td><td>{booking.location || "Not provided"}</td><td><BookingStatusBadge status={booking.status} /></td><td>{formatDate(booking.createdAt)}</td><td><button className="booking-view-button" type="button" onClick={() => window.location.assign(`/studio/bookings/${booking.id}`)}>View details</button></td></tr>)}</tbody></table></div>
    </section>}
  </>;
}
