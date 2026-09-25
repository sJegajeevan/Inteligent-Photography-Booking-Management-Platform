import { useState } from "react";
import { useAuth } from "../../context/useAuth";
import "./admin.css";

const navigation = [
  ["/admin/dashboard", "Dashboard", "▦"],
  ["/admin/studios", "Studios", "▤"],
  ["/admin/customers", "Customers", "◎"],
  ["/admin/bookings", "Bookings", "□"],
  ["/admin/reviews", "Reviews", "★"],
  ["/admin/reports", "Reports", "◒"],
];

const titles = { dashboard: "Platform overview", studios: "Studio management", customers: "Customer management", bookings: "Booking monitoring", reviews: "Review management", reports: "Platform reports", profile: "Admin profile" };

export default function AdminLayout({ page, children }) {
  const { user, logout } = useAuth();
  const [open, setOpen] = useState(false);
  const currentPath = window.location.pathname.replace(/\/+$/, "") || "/admin/dashboard";
  const go = (path) => { setOpen(false); if (path !== currentPath) window.location.assign(path); };
  const signOut = () => { logout(); window.location.replace("/auth"); };
  const name = user?.fullName?.trim() || user?.email || "Administrator";
  return <div className="admin-shell">
    <button className={`admin-shade${open ? " is-open" : ""}`} type="button" aria-label="Close navigation" onClick={() => setOpen(false)} />
    <aside className={`admin-sidebar${open ? " is-open" : ""}`}>
      <div className="admin-brand"><span className="admin-brand-mark">S</span><div><strong>SnapSync AI</strong><small>ADMIN PORTAL</small></div><button type="button" className="admin-close" onClick={() => setOpen(false)} aria-label="Close navigation">×</button></div>
      <nav className="admin-nav" aria-label="Admin navigation">{navigation.map(([path, label, icon]) => <button key={path} type="button" className={currentPath === path || currentPath.startsWith(`${path}/`) ? "is-active" : ""} onClick={() => go(path)}><span className="admin-nav-icon">{icon}</span>{label}</button>)}</nav>
      <div className="admin-sidebar-bottom"><button type="button" onClick={() => go("/admin/profile")} className={currentPath === "/admin/profile" ? "is-active" : ""}><span className="admin-nav-icon">◉</span>Profile</button><button type="button" onClick={signOut}><span className="admin-nav-icon">↪</span>Logout</button></div>
    </aside>
    <div className="admin-main">
      <header className="admin-header"><button type="button" className="admin-menu" onClick={() => setOpen(true)} aria-label="Open navigation">☰</button><div><span className="admin-kicker">ADMIN WORKSPACE</span><h1>{titles[page] || "Admin"}</h1></div><button type="button" className="admin-account" onClick={() => go("/admin/profile")}><span className="admin-avatar">{name.charAt(0).toUpperCase()}</span><span><strong>{name}</strong><small>Administrator</small></span></button></header>
      <main className="admin-content">{children}</main>
    </div>
  </div>;
}
