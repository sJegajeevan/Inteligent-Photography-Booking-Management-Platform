const API_URL = (import.meta.env?.VITE_API_URL || "").replace(/\/$/, "");
export const workflowLabels = Object.freeze({ Submitted: "Processing", StudioMatching: "Processing", PackageRecommendation: "Processing", Scheduling: "Processing", Validation: "Processing", AwaitingApproval: "Awaiting Approval", Approved: "Approved", Rejected: "Rejected", RevalidationRequired: "Revalidation Required", Failed: "Failed", NeedsInput: "More information needed", Cancelled: "Cancelled", Expired: "Expired" });
export const revalidationMessage = "The recommendation needs to be refreshed because availability or pricing has changed.";
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const invalid = () => new Error("Unable to read this recommendation. Please refresh and try again.");
const text = (v, max = 500) => typeof v === "string" && v.trim().length > 0 && v.length <= max;

// Project only customer-facing canonical fields. Never retain raw evidence or events in UI state.
export function parseWorkflow(value) {
  if (!value || !uuid.test(value.id) || !Object.hasOwn(workflowLabels, value.status) ||
      !Number.isInteger(value.proposalVersion) || value.proposalVersion < 0 ||
      !Number.isFinite(Date.parse(value.expiresAt))) throw invalid();
  let proposal = null;
  if (value.proposal != null) {
    const p = value.proposal, s = p.selection, r = p.requirements, c = s?.customization;
    if (p.version !== value.proposalVersion || !s || !uuid.test(s.studioId) || !uuid.test(s.packageId) ||
        s.studioId !== value.selectedStudioId || s.packageId !== value.selectedPackageId ||
        !/^\d{4}-\d{2}-\d{2}$/.test(s.date) || !/^\d{2}:\d{2}:\d{2}(\.\d+)?$/.test(s.startTime) ||
        !/^\d{2}:\d{2}:\d{2}(\.\d+)?$/.test(s.endTime) || !text(p.pricing?.packageName, 500) ||
        !Number.isFinite(p.pricing.finalPrice) || p.pricing.finalPrice < 0 || !r || !text(r.photographyType, 100) ||
        !text(r.location) || !Number.isFinite(r.maximumBudget) || !Number.isFinite(r.coverageHours) ||
        !Array.isArray(r.requestedServices) || r.requestedServices.length > 20 || r.requestedServices.some(s => !text(s, 120)) ||
        !c || !Number.isInteger(c.extraHours) || c.extraHours < 0 || !Number.isInteger(c.additionalPhotographers) ||
        c.additionalPhotographers < 0 || !Array.isArray(p.pricing.selectedAddons)) throw invalid();
    proposal = { studioId: s.studioId, packageName: p.pricing.packageName, date: s.date,
      startTime: s.startTime.slice(0, 5), endTime: s.endTime.slice(0, 5), price: p.pricing.finalPrice,
      extraHours: c.extraHours, additionalPhotographers: c.additionalPhotographers,
      addons: p.pricing.selectedAddons.map(a => { if (!text(a.name)) throw invalid(); return a.name; }),
      photographyType: r.photographyType, location: r.location, maximumBudget: r.maximumBudget,
      coverageHours: r.coverageHours, requestedServices: [...r.requestedServices],
      earliestDate: r.earliestDate, latestDate: r.latestDate };
  }
  if (["AwaitingApproval", "Approved", "Rejected"].includes(value.status) && !proposal) throw invalid();
  return { id: value.id, status: value.status, proposalVersion: value.proposalVersion, expiresAt: value.expiresAt, proposal };
}

async function request(token, path, { signal, body } = {}) {
  if (!token) throw new Error("Please sign in with your Studio account.");
  const timeout = new AbortController();
  const timer = setTimeout(() => timeout.abort(), 30000);
  const abort = () => timeout.abort();
  signal?.addEventListener("abort", abort, { once: true });
  if (signal?.aborted) timeout.abort();
  try {
    const response = await fetch(`${API_URL}/api/ai-workflows${path}`, {
      method: body ? "POST" : "GET", signal: timeout.signal,
      headers: { Authorization: `Bearer ${token}`, Accept: "application/json", ...(body ? { "Content-Type": "application/json" } : {}) },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    if (!response.ok) throw new Error(({ 400: "Check the proposal version and rejection reason.",
      401: "Your session has expired. Please sign in again.", 403: "This recommendation is not available to your account.",
      404: "This recommendation was not found or is not available to your account.",
      409: "The recommendation changed, expired, or was already reviewed. Refresh before trying again." })[response.status] ||
      "The recommendation service is unavailable. Refresh to check its status before trying again.");
    try { return await response.json(); } catch { throw invalid(); }
  } catch (error) {
    if (signal?.aborted) throw new DOMException("Request cancelled", "AbortError");
    if (error.name === "AbortError" || error instanceof TypeError)
      // Raw transport errors are deliberately excluded from UI-visible errors.
      // eslint-disable-next-line preserve-caught-error
      throw new Error("The connection was interrupted. Refresh to check the recommendation before trying again.");
    throw error;
  } finally { clearTimeout(timer); signal?.removeEventListener("abort", abort); }
}

export async function listWorkflows(token, { page = 1, status = "AwaitingApproval", signal } = {}) {
  if (!Number.isInteger(page) || page < 1 || page > 10000 || (status && !Object.hasOwn(workflowLabels, status))) throw invalid();
  const query = new URLSearchParams({ page: String(page), pageSize: "20", ...(status ? { status } : {}) });
  const data = await request(token, `?${query}`, { signal });
  if (!Array.isArray(data?.items) || data.items.length > 20 || typeof data.hasMore !== "boolean" || data.page !== page) throw invalid();
  return { items: data.items.map(parseWorkflow), hasMore: data.hasMore };
}
export async function getWorkflow(token, id, signal) {
  if (!uuid.test(id)) throw invalid();
  const workflow = parseWorkflow(await request(token, `/${id}`, { signal }));
  if (workflow.id.toLowerCase() !== id.toLowerCase()) throw invalid();
  return workflow;
}
export async function reviewWorkflow(token, workflow, decision, reason, signal) {
  if (!uuid.test(workflow.id) || workflow.status !== "AwaitingApproval" || !Number.isInteger(workflow.proposalVersion) || workflow.proposalVersion < 1 ||
      !["approve", "reject"].includes(decision)) throw invalid();
  if (decision === "reject" && (!text(reason, 1000))) throw new Error("Enter a rejection reason of 1 to 1,000 characters.");
  const body = { proposalVersion: workflow.proposalVersion, ...(decision === "reject" ? { reason: reason.trim() } : {}) };
  const result = await request(token, `/${workflow.id}/${decision}`, { body, signal });
  if (result?.workflowId !== workflow.id || result.proposalVersion !== workflow.proposalVersion ||
      !(decision === "approve" ? ["Approved", "RevalidationRequired"] : ["Rejected"]).includes(result.status)) throw invalid();
  return result.status;
}
