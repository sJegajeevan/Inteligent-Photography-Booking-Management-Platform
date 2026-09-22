import { useMemo, useState } from "react";
import { createPortal } from "react-dom";
import Button from "../../components/common/Button";
import Card from "../../components/common/Card";
import Pagination from "../../components/common/Pagination";

const emptyForm = { date: "", isAvailable: true, startTime: "09:00", endTime: "18:00", notes: "" };
const pageSize = 5;
const dateFormatter = new Intl.DateTimeFormat("en-LK", { year: "numeric", month: "short", day: "numeric", timeZone: "UTC" });
const formatDate = (date) => dateFormatter.format(new Date(`${date}T00:00:00Z`));
function getLocalDate() {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}
function formatTime(time) {
  if (!time) return "—";
  const [hours, minutes] = time.split(":").map(Number);
  return new Intl.DateTimeFormat("en-LK", { hour: "numeric", minute: "2-digit", timeZone: "UTC" }).format(new Date(Date.UTC(2000, 0, 1, hours, minutes)));
}

function StudioAvailability({ items, isLoading, error, onRetry, onCreate, onUpdate, onDelete }) {
  const [editing, setEditing] = useState(undefined);
  const [form, setForm] = useState(emptyForm);
  const [isSaving, setIsSaving] = useState(false);
  const [deletingId, setDeletingId] = useState(null);
  const [actionError, setActionError] = useState("");
  const [success, setSuccess] = useState("");
  const [statusFilter, setStatusFilter] = useState("all");
  const [dateFilter, setDateFilter] = useState("all");
  const [sortBy, setSortBy] = useState("nearest");
  const [currentPage, setCurrentPage] = useState(1);
  const availabilityItems = useMemo(() => Array.isArray(items) ? items.filter(Boolean) : [], [items]);
  const today = getLocalDate();
  const filteredItems = useMemo(() => [...availabilityItems].filter((item) => {
    const statusMatches = statusFilter === "all" || (statusFilter === "available" ? item.isAvailable === true : item.isAvailable === false);
    const date = typeof item.date === "string" ? item.date.slice(0, 10) : "";
    const dateMatches = dateFilter === "all" || (dateFilter === "today" ? date === today : date > today);
    return statusMatches && dateMatches;
  }).sort((a, b) => sortBy === "latest" ? String(b.date ?? "").localeCompare(String(a.date ?? "")) : String(a.date ?? "").localeCompare(String(b.date ?? ""))), [availabilityItems, statusFilter, dateFilter, sortBy, today]);
  const totalPages = Math.max(1, Math.ceil(filteredItems.length / pageSize));
  const safeCurrentPage = Math.min(currentPage, totalPages);
  const visibleItems = filteredItems.slice((safeCurrentPage - 1) * pageSize, safeCurrentPage * pageSize);
  const resetPage = (setter) => (event) => { setter(event.target.value); setCurrentPage(1); };
  const openCreate = () => { setEditing(null); setForm(emptyForm); setActionError(""); setSuccess(""); };
  const openEdit = (item) => { setEditing(item); setForm({ date: item.date, isAvailable: item.isAvailable, startTime: item.startTime?.slice(0, 5) || "", endTime: item.endTime?.slice(0, 5) || "", notes: item.notes || "" }); setActionError(""); setSuccess(""); };
  const close = () => { setEditing(undefined); setActionError(""); };
  const change = (field) => (event) => {
    const value = field === "isAvailable" ? event.target.value === "true" : event.target.value;
    setForm((current) => field === "isAvailable" && !value ? { ...current, isAvailable: false, startTime: "", endTime: "" } : { ...current, [field]: value });
  };
  const submit = async (event) => {
    event.preventDefault();
    if (form.date < getLocalDate()) { setActionError("Past dates are not allowed."); return; }
    if (form.isAvailable && !form.startTime) { setActionError("Start time is required for an available date."); return; }
    if (form.isAvailable && !form.endTime) { setActionError("End time is required for an available date."); return; }
    if (form.isAvailable && form.endTime <= form.startTime) { setActionError("End time must be later than start time."); return; }
    setIsSaving(true); setActionError("");
    try {
      const values = { date: form.date, isAvailable: form.isAvailable, startTime: form.isAvailable ? form.startTime : null, endTime: form.isAvailable ? form.endTime : null, notes: form.notes.trim() || null };
      const wasEditing = Boolean(editing);
      if (editing) await onUpdate(editing.id, values); else await onCreate(values);
      close(); setSuccess(wasEditing ? "Availability updated successfully." : "Availability added successfully.");
    } catch (failure) { setActionError(failure.message || "Unable to save availability."); }
    finally { setIsSaving(false); }
  };
  const remove = async (item) => {
    if (!window.confirm(`Delete availability for ${formatDate(item.date)}? This action cannot be undone.`)) return;
    setDeletingId(item.id); setActionError(""); setSuccess("");
    try { await onDelete(item.id); setSuccess("Availability deleted successfully."); }
    catch (failure) { setActionError(failure.message || "Unable to delete availability."); }
    finally { setDeletingId(null); }
  };
  const editorOpen = editing !== undefined;
  return <Card className="studio-panel availability-panel" ariaLabel="Availability">
    <div className="panel-heading"><div><p className="studio-kicker">SCHEDULE</p><h2>Availability</h2></div><Button onClick={openCreate}>Add availability</Button></div>
    {!isLoading && !error && availabilityItems.length > 0 && <div className="management-controls availability-controls">
      <label className="management-field"><span>Status</span><select value={statusFilter} onChange={resetPage(setStatusFilter)} aria-label="Filter availability by status"><option value="all">All Statuses</option><option value="available">Available</option><option value="unavailable">Unavailable</option></select></label>
      <label className="management-field"><span>Date</span><select value={dateFilter} onChange={resetPage(setDateFilter)} aria-label="Filter availability by date"><option value="all">All Dates</option><option value="upcoming">Upcoming</option><option value="today">Today</option></select></label>
      <label className="management-field"><span>Sort By</span><select value={sortBy} onChange={resetPage(setSortBy)} aria-label="Sort availability"><option value="nearest">Date: Nearest First</option><option value="latest">Date: Latest First</option></select></label>
    </div>}
    {isLoading ? <p className="portfolio-feedback">Loading availability…</p> : error ? <div className="portfolio-feedback error"><p>{error}</p><button type="button" onClick={onRetry}>Try again</button></div> : availabilityItems.length === 0 ? <div className="availability-empty"><p>No availability configured yet.</p></div> : filteredItems.length === 0 ? <div className="availability-empty"><p>No availability records match the selected filters.</p></div> : <><div className="availability-records">{visibleItems.map((item) => <div className="availability-record" key={item.id}>
      <div className="availability-record-main"><strong>{formatDate(item.date)}</strong><span className={`availability-chip ${item.isAvailable ? "available" : "unavailable"}`}>{item.isAvailable ? "Available" : "Unavailable"}</span></div>
      <dl><div><dt>Start Time</dt><dd>{formatTime(item.startTime)}</dd></div><div><dt>End Time</dt><dd>{formatTime(item.endTime)}</dd></div><div><dt>Notes</dt><dd>{item.notes || "—"}</dd></div></dl>
      <div className="item-actions"><button type="button" onClick={() => openEdit(item)}>Edit</button><button type="button" className="delete-action" onClick={() => remove(item)} disabled={deletingId === item.id}>{deletingId === item.id ? "Deleting…" : "Delete"}</button></div>
    </div>)}</div><Pagination currentPage={safeCurrentPage} totalPages={totalPages} onPageChange={setCurrentPage} /></>}
    {success && <p className="portfolio-feedback success" role="status">{success}</p>}{actionError && !editorOpen && <p className="portfolio-feedback error" role="alert">{actionError}</p>}
    {editorOpen && createPortal(<div className="profile-editor-backdrop"><form className="profile-editor" onSubmit={submit} aria-label={editing ? "Edit availability" : "Add availability"}>
      <div className="profile-editor-heading"><h3>{editing ? "Edit availability" : "Add availability"}</h3><button type="button" onClick={close} aria-label="Close availability editor">×</button></div>
      <label>Date<input required type="date" min={getLocalDate()} value={form.date} onChange={change("date")} /></label>
      <label>Status<select required value={String(form.isAvailable)} onChange={change("isAvailable")}><option value="true">Available</option><option value="false">Unavailable</option></select></label>
      <div className="availability-time-fields"><label>Start Time<input required={form.isAvailable} disabled={!form.isAvailable} type="time" value={form.startTime} onChange={change("startTime")} /></label><label>End Time<input required={form.isAvailable} disabled={!form.isAvailable} type="time" value={form.endTime} onChange={change("endTime")} /></label></div>
      <label>Notes<textarea maxLength="1000" rows="3" value={form.notes} onChange={change("notes")} /></label>
      {actionError && <p className="profile-feedback error" role="alert">{actionError}</p>}
      <div className="profile-editor-actions"><button type="button" onClick={close} disabled={isSaving}>Cancel</button><Button type="submit" disabled={isSaving}>{isSaving ? "Saving…" : "Save availability"}</Button></div>
    </form></div>, document.body)}
  </Card>;
}

export default StudioAvailability;
