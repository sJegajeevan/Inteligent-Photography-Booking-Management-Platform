import { useEffect, useState } from "react";
import { getStudioNotifications, markStudioNotificationRead } from "../../services/studioNotificationsService";
import "./StudioNotifications.css";

export default function StudioNotifications({ token }) {
  const [items, setItems] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [refresh, setRefresh] = useState(0);
  const [reading, setReading] = useState(null);

  useEffect(() => {
    let active = true;
    let busy = false;
    async function load() {
      if (busy) return;
      busy = true;
      try {
        const result = await getStudioNotifications(token);
        if (active) { setItems(result); setError(""); }
      } catch (e) { if (active) setError(e.message); }
      finally { busy = false; if (active) setLoading(false); }
    }
    const initial = setTimeout(load, 0);
    const timer = setInterval(load, 30000);
    return () => { active = false; clearTimeout(initial); clearInterval(timer); };
  }, [token, refresh]);

  async function markRead(id) {
    setReading(id);
    try {
      await markStudioNotificationRead(token, id);
      setItems((rows) => rows.map((row) => row.id === id ? { ...row, isRead: true } : row));
      setRefresh((value) => value + 1);
      window.dispatchEvent(new Event("studio-notifications-read"));
      setError("");
    } catch (e) { setError(e.message); }
    finally { setReading(null); }
  }

  return <>
    <section className="studio-route-heading"><h1>Notifications</h1><p>Customer messages and new bookings. Updates every 30 seconds.</p></section>
    <section className="dashboard-panel studio-notifications" aria-label="Studio notifications">
      <div className="dashboard-panel-heading"><h2>Recent notifications</h2><button type="button" className="dashboard-primary-button" onClick={() => setRefresh((value) => value + 1)} disabled={loading}>Refresh</button></div>
      {error && <p role="alert">{error}</p>}
      {loading && <p role="status">Loading notifications...</p>}
      {!loading && !error && !items.length && <p>No notifications yet.</p>}
      {items.map((item) => <article key={item.id} className={`studio-notification-item ${item.isRead ? "read" : "unread"}`}>
        <div><strong>{item.customerName || "Customer"}</strong><span className="studio-notification-type">{item.type}</span><span>{item.isRead ? "Read" : "Unread"}</span></div>
        <h3>{item.title}</h3><p>{item.message}</p>
        <time dateTime={item.createdAt}>{new Date(item.createdAt).toLocaleString()}</time>
        <div className="studio-notification-actions">
          {item.bookingId && <a href={`/studio/bookings/${item.bookingId}`}>View booking</a>}
          {!item.isRead && <button type="button" className="dashboard-primary-button" onClick={() => markRead(item.id)} disabled={reading !== null}>{reading === item.id ? "Saving..." : "Mark as read"}</button>}
        </div>
      </article>)}
    </section>
  </>;
}
