import { useEffect, useRef, useState } from "react";
import { useAuth } from "../../context/useAuth";
import { getWorkflow, listWorkflows, reviewWorkflow, revalidationMessage } from "../../services/aiWorkflowService";
import AiWorkflowView from "./AiWorkflowView";
import "./StudioAiWorkflows.css";

export default function StudioAiWorkflows({ workflowId, studioName }) {
  const { token } = useAuth();
  const [page, setPage] = useState(1);
  const [status, setStatus] = useState("AwaitingApproval");
  const [attempt, setAttempt] = useState(0);
  const [state, setState] = useState({ loading: true, error: "", items: [], workflow: null, hasMore: false });
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const pending = useRef(false);
  const controller = useRef(null);
  useEffect(() => {
    const abort = new AbortController();
    controller.current = abort;
    const load = workflowId ? getWorkflow(token, workflowId, abort.signal) : listWorkflows(token, { page, status, signal: abort.signal });
    load.then(result => { if (!abort.signal.aborted) setState({ loading: false, error: "", items: result.items || [], hasMore: result.hasMore || false, workflow: workflowId ? result : null }); })
      .catch(error => { if (!abort.signal.aborted) setState({ loading: false, error: error.message, items: [], workflow: null, hasMore: false }); });
    return () => { abort.abort(); controller.current?.abort(); };
  }, [token, workflowId, page, status, attempt]);
  const refresh = () => { if (pending.current) return; setState(s => ({ ...s, loading: true, workflow: null, error: "" })); setAttempt(n => n + 1); };
  const decide = async decision => {
    if (pending.current || !state.workflow || state.workflow.status !== "AwaitingApproval") return;
    pending.current = true; setBusy(true); setMessage("");
    const abort = new AbortController(); controller.current = abort;
    try {
      const result = await reviewWorkflow(token, state.workflow, decision, reason, abort.signal);
      if (!abort.signal.aborted) setMessage(result === "RevalidationRequired" ? revalidationMessage : result === "Approved" ? "Recommendation approved. No booking was created." : "Recommendation rejected.");
      const updated = await getWorkflow(token, workflowId, abort.signal);
      if (!abort.signal.aborted) { setState(s => ({ ...s, workflow: updated, error: "" })); setReason(""); }
    } catch (error) {
      // Never allow another decision on a stale snapshot after an uncertain outcome.
      if (!abort.signal.aborted) setState(s => ({ ...s, workflow: null, error: error.message }));
    } finally { pending.current = false; if (!abort.signal.aborted) setBusy(false); }
  };
  return <div className="ai-workflows">
    <section className="studio-route-heading"><p className="studio-kicker">AI RECOMMENDATIONS</p><h1>{workflowId ? "Review recommendation" : "Recommendation review queue"}</h1><p>Review the customer's proposed session. Approval does not create a booking.</p></section>
    <div className="ai-workflow-toolbar">
      {workflowId ? <a href="/studio/ai-workflows">Back to review queue</a> : <label>Status <select value={status} disabled={busy || state.loading} onChange={e => { setStatus(e.target.value); setPage(1); setState(s => ({ ...s, loading: true })); }}>
        <option value="AwaitingApproval">Awaiting Approval</option><option value="Approved">Approved</option><option value="Rejected">Rejected</option><option value="RevalidationRequired">Revalidation Required</option><option value="">All statuses</option>
      </select></label>}
      <button type="button" disabled={busy || state.loading} onClick={refresh}>Refresh</button>
    </div>
    {message && <p role="status">{message}</p>}
    {state.loading ? <p role="status">Loading recommendations…</p> : state.error ? <p role="alert">{state.error}</p> : workflowId ?
      state.workflow && <AiWorkflowView workflow={state.workflow} studioName={studioName} busy={busy} reason={reason} onReason={setReason} onApprove={() => decide("approve")} onReject={() => decide("reject")} /> : <>
        {!state.items.length && <p>No recommendations in this queue.</p>}
        {state.items.map(workflow => <div key={workflow.id}><AiWorkflowView workflow={workflow} studioName={studioName} /><a className="ai-workflow-open" href={`/studio/ai-workflows/${workflow.id}`}>Review recommendation</a></div>)}
        <nav className="ai-workflow-toolbar" aria-label="Recommendation pages"><button disabled={page === 1} onClick={() => { setState(s => ({ ...s, loading: true })); setPage(n => n - 1); }}>Previous</button><span>Page {page}</span><button disabled={!state.hasMore || page >= 10000} onClick={() => { setState(s => ({ ...s, loading: true })); setPage(n => n + 1); }}>Next</button></nav>
      </>}
  </div>;
}
