import { workflowLabels, revalidationMessage } from "../../services/aiWorkflowService";

const money = value => new Intl.NumberFormat("en-LK", { style: "currency", currency: "LKR" }).format(value);

export default function AiWorkflowView({ workflow, studioName, busy = false, reason = "", onReason, onApprove, onReject }) {
  const p = workflow.proposal;
  return <article className="ai-workflow-card">
    <header><h2>{p?.packageName || "Recommendation in progress"}</h2><span className="ai-workflow-status">{workflowLabels[workflow.status]}</span></header>
    <p>Recommendation {workflow.id.slice(0, 8)}</p>
    <p>Proposal version {workflow.proposalVersion} · Expires {new Date(workflow.expiresAt).toLocaleString("en-LK", { timeZone: "Asia/Colombo" })} (Sri Lanka)</p>
    {workflow.status === "RevalidationRequired" && <p role="status">{revalidationMessage}</p>}
    {workflow.status === "Approved" && <p role="status">Recommendation approved. A booking has not been created.</p>}
    {workflow.status === "Rejected" && <p role="status">This recommendation was rejected.</p>}
    {p && <>
      <dl className="ai-workflow-facts">
        <div><dt>Studio</dt><dd>{studioName || "Your selected studio"}</dd></div>
        <div><dt>Package</dt><dd>{p.packageName}</dd></div>
        <div><dt>Date</dt><dd>{p.date}</dd></div>
        <div><dt>Time (Sri Lanka)</dt><dd>{p.startTime}–{p.endTime}</dd></div>
        <div><dt>Authoritative price</dt><dd>{money(p.price)}</dd></div>
        <div><dt>Customization</dt><dd>{p.extraHours} extra hours · {p.additionalPhotographers} additional photographers · Add-ons: {p.addons.join(", ") || "None"}</dd></div>
      </dl>
      <h3>Customer requirements</h3>
      <p>{p.photographyType} in {p.location} · {p.coverageHours} hours · Budget up to {money(p.maximumBudget)}</p>
      <p>Requested dates: {p.earliestDate} to {p.latestDate}</p>
      <p>Requested services: {p.requestedServices.join(", ") || "No specific services"}</p>
    </>}
    {workflow.status === "AwaitingApproval" && onApprove && <section className="ai-workflow-actions" aria-label="Review recommendation">
      <p>Approval confirms this recommendation only. Availability and pricing are checked again when you approve.</p>
      <button type="button" disabled={busy} onClick={onApprove}>Approve</button>
      <label>Rejection reason (up to 1,000 characters)<textarea value={reason} maxLength={1000} disabled={busy} onChange={e => onReason(e.target.value)} /></label>
      <button type="button" disabled={busy || !reason.trim() || reason.length > 1000} onClick={onReject}>Reject</button>
      {busy && <p role="status">Saving review…</p>}
    </section>}
  </article>;
}
