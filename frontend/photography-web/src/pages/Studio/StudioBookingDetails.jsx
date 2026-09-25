import { useCallback, useEffect, useState } from "react";
import BookingStatusBadge from "../../components/booking/BookingStatusBadge";
import { cancelBooking, getBooking, getBookingHistory, updateBookingStatus } from "../../services/bookingService";
import { useAuth } from "../../context/useAuth";

const dateFormatter = new Intl.DateTimeFormat("en-LK", { day: "2-digit", month: "long", year: "numeric", timeZone: "UTC" });
const dateTimeFormatter = new Intl.DateTimeFormat("en-LK", { day: "2-digit", month: "short", year: "numeric", hour: "numeric", minute: "2-digit" });
const timeFormatter = new Intl.DateTimeFormat("en-LK", { hour: "numeric", minute: "2-digit", timeZone: "UTC" });

const transitions = {
  Pending: ["AIRecommended", "AwaitingApproval", "Confirmed", "Rejected", "Cancelled"],
  AIRecommended: ["AwaitingApproval", "Confirmed", "Rejected", "Cancelled"],
  AwaitingApproval: ["Confirmed", "Rejected", "Cancelled"],
  Confirmed: ["Rescheduled", "Completed", "Cancelled"],
  Rescheduled: ["AwaitingApproval", "Confirmed", "Cancelled"],
};

function readableStatus(status) {
  return status === "AIRecommended" ? "AI Recommended" : status === "AwaitingApproval" ? "Awaiting Approval" : status;
}

function actionLabel(action) {
  if (action === "Confirmed") return "Confirm booking";
  if (action === "Completed") return "Mark as completed";
  if (action === "Rejected") return "Reject booking";
  if (action === "Cancelled") return "Cancel booking";
  if (action === "Rescheduled") return "Mark as rescheduled";
  return `Mark as ${readableStatus(action).toLowerCase()}`;
}

function formatDate(value) { return value ? dateFormatter.format(new Date(`${String(value).slice(0, 10)}T00:00:00Z`)) : "Not set"; }
function formatDateTime(value) { return value ? dateTimeFormatter.format(new Date(value)) : "Not available"; }
function formatTime(value) { if (!/^\d{2}:\d{2}/.test(value || "")) return "Not set"; const [hours, minutes] = value.split(":").map(Number); return timeFormatter.format(new Date(Date.UTC(2000, 0, 1, hours, minutes))); }

function ActionDialog({ action, isSaving, onClose, onSubmit }) {
  const [reason, setReason] = useState("");
  const needsReason = action === "Rejected" || action === "Cancelled";
  return <div className="booking-dialog-backdrop" role="presentation"><section className="booking-dialog" role="dialog" aria-modal="true" aria-labelledby="booking-action-title"><p className="studio-kicker">BOOKING ACTION</p><h2 id="booking-action-title">{action === "Cancelled" ? "Cancel this booking?" : `${readableStatus(action)} this booking?`}</h2><p>This changes the booking status and records the action in its history.</p>{needsReason && <label>Reason<textarea value={reason} onChange={(event) => setReason(event.target.value)} placeholder={`Why is this booking being ${action.toLowerCase()}?`} maxLength="1000" /></label>}<div className="booking-dialog-actions"><button type="button" onClick={onClose} disabled={isSaving}>Keep booking</button><button className={action === "Cancelled" || action === "Rejected" ? "danger" : "confirm"} type="button" onClick={() => onSubmit(reason)} disabled={isSaving}>{isSaving ? "Saving…" : actionLabel(action)}</button></div></section></div>;
}

export default function StudioBookingDetails({ bookingId }) {
  const { token, user } = useAuth();
  const [booking, setBooking] = useState(null);
  const [history, setHistory] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState("");
  const [action, setAction] = useState("");
  const [isSaving, setIsSaving] = useState(false);
  const [feedback, setFeedback] = useState("");

  const load = useCallback(async () => {
    setIsLoading(true); setError("");
    try {
      const [loadedBooking, loadedHistory] = await Promise.all([getBooking(token, bookingId), getBookingHistory(token, bookingId)]);
      setBooking(loadedBooking); setHistory([...loadedHistory].sort((first, second) => new Date(first.createdAt) - new Date(second.createdAt)));
    } catch (requestError) { setError(requestError.message || "Unable to load this booking."); }
    finally { setIsLoading(false); }
  }, [bookingId, token]);

  useEffect(() => {
    const loadTimer = window.setTimeout(() => { load(); }, 0);
    return () => window.clearTimeout(loadTimer);
  }, [load]);

  const submitAction = async (reason) => {
    if (!booking || !action) return;
    setIsSaving(true); setFeedback("");
    try {
      const changedBy = user?.fullName || user?.email || "Authenticated user";
      if (action === "Cancelled") await cancelBooking(token, booking.id, changedBy, reason);
      else await updateBookingStatus(token, booking.id, action, changedBy, reason);
      setAction("");
      setFeedback(`Booking status changed to ${readableStatus(action)}.`);
      await load();
    } catch (requestError) { setFeedback(requestError.message || "Unable to update this booking."); }
    finally { setIsSaving(false); }
  };

  if (isLoading) return <section className="booking-state"><span className="dashboard-loading-pulse" /> Loading booking details…</section>;
  if (error) return <section className="booking-state booking-error"><strong>Unable to load this booking.</strong><p>{error}</p><button className="dashboard-primary-button" type="button" onClick={load}>Retry</button><button className="booking-link-button" type="button" onClick={() => window.location.assign("/studio/bookings")}>Back to bookings</button></section>;

  const availableActions = transitions[booking.status] || [];
  return <>
    <section className="studio-route-heading booking-route-heading"><div><button className="booking-back-link" type="button" onClick={() => window.location.assign("/studio/bookings")}>← All bookings</button><p className="studio-kicker">BOOKING #{booking.id}</p><h1>Booking details</h1><p>Review the complete request and status activity.</p></div><BookingStatusBadge status={booking.status} /></section>
    {feedback && <p className="booking-feedback" role="status">{feedback}</p>}
    <section className="booking-detail-grid"><article className="booking-detail-card"><h2>Booking details</h2><dl><div><dt>Customer</dt><dd>Customer #{booking.customerId}</dd></div><div><dt>Studio</dt><dd>Studio #{booking.studioId}</dd></div><div><dt>Package</dt><dd>Package #{booking.packageId}</dd></div><div><dt>Shoot date</dt><dd>{formatDate(booking.bookingDate)}</dd></div><div><dt>Time</dt><dd>{formatTime(booking.startTime)} – {formatTime(booking.endTime)}</dd></div><div><dt>Location</dt><dd>{booking.location || "Not provided"}</dd></div><div><dt>Total price</dt><dd>{Number(booking.totalPrice || 0).toLocaleString("en-LK", { style: "currency", currency: "LKR" })}</dd></div><div><dt>Created</dt><dd>{formatDateTime(booking.createdAt)}</dd></div></dl>{booking.notes && <div className="booking-notes"><h3>Notes</h3><p>{booking.notes}</p></div>}</article>
      <aside className="booking-actions-card"><h2>Actions</h2><p>Available actions follow the current backend status rules.</p>{availableActions.length ? <div>{availableActions.map((item) => <button key={item} type="button" className={item === "Cancelled" || item === "Rejected" ? "booking-danger-action" : "booking-primary-action"} onClick={() => setAction(item)}>{item === "Confirmed" ? "Confirm booking" : item === "Completed" ? "Mark as completed" : item === "Rejected" ? "Reject booking" : "Cancel booking"}</button>)}</div> : <p className="booking-muted">No further actions are available for this status.</p>}</aside>
    </section>
    <section className="booking-history-card"><div><p className="studio-kicker">STATUS HISTORY</p><h2>Timeline</h2></div>{history.length ? <ol className="booking-timeline">{history.map((item) => <li key={item.id}><span className="booking-timeline-dot" /><div><div><strong>{item.oldStatus ? `${readableStatus(item.oldStatus)} → ` : ""}{readableStatus(item.newStatus)}</strong><time>{formatDateTime(item.createdAt)}</time></div><p>Changed by {item.changedBy}{item.reason ? ` · ${item.reason}` : ""}</p></div></li>)}</ol> : <p className="booking-muted">No status changes have been recorded yet.</p>}</section>
    {action && <ActionDialog action={action} isSaving={isSaving} onClose={() => setAction("")} onSubmit={submitAction} />}
  </>;
}
