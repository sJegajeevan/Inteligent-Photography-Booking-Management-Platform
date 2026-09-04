import { useState } from "react";
import { useAuth } from "../../context/useAuth";

const navigation = [
  ["/studio/dashboard", "Dashboard", "dashboard"],
  ["/studio/profile", "Profile", "profile"],
  ["/studio/availability", "Availability", "calendar"],
  ["/studio/portfolio", "Portfolio", "portfolio"],
  ["/studio/services", "Services", "services"],
];

const titles = {
  dashboard: "Dashboard",
  profile: "Studio Profile",
  availability: "Availability",
  portfolio: "Portfolio",
  services: "Services",
};

export function StudioIcon({ name }) {
  const paths = {
    dashboard: <><rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/></>,
    profile: <><circle cx="12" cy="8" r="3.5"/><path d="M5 21a7 7 0 0 1 14 0"/></>,
    calendar: <><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M16 3v4M8 3v4M3 10h18"/></>,
    portfolio: <><rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="2"/><path d="m21 15-5-5L5 20"/></>,
    services: <><path d="M8 7V5.5A1.5 1.5 0 0 1 9.5 4h5A1.5 1.5 0 0 1 16 5.5V7"/><rect x="3" y="7" width="18" height="13" rx="2"/><path d="M3 12h18M10 12v2h4v-2"/></>,
    logout: <><path d="M10 17l5-5-5-5M15 12H3"/><path d="M14 3h5a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-5"/></>,
    bell: <><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9"/><path d="M10 21h4"/></>,
    menu: <path d="M4 7h16M4 12h16M4 17h16"/>,
    close: <path d="m6 6 12 12M18 6 6 18"/>,
    arrow: <path d="m9 18 6-6-6-6"/>,
    check: <path d="m5 12 4 4L19 6"/>,
    x: <path d="m6 6 12 12M18 6 6 18"/>,
  };
  return <svg className="studio-ui-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths[name]}</svg>;
}

function StudioAvatar({ profile }) {
  const [failed, setFailed] = useState(false);
  const name = profile?.studioName?.trim() || "Your Studio";
  const image = profile?.logoUrl?.trim();
  return <span className="studio-layout-avatar">{image && !failed ? <img src={image} alt="" onError={() => setFailed(true)} /> : name.charAt(0).toUpperCase()}</span>;
}

export default function StudioLayout({ page, profile, children }) {
  const { logout } = useAuth();
  const [drawerOpen, setDrawerOpen] = useState(false);
  const currentPath = window.location.pathname.replace(/\/+$/, "");
  const studioName = profile?.studioName?.trim() || "Your Studio";
  const go = (path) => { if (path !== currentPath) window.location.assign(path); };
  const signOut = () => { logout(); window.location.replace("/auth"); };

  return <div className="studio-app-shell">
    <button className={`studio-drawer-shade${drawerOpen ? " open" : ""}`} type="button" aria-label="Close navigation" onClick={() => setDrawerOpen(false)} />
    <aside className={`studio-sidebar${drawerOpen ? " open" : ""}`}>
      <div className="studio-sidebar-brand"><span className="studio-brand-mark">P</span><div><strong>Photography AI</strong><small>Studio Management</small></div><button type="button" onClick={() => setDrawerOpen(false)} aria-label="Close navigation"><StudioIcon name="close" /></button></div>
      <nav aria-label="Studio navigation">{navigation.map(([path, label, icon]) => <button key={path} type="button" className={currentPath === path ? "active" : ""} aria-current={currentPath === path ? "page" : undefined} onClick={() => go(path)}><StudioIcon name={icon} /><span>{label}</span></button>)}</nav>
      <button className="studio-logout" type="button" onClick={signOut}><StudioIcon name="logout" /><span>Logout</span></button>
    </aside>
    <div className="studio-main-shell">
      <header className="studio-top-header"><div className="studio-header-title"><button className="studio-menu-button" type="button" onClick={() => setDrawerOpen(true)} aria-label="Open navigation"><StudioIcon name="menu" /></button><h1>{titles[page]}</h1></div><div className="studio-header-account"><button className="studio-notification-button" type="button" aria-label="Notifications"><StudioIcon name="bell" /></button><StudioAvatar profile={profile} /><span className="studio-account-text"><strong>{studioName}</strong><small>Studio Owner</small></span><span className="studio-account-chevron" aria-hidden="true">⌄</span></div></header>
      <main className={`studio-page studio-route-page studio-${page}-page`}>{children}</main>
    </div>
  </div>;
}
