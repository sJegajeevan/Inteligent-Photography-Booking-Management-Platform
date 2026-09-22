const API_URL = (import.meta.env.VITE_API_URL || "").replace(/\/$/, "");

export const BOOKING_STATUSES = [
  "Pending",
  "AIRecommended",
  "AwaitingApproval",
  "Confirmed",
  "Rejected",
  "Cancelled",
  "Rescheduled",
  "Completed",
];

function getStatusLabel(value) {
  if (typeof value === "number") return BOOKING_STATUSES[value] || "Unknown";
  return BOOKING_STATUSES.includes(value) ? value : "Unknown";
}

function getStatusValue(value) {
  return typeof value === "number" ? value : BOOKING_STATUSES.indexOf(value);
}

function normalizeBooking(booking) {
  return { ...booking, status: getStatusLabel(booking.status) };
}

function normalizeHistoryItem(item) {
  return {
    ...item,
    oldStatus: item.oldStatus === null || item.oldStatus === undefined ? null : getStatusLabel(item.oldStatus),
    newStatus: getStatusLabel(item.newStatus),
  };
}

async function request(token, path = "", options = {}) {
  let response;

  try {
    response = await fetch(`${API_URL}/api/bookings${path}`, {
      ...options,
      headers: {
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        "Content-Type": "application/json",
        ...options.headers,
      },
    });
  } catch {
    throw new Error("Unable to connect to the booking server. Please try again.");
  }

  const data = await response.json().catch(() => null);

  if (!response.ok) {
    if (response.status === 401) throw new Error("Your session has expired. Please sign in again.");
    if (response.status === 403) throw new Error("You do not have permission to manage these bookings.");
    if (response.status === 404) throw new Error(data?.message || "Booking not found.");
    const validationMessage = data?.errors ? Object.values(data.errors).flat().join(" ") : "";
    throw new Error(validationMessage || data?.message || data?.title || "Unable to process the booking request.");
  }

  return data;
}

export async function getBookings(token) {
  const bookings = await request(token);
  return Array.isArray(bookings) ? bookings.map(normalizeBooking) : [];
}

export async function getBooking(token, id) {
  return normalizeBooking(await request(token, `/${id}`));
}

export async function getBookingHistory(token, id) {
  const history = await request(token, `/${id}/history`);
  return Array.isArray(history) ? history.map(normalizeHistoryItem) : [];
}

export async function updateBookingStatus(token, id, newStatus, changedBy, reason) {
  const statusValue = getStatusValue(newStatus);
  if (statusValue < 0) throw new Error("Unsupported booking status.");

  return normalizeBooking(await request(token, `/${id}/status`, {
    method: "PATCH",
    body: JSON.stringify({ newStatus: statusValue, changedBy, reason: reason || null }),
  }));
}

export async function cancelBooking(token, id, changedBy, reason) {
  return normalizeBooking(await request(token, `/${id}/cancel`, {
    method: "POST",
    body: JSON.stringify({ changedBy, reason: reason || null }),
  }));
}
