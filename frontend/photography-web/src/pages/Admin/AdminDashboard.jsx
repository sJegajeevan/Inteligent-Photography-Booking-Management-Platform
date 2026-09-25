import { useEffect, useState } from "react";
import { useAuth } from "../../context/useAuth";
import {
  getAdminBooking, getAdminBookings, getAdminCustomer, getAdminCustomers,
  getAdminDashboard, getAdminReports, getAdminReviews, getAdminStudio, getAdminStudios,
} from "../../services/adminService";
import AdminLayout from "./AdminLayout";

const statuses = ["Pending", "AIRecommended", "AwaitingApproval", "Confirmed", "Rejected", "Cancelled", "Rescheduled", "Completed"];
const formatDate = (value) => value ? new Date(value).toLocaleDateString() : "Not available";
const formatMoney = (value) => value === null || value === undefined ? "Not available" : new Intl.NumberFormat(undefined, { style: "currency", currency: "USD" }).format(value);
const label = (value) => String(value || "").replace(/([a-z])([A-Z])/g, "$1 $2");

function State({ loading, error, children }) {
  if (loading) return <div className="admin-loading">Loading platform data…</div>;
  if (error) return <div className="admin-error" role="alert">{error}</div>;
  return children;
}
function Panel({ heading, action, children }) {
  return <section className="admin-panel"><div className="admin-panel-heading"><h2>{heading}</h2>{action && <button className="admin-link" type="button" onClick={action.onClick}>{action.label}</button>}</div>{children}</section>;
}
function StatusBadge({ value }) { return <span className={`admin-badge ${String(value || "").toLowerCase()}`}>{label(value)}</span>; }
function Stats({ data }) {
  const cards = [["Studios", data.totalStudios, "▤"], ["Customers", data.totalCustomers, "◎"], ["Bookings", data.totalBookings, "□"], ["Packages", data.totalPackages, "▥"], ["Reviews", data.totalReviews, "★"]];
  return <div className="admin-grid">{cards.map(([name, value, icon]) => <div className="admin-stat" key={name}><i>{icon}</i><span>{name}</span><strong>{value}</strong></div>)}</div>;
}
function BookingTable({ items }) {
  if (!items.length) return <div className="admin-empty">No bookings found.</div>;
  return <div className="admin-table-wrap"><table className="admin-table"><thead><tr><th>Reference</th><th>Customer</th><th>Studio</th><th>Date</th><th>Status</th><th>Total</th></tr></thead><tbody>{items.map((item) => <tr key={item.id} onClick={() => window.location.assign(`/admin/bookings/${item.id}`)}><td>#{item.id}</td><td>{item.customerName}</td><td>{item.studioName}</td><td>{formatDate(item.bookingDate)}</td><td><StatusBadge value={item.status} /></td><td>{formatMoney(item.totalPrice)}</td></tr>)}</tbody></table></div>;
}
function StudioTable({ items }) {
  if (!items.length) return <div className="admin-empty">No studios found.</div>;
  return <div className="admin-table-wrap"><table className="admin-table"><thead><tr><th>Studio</th><th>Owner</th><th>Location</th><th>Contact</th></tr></thead><tbody>{items.map((item) => <tr key={item.id} onClick={() => window.location.assign(`/admin/studios/${item.id}`)}><td>{item.studioName || "Unnamed studio"}</td><td>{item.ownerName}</td><td>{item.location || "Not provided"}</td><td>{item.contactNumber || item.email || "Not provided"}</td></tr>)}</tbody></table></div>;
}
function CustomerTable({ items }) {
  if (!items.length) return <div className="admin-empty">No customers found.</div>;
  return <div className="admin-table-wrap"><table className="admin-table"><thead><tr><th>Customer</th><th>Email</th><th>Bookings</th><th>Reviews</th><th>Joined</th></tr></thead><tbody>{items.map((item) => <tr key={item.id} onClick={() => window.location.assign(`/admin/customers/${item.id}`)}><td>{item.fullName}</td><td>{item.email}</td><td>{item.bookingCount}</td><td>{item.reviewCount}</td><td>{formatDate(item.createdAt)}</td></tr>)}</tbody></table></div>;
}
function ReviewTable({ items }) {
  if (!items.length) return <div className="admin-empty">No reviews found.</div>;
  return <div className="admin-table-wrap"><table className="admin-table"><thead><tr><th>Customer</th><th>Studio</th><th>Rating</th><th>Comment</th><th>Created</th></tr></thead><tbody>{items.map((item) => <tr key={item.id}><td>{item.customerName}</td><td>{item.studioName}</td><td>{"★".repeat(item.rating)}{"☆".repeat(5 - item.rating)}</td><td>{item.comment || "No comment"}</td><td>{formatDate(item.createdAt)}</td></tr>)}</tbody></table></div>;
}
function DashboardHome() {
  const { token } = useAuth();
  const [data, setData] = useState(null); const [error, setError] = useState("");
  useEffect(() => { getAdminDashboard(token).then(setData).catch((item) => setError(item.message)); }, [token]);
  const max = Math.max(...(data?.bookingStatuses || []).map((item) => item.count), 1);
  return <AdminLayout page="dashboard"><State loading={!data && !error} error={error}>{data && <><Stats data={data} /><div className="admin-columns"><Panel heading="Booking status summary"><div className="admin-status-list">{data.bookingStatuses.length ? data.bookingStatuses.map((item) => <div className="admin-status-row" key={item.status}><span>{label(item.status)}</span><div className="admin-status-bar"><span style={{ width: `${Math.max((item.count / max) * 100, 5)}%` }} /></div><strong>{item.count}</strong></div>) : <div className="admin-empty">No bookings yet.</div>}</div></Panel><Panel heading="Recent studios" action={{ label: "View all", onClick: () => window.location.assign("/admin/studios") }}><div className="admin-list">{data.recentStudios.length ? data.recentStudios.map((item) => <div className="admin-list-item" key={item.id}><span><strong>{item.studioName}</strong><small>{item.location || "Location not provided"}</small></span><small>{item.ownerName}</small></div>) : <div className="admin-empty">No studios registered.</div>}</div></Panel></div><div className="admin-panel" style={{ marginTop: 18 }}><div className="admin-panel-heading"><h2>Recent bookings</h2><button className="admin-link" type="button" onClick={() => window.location.assign("/admin/bookings")}>View all</button></div><BookingTable items={data.recentBookings} /></div></>}</State></AdminLayout>;
}
function CollectionPage({ kind }) {
  const { token } = useAuth();
  const [items, setItems] = useState([]); const [search, setSearch] = useState(""); const [status, setStatus] = useState(""); const [rating, setRating] = useState(""); const [error, setError] = useState(""); const [loading, setLoading] = useState(true);
  useEffect(() => { setLoading(true); setError(""); const load = kind === "studios" ? getAdminStudios(token, search) : kind === "customers" ? getAdminCustomers(token, search) : kind === "bookings" ? getAdminBookings(token, { search, status }) : getAdminReviews(token, { search, rating }); load.then(setItems).catch((item) => setError(item.message)).finally(() => setLoading(false)); }, [token, kind, search, status, rating]);
  const table = kind === "studios" ? <StudioTable items={items} /> : kind === "customers" ? <CustomerTable items={items} /> : kind === "bookings" ? <BookingTable items={items} /> : <ReviewTable items={items} />;
  return <AdminLayout page={kind}><div className="admin-toolbar"><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder={`Search ${kind}`} aria-label={`Search ${kind}`} />{kind === "bookings" && <select value={status} onChange={(event) => setStatus(event.target.value)} aria-label="Filter booking status"><option value="">All statuses</option>{statuses.map((item) => <option key={item} value={item}>{label(item)}</option>)}</select>}{kind === "reviews" && <select value={rating} onChange={(event) => setRating(event.target.value)} aria-label="Filter rating"><option value="">All ratings</option>{[5, 4, 3, 2, 1].map((item) => <option key={item} value={item}>{item} stars</option>)}</select>}</div><State loading={loading} error={error}><Panel heading={`${items.length} ${kind}`}>{table}</Panel></State></AdminLayout>;
}
function Info({ title, values }) { return <section className="admin-detail-card"><h3>{title}</h3><dl>{values.map(([name, value]) => <div key={name}><dt>{name}</dt><dd>{value}</dd></div>)}</dl></section>; }
function NamedList({ items }) { return items.length ? <div className="admin-list">{items.map((item) => <div className="admin-list-item" key={item.id}><span><strong>{item.name}</strong><small>{item.category || ""}</small></span><small>{item.price === null || item.price === undefined ? "" : formatMoney(item.price)} {item.status || ""}</small></div>)}</div> : <div className="admin-empty">No records available.</div>; }
function DetailContent({ kind, data }) {
  if (kind === "studio") return <><div className="admin-detail-grid"><Info title={data.studioName} values={[["Owner", data.ownerName], ["Owner email", data.ownerEmail], ["Location", data.location], ["Address", data.address], ["Contact", data.contactNumber], ["Email", data.email], ["Experience", `${data.experienceYears} years`], ["Average rating", data.averageRating ? data.averageRating.toFixed(1) : "No reviews"]]} /><Info title="Studio totals" values={[["Portfolio items", data.portfolioCount], ["Services", data.serviceCount], ["Packages", data.packageCount], ["Availability records", data.availabilityCount], ["Bookings", data.bookingCount]]} /><Info title="Photography types" values={[["Types", data.photographyTypes || "Not specified"], ["Starting price", formatMoney(data.startingPrice)]]} /></div><div className="admin-columns"><Panel heading="Services"><NamedList items={data.services} /></Panel><Panel heading="Packages"><NamedList items={data.packages} /></Panel></div></>;
  if (kind === "customer") return <><div className="admin-detail-grid"><Info title={data.fullName} values={[["Email", data.email], ["Phone", data.phoneNumber || "Not provided"], ["Joined", formatDate(data.createdAt)]]} /></div><div className="admin-columns"><Panel heading="Booking history"><BookingTable items={data.bookings} /></Panel><Panel heading="Review history"><ReviewTable items={data.reviews} /></Panel></div></>;
  return <><div className="admin-detail-grid"><Info title={`Booking #${data.id}`} values={[["Customer", data.customerName], ["Customer email", data.customerEmail], ["Studio", data.studioName], ["Package", data.packageName], ["Event date", formatDate(data.bookingDate)], ["Time", `${data.startTime}–${data.endTime}`], ["Status", label(data.status)], ["Total", formatMoney(data.totalPrice)], ["Created", formatDate(data.createdAt)], ["Location", data.location || "Not provided"]]} /><Info title="Location details" values={data.bookingLocation ? [["Address", data.bookingLocation.address], ["City", data.bookingLocation.city], ["Notes", data.bookingLocation.notes || "None"]] : [["Details", "No separate booking location"]]} /><Info title="Pricing snapshot" values={[["Snapshot", data.pricingSnapshotJson || "No snapshot saved"]]} /></div><div className="admin-panel" style={{ marginTop: 18 }}><div className="admin-panel-heading"><h2>Status history</h2></div>{data.statusHistory.length ? <div className="admin-list">{data.statusHistory.map((item, index) => <div className="admin-list-item" key={`${item.createdAt}-${index}`}><span><strong>{label(item.newStatus)}</strong><small>{item.reason || "Status updated"} · {item.changedBy}</small></span><small>{formatDate(item.createdAt)}</small></div>)}</div> : <div className="admin-empty">No status history.</div>}</div></>;
}
function DetailPage({ kind, id }) {
  const { token } = useAuth(); const [data, setData] = useState(null); const [error, setError] = useState("");
  useEffect(() => { const load = kind === "studio" ? getAdminStudio(token, id) : kind === "customer" ? getAdminCustomer(token, id) : getAdminBooking(token, id); load.then(setData).catch((item) => setError(item.message)); }, [token, kind, id]);
  return <AdminLayout page={kind === "studio" ? "studios" : kind === "customer" ? "customers" : "bookings"}><State loading={!data && !error} error={error}>{data && <DetailContent kind={kind} data={data} />}</State></AdminLayout>;
}
function Reports() {
  const { token } = useAuth(); const [data, setData] = useState(null); const [error, setError] = useState("");
  useEffect(() => { getAdminReports(token).then(setData).catch((item) => setError(item.message)); }, [token]);
  const bars = (items) => { const max = Math.max(...items.map((item) => item.count), 1); return items.length ? <div className="admin-bars">{items.map((item) => <div className="admin-bar-row" key={item.name || item.status}><span>{label(item.name || item.status)}</span><div className="admin-status-bar"><span style={{ width: `${Math.max(item.count / max * 100, 5)}%` }} /></div><strong>{item.count}</strong></div>)}</div> : <div className="admin-empty">No data available.</div>; };
  return <AdminLayout page="reports"><State loading={!data && !error} error={error}>{data && <><Stats data={{ totalStudios: data.totalStudios, totalCustomers: data.totalCustomers, totalBookings: data.totalBookings, totalPackages: "—", totalReviews: data.totalReviews }} /><div className="admin-columns"><Panel heading="Booking status distribution">{bars(data.bookingStatuses)}</Panel><Panel heading="Bookings by studio">{bars(data.bookingsByStudio)}</Panel></div><div className="admin-columns"><Panel heading="Popular packages">{bars(data.popularPackages)}</Panel><Panel heading="Review summary"><div className="admin-stat"><span>Average rating</span><strong>{data.averageRating ? data.averageRating.toFixed(1) : "—"} / 5</strong><small>Based on {data.totalReviews} reviews</small></div></Panel></div></>}</State></AdminLayout>;
}
function Profile() { const { user, logout } = useAuth(); return <AdminLayout page="profile"><section className="admin-panel admin-profile-card"><span className="admin-profile-avatar">{(user?.fullName || user?.email || "A").charAt(0).toUpperCase()}</span><div><span className="admin-kicker">AUTHENTICATED ACCOUNT</span><h2>{user?.fullName || "Administrator"}</h2><p>{user?.email}</p><p><StatusBadge value={user?.role} /></p><button className="admin-link" type="button" onClick={() => { logout(); window.location.replace("/auth"); }}>Sign out</button></div></section></AdminLayout>; }

export default function AdminDashboard({ page = "dashboard", id }) {
  if (page === "dashboard") return <DashboardHome />;
  if (page === "reports") return <Reports />;
  if (page === "profile") return <Profile />;
  if (["studio", "customer", "booking"].includes(page)) return <DetailPage kind={page} id={id} />;
  return <CollectionPage kind={page} />;
}
