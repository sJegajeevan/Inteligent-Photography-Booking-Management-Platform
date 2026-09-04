import { useEffect, useMemo, useState } from "react";
import { createPortal } from "react-dom";
import Button from "../../components/common/Button";
import Pagination from "../../components/common/Pagination";
import { resolvePortfolioImageUrl } from "../../services/studioPortfolioService";

const formCategories = ["Wedding", "Birthday", "Pre-Wedding", "Portrait", "Event", "Corporate", "Product", "Other"];
const emptyForm = { title: "", category: "", description: "", photos: [], removedImageIds: [] };
const allowedTypes = new Set(["image/jpeg", "image/png", "image/webp"]);
const maxImageBytes = 5 * 1024 * 1024;
const pageSize = 9;
const dateFormatter = new Intl.DateTimeFormat("en-GB", { day: "2-digit", month: "short", year: "numeric" });

function projectImages(item) {
  if (Array.isArray(item?.images) && item.images.length) return [...item.images].sort((a, b) => (a.displayOrder ?? 0) - (b.displayOrder ?? 0));
  return item?.imageUrl ? [{ id: `legacy-${item.id}`, imageUrl: item.imageUrl, displayOrder: 0 }] : [];
}
function formatDate(value) { const date = new Date(value); return value && !Number.isNaN(date.getTime()) ? dateFormatter.format(date) : "Date unavailable"; }
function SafeImage({ src, alt = "", className = "" }) {
  const [failed, setFailed] = useState(false);
  return failed || !src ? <span className={`portfolio-image-fallback ${className}`} role="img" aria-label="Image unavailable">◇</span> : <img className={className} src={resolvePortfolioImageUrl(src)} alt={alt} onError={() => setFailed(true)} />;
}

function StudioPortfolio({ items, isLoading, error, onRetry, onCreate, onUpdate, onDelete }) {
  const [editingItem, setEditingItem] = useState(undefined);
  const [form, setForm] = useState(emptyForm);
  const [existingImages, setExistingImages] = useState([]);
  const [previews, setPreviews] = useState([]);
  const [galleryItem, setGalleryItem] = useState(null);
  const [lightboxIndex, setLightboxIndex] = useState(null);
  const [isSaving, setIsSaving] = useState(false);
  const [deletingId, setDeletingId] = useState(null);
  const [actionError, setActionError] = useState("");
  const [success, setSuccess] = useState("");
  const [search, setSearch] = useState("");
  const [category, setCategory] = useState("");
  const [sortBy, setSortBy] = useState("newest");
  const [currentPage, setCurrentPage] = useState(1);
  const portfolioItems = useMemo(() => Array.isArray(items) ? items.filter(Boolean) : [], [items]);
  const categoryOptions = useMemo(() => [...new Set(portfolioItems.map((item) => String(item.category || "").trim()).filter(Boolean))].sort(), [portfolioItems]);
  const editorCategories = useMemo(() => [...new Set([...formCategories, ...categoryOptions])], [categoryOptions]);
  const filteredItems = useMemo(() => {
    const term = search.trim().toLowerCase();
    return [...portfolioItems].filter((item) => (!term || `${item.title || ""} ${item.description || ""} ${item.category || ""}`.toLowerCase().includes(term)) && (!category || item.category === category)).sort((a, b) => {
      if (sortBy === "oldest") return new Date(a.createdAt || 0) - new Date(b.createdAt || 0);
      if (sortBy === "title-asc") return String(a.title || "").localeCompare(String(b.title || ""));
      if (sortBy === "title-desc") return String(b.title || "").localeCompare(String(a.title || ""));
      return new Date(b.createdAt || 0) - new Date(a.createdAt || 0);
    });
  }, [portfolioItems, search, category, sortBy]);
  const totalPages = Math.max(1, Math.ceil(filteredItems.length / pageSize));
  const safeCurrentPage = Math.min(currentPage, totalPages);
  const visibleItems = filteredItems.slice((safeCurrentPage - 1) * pageSize, safeCurrentPage * pageSize);
  const galleryImages = galleryItem ? projectImages(galleryItem) : [];

  useEffect(() => {
    if (!galleryItem) return undefined;
    const onKeyDown = (event) => {
      if (event.key === "Escape") lightboxIndex === null ? setGalleryItem(null) : setLightboxIndex(null);
      if (lightboxIndex !== null && event.key === "ArrowLeft") setLightboxIndex((lightboxIndex - 1 + galleryImages.length) % galleryImages.length);
      if (lightboxIndex !== null && event.key === "ArrowRight") setLightboxIndex((lightboxIndex + 1) % galleryImages.length);
    };
    document.body.classList.add("portfolio-modal-open"); window.addEventListener("keydown", onKeyDown);
    return () => { document.body.classList.remove("portfolio-modal-open"); window.removeEventListener("keydown", onKeyDown); };
  }, [galleryItem, lightboxIndex, galleryImages.length]);

  const clearPreviews = () => { previews.forEach(({ url }) => URL.revokeObjectURL(url)); setPreviews([]); };
  const openCreate = () => { clearPreviews(); setEditingItem(null); setExistingImages([]); setForm(emptyForm); setActionError(""); setSuccess(""); };
  const openEdit = (item) => { clearPreviews(); setEditingItem(item); setExistingImages(projectImages(item)); setForm({ title: item.title || "", category: item.category || "", description: item.description || "", photos: [], removedImageIds: [] }); setActionError(""); setSuccess(""); };
  const closeEditor = () => { clearPreviews(); setEditingItem(undefined); setActionError(""); };
  const change = (field) => (event) => setForm((current) => ({ ...current, [field]: event.target.value }));
  const chooseCategory = (value) => { setCategory(value); setCurrentPage(1); };
  const resetPage = (setter) => (event) => { setter(event.target.value); setCurrentPage(1); };
  const selectPhotos = (event) => {
    const files = [...(event.target.files || [])]; event.target.value = "";
    if (files.some((file) => !allowedTypes.has(file.type))) { setActionError("Only JPG, PNG and WEBP images are allowed."); return; }
    if (files.some((file) => file.size > maxImageBytes)) { setActionError("Each image must be smaller than 5 MB."); return; }
    const additions = files.map((file) => ({ file, url: URL.createObjectURL(file), key: `${file.name}-${file.size}-${file.lastModified}-${crypto.randomUUID()}` }));
    setPreviews((current) => [...current, ...additions]); setForm((current) => ({ ...current, photos: [...current.photos, ...files] })); setActionError("");
  };
  const removePreview = (key) => setPreviews((current) => { const index = current.findIndex((item) => item.key === key); if (index < 0) return current; URL.revokeObjectURL(current[index].url); setForm((value) => ({ ...value, photos: value.photos.filter((_, photoIndex) => photoIndex !== index) })); return current.filter((item) => item.key !== key); });
  const removeExisting = (image) => { setExistingImages((current) => current.filter((item) => item.id !== image.id)); if (!String(image.id).startsWith("legacy-")) setForm((current) => ({ ...current, removedImageIds: [...current.removedImageIds, image.id] })); };
  const submit = async (event) => {
    event.preventDefault(); setActionError("");
    if (!editingItem && form.photos.length === 0) { setActionError("Select at least one photo."); return; }
    if (editingItem && existingImages.length + form.photos.length === 0) { setActionError("An album must contain at least one photo."); return; }
    setIsSaving(true);
    try { if (editingItem) await onUpdate(editingItem.id, form); else await onCreate(form); const message = editingItem ? "Album updated successfully." : "Album created successfully."; closeEditor(); setSuccess(message); }
    catch (failure) { setActionError(failure.message || "Unable to save the album."); } finally { setIsSaving(false); }
  };
  const remove = async (item) => { if (!window.confirm(`Delete “${item.title}” and all its photos? This action cannot be undone.`)) return; setDeletingId(item.id); setActionError(""); setSuccess(""); try { await onDelete(item.id); setSuccess("Album deleted successfully."); } catch (failure) { setActionError(failure.message || "Unable to delete the album."); } finally { setDeletingId(null); } };
  const openGallery = (item) => { setGalleryItem(item); setLightboxIndex(null); };

  return <section id="portfolio" className="studio-section portfolio-albums" aria-labelledby="portfolio-title">
    <div className="section-heading portfolio-page-heading"><div><p className="studio-kicker">CURATED WORK</p><h2 id="portfolio-title">Portfolio Albums</h2><p>Present every completed story as a thoughtfully curated photography album.</p></div><Button onClick={openCreate}>+ Add Album</Button></div>
    {!isLoading && !error && portfolioItems.length > 0 && <><nav className="portfolio-category-bar" aria-label="Filter albums by category">{["", ...categoryOptions].map((option) => <button key={option || "all"} type="button" className={category === option ? "active" : ""} aria-pressed={category === option} onClick={() => chooseCategory(option)}>{option || "All"}</button>)}</nav><div className="portfolio-toolbar"><label className="portfolio-search"><span aria-hidden="true">⌕</span><input type="search" value={search} onChange={resetPage(setSearch)} placeholder="Search albums..." aria-label="Search albums" /></label><label><span>Category</span><select value={category} onChange={resetPage(setCategory)}><option value="">All categories</option>{categoryOptions.map((option) => <option key={option}>{option}</option>)}</select></label><label><span>Sort</span><select value={sortBy} onChange={resetPage(setSortBy)}><option value="newest">Newest First</option><option value="oldest">Oldest First</option><option value="title-asc">Title A-Z</option><option value="title-desc">Title Z-A</option></select></label></div></>}
    {isLoading ? <p className="portfolio-feedback">Loading albums…</p> : error ? <div className="portfolio-feedback error"><p>{error}</p><button type="button" onClick={onRetry}>Try again</button></div> : portfolioItems.length === 0 ? <div className="portfolio-empty portfolio-album-empty"><span aria-hidden="true">◇</span><h3>No portfolio albums yet.</h3><p>Create your first album and fill it with your best work.</p><Button onClick={openCreate}>Add Your First Album</Button></div> : filteredItems.length === 0 ? <div className="portfolio-empty"><h3>No albums found.</h3><p>Try a different search or category.</p><button type="button" onClick={() => { setSearch(""); chooseCategory(""); }}>Clear filters</button></div> : <><div className="portfolio-album-grid">{visibleItems.map((item) => { const images = projectImages(item); return <article className="portfolio-album-card" key={item.id}><button type="button" className="portfolio-album-cover" onClick={() => openGallery(item)} aria-label={`View ${item.title} album`}><SafeImage src={images[0]?.imageUrl} alt={item.title} /><span className="portfolio-cover-shade" /><span className="portfolio-view-action">View Album <b aria-hidden="true">→</b></span><span className="portfolio-count-badge">{images.length} {images.length === 1 ? "Photo" : "Photos"}</span></button><div className="portfolio-album-details"><div className="portfolio-album-copy"><span className="portfolio-category">{item.category || "Uncategorized"}</span><h3><button type="button" onClick={() => openGallery(item)}>{item.title || "Untitled album"}</button></h3><p><time dateTime={item.createdAt}>{formatDate(item.createdAt)}</time><i aria-hidden="true" />{images.length} {images.length === 1 ? "photo" : "photos"}</p></div><div className="portfolio-album-actions"><button type="button" onClick={() => openEdit(item)} aria-label={`Edit ${item.title}`}>Edit</button><button type="button" className="delete-action" onClick={() => remove(item)} disabled={deletingId === item.id} aria-label={`Delete ${item.title}`}>{deletingId === item.id ? "Deleting…" : "Delete"}</button></div></div></article>; })}</div><Pagination currentPage={safeCurrentPage} totalPages={totalPages} onPageChange={setCurrentPage} /></>}
    {success && <p className="portfolio-feedback success" role="status">{success}</p>}{actionError && editingItem === undefined && <p className="portfolio-feedback error" role="alert">{actionError}</p>}
    {editingItem !== undefined && createPortal(<div className="profile-editor-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) closeEditor(); }}><form className="profile-editor portfolio-editor" onSubmit={submit}><div className="profile-editor-heading"><div><p className="studio-kicker">ALBUM DETAILS</p><h3>{editingItem ? "Edit portfolio album" : "Create portfolio album"}</h3></div><button type="button" onClick={closeEditor} aria-label="Close">×</button></div><label>Album title<input required minLength="2" maxLength="160" value={form.title} onChange={change("title")} placeholder="e.g. Coastal wedding story" /></label><label>Category<select required value={form.category} onChange={change("category")}><option value="">Select a category</option>{editorCategories.map((value) => <option key={value}>{value}</option>)}</select></label><label>Description<textarea maxLength="1000" rows="4" value={form.description} onChange={change("description")} placeholder="Share a short note about this photography story." /></label>{existingImages.length > 0 && <fieldset className="portfolio-photo-field"><legend>Album photos</legend><div className="portfolio-photo-previews">{existingImages.map((image) => <div key={image.id}><SafeImage src={image.imageUrl} /><button type="button" onClick={() => removeExisting(image)} aria-label="Remove existing photo">×</button></div>)}</div></fieldset>}<label className="portfolio-file-picker">Add photos<input type="file" accept="image/jpeg,image/png,image/webp" multiple onChange={selectPhotos} /><span>Choose one or more JPG, PNG or WEBP files (maximum 5 MB each).</span></label>{previews.length > 0 && <fieldset className="portfolio-photo-field"><legend>New photos</legend><div className="portfolio-photo-previews">{previews.map((preview) => <div key={preview.key}><img src={preview.url} alt="Selected preview" /><button type="button" onClick={() => removePreview(preview.key)} aria-label="Remove selected photo">×</button></div>)}</div></fieldset>}{actionError && <p className="profile-feedback error" role="alert">{actionError}</p>}<div className="profile-editor-actions"><button type="button" onClick={closeEditor} disabled={isSaving}>Cancel</button><Button type="submit" disabled={isSaving}>{isSaving ? "Saving…" : editingItem ? "Save Changes" : "Create Album"}</Button></div></form></div>, document.body)}
    {galleryItem && createPortal(<div className="portfolio-gallery-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) { setGalleryItem(null); setLightboxIndex(null); } }}><section className="portfolio-gallery-modal" role="dialog" aria-modal="true" aria-labelledby="album-dialog-title"><header className="portfolio-gallery-heading"><div><button className="portfolio-gallery-back" type="button" onClick={() => setGalleryItem(null)}>← All albums</button><span className="portfolio-category">{galleryItem.category || "Uncategorized"}</span><h3 id="album-dialog-title">{galleryItem.title}</h3><div className="portfolio-gallery-meta"><span>{formatDate(galleryItem.createdAt)}</span><i aria-hidden="true" /><span>{galleryImages.length} {galleryImages.length === 1 ? "photo" : "photos"}</span></div>{galleryItem.description && <p className="portfolio-gallery-description">{galleryItem.description}</p>}</div><button className="portfolio-gallery-close" type="button" onClick={() => { setGalleryItem(null); setLightboxIndex(null); }} aria-label="Close album">×</button></header>{galleryImages.length ? <div className="portfolio-gallery-grid">{galleryImages.map((image, index) => <button type="button" key={image.id} onClick={() => setLightboxIndex(index)} aria-label={`Open photo ${index + 1} of ${galleryImages.length}`}><SafeImage src={image.imageUrl} alt={`${galleryItem.title} photo ${index + 1}`} /></button>)}</div> : <p className="portfolio-gallery-empty">No photos are available for this album.</p>}</section>{lightboxIndex !== null && galleryImages[lightboxIndex] && <div className="portfolio-lightbox" role="dialog" aria-modal="true" aria-label="Photo viewer"><button className="lightbox-close" type="button" onClick={() => setLightboxIndex(null)} aria-label="Close photo">×</button><span className="lightbox-counter">{lightboxIndex + 1} / {galleryImages.length}</span>{galleryImages.length > 1 && <button type="button" onClick={() => setLightboxIndex((lightboxIndex - 1 + galleryImages.length) % galleryImages.length)} aria-label="Previous photo">‹</button>}<SafeImage src={galleryImages[lightboxIndex].imageUrl} alt={`${galleryItem.title} photo ${lightboxIndex + 1}`} />{galleryImages.length > 1 && <button type="button" onClick={() => setLightboxIndex((lightboxIndex + 1) % galleryImages.length)} aria-label="Next photo">›</button>}</div>}</div>, document.body)}
  </section>;
}
export default StudioPortfolio;
