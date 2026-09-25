const API_URL = (import.meta.env.VITE_API_URL || "").replace(/\/$/, "");

async function requestCustomers(token, path, signal) {
  if (!token) throw new Error("Please sign in to view your studio customers.");
  let response;
  try {
    response = await fetch(`${API_URL}/api/studio/customers${path}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
      signal,
    });
  } catch (error) {
    if (error.name === "AbortError") throw error;
    throw new Error("Unable to connect to the customer server. Please try again.");
  }
  const data = await response.json().catch(() => null);
  if (!response.ok) {
    if (response.status === 404) {
      const error = new Error("Customer was not found.");
      error.status = 404;
      throw error;
    }
    if (response.status === 401) throw new Error("Your session has expired. Please sign in again.");
    if (response.status === 403) throw new Error("You do not have permission to view studio customers.");
    throw new Error(response.status >= 500
      ? "The customer server is unavailable. Please try again later."
      : data?.message || "Unable to load customers. Please try again.");
  }
  return data;
}

export async function getStudioCustomers(token, signal) {
  const data = await requestCustomers(token, "", signal);
  if (!Array.isArray(data) || data.some((customer) =>
    !customer || !Number.isInteger(customer.customerId) || customer.customerId < 1 ||
    typeof customer.name !== "string" || typeof customer.email !== "string" ||
    !Number.isInteger(customer.totalBookings) || customer.totalBookings < 1 ||
    typeof customer.latestBookingStatus !== "string" || !customer.latestBookingStatus.trim() ||
    typeof customer.latestBookingDate !== "string" ||
    !/^\d{4}-\d{2}-\d{2}$/.test(customer.latestBookingDate) ||
    !Number.isFinite(Date.parse(`${customer.latestBookingDate}T00:00:00Z`))
  )) throw new Error("The server returned invalid customer data. Please try again.");
  return data;
}

export async function getStudioCustomer(token, customerId, signal) {
  const id = Number(customerId);
  if (!Number.isSafeInteger(id) || id < 1 || id > 2147483647) {
    const error = new Error("Customer was not found.");
    error.status = 404;
    throw error;
  }
  const data = await requestCustomers(token, `/${id}`, signal);
  if (!data || data.customerId !== id || typeof data.name !== "string" || typeof data.email !== "string" ||
      ![data.totalBookings, data.completedBookings, data.activeBookings].every((value) => Number.isInteger(value) && value >= 0) ||
      !Array.isArray(data.bookings) || data.bookings.some((booking) =>
        !booking || !Number.isInteger(booking.bookingId) || typeof booking.packageName !== "string" ||
        typeof booking.status !== "string" || typeof booking.totalPrice !== "number" || !Number.isFinite(booking.totalPrice) ||
        typeof booking.bookingDate !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(booking.bookingDate) ||
        !Number.isFinite(Date.parse(`${booking.bookingDate}T00:00:00Z`)) ||
        typeof booking.createdAt !== "string" || !Number.isFinite(Date.parse(booking.createdAt))
      )) throw new Error("The server returned invalid customer details. Please try again.");
  return data;
}
