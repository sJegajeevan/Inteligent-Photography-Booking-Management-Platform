import { useCallback, useEffect, useRef, useState } from "react";
import { getBookingConversations, getBookingMessages, sendBookingMessage } from "../../services/bookingService";
import "./StudioMessages.css";

const sentTime = (value) => value ? new Date(value).toLocaleString() : "";

function Conversation({ token, booking, onSent }) {
  const [messages, setMessages] = useState([]);
  const [draft, setDraft] = useState("");
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState("");
  const busy = useRef(false);
  const alive = useRef(false);
  const loadVersion = useRef(0);
  const end = useRef(null);
  const load = useCallback(async () => {
    const version = ++loadVersion.current;
    setLoading(true);
    setError("");
    try {
      const result = await getBookingMessages(token, booking.bookingId);
      if (alive.current && version === loadVersion.current) setMessages(result);
    } catch (e) {
      if (alive.current && version === loadVersion.current) setError(e.message);
    } finally {
      if (alive.current && version === loadVersion.current) setLoading(false);
    }
  }, [token, booking.bookingId]);
  useEffect(() => {
    alive.current = true;
    const pendingLoads = loadVersion;
    const timer = setTimeout(load, 0);
    return () => { alive.current = false; ++pendingLoads.current; clearTimeout(timer); };
  }, [load]);
  useEffect(() => { end.current?.scrollIntoView({ block: "nearest" }); }, [messages]);

  async function send(event) {
    event.preventDefault();
    if (busy.current || !draft.trim() || draft.length > 1000) return;
    busy.current = true;
    setSending(true);
    setError("");
    try {
      const created = await sendBookingMessage(token, booking.bookingId, draft);
      if (!alive.current) return;
      setDraft("");
      setMessages((items) => [...items, created]);
      await load();
      onSent();
    } catch (e) {
      if (alive.current) setError(`${e.message} Refresh the conversation before retrying if delivery is uncertain.`);
    } finally {
      busy.current = false;
      if (alive.current) setSending(false);
    }
  }

  return <section className="booking-conversation" aria-label="Booking conversation">
    <header><div><h2>{booking.customerName || "Customer"}</h2><p>{booking.packageName || "Photography session"} · {booking.bookingDate}</p></div>
      <button type="button" onClick={load} disabled={loading || sending}>Refresh</button></header>
    {error && <div role="alert" className="message-error">{error} <button onClick={load} disabled={loading || sending}>Retry refresh</button></div>}
    <div className="booking-message-list" role="log" aria-label="Messages" aria-busy={loading}>
      {loading && <p role="status">Loading conversation…</p>}
      {!loading && !error && !messages.length && <p>No messages yet. Start a conversation about this booking.</p>}
      {messages.map((message) => <article key={message.id} className={`booking-message ${message.senderRole === "Studio" ? "own" : ""}`}>
        <strong>{message.senderName || message.senderRole} · {message.senderRole}</strong>
        <p>{message.message}</p><time dateTime={message.sentAt}>{sentTime(message.sentAt)}</time>
      </article>)}<div ref={end} />
    </div>
    <form onSubmit={send} className="booking-message-compose">
      <label htmlFor="booking-message">Message</label>
      <textarea id="booking-message" value={draft} onChange={(event) => setDraft(event.target.value)} maxLength={1000} rows={3} disabled={sending} placeholder="Discuss this booking…" />
      <div><small>{draft.length}/1000</small><button className="dashboard-primary-button" disabled={sending || loading || !draft.trim() || draft.length > 1000}>{sending ? "Sending…" : "Send"}</button></div>
    </form>
  </section>;
}

export default function StudioMessages({ token }) {
  const [items, setItems] = useState([]);
  const [selected, setSelected] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const alive = useRef(false);
  const version = useRef(0);
  const load = useCallback(async () => {
    const current = ++version.current;
    setLoading(true); setError("");
    try {
      const result = await getBookingConversations(token);
      if (!alive.current || current !== version.current) return;
      setItems(result);
      setSelected((id) => result.some((item) => item.bookingId === id) ? id : result[0]?.bookingId ?? null);
    } catch (e) { if (alive.current && current === version.current) setError(e.message); }
    finally { if (alive.current && current === version.current) setLoading(false); }
  }, [token]);
  useEffect(() => {
    alive.current = true;
    const pendingLoads = version;
    const timer = setTimeout(load, 0);
    return () => { alive.current = false; ++pendingLoads.current; clearTimeout(timer); };
  }, [load]);
  const booking = items.find((item) => item.bookingId === selected);
  return <>
    <section className="studio-route-heading"><h1>Booking messages</h1><p>Keep each conversation connected to its photography session.</p></section>
    <div className="studio-messages">
      <aside aria-label="Booking conversations"><header><h2>Conversations</h2><button onClick={load} disabled={loading}>Refresh</button></header>
        {loading && <p role="status">Loading conversations…</p>}
        {error && <p role="alert">{error} <button onClick={load}>Retry</button></p>}
        {!loading && !error && !items.length && <p>No bookings yet. Customer conversations will appear here.</p>}
        {items.map((item) => <button className={`booking-conversation-choice ${item.bookingId === selected ? "selected" : ""}`} key={item.bookingId} onClick={() => setSelected(item.bookingId)} aria-pressed={item.bookingId === selected}>
          <strong>{item.customerName || "Customer"}</strong><span>{item.packageName || "Photography session"} · {item.bookingDate}</span>
          <span className="message-preview">{item.latestMessage || "Start a conversation"}</span><small>{sentTime(item.latestMessageTime)}</small>
        </button>)}
      </aside>
      {booking ? <Conversation key={booking.bookingId} token={token} booking={booking} onSent={load} /> : <section className="booking-conversation"><p>Select a booking to view its conversation.</p></section>}
    </div>
  </>;
}
