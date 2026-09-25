import { useEffect, useState } from "react";
import { useAuth } from "../../context/useAuth";
import { getStudioCustomer } from "../../services/studioCustomersService";
import "./StudioCustomers.css";

const dateFormatter = new Intl.DateTimeFormat("en-LK", { dateStyle: "medium", timeZone: "UTC" });
const createdFormatter = new Intl.DateTimeFormat("en-LK", { dateStyle: "medium", timeStyle: "short" });
const priceFormatter = new Intl.NumberFormat("en-LK", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

export default function StudioCustomerDetails({ customerId }) {
  const { token } = useAuth();
  const [attempt, setAttempt] = useState(0);
  const [state, setState] = useState({ loading: true, error: null, customer: null });
  useEffect(() => {
    const controller = new AbortController();
    getStudioCustomer(token, customerId, controller.signal)
      .then((customer) => {
        if (!controller.signal.aborted) setState({ loading: false, error: null, customer });
      })
      .catch((error) => {
        if (!controller.signal.aborted) setState({ loading: false, error, customer: null });
      });
    return () => controller.abort();
  }, [token, customerId, attempt]);

  const retry = () => {
    setState({ loading: true, error: null, customer: null });
    setAttempt((value) => value + 1);
  };
  const { loading, error, customer } = state;
  return <div className="customers-page">
    <a className="customers-back" href="/studio/customers">← Back to Customers</a>
    {loading ? <section className="customers-state" role="status">Loading customer details…</section>
      : error ? <section className="customers-state customers-error" role="alert">
        <h1>{error.status === 404 ? "Customer not found" : "Unable to load customer details"}</h1>
        <p>{error.status === 404 ? "This customer has no bookings available to your studio." : error.message}</p>
        <button type="button" onClick={retry}>Retry</button>
      </section>
      : <>
        <section className="customers-heading">
          <p>CUSTOMER #{customer.customerId}</p>
          <h1>{customer.name.trim() || "Name unavailable"}</h1>
          <span>{customer.email.trim() || "Email unavailable"}</span>
        </section>
        <section className="customers-detail-summary" aria-label="Booking summary for your studio">
          <div><span>Total bookings</span><strong>{customer.totalBookings}</strong></div>
          <div><span>Completed bookings</span><strong>{customer.completedBookings}</strong></div>
          <div><span>Active bookings</span><strong>{customer.activeBookings}</strong></div>
        </section>
        <p className="customers-history-note">Active includes pending, AI recommended, awaiting approval, confirmed, and rescheduled bookings.</p>
        <h2 className="customers-history-title">Booking History</h2>
        {!customer.bookings.length ? <section className="customers-state"><h3>No bookings yet</h3><p>No booking history is available for this customer with your studio.</p></section>
          : <div className="customers-list">{customer.bookings.map((booking) => {
            const status = booking.status === "AIRecommended" ? "AI Recommended" : booking.status === "AwaitingApproval" ? "Awaiting Approval" : booking.status;
            const tone = booking.status === "Completed" ? "complete" : ["Cancelled", "Rejected"].includes(booking.status) ? "closed" : "active";
            return <article className="customers-card" key={booking.bookingId}>
              <header className="customers-booking-header"><h3>Booking #{booking.bookingId}</h3><span className={`customers-status ${tone}`}>{status}</span></header>
              <dl>
                <div><dt>Package</dt><dd>{booking.packageName.trim() || "Package name unavailable"}</dd></div>
                <div><dt>Event date</dt><dd><time dateTime={booking.bookingDate}>{dateFormatter.format(new Date(`${booking.bookingDate}T00:00:00Z`))}</time></dd></div>
                <div><dt>Booking total</dt><dd>LKR {priceFormatter.format(booking.totalPrice)}</dd></div>
                <div><dt>Booked on</dt><dd><time dateTime={booking.createdAt}>{createdFormatter.format(new Date(booking.createdAt))}</time></dd></div>
              </dl>
            </article>;
          })}</div>}
      </>}
  </div>;
}
