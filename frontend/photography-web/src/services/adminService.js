const API_URL = (import.meta.env?.VITE_API_URL || "").replace(/\/$/, "");

async function request(token, path, signal) {
  if (!token) throw new Error("Please sign in with your Admin account.");
  let response;
  try {
    response = await fetch(`${API_URL}${path}`, { method: "GET", signal, headers: { Authorization: `Bearer ${token}`, Accept: "application/json" } });
  } catch (error) {
    if (error.name === "AbortError") throw error;
    // Raw transport errors can contain infrastructure details.
    // eslint-disable-next-line preserve-caught-error
    throw new Error("Unable to connect to the Admin API.");
  }
  if (!response.ok) throw new Error(({ 400: "Check the selected filters and page size.", 401: "Your session has expired. Please sign in again.", 403: "Admin access is required.", 404: "The requested record was not found." })[response.status] || "Unable to load Admin data. Please retry.");
  try { return await response.json(); } catch { throw new Error("Unable to read Admin data. Please retry."); }
}

const query = (params) => {
  const value = new URLSearchParams(Object.entries(params || {}).filter(([, item]) => item !== undefined && item !== null && item !== ""));
  return value.toString() ? `?${value}` : "";
};
const collection = async (token, path, params, signal) => {
  const data = await request(token, `/api/admin/${path}${query(params)}`, signal);
  if (!Array.isArray(data?.items) || !Number.isInteger(data.totalCount) || !Number.isInteger(data.totalPages)) throw new Error("Unable to read Admin results. Please retry.");
  return data;
};
export const getAdminDashboard = (token, signal) => request(token, "/api/admin/dashboard", signal);
export const getAdminStudios = (token, params, signal) => collection(token, "studios", typeof params === "string" ? { search: params } : params, signal);
export const getAdminStudio = (token, id, signal) => request(token, `/api/admin/studios/${encodeURIComponent(id)}`, signal);
export const getAdminCustomers = (token, params, signal) => collection(token, "customers", typeof params === "string" ? { search: params } : params, signal);
export const getAdminCustomer = (token, id, signal) => request(token, `/api/admin/customers/${encodeURIComponent(id)}`, signal);
export const getAdminBookings = (token, params, signal) => collection(token, "bookings", params, signal);
export const getAdminBooking = (token, id, signal) => request(token, `/api/admin/bookings/${encodeURIComponent(id)}`, signal);
export const getAdminReviews = (token, params, signal) => collection(token, "reviews", params, signal);
export const getAdminReports = (token, signal) => request(token, "/api/admin/reports", signal);
export const getAdminWorkflows = (token, params, signal) => request(token, `/api/ai-workflows${query(params)}`, signal);
export const getAdminWorkflow = (token, id, signal) => request(token, `/api/ai-workflows/${encodeURIComponent(id)}`, signal);
