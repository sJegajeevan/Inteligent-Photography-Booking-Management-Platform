import { workflowLabels, revalidationMessage } from "../../services/aiWorkflowService";

const money = value => new Intl.NumberFormat("en-LK", { style: "currency", currency: "LKR" }).format(value);

export default function AiWorkflowView({ workflow, studioName, busy = false, reason = "", onReason, onApprove, onReject }) {
  const p = workflow.proposal;
  return <article className="ai-workflow-card">
    <header><h2>{p?.packageName || "Recommendation in progress"}</h2><span className="ai-workflow-status">{workflowLabels[workflow.status]}</span></header>
    <p>Proposal version {workflow.proposalVersion} · Expires {new Date(workflow.expiresAt).toLocaleString("en-LK", { timeZone: "Asia/Colombo" })} (Sri Lanka)</p>
    {workflow.status === "RevalidationRequired" && <p role="status">{revalidationMessage}</p>}
    {workflow.status === "Approved" && <p role="status">Recommendation approved. Check My Bookings for the booking.</p>}
    {workflow.status === "Rejected" && <p role="status">This recommendation was rejected.</p>}
    <section aria-label="AI Recommendation Summary">
      <h3>AI Recommendation Summary</h3>
      <p>Customer Requirements → Selected Studio → Selected Package → Selected Schedule → {p?.validationOutcome === 'Pass' ? 'Validation Passed' : 'Validation'}</p>
      <ol className="ai-agent-summary">
        {[
          ['Studio Match', p ? studioName || 'Your selected studio' : 'Studio result not available.'],
          ['Package Recommendation', p ? `${p.packageName} · Authoritative price: ${money(p.price)}${p.addons.length ? ` · Add-ons: ${p.addons.join(', ')}` : ''}` : 'Package result not available.'],
          ['Schedule', p ? `${p.date} · ${p.startTime}–${p.endTime} (Sri Lanka). Availability is checked again on approval.` : 'Schedule result not available.'],
          ['Validation', p?.validationOutcome === 'Pass' ? 'Proposal validation passed at recommendation time. This is not a reservation.' : p?.validationOutcome === 'Fail' ? 'Proposal validation failed.' : p?.validationOutcome === 'NeedsInput' ? 'Validation needs more information.' : 'Validation result not available.'],
        ].map(([title, detail]) => <li key={title}>
          <h4><span aria-hidden="true">{p ? '✓' : '○'}</span> {title}</h4>
          <span className="ai-agent-state">{p ? 'Completed' : 'Not confirmed'}</span>
          <p>{detail}</p>
        </li>)}
      </ol>
      <p className="ai-workflow-status">Overall status: {workflow.status === 'AwaitingApproval' ? 'Awaiting Studio Approval' : workflowLabels[workflow.status]}</p>
    </section>
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
      <p>Approval creates a booking after availability and pricing are checked again.</p>
      <button type="button" disabled={busy} onClick={onApprove}>Approve</button>
      <label>Rejection reason (up to 1,000 characters)<textarea value={reason} maxLength={1000} disabled={busy} onChange={e => onReason(e.target.value)} /></label>
      <button type="button" disabled={busy || !reason.trim() || reason.length > 1000} onClick={onReject}>Reject</button>
      {busy && <p role="status">Saving review…</p>}
    </section>}
  </article>;
}
