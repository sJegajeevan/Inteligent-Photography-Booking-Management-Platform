import { useMemo, useState } from "react";
import { createPortal } from "react-dom";
import Button from "../../components/common/Button";
import Card from "../../components/common/Card";
import Pagination from "../../components/common/Pagination";

const emptyService = { serviceName: "", description: "", packageDetails: [""], startingPrice: "" };
const priceFormatter = new Intl.NumberFormat("en-LK", { style: "currency", currency: "LKR", minimumFractionDigits: 2 });
const pageSize = 5;

function StudioServices({ services, isLoading, error, onRetry, onCreate, onUpdate, onDelete }) {
  const [editingService, setEditingService] = useState(undefined);
  const [form, setForm] = useState(emptyService);
  const [isSaving, setIsSaving] = useState(false);
  const [deletingId, setDeletingId] = useState(null);
  const [actionError, setActionError] = useState("");
  const [success, setSuccess] = useState("");
  const [search, setSearch] = useState("");
  const [sortBy, setSortBy] = useState("newest");
  const [currentPage, setCurrentPage] = useState(1);
  const serviceItems = useMemo(() => Array.isArray(services) ? services.filter(Boolean) : [], [services]);
  const filteredServices = useMemo(() => {
    const term = search.trim().toLowerCase();
    return serviceItems
      .map((service, index) => ({ service, index }))
      .filter(({ service }) => {
        const packageDetails = Array.isArray(service.packageDetails) ? service.packageDetails.join(" ") : "";
        return !term || [service.serviceName, service.description, packageDetails].some((value) => String(value ?? "").trim().toLowerCase().includes(term));
      })
      .sort((a, b) => {
        if (sortBy === "price-asc") return (Number(a.service.startingPrice) || 0) - (Number(b.service.startingPrice) || 0);
        if (sortBy === "price-desc") return (Number(b.service.startingPrice) || 0) - (Number(a.service.startingPrice) || 0);
        if (sortBy === "name-asc") return String(a.service.serviceName ?? "").localeCompare(String(b.service.serviceName ?? ""));
        if (sortBy === "name-desc") return String(b.service.serviceName ?? "").localeCompare(String(a.service.serviceName ?? ""));
        return a.index - b.index;
      })
      .map(({ service }) => service);
  }, [serviceItems, search, sortBy]);
  const totalPages = Math.max(1, Math.ceil(filteredServices.length / pageSize));
  const safeCurrentPage = Math.min(currentPage, totalPages);
  const visibleServices = filteredServices.slice((safeCurrentPage - 1) * pageSize, safeCurrentPage * pageSize);
  const resetPage = (setter) => (event) => { setter(event.target.value); setCurrentPage(1); };

  const openCreate = () => { setEditingService(null); setForm(emptyService); setActionError(""); setSuccess(""); };
  const openEdit = (service) => {
    setEditingService(service);
    setForm({
      serviceName: service.serviceName,
      description: service.description || "",
      packageDetails: Array.isArray(service.packageDetails) && service.packageDetails.length > 0 ? [...service.packageDetails] : [""],
      startingPrice: String(service.startingPrice),
    });
    setActionError(""); setSuccess("");
  };
  const close = () => { setEditingService(undefined); setActionError(""); };
  const isEditorOpen = editingService !== undefined;
  const change = (field) => (event) => setForm((current) => ({ ...current, [field]: event.target.value }));
  const changePackageDetail = (index) => (event) => setForm((current) => ({
    ...current,
    packageDetails: current.packageDetails.map((detail, detailIndex) => detailIndex === index ? event.target.value : detail),
  }));
  const addPackageDetail = () => setForm((current) => ({ ...current, packageDetails: [...current.packageDetails, ""] }));
  const removePackageDetail = (index) => setForm((current) => ({
    ...current,
    packageDetails: current.packageDetails.filter((_, detailIndex) => detailIndex !== index),
  }));
  const submit = async (event) => {
    event.preventDefault();
    const startingPrice = Number(form.startingPrice);
    if (!Number.isFinite(startingPrice) || startingPrice < 0) { setActionError("Starting price must be a valid non-negative number."); return; }
    setIsSaving(true); setActionError("");
    try {
      const values = {
        ...form,
        serviceName: form.serviceName.trim(),
        description: form.description.trim(),
        packageDetails: form.packageDetails.map((detail) => detail.trim()).filter(Boolean),
        startingPrice,
      };
      if (editingService) await onUpdate(editingService.id, values); else await onCreate(values);
      close(); setSuccess(editingService ? "Service updated successfully." : "Service added successfully.");
    } catch (failure) { setActionError(failure.message || "Unable to save the service."); }
    finally { setIsSaving(false); }
  };
  const remove = async (service) => {
    if (!window.confirm(`Delete “${service.serviceName}”? This action cannot be undone.`)) return;
    setDeletingId(service.id); setActionError(""); setSuccess("");
    try { await onDelete(service.id); setSuccess("Service deleted successfully."); }
    catch (failure) { setActionError(failure.message || "Unable to delete the service."); }
    finally { setDeletingId(null); }
  };

  return <section className="studio-section" aria-labelledby="services-title">
    <div className="section-heading"><div><p className="studio-kicker">WHAT YOU OFFER</p><h2 id="services-title">Services</h2><p>Present your photography packages with clarity.</p></div><Button onClick={openCreate}>Add Service</Button></div>
    {!isLoading && !error && serviceItems.length > 0 && <div className="management-controls management-controls-two">
      <label className="management-search"><span aria-hidden="true">⌕</span><input type="search" value={search} onChange={resetPage(setSearch)} placeholder="Search services..." aria-label="Search services" /></label>
      <label className="management-field"><span>Sort By</span><select value={sortBy} onChange={resetPage(setSortBy)} aria-label="Sort services"><option value="newest">Newest First</option><option value="price-asc">Price: Low to High</option><option value="price-desc">Price: High to Low</option><option value="name-asc">Name: A-Z</option><option value="name-desc">Name: Z-A</option></select></label>
    </div>}
    {isLoading ? <p className="portfolio-feedback">Loading services…</p>
      : error ? <div className="portfolio-feedback error"><p>{error}</p><button type="button" onClick={onRetry}>Try again</button></div>
        : serviceItems.length === 0 ? <div className="portfolio-empty"><h3>No services added yet.</h3></div>
          : filteredServices.length === 0 ? <div className="portfolio-empty"><p>No services match your search.</p></div>
          : <><div className="services-grid">{visibleServices.map((service) => <Card key={service.id} className="service-card">
            <div className="service-top"><span className="service-mark">✧</span></div>
            <h3>{service.serviceName}</h3>
            <div className="service-description"><h4>Description</h4><p>{service.description}</p></div>
            <div className="service-package-details"><h4>Package Details</h4>
              {Array.isArray(service.packageDetails) && service.packageDetails.length > 0
                ? <ul>{service.packageDetails.map((detail, index) => <li key={`${detail}-${index}`}>{detail}</li>)}</ul>
                : <p>No package details provided.</p>}
            </div>
            <strong className="service-price">{priceFormatter.format(Number(service.startingPrice))}</strong>
            <div className="item-actions"><button type="button" onClick={() => openEdit(service)}>Edit</button><button type="button" className="delete-action" onClick={() => remove(service)} disabled={deletingId === service.id}>{deletingId === service.id ? "Deleting…" : "Delete"}</button></div>
          </Card>)}</div><Pagination currentPage={safeCurrentPage} totalPages={totalPages} onPageChange={setCurrentPage} /></>}
    {success && <p className="portfolio-feedback success" role="status">{success}</p>}
    {actionError && !isEditorOpen && <p className="portfolio-feedback error" role="alert">{actionError}</p>}
    {isEditorOpen && createPortal(<div className="profile-editor-backdrop"><form className="profile-editor" onSubmit={submit} aria-label={editingService ? "Edit service" : "Add service"}>
      <div className="profile-editor-heading"><h3>{editingService ? "Edit service" : "Add service"}</h3><button type="button" onClick={close} aria-label="Close service editor">×</button></div>
      <label>Service Name<input required maxLength="160" value={form.serviceName} onChange={change("serviceName")} /></label>
      <label>Description<textarea required maxLength="1000" rows="4" value={form.description} onChange={change("description")} /></label>
      <fieldset className="package-details-editor"><legend>Package Details</legend>
        {form.packageDetails.map((detail, index) => <div className="package-detail-row" key={index}>
          <input maxLength="300" aria-label={`Package detail ${index + 1}`} value={detail} onChange={changePackageDetail(index)} />
          <button type="button" onClick={() => removePackageDetail(index)} aria-label={`Remove package detail ${index + 1}`}>Remove</button>
        </div>)}
        <button type="button" className="add-detail-button" onClick={addPackageDetail}>+ Add Detail</button>
      </fieldset>
      <label>Starting Price<input required type="number" min="0" step="0.01" value={form.startingPrice} onChange={change("startingPrice")} /></label>
      {actionError && <p className="profile-feedback error" role="alert">{actionError}</p>}
      <div className="profile-editor-actions"><button type="button" onClick={close} disabled={isSaving}>Cancel</button><Button type="submit" disabled={isSaving}>{isSaving ? "Saving…" : "Save service"}</Button></div>
    </form></div>, document.body)}
  </section>;
}

export default StudioServices;
