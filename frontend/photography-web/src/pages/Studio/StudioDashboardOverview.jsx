import { useState } from "react";
import Card from "../../components/common/Card";
import { StudioIcon } from "./StudioLayout";
import { resolvePortfolioImageUrl } from "../../services/studioPortfolioService";

const dateFormatter = new Intl.DateTimeFormat("en-LK", { day: "2-digit", month: "short", year: "numeric", timeZone: "UTC" });
const timeFormatter = new Intl.DateTimeFormat("en-LK", { hour: "numeric", minute: "2-digit", timeZone: "UTC" });
const dateValue = (value) => typeof value === "string" ? value.slice(0, 10) : "";
function localToday() { const now = new Date(); return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`; }
const formatDate = (value) => dateFormatter.format(new Date(`${dateValue(value)}T00:00:00Z`));
function formatTime(value) { if (!/^\d{2}:\d{2}/.test(value || "")) return "Not set"; const [h, m] = value.split(":").map(Number); return timeFormatter.format(new Date(Date.UTC(2000, 0, 1, h, m))); }
const go = (path) => window.location.assign(path);

function ImageAvatar({ profile, failedLogoUrl, onLogoError }) {
  const name = profile?.studioName?.trim() || "Your Studio";
  const image = profile?.logoUrl?.trim();
  return <span className="dashboard-profile-avatar">{image && image !== failedLogoUrl ? <img src={image} alt={`${name} logo`} onError={() => onLogoError(image)} /> : name.charAt(0).toUpperCase()}</span>;
}

function LoadValue({ loading, error, children }) {
  if (loading) return <span className="dashboard-loading-pulse" aria-label="Loading" />;
  if (error) return <span className="dashboard-metric-error" title={error}>—</span>;
  return children;
}

export default function StudioDashboardOverview(props) {
  const [failedCoverUrl, setFailedCoverUrl] = useState("");
  const { profile, profileLoading, profileError, profileCompletion, portfolio, portfolioLoading, portfolioError, services, servicesLoading, servicesError, availability, availabilityLoading, availabilityError, failedLogoUrl, onLogoError } = props;
  const portfolioItems = Array.isArray(portfolio) ? portfolio.filter(Boolean) : [];
  const serviceItems = Array.isArray(services) ? services.filter(Boolean) : [];
  const availabilityItems = Array.isArray(availability) ? availability.filter(Boolean) : [];
  const studioName = profile?.studioName?.trim() || "Your Studio";
  const upcoming = availabilityItems.filter((item) => /^\d{4}-\d{2}-\d{2}$/.test(dateValue(item.date)) && dateValue(item.date) >= localToday()).sort((a, b) => dateValue(a.date).localeCompare(dateValue(b.date)));
  const recentPortfolio = [...portfolioItems].sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0)).slice(0, 4);
  const cover = profile?.coverPhotoUrl?.trim();
  const showCover = Boolean(cover && cover !== failedCoverUrl);
  const metrics = [
    ["portfolio", "violet", "Portfolio Items", portfolioLoading, portfolioError, portfolioItems.length, "Photos in your showcase"],
    ["services", "blue", "Services", servicesLoading, servicesError, serviceItems.length, "Packages offered"],
    ["calendar", "green", "Availability", availabilityLoading, availabilityError, availabilityItems.length, "Schedule records"],
    ["profile", "amber", "Profile Completion", profileLoading, profileError, `${profileCompletion}%`, "Studio details completed"],
  ];
  const actions = [
    ["portfolio", "Add New Portfolio", "Showcase a recent photography project", "/studio/portfolio"],
    ["services", "Add New Service", "Create a new client package", "/studio/services"],
    ["calendar", "Manage Availability", "Update your booking schedule", "/studio/availability"],
    ["profile", "View Studio Profile", "Review your public studio details", "/studio/profile"],
  ];

  return <>
    <section className="dashboard-welcome"><h2>Welcome back, {profileLoading ? "Studio" : studioName}! <span aria-hidden="true">👋</span></h2><p>Here&apos;s what&apos;s happening with your studio.</p></section>
    <section className="dashboard-metrics" aria-label="Studio statistics">{metrics.map(([icon, tone, label, loading, error, value, detail]) => <Card className="metric-card" key={label}><span className={`metric-icon metric-${tone}`}><StudioIcon name={icon} /></span><div><p>{label}</p><h3><LoadValue loading={loading} error={error}>{value}</LoadValue></h3><small>{error || detail}</small></div></Card>)}</section>
    <section className="dashboard-two-column dashboard-primary-row">
      <Card className="dashboard-panel studio-summary-card"><div className={`studio-summary-cover${showCover ? " has-image" : ""}`}>{showCover && <img src={cover} alt={`${studioName} cover`} onError={() => setFailedCoverUrl(cover)} />}<button className="studio-cover-action" type="button" onClick={() => go("/studio/profile")}><StudioIcon name="portfolio" />{showCover ? "Change Cover Photo" : "Add Cover Photo"}</button></div><div className="studio-summary-content"><ImageAvatar profile={profile} failedLogoUrl={failedLogoUrl} onLogoError={onLogoError} /><button className="dashboard-secondary-button" type="button" onClick={() => go("/studio/profile")}>Edit Profile</button><div className="studio-summary-copy">{profileLoading ? <p>Loading studio profile…</p> : profileError ? <p className="dashboard-error">{profileError}</p> : <><h3>{profile?.studioName?.trim() || "Studio profile not set up"}</h3><p className="studio-summary-location">{profile?.location?.trim() || "Location not provided"}</p>{profile?.description?.trim() && <p className="studio-summary-description">{profile.description.trim()}</p>}<p className="studio-summary-types">{profile?.photographyTypes?.trim() || "Photography types not provided"}</p></>}</div></div></Card>
      <Card className="dashboard-panel"><div className="dashboard-panel-heading"><div><h3>Upcoming Availability</h3><p>Your next schedule entries</p></div><button type="button" onClick={() => go("/studio/availability")}>Manage Availability</button></div>{availabilityLoading ? <p className="dashboard-empty">Loading availability…</p> : availabilityError ? <p className="dashboard-empty dashboard-error">{availabilityError}</p> : upcoming.length ? <div className="upcoming-list">{upcoming.slice(0, 7).map((item, index) => <div key={item.id ?? `${item.date}-${index}`}><span className={`availability-state ${item.isAvailable ? "available" : "unavailable"}`}><StudioIcon name={item.isAvailable ? "check" : "x"} /></span><span><strong>{formatDate(item.date)}</strong><small>{formatTime(item.startTime)} – {formatTime(item.endTime)}</small></span><em className={item.isAvailable ? "available" : "unavailable"}>{item.isAvailable ? "Available" : "Unavailable"}</em></div>)}</div> : <p className="dashboard-empty">No upcoming availability records.</p>}</Card>
    </section>
    <section className="dashboard-two-column">
      <Card className="dashboard-panel"><div className="dashboard-panel-heading portfolio-heading"><div><h3>Recent Portfolio</h3><p>Your latest published work</p></div><div><button type="button" onClick={() => go("/studio/portfolio")}>View All</button><button className="dashboard-primary-button" type="button" onClick={() => go("/studio/portfolio")}>+ Add Project</button></div></div>{portfolioLoading ? <p className="dashboard-empty">Loading portfolio…</p> : portfolioError ? <p className="dashboard-empty dashboard-error">{portfolioError}</p> : recentPortfolio.length ? <div className="recent-portfolio-grid">{recentPortfolio.map((item, index) => { const cover = item.images?.[0]?.imageUrl || item.imageUrl; return <button type="button" key={item.id ?? index} onClick={() => go("/studio/portfolio")}><span>{cover ? <img src={resolvePortfolioImageUrl(cover)} alt="" /> : <StudioIcon name="portfolio" />}</span><strong>{item.title || "Untitled"}</strong><small>{item.category || "Uncategorized"}</small></button>; })}</div> : <p className="dashboard-empty">No portfolio items yet.</p>}</Card>
      <Card className="dashboard-panel quick-actions-panel"><div className="dashboard-panel-heading"><div><h3>Quick Actions</h3><p>Shortcuts to manage your studio</p></div></div><div className="dashboard-action-list">{actions.map(([icon, title, description, path]) => <button type="button" key={title} onClick={() => go(path)}><span className="action-icon"><StudioIcon name={icon} /></span><span><strong>{title}</strong><small>{description}</small></span><StudioIcon name="arrow" /></button>)}</div></Card>
    </section>
  </>;
}
