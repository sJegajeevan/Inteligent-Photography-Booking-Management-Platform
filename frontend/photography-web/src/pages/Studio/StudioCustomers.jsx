import { useEffect, useState } from "react";
import { useAuth } from "../../context/useAuth";
import { getStudioCustomers } from "../../services/studioCustomersService";
import "./StudioCustomers.css";

const dateFormatter = new Intl.DateTimeFormat("en-LK", {
  day: "numeric", month: "short", year: "numeric", timeZone: "UTC",
});

function CustomerCard({ customer }) {
  const status = customer.latestBookingStatus;
  const statusLabel = status === "AIRecommended" ? "AI Recommended"
    : status === "AwaitingApproval" ? "Awaiting Approval" : status;
  return <article className="customers-card">
    <header><span className="customers-avatar" aria-hidden="true">{Array.from(customer.name.trim())[0]?.toUpperCase() || "—"}</span>
      <div><h2>{customer.name.trim() || "Name unavailable"}</h2><p>{customer.email.trim() || "Email unavailable"}</p></div>
    </header>
    <dl>
      <div><dt>Bookings with your studio</dt><dd className="customers-count">{customer.totalBookings}</dd></div>
      <div><dt>Latest booking date</dt><dd><time dateTime={customer.latestBookingDate}>{dateFormatter.format(new Date(`${customer.latestBookingDate}T00:00:00Z`))}</time></dd></div>
      <div><dt>Latest booking status</dt><dd><span className="customers-status">{statusLabel}</span></dd></div>
    </dl>
    <footer><button type="button" onClick={() => window.location.assign(`/studio/customers/${customer.customerId}`)}>View Details</button></footer>
  </article>;
}

export default function StudioCustomers() {
  const { token } = useAuth();
  const [search, setSearch] = useState("");
  const [attempt, setAttempt] = useState(0);
  const [state, setState] = useState({ loading: true, error: "", customers: [] });

  useEffect(() => {
    const controller = new AbortController();
    getStudioCustomers(token, controller.signal)
      .then((customers) => {
        if (!controller.signal.aborted) setState({ loading: false, error: "", customers });
      })
      .catch((error) => {
        if (!controller.signal.aborted) setState({ loading: false, error: error.message, customers: [] });
      });
    return () => controller.abort();
  }, [token, attempt]);

  const retry = () => {
    setState({ loading: true, error: "", customers: [] });
    setAttempt((value) => value + 1);
  };
  const { loading, error, customers } = state;
  const query = search.trim().toLowerCase();
  const visibleCustomers = customers.filter((customer) =>
    customer.name.toLowerCase().includes(query) || customer.email.toLowerCase().includes(query));

  return <div className="customers-page">
    <section className="customers-heading"><p>YOUR STUDIO COMMUNITY</p><h1>Customers</h1><span>The people who have booked with your studio.</span></section>
    {loading ? <section className="customers-state" role="status"><span className="dashboard-loading-pulse" /> Loading customers…</section>
      : error ? <section className="customers-state customers-error" role="alert"><h2>Unable to load customers</h2><p>{error}</p><button type="button" onClick={retry}>Retry</button></section>
      : !customers.length ? <section className="customers-state"><h2>No customers yet</h2><p>Customers will appear here when they have bookings with your studio.</p></section>
      : <>
        <section className="customers-toolbar" aria-label="Customer search">
          <label htmlFor="studio-customer-search">Search customers<input id="studio-customer-search" type="search" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search by name or email" /></label>
          <span role="status">{visibleCustomers.length} of {customers.length} customers</span>
        </section>
        {!visibleCustomers.length ? <section className="customers-state"><h2>No matching customers</h2><p>Try another name or email.</p><button type="button" onClick={() => setSearch("")}>Clear search</button></section>
          : <div className="customers-list">{visibleCustomers.map((customer) => <CustomerCard key={customer.customerId} customer={customer} />)}</div>}
      </>}
  </div>;
}
