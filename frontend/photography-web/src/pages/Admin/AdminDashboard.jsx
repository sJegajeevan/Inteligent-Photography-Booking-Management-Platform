import { useEffect, useState } from "react";
import { useAuth } from "../../context/useAuth";
import {
  getAdminBooking, getAdminBookings, getAdminCustomer, getAdminCustomers,
  getAdminDashboard, getAdminReports, getAdminReviews, getAdminStudio, getAdminStudios, getAdminWorkflows, getAdminWorkflow,
} from "../../services/adminService";
import AdminLayout from "./AdminLayout";

const statuses = ["Pending", "AIRecommended", "AwaitingApproval", "Confirmed", "Rejected", "Cancelled", "Rescheduled", "Completed"];
const formatDate = (value) => value ? new Date(value).toLocaleDateString() : "Not available";
const formatMoney = (value) => value === null || value === undefined ? "Not available" : new Intl.NumberFormat("en-LK", { style: "currency", currency: "LKR" }).format(value);
const label = (value) => String(value || "").replace(/([a-z])([A-Z])/g, "$1 $2");

function useAdminData(load, dependencies) {
  const [attempt, setAttempt] = useState(0);
  const identity = JSON.stringify([...dependencies, attempt]);
  const [result, setResult] = useState({ identity: null, data: null, error: "" });
  useEffect(() => {
    const controller = new AbortController();
    let active = true;
    load(controller.signal).then(data => {
      if (active) setResult({ identity, data, error: "" });
    }).catch(error => {
      if (active && error.name !== "AbortError") setResult({ identity, data: null, error: error.message });
    });
    return () => { active = false; controller.abort(); };
    // Callers provide the complete request identity; load is intentionally recreated.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [identity]);
  const loading = result.identity !== identity;
  return { data: loading ? null : result.data, error: loading ? "" : result.error, loading, retry: () => setAttempt(value => value + 1) };
}
function State({ loading, error, retry, children }) {
  if (loading) return <div className="admin-loading" role="status">Loading platform data?</div>;
  if (error) return <div className="admin-error" role="alert"><p>{error}</p>{retry && <button className="admin-link" type="button" onClick={retry}>Retry</button>}</div>;
  return children;
}
function Refresh({ onClick, disabled }) { return <div className="admin-actions"><button className="admin-link" type="button" onClick={onClick} disabled={disabled}>Refresh</button></div>; }
function Pagination({ data, onPage, loading }) {
  if (!data) return null;
  return <nav className="admin-pagination" aria-label="Results pagination"><span>{data.totalCount} results ? Page {data.page} of {Math.max(data.totalPages, 1)}</span><button type="button" disabled={loading || data.page <= 1} onClick={() => onPage(data.page - 1)}>Previous</button><button type="button" disabled={loading || data.page >= data.totalPages} onClick={() => onPage(data.page + 1)}>Next</button></nav>;
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
  return <div className="admin-table-wrap"><table className="admin-table"><thead><tr><th>Reference</th><th>Customer</th><th>Studio</th><th>Date</th><th>Status</th><th>Total</th></tr></thead><tbody>{items.map((item) => <tr key={item.id} onClick={() => window.location.assign(`/admin/bookings/${item.id}`)}><td><a href={`/admin/bookings/${item.id}`}>#{item.id}</a></td><td>{item.customerName}</td><td>{item.studioName}</td><td>{formatDate(item.bookingDate)}</td><td><StatusBadge value={item.status} /></td><td>{formatMoney(item.totalPrice)}</td></tr>)}</tbody></table></div>;
}
function StudioTable({ items }) {
  if (!items.length) return <div className="admin-empty">No studios found.</div>;
  return <div className="admin-table-wrap"><table className="admin-table"><thead><tr><th>Studio</th><th>Owner</th><th>Location</th><th>Contact</th></tr></thead><tbody>{items.map((item) => <tr key={item.id} onClick={() => window.location.assign(`/admin/studios/${item.id}`)}><td><a href={`/admin/studios/${item.id}`}>{item.studioName || "Unnamed studio"}</a></td><td>{item.ownerName}</td><td>{item.location || "Not provided"}</td><td>{item.contactNumber || item.email || "Not provided"}</td></tr>)}</tbody></table></div>;
}
function CustomerTable({ items }) {
  if (!items.length) return <div className="admin-empty">No customers found.</div>;
  return <div className="admin-table-wrap"><table className="admin-table"><thead><tr><th>Customer</th><th>Email</th><th>Bookings</th><th>Reviews</th><th>Joined</th></tr></thead><tbody>{items.map((item) => <tr key={item.id} onClick={() => window.location.assign(`/admin/customers/${item.id}`)}><td><a href={`/admin/customers/${item.id}`}>{item.fullName}</a></td><td>{item.email}</td><td>{item.bookingCount}</td><td>{item.reviewCount}</td><td>{formatDate(item.createdAt)}</td></tr>)}</tbody></table></div>;
}
function ReviewTable({ items }) {
  if (!items.length) return <div className="admin-empty">No reviews found.</div>;
  return <div className="admin-table-wrap"><table className="admin-table"><thead><tr><th>Customer</th><th>Studio</th><th>Rating</th><th>Comment</th><th>Created</th></tr></thead><tbody>{items.map((item) => <tr key={item.id}><td>{item.customerName}</td><td>{item.studioName}</td><td>{"★".repeat(item.rating)}{"☆".repeat(5 - item.rating)}</td><td>{item.comment || "No comment"}</td><td>{formatDate(item.createdAt)}</td></tr>)}</tbody></table></div>;
}
function DashboardHome() {
  const { token } = useAuth();
  const { data, error, loading, retry } = useAdminData(signal => getAdminDashboard(token, signal), [token]);
  const max = Math.max(...(data?.bookingStatuses || []).map((item) => item.count), 1);
  return <AdminLayout page="dashboard"><Refresh onClick={retry} disabled={loading} /><State loading={loading} error={error} retry={retry}>{data && <><Stats data={data} /><div className="admin-columns"><Panel heading="Booking status summary"><div className="admin-status-list">{data.bookingStatuses.length ? data.bookingStatuses.map((item) => <div className="admin-status-row" key={item.status}><span>{label(item.status)}</span><div className="admin-status-bar"><span style={{ width: `${Math.max((item.count / max) * 100, 5)}%` }} /></div><strong>{item.count}</strong></div>) : <div className="admin-empty">No bookings yet.</div>}</div></Panel><Panel heading="Studio summaries" action={{ label: "View all", onClick: () => window.location.assign("/admin/studios") }}><div className="admin-list">{data.recentStudios.length ? data.recentStudios.map((item) => <div className="admin-list-item" key={item.id}><span><strong>{item.studioName}</strong><small>{item.location || "Location not provided"}</small></span><small>{item.ownerName}</small></div>) : <div className="admin-empty">No studios registered.</div>}</div></Panel></div><div className="admin-panel" style={{ marginTop: 18 }}><div className="admin-panel-heading"><h2>Recent bookings</h2><button className="admin-link" type="button" onClick={() => window.location.assign("/admin/bookings")}>View all</button></div><BookingTable items={data.recentBookings} /></div></>}</State></AdminLayout>;
}
function CollectionPage({ kind }) {
  const { token } = useAuth();
  const emptyFilters = { search: "", status: "", rating: "", studioId: "", fromDate: "", toDate: "" };
  const [draft, setDraft] = useState(emptyFilters);
  const [filters, setFilters] = useState(emptyFilters);
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(10);
  const [filterError, setFilterError] = useState("");
  const [studioSearch, setStudioSearch] = useState("");
  const [studioPage, setStudioPage] = useState(1);
  const params = { ...filters, page, pageSize };
  const loader = { studios: getAdminStudios, customers: getAdminCustomers, bookings: getAdminBookings, reviews: getAdminReviews }[kind];
  const { data, error, loading, retry } = useAdminData(signal => loader(token, params, signal), [token, kind, JSON.stringify(params)]);
  // Studio options are bounded and searchable rather than downloading every studio.
  const options = useAdminData(signal => kind === "bookings" ? getAdminStudios(token, { search: studioSearch, page: studioPage, pageSize: 10 }, signal) : Promise.resolve(null), [token, kind, studioSearch, studioPage]);
  const change = (name, value) => setDraft(previous => ({ ...previous, [name]: value }));
  const apply = event => {
    event.preventDefault();
    if (draft.fromDate && draft.toDate && draft.fromDate > draft.toDate) { setFilterError("From date must not exceed to date."); return; }
    setFilterError(""); setFilters(draft); setPage(1);
  };
  const clear = () => { setDraft(emptyFilters); setFilters(emptyFilters); setPage(1); setFilterError(""); setStudioSearch(""); setStudioPage(1); };
  const items = data?.items || [];
  const table = kind === "studios" ? <StudioTable items={items} /> : kind === "customers" ? <CustomerTable items={items} /> : kind === "bookings" ? <BookingTable items={items} /> : <ReviewTable items={items} />;
  return <AdminLayout page={kind}><Refresh onClick={retry} disabled={loading} /><form className="admin-toolbar" onSubmit={apply}>
    <label>Search<input value={draft.search} maxLength={200} onChange={event => change("search", event.target.value)} placeholder={`Search ${kind}`} aria-label={`Search ${kind}`} /></label>
    {kind === "bookings" && <><label>Status<select value={draft.status} onChange={event => change("status", event.target.value)} aria-label="Filter booking status"><option value="">All statuses</option>{statuses.map(item => <option key={item} value={item}>{label(item)}</option>)}</select></label>
      <label>Studio<select value={draft.studioId} onChange={event => change("studioId", event.target.value)} aria-label="Filter studio"><option value="">All studios</option>{draft.studioId && !options.data?.items.some(item => item.id === draft.studioId) && <option value={draft.studioId}>Selected studio</option>}{options.data?.items.map(item => <option key={item.id} value={item.id}>{item.studioName} ? {item.ownerName}</option>)}</select></label>
      <label>From date<input type="date" value={draft.fromDate} onChange={event => change("fromDate", event.target.value)} /></label><label>To date<input type="date" value={draft.toDate} onChange={event => change("toDate", event.target.value)} /></label></>}
    {kind === "reviews" && <label>Rating<select value={draft.rating} onChange={event => change("rating", event.target.value)} aria-label="Filter rating"><option value="">All ratings</option>{[5, 4, 3, 2, 1].map(item => <option key={item} value={item}>{item} stars</option>)}</select></label>}
    <label>Page size<select value={pageSize} onChange={event => { setPageSize(Number(event.target.value)); setPage(1); }} aria-label="Page size">{[10, 20, 50, 100].map(size => <option key={size} value={size}>{size}</option>)}</select></label>
    <button type="submit">Search</button><button type="button" onClick={clear}>Clear filters</button>
  </form>{filterError && <p role="alert">{filterError}</p>}
  {kind === "bookings" && <StudioOptions options={options} search={studioSearch} onSearch={value => { setStudioSearch(value); setStudioPage(1); }} onPage={setStudioPage} />}
  <State loading={loading} error={error} retry={retry}><Panel heading={`${data?.totalCount || 0} ${kind}`}>{table}<Pagination data={data} onPage={setPage} loading={loading} /></Panel></State></AdminLayout>;
}
function StudioOptions({ options, search, onSearch, onPage }) {
  const [draft, setDraft] = useState(search);
  return <details className="admin-studio-options"><summary>Find studio filter options</summary><form className="admin-toolbar" onSubmit={event => { event.preventDefault(); onSearch(draft); }}><label>Studio name or owner<input value={draft} maxLength={200} onChange={event => setDraft(event.target.value)} aria-label="Search studio options" /></label><button type="submit">Find studios</button></form><State loading={options.loading} error={options.error} retry={options.retry}>{options.data?.totalCount === 0 && <p>No studios found.</p>}<Pagination data={options.data} onPage={onPage} loading={options.loading} /></State></details>;
}
function Info({ title, values }) { return <section className="admin-detail-card"><h3>{title}</h3><dl>{values.map(([name, value]) => <div key={name}><dt>{name}</dt><dd>{value}</dd></div>)}</dl></section>; }
function NamedList({ items }) { return items.length ? <div className="admin-list">{items.map((item) => <div className="admin-list-item" key={item.id}><span><strong>{item.name}</strong><small>{item.category || ""}</small></span><small>{item.price === null || item.price === undefined ? "" : formatMoney(item.price)} {item.status || ""}</small></div>)}</div> : <div className="admin-empty">No records available.</div>; }
function DetailContent({ kind, data }) {
  if (kind === "studio") return <><div className="admin-detail-grid"><Info title={data.studioName} values={[["Owner", data.ownerName], ["Owner email", data.ownerEmail], ["Location", data.location], ["Address", data.address], ["Contact", data.contactNumber], ["Email", data.email], ["Experience", `${data.experienceYears} years`], ["Average rating", data.averageRating ? data.averageRating.toFixed(1) : "No reviews"]]} /><Info title="Studio totals" values={[["Reviews", data.reviewCount], ["Portfolio items", data.portfolioCount], ["Services", data.serviceCount], ["Packages", data.packageCount], ["Availability records", data.availabilityCount], ["Bookings", data.bookingCount]]} /><Info title="Photography types" values={[["Types", data.photographyTypes || "Not specified"], ["Starting price", formatMoney(data.startingPrice)]]} /></div><div className="admin-columns"><Panel heading="Services"><NamedList items={data.services} /></Panel><Panel heading="Packages"><NamedList items={data.packages} /></Panel></div></>;
  if (kind === "customer") return <><div className="admin-detail-grid"><Info title={data.fullName} values={[["Email", data.email], ["Phone", data.phoneNumber || "Not provided"], ["Joined", formatDate(data.createdAt)]]} /></div><div className="admin-columns"><Panel heading="Booking history"><BookingTable items={data.bookings} /></Panel><Panel heading="Review history"><ReviewTable items={data.reviews} /></Panel></div></>;
  return <><div className="admin-detail-grid"><Info title={`Booking #${data.id}`} values={[["Customer", data.customerName], ["Customer email", data.customerEmail], ["Studio", data.studioName], ["Package", data.packageName], ["Event date", formatDate(data.bookingDate)], ["Time", `${data.startTime}–${data.endTime}`], ["Status", label(data.status)], ["Total", formatMoney(data.totalPrice)], ["Created", formatDate(data.createdAt)], ["Location", data.location || "Not provided"], ["Notes", data.notes || "None"]]} /><Info title="Location details" values={data.bookingLocation ? [["Address", data.bookingLocation.address], ["City", data.bookingLocation.city], ["Notes", data.bookingLocation.notes || "None"]] : [["Details", "No separate booking location"]]} /><PricingSnapshot value={data.pricingSnapshotJson} /></div><div className="admin-panel" style={{ marginTop: 18 }}><div className="admin-panel-heading"><h2>Status history</h2></div>{data.statusHistory.length ? <div className="admin-list">{data.statusHistory.map((item, index) => <div className="admin-list-item" key={`${item.createdAt}-${index}`}><span><strong>{label(item.newStatus)}</strong><small>{item.reason || "Status updated"} · {item.changedBy}</small></span><small>{formatDate(item.createdAt)}</small></div>)}</div> : <div className="admin-empty">No status history.</div>}</div></>;
}
function PricingSnapshot({ value }) {
  let pricing;
  try { pricing = typeof value === "string" ? JSON.parse(value) : value; } catch { pricing = null; }
  if (!pricing || typeof pricing !== "object") return <Info title="Pricing snapshot" values={[["Details", "No readable pricing snapshot available"]]} />;
  const field = name => pricing[name] ?? pricing[name.charAt(0).toLowerCase() + name.slice(1)];
  const amount = name => typeof field(name) === "number" && Number.isFinite(field(name)) ? formatMoney(field(name)) : "Not available";
  const addons = field("SelectedAddons");
  return <Info title="Pricing snapshot" values={[["Base price", amount("BasePrice")], ["Add-ons", Array.isArray(addons) ? addons.map(addon => `${addon.Name ?? addon.name ?? "Add-on"} (${formatMoney(addon.Price ?? addon.price)})`).join(", ") || "None" : "Not available"], ["Extra hours", typeof field("ExtraHours") === "number" ? field("ExtraHours") : "Not available"], ["Extra hours cost", amount("ExtraHoursCost")], ["Additional photographers", typeof field("AdditionalPhotographers") === "number" ? field("AdditionalPhotographers") : "Not available"], ["Additional photographers cost", amount("AdditionalPhotographersCost")], ["Final price", amount("FinalPrice")]]} />;
}
function DetailPage({ kind, id }) {
  const { token } = useAuth();
  const load = kind === "studio" ? getAdminStudio : kind === "customer" ? getAdminCustomer : getAdminBooking;
  const { data, error, loading, retry } = useAdminData(signal => load(token, id, signal), [token, kind, id]);
  return <AdminLayout page={kind === "studio" ? "studios" : kind === "customer" ? "customers" : "bookings"}><Refresh onClick={retry} disabled={loading} /><State loading={loading} error={error} retry={retry}>{data && <DetailContent kind={kind} data={data} />}</State></AdminLayout>;
}
function Reports() {
  const { token } = useAuth();
  const { data, error, loading, retry } = useAdminData(signal => getAdminReports(token, signal), [token]);
  const bars = (items) => { const max = Math.max(...items.map((item) => item.count), 1); return items.length ? <div className="admin-bars">{items.map((item) => <div className="admin-bar-row" key={item.id || item.status}><span>{label(item.name || item.status)}</span><div className="admin-status-bar"><span style={{ width: `${Math.max(item.count / max * 100, 5)}%` }} /></div><strong>{item.count}</strong></div>)}</div> : <div className="admin-empty">No data available.</div>; };
  return <AdminLayout page="reports"><Refresh onClick={retry} disabled={loading} /><State loading={loading} error={error} retry={retry}>{data && <><Stats data={{ totalStudios: data.totalStudios, totalCustomers: data.totalCustomers, totalBookings: data.totalBookings, totalPackages: "—", totalReviews: data.totalReviews }} /><div className="admin-columns"><Panel heading="Booking status distribution">{bars(data.bookingStatuses)}</Panel><Panel heading="Bookings by studio">{bars(data.bookingsByStudio)}</Panel></div><div className="admin-columns"><Panel heading="Popular packages">{bars(data.popularPackages)}</Panel><Panel heading="Review summary"><div className="admin-stat"><span>Average rating</span><strong>{data.averageRating ? data.averageRating.toFixed(1) : "—"} / 5</strong><small>Based on {data.totalReviews} reviews</small></div></Panel></div></>}</State></AdminLayout>;
}
function Workflows({ id }) {
  const { token } = useAuth();
  const [page, setPage] = useState(1);
  const [status, setStatus] = useState("");
  const { data, error, loading, retry } = useAdminData(signal => id ? getAdminWorkflow(token, id, signal) : getAdminWorkflows(token, { page, pageSize: 20, status }, signal), [token, id, page, status]);
  return <AdminLayout page="workflows"><Refresh onClick={retry} disabled={loading} />{!id && <div className="admin-toolbar"><label>Workflow status<select aria-label="Workflow status" value={status} onChange={event => { setStatus(event.target.value); setPage(1); }}><option value="">All statuses</option>{["Submitted", "StudioMatching", "PackageRecommendation", "Scheduling", "Validation", "AwaitingApproval", "Approved", "Rejected", "NeedsInput", "Failed", "Cancelled", "Expired", "RevalidationRequired"].map(value => <option key={value}>{value}</option>)}</select></label></div>}<State loading={loading} error={error} retry={retry}>{data && (id ? <WorkflowDetails data={data} /> : <Panel heading="AI workflows">{data.items.length ? <div className="admin-table-wrap"><table className="admin-table"><thead><tr><th>Workflow</th><th>Customer</th><th>Studio</th><th>Stage</th><th>Status</th><th>Updated</th></tr></thead><tbody>{data.items.map(item => <tr key={item.id}><td><a href={`/admin/workflows/${item.id}`}>{item.id}</a></td><td>{item.monitoring?.customerName || "Not available"}</td><td>{item.monitoring?.studioName || "Not selected"}</td><td>{label(item.currentStep)}</td><td><StatusBadge value={item.status} /></td><td>{formatDate(item.updatedAt)}</td></tr>)}</tbody></table></div> : <div className="admin-empty">No AI workflows found.</div>}<nav className="admin-pagination" aria-label="Workflow pagination"><span>Page {page}</span><button type="button" disabled={page === 1} onClick={() => setPage(page - 1)}>Previous</button><button type="button" disabled={!data.hasMore || page >= 10000} onClick={() => setPage(page + 1)}>Next</button></nav></Panel>)}</State></AdminLayout>;
}
function WorkflowDetails({ data }) {
  const p = data.proposal;
  return <><div className="admin-detail-grid"><Info title="Workflow" values={[["ID", data.id], ["Customer", data.monitoring?.customerName || "Not available"], ["Studio", data.monitoring?.studioName || "Not selected"], ["Stage", label(data.currentStep)], ["Status / approval state", label(data.status)], ["Proposal version", data.proposalVersion], ["Created", formatDate(data.createdAt)], ["Updated", formatDate(data.updatedAt)], ["Expires", formatDate(data.expiresAt)]]} /><Info title="Failure state" values={[["Details", data.failure?.message || "No reported failure"], ["Stage", data.failure?.stage || "Not applicable"]]} />{p && <Info title="Proposal" values={[["Package", p.pricing?.packageName], ["Price", formatMoney(p.pricing?.finalPrice)], ["Date", formatDate(p.selection?.date)], ["Time", `${p.selection?.startTime} ? ${p.selection?.endTime}`], ["Photography", p.requirements?.photographyType], ["Location", p.requirements?.location]]} />}</div><Panel heading="Latest workflow events (up to 50)">{data.monitoring?.events?.length ? <div className="admin-list">{data.monitoring.events.map(event => <div className="admin-list-item" key={event.id}><span>{label(event.eventType)} ? {label(event.stage)} ? {event.success ? "Successful" : "Unsuccessful"}</span><time>{new Date(event.createdAt).toLocaleString("en-LK", { timeZone: "Asia/Colombo" })}</time></div>)}</div> : <div className="admin-empty">No workflow events available.</div>}</Panel></>;
}
function Profile() { const { user, logout } = useAuth(); return <AdminLayout page="profile"><section className="admin-panel admin-profile-card"><span className="admin-profile-avatar">{(user?.fullName || user?.email || "A").charAt(0).toUpperCase()}</span><div><span className="admin-kicker">AUTHENTICATED ACCOUNT</span><h2>{user?.fullName || "Administrator"}</h2><p>{user?.email}</p><p><StatusBadge value={user?.role} /></p><button className="admin-link" type="button" onClick={() => { logout(); window.location.replace("/auth"); }}>Sign out</button></div></section></AdminLayout>; }

export default function AdminDashboard({ page = "dashboard", id }) {
  if (page === "dashboard") return <DashboardHome />;
  if (page === "reports") return <Reports />;
  if (page === "profile") return <Profile />;
  if (page === "workflows" || page === "workflow") return <Workflows id={id} />;
  if (["studio", "customer", "booking"].includes(page)) return <DetailPage kind={page} id={id} />;
  return <CollectionPage kind={page} />;
}
