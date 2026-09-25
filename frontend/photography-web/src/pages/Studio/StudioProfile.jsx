import { useState } from "react";
import { createPortal } from "react-dom";
import Button from "../../components/common/Button";
import Card from "../../components/common/Card";
import StudioLocationPicker from "./StudioLocationPicker";

const emptyProfile = {
  studioName: "", description: "", location: "", address: "", contactNumber: "", email: "",
  latitude: "", longitude: "", experienceYears: 0, photographyTypes: "", startingPrice: 0, logoUrl: "", coverPhotoUrl: "", logoImage: null, coverImage: null,
};

const formatText = (value) => typeof value === "string" && value.trim() ? value.trim() : "Not provided";
const formatExperience = (value) => Number.isFinite(Number(value)) && Number(value) > 0 ? `${Number(value)} years` : "Not provided";
const formatPrice = (value) => Number.isFinite(Number(value)) && Number(value) > 0 ? `LKR ${Number(value).toLocaleString()}` : "Not provided";

function StudioProfile({ profile, isLoading, error, onSave, onDelete, onRetry }) {
  const [isEditing, setIsEditing] = useState(false);
  const [form, setForm] = useState(emptyProfile);
  const [actionError, setActionError] = useState("");
  const [success, setSuccess] = useState("");
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);

  const openEditor = () => {
    setForm(profile ? { ...emptyProfile, ...profile, latitude: profile.latitude ?? "", longitude: profile.longitude ?? "" } : emptyProfile);
    setActionError(""); setSuccess(""); setIsEditing(true);
  };
  const submit = async (event) => {
    event.preventDefault(); setActionError("");
    const latitude = String(form.latitude).trim() === "" ? null : Number(form.latitude);
    const longitude = String(form.longitude).trim() === "" ? null : Number(form.longitude);
    if ((latitude === null) !== (longitude === null) ||
        (latitude !== null && (!Number.isFinite(latitude) || latitude < -90 || latitude > 90)) ||
        (longitude !== null && (!Number.isFinite(longitude) || longitude < -180 || longitude > 180))) {
      setActionError("Enter both coordinates: latitude -90 to 90 and longitude -180 to 180, or clear both.");
      return;
    }
    setIsSaving(true);
    try {
      await onSave({ ...form, latitude, longitude, experienceYears: Number(form.experienceYears), startingPrice: Number(form.startingPrice) });
      setIsEditing(false); setSuccess("Studio profile saved successfully.");
    } catch (failure) { setActionError(failure.message || "Unable to save the studio profile."); }
    finally { setIsSaving(false); }
  };
  const remove = async () => {
    if (!window.confirm("Delete your studio profile? This action cannot be undone.")) return;
    setIsDeleting(true); setActionError("");
    try { await onDelete(); setSuccess("Studio profile deleted successfully."); }
    catch (failure) { setActionError(failure.message || "Unable to delete the studio profile."); }
    finally { setIsDeleting(false); }
  };
  const change = (field) => (event) => setForm((current) => ({ ...current, [field]: event.target.value }));
  const fileChange = (field) => (event) => setForm((current) => ({ ...current, [field]: event.target.files?.[0] || null }));

  return (
    <Card className="studio-panel profile-panel studio-profile-live" ariaLabel="Studio profile">
      <div className="panel-heading">
        <div><p className="studio-kicker">YOUR PRESENCE</p><h2>Studio profile</h2></div>
        <div className="profile-heading-actions">
          {profile && <button className="profile-delete-button" type="button" onClick={remove} disabled={isDeleting}>{isDeleting ? "Deleting…" : "Delete profile"}</button>}
          <Button onClick={openEditor}>{profile ? "Edit profile" : "Create profile"}</Button>
        </div>
      </div>
      {isLoading ? <p className="profile-feedback">Loading your studio profile…</p>
        : error ? <div className="profile-feedback error"><p>{error}</p><button type="button" onClick={onRetry}>Try again</button></div>
          : profile ? <div className="profile-showcase">
            <div className={`profile-cover${profile.coverPhotoUrl?.trim() ? " has-image" : ""}`}>
              {profile.coverPhotoUrl?.trim() && <img className="profile-cover-image" src={profile.coverPhotoUrl} alt={`${formatText(profile.studioName)} cover`} />}
              <span className="profile-cover-wash" aria-hidden="true" />
              <span className="profile-cover-label">Studio identity</span>
            </div>
            <div className="profile-content">
              {profile.logoUrl?.trim() ? <img className="profile-image" src={profile.logoUrl} alt={`${formatText(profile.studioName)} logo`} /> : <div className="profile-avatar" aria-hidden="true">{profile.studioName?.trim()?.slice(0, 1).toUpperCase() || "S"}</div>}
              <div className="profile-details"><p className="profile-eyebrow">PHOTOGRAPHY STUDIO</p><h3>{formatText(profile.studioName)}</h3><p>{formatText(profile.description)}</p><dl>
              <div><span className="profile-detail-icon" aria-hidden="true">⌖</span><dt>Location</dt><dd>{formatText(profile.location)}</dd></div><div><span className="profile-detail-icon" aria-hidden="true">⌂</span><dt>Address</dt><dd>{formatText(profile.address)}</dd></div>
              <div><span className="profile-detail-icon" aria-hidden="true">☏</span><dt>Contact number</dt><dd>{formatText(profile.contactNumber)}</dd></div><div><span className="profile-detail-icon" aria-hidden="true">@</span><dt>Email</dt><dd>{formatText(profile.email)}</dd></div>
              <div><span className="profile-detail-icon" aria-hidden="true">✦</span><dt>Experience</dt><dd>{formatExperience(profile.experienceYears)}</dd></div><div><span className="profile-detail-icon" aria-hidden="true">✧</span><dt>Photography types</dt><dd>{formatText(profile.photographyTypes)}</dd></div>
              <div><span className="profile-detail-icon" aria-hidden="true">◈</span><dt>Starting price</dt><dd>{formatPrice(profile.startingPrice)}</dd></div>
              <div><dt>Coordinates</dt><dd>{profile.latitude != null && profile.longitude != null ? `${profile.latitude}, ${profile.longitude}` : "Not set"}</dd></div>
              </dl></div>
            </div>
          </div> : <div className="profile-empty"><h3>Complete your Studio Profile</h3><p>Add your business details so clients can get to know your studio.</p></div>}
      {success && <p className="profile-feedback success" role="status">{success}</p>}
      {actionError && !isEditing && <p className="profile-feedback error" role="alert">{actionError}</p>}
      {isEditing && createPortal(<div className="profile-editor-backdrop"><form className="profile-editor" onSubmit={submit} aria-label="Edit studio profile">
        <div className="profile-editor-heading"><h3>{profile ? "Edit studio profile" : "Create studio profile"}</h3><button type="button" onClick={() => setIsEditing(false)} aria-label="Close profile editor">×</button></div>
        <label>Studio name<input required minLength="2" maxLength="120" value={form.studioName} onChange={change("studioName")} /></label>
        <label>Description<textarea required minLength="10" maxLength="1000" rows="4" value={form.description} onChange={change("description")} /></label>
        <div className="profile-form-grid"><label>Location<input required minLength="2" maxLength="160" value={form.location} onChange={change("location")} /></label><label>Address<input required minLength="5" maxLength="240" value={form.address} onChange={change("address")} /></label></div>
        <StudioLocationPicker latitude={form.latitude} longitude={form.longitude}
          onSelect={(latitude, longitude) => setForm((current) => ({ ...current, latitude, longitude }))} />
        <div className="profile-form-grid">
          <label>Latitude<input type="number" min="-90" max="90" step="any" value={form.latitude} onChange={change("latitude")} aria-describedby="coordinate-help" /></label>
          <label>Longitude<input type="number" min="-180" max="180" step="any" value={form.longitude} onChange={change("longitude")} aria-describedby="coordinate-help" /></label>
        </div>
        <small id="coordinate-help">Optional: enter both coordinates so customers can find your studio with Near Me. Leave both blank to remove the location pin. Coordinates are saved to six decimal places.</small>
        <div className="profile-form-grid"><label>Contact number<input required minLength="7" maxLength="30" value={form.contactNumber} onChange={change("contactNumber")} /></label><label>Email<input required type="email" maxLength="254" value={form.email} onChange={change("email")} /></label></div>
        <div className="profile-form-grid"><label>Experience years<input required type="number" min="0" max="100" step="1" value={form.experienceYears} onChange={change("experienceYears")} /></label><label>Starting price (LKR)<input required type="number" min="0" max="9999999999.99" step="0.01" value={form.startingPrice} onChange={change("startingPrice")} /></label></div>
        <label>Photography types<input required minLength="2" maxLength="500" placeholder="Wedding, portrait, event" value={form.photographyTypes} onChange={change("photographyTypes")} /></label>
        <div className="profile-form-grid"><label>Profile picture<input type="file" accept="image/jpeg,image/png,image/webp" onChange={fileChange("logoImage")} />{form.logoImage && <small>{form.logoImage.name}</small>}</label><label>Cover photo<input type="file" accept="image/jpeg,image/png,image/webp" onChange={fileChange("coverImage")} />{form.coverImage && <small>{form.coverImage.name}</small>}</label></div>
        {actionError && <p className="profile-feedback error" role="alert">{actionError}</p>}
        <div className="profile-editor-actions"><button type="button" onClick={() => setIsEditing(false)} disabled={isSaving}>Cancel</button><Button type="submit" disabled={isSaving}>{isSaving ? "Saving…" : "Save profile"}</Button></div>
      </form></div>, document.body)}
    </Card>
  );
}

export default StudioProfile;
