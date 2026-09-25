const API_URL = (import.meta.env.VITE_API_URL || "").replace(/\/$/, "");

async function request(token, path) {
  let response;
  try {
    response = await fetch(`${API_URL}/api/admin${path}`, { headers: { Authorization: `Bearer ${token}`, Accept: "application/json" } });
  } catch {
    throw new Error("Unable to connect to the Admin API.");
  }
  const data = await response.json().catch(() => null);
  if (!response.ok) throw new Error(data?.message || data?.title || (response.status === 403 ? "Admin access is required." : "Unable to load Admin data."));
  return data;
}

const query = (params) => {
  const value = new URLSearchParams(Object.entries(params || {}).filter(([, item]) => item !== undefined && item !== ""));
  return value.toString() ? `?${value}` : "";
};

export const getAdminDashboard = (token) => request(token, "/dashboard");
export const getAdminStudios = (token, search) => request(token, `/studios${query({ search })}`);
export const getAdminStudio = (token, id) => request(token, `/studios/${encodeURIComponent(id)}`);
export const getAdminCustomers = (token, search) => request(token, `/customers${query({ search })}`);
export const getAdminCustomer = (token, id) => request(token, `/customers/${encodeURIComponent(id)}`);
export const getAdminBookings = (token, params) => request(token, `/bookings${query(params)}`);
export const getAdminBooking = (token, id) => request(token, `/bookings/${encodeURIComponent(id)}`);
export const getAdminReviews = (token, params) => request(token, `/reviews${query(params)}`);
export const getAdminReports = (token) => request(token, "/reports");
