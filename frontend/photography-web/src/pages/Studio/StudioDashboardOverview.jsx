import { useState } from "react";
import Card from "../../components/common/Card";
import { StudioIcon } from "./StudioLayout";
import { resolvePortfolioImageUrl } from "../../services/studioPortfolioService";
import StudioPhotographyHero from "./StudioPhotographyHero";

const dateFormatter = new Intl.DateTimeFormat("en-LK", { day: "2-digit", month: "short", year: "numeric", timeZone: "UTC" });
const timeFormatter = new Intl.DateTimeFormat("en-LK", { hour: "numeric", minute: "2-digit", timeZone: "UTC" });
const dateValue = (value) => typeof value === "string" ? value.slice(0, 10) : "";
function localToday() { const now = new Date(); return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`; }
const formatDate = (value) => dateFormatter.format(new Date(`${dateValue(value)}T00:00:00Z`));
function formatTime(value) { if (!/^\d{2}:\d{2}/.test(value || "")) return "Not set"; const [h, m] = value.split(":").map(Number); return timeFormatter.format(new Date(Date.UTC(2000, 0, 1, h, m))); }
const monthFormatter = new Intl.DateTimeFormat("en-LK", { month: "long", year: "numeric" });
const go = (path) => window.location.assign(path);

function ImageAvatar({ profile, failedLogoUrl, onLogoError }) {
  const name = profile?.studioName?.trim() || "Studio";
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
  const { profile, profileLoading, profileError, profileCompletion, portfolio, portfolioLoading, portfolioError, services, servicesLoading, servicesError, availability, availabilityLoading, availabilityError, bookings, bookingsLoading, bookingsError, failedLogoUrl, onLogoError } = props;
  const portfolioItems = Array.isArray(portfolio) ? portfolio.filter(Boolean) : [];
  const serviceItems = Array.isArray(services) ? services.filter(Boolean) : [];
  const availabilityItems = Array.isArray(availability) ? availability.filter(Boolean) : [];
  const bookingItems = Array.isArray(bookings) ? bookings.filter(Boolean) : [];
  const studioName = profile?.studioName?.trim() || (profileError ? "Studio" : "Complete your Studio Profile");
  const upcoming = availabilityItems.filter((item) => /^\d{4}-\d{2}-\d{2}$/.test(dateValue(item.date)) && dateValue(item.date) >= localToday()).sort((a, b) => dateValue(a.date).localeCompare(dateValue(b.date)));
  const recentPortfolio = [...portfolioItems].sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0)).slice(0, 4);
  const bookingCounts = {
    pending: bookingItems.filter((item) => item.status === "Pending").length,
    confirmed: bookingItems.filter((item) => item.status === "Confirmed").length,
    completed: bookingItems.filter((item) => item.status === "Completed").length,
    upcoming: bookingItems.filter((item) => ["Pending", "AIRecommended", "AwaitingApproval", "Confirmed", "Rescheduled"].includes(item.status) && dateValue(item.bookingDate) >= localToday()).length,
  };
  const cover = profile?.coverPhotoUrl?.trim();
  const showCover = Boolean(cover && cover !== failedCoverUrl);
  const metrics = [
    ["portfolio", "violet", "Portfolio Items", portfolioLoading, portfolioError, portfolioItems.length, "Photos in your showcase"],
    ["services", "blue", "Services", servicesLoading, servicesError, serviceItems.length, "Packages offered"],
    ["calendar", "green", "Availability", availabilityLoading, availabilityError, availabilityItems.length, "Schedule records"],
    ["profile", "amber", "Profile Completion", profileLoading, profileError, `${profileCompletion}%`, "Studio details completed"],
  ];
  const calendarDate = new Date();
  const calendarYear = calendarDate.getFullYear();
  const calendarMonth = calendarDate.getMonth();
  const firstWeekday = new Date(calendarYear, calendarMonth, 1).getDay();
  const daysInMonth = new Date(calendarYear, calendarMonth + 1, 0).getDate();
  const programmeDates = new Set(bookingItems.map((item) => dateValue(item.bookingDate)).filter((date) => date.startsWith(`${calendarYear}-${String(calendarMonth + 1).padStart(2, "0")}-`)));
  const calendarDays = Array.from({ length: firstWeekday + daysInMonth }, (_, index) => index < firstWeekday ? null : index - firstWeekday + 1);
  const upcomingProgrammes = bookingItems
    .filter((item) => /^\d{4}-\d{2}-\d{2}$/.test(dateValue(item.bookingDate)) && dateValue(item.bookingDate) >= localToday())
    .sort((a, b) => dateValue(a.bookingDate).localeCompare(dateValue(b.bookingDate)))
    .slice(0, 3);

  return <>
    <StudioPhotographyHero profile={profile} profileLoading={profileLoading} profileError={profileError} portfolio={portfolio} portfolioLoading={portfolioLoading} portfolioError={portfolioError} />
    <section className="dashboard-metrics" aria-label="Studio statistics">{metrics.map(([icon, tone, label, loading, error, value, detail]) => <Card className="metric-card" key={label}><span className={`metric-icon metric-${tone}`}><StudioIcon name={icon} /></span><div><p>{label}</p><h3><LoadValue loading={loading} error={error}>{value}</LoadValue></h3><small>{error || detail}</small></div></Card>)}</section>
    <section className="booking-dashboard-panel"><div><p className="studio-kicker">BOOKINGS</p><h3>Booking overview</h3><p>Live booking counts from the booking management API.</p></div><button type="button" className="dashboard-primary-button" onClick={() => go("/studio/bookings")}>Manage bookings</button><div className="booking-dashboard-counts">{[["Pending", bookingCounts.pending], ["Confirmed", bookingCounts.confirmed], ["Upcoming", bookingCounts.upcoming], ["Completed", bookingCounts.completed]].map(([label, value]) => <div key={label}><span>{label}</span><strong><LoadValue loading={bookingsLoading} error={bookingsError}>{value}</LoadValue></strong></div>)}</div>{bookingsError && <p className="booking-dashboard-error">{bookingsError}</p>}</section>
    <section className="dashboard-two-column dashboard-primary-row">
      <Card className="dashboard-panel studio-summary-card"><div className={`studio-summary-cover${showCover ? " has-image" : ""}`}>{showCover && <img src={cover} alt={`${studioName} cover`} onError={() => setFailedCoverUrl(cover)} />}<button className="studio-cover-action" type="button" onClick={() => go("/studio/profile")}><StudioIcon name="portfolio" />{showCover ? "Change Cover Photo" : "Add Cover Photo"}</button></div><div className="studio-summary-content"><ImageAvatar profile={profile} failedLogoUrl={failedLogoUrl} onLogoError={onLogoError} /><button className="dashboard-secondary-button" type="button" onClick={() => go("/studio/profile")}>Edit Profile</button><div className="studio-summary-copy">{profileLoading ? <p>Loading studio profile…</p> : profileError ? <p className="dashboard-error">{profileError}</p> : <><h3>{profile?.studioName?.trim() || "Studio profile not set up"}</h3><p className="studio-summary-location">{profile?.location?.trim() || "Location not provided"}</p>{profile?.description?.trim() && <p className="studio-summary-description">{profile.description.trim()}</p>}<p className="studio-summary-types">{profile?.photographyTypes?.trim() || "Photography types not provided"}</p></>}</div></div></Card>
      <Card className="dashboard-panel"><div className="dashboard-panel-heading"><div><h3>Upcoming Availability</h3><p>Your next schedule entries</p></div><button type="button" onClick={() => go("/studio/availability")}>Manage Availability</button></div>{availabilityLoading ? <p className="dashboard-empty">Loading availability…</p> : availabilityError ? <p className="dashboard-empty dashboard-error">{availabilityError}</p> : upcoming.length ? <div className="upcoming-list">{upcoming.slice(0, 7).map((item, index) => <div key={item.id ?? `${item.date}-${index}`}><span className={`availability-state ${item.isAvailable ? "available" : "unavailable"}`}><StudioIcon name={item.isAvailable ? "check" : "x"} /></span><span><strong>{formatDate(item.date)}</strong><small>{formatTime(item.startTime)} – {formatTime(item.endTime)}</small></span><em className={item.isAvailable ? "available" : "unavailable"}>{item.isAvailable ? "Available" : "Unavailable"}</em></div>)}</div> : <p className="dashboard-empty">No upcoming availability records.</p>}</Card>
    </section>
    <section className="dashboard-two-column">
      <Card className="dashboard-panel"><div className="dashboard-panel-heading portfolio-heading"><div><h3>Recent Portfolio</h3><p>Your latest published work</p></div><div><button type="button" onClick={() => go("/studio/portfolio")}>View All</button><button className="dashboard-primary-button" type="button" onClick={() => go("/studio/portfolio")}>+ Add Project</button></div></div>{portfolioLoading ? <p className="dashboard-empty">Loading portfolio…</p> : portfolioError ? <p className="dashboard-empty dashboard-error">{portfolioError}</p> : recentPortfolio.length ? <div className="recent-portfolio-grid">{recentPortfolio.map((item, index) => { const cover = item.images?.[0]?.imageUrl || item.imageUrl; return <button type="button" key={item.id ?? index} onClick={() => go("/studio/portfolio")}><span>{cover ? <img src={resolvePortfolioImageUrl(cover)} alt="" /> : <StudioIcon name="portfolio" />}</span><strong>{item.title || "Untitled"}</strong><small>{item.category || "Uncategorized"}</small></button>; })}</div> : <p className="dashboard-empty">No portfolio items yet.</p>}</Card>
      <Card className="dashboard-panel programmes-calendar-panel">
        <div className="dashboard-panel-heading"><div><h3>Upcoming Studio Programmes</h3><p>Your confirmed and pending sessions</p></div><button type="button" onClick={() => go("/studio/bookings")}>View Bookings</button></div>
        <div className="programmes-calendar">
          <div className="programmes-calendar-title"><strong>{monthFormatter.format(calendarDate)}</strong><span><i /> Programme scheduled</span></div>
          <div className="calendar-weekdays">{["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].map((day) => <span key={day}>{day}</span>)}</div>
          <div className="calendar-grid" aria-label={`${monthFormatter.format(calendarDate)} programme calendar`}>{calendarDays.map((day, index) => day ? <span className={`${day === calendarDate.getDate() ? "today " : ""}${programmeDates.has(`${calendarYear}-${String(calendarMonth + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`) ? "has-programme" : ""}`} key={day}>{day}</span> : <span className="calendar-empty" key={`empty-${index}`} />)}</div>
        </div>
        <div className="programme-list">{upcomingProgrammes.length ? upcomingProgrammes.map((item, index) => <div key={item.id ?? `${item.bookingDate}-${index}`}><span className="programme-date"><strong>{new Date(`${dateValue(item.bookingDate)}T00:00:00Z`).getUTCDate()}</strong><small>{new Intl.DateTimeFormat("en-LK", { month: "short", timeZone: "UTC" }).format(new Date(`${dateValue(item.bookingDate)}T00:00:00Z`))}</small></span><span><strong>{item.packageName || item.serviceName || item.title || "Studio programme"}</strong><small>{formatTime(item.startTime) === "Not set" ? "Scheduled session" : formatTime(item.startTime)}</small></span><em className={item.status === "Confirmed" ? "confirmed" : "pending"}>{item.status === "Confirmed" ? "Confirmed" : "Pending"}</em></div>) : <p className="dashboard-empty">No upcoming studio programmes.</p>}</div>
      </Card>
    </section>
  </>;
}
