const API_URL = (import.meta.env?.VITE_API_URL || "").replace(/\/$/, "");

async function request(token, path = "", method = "GET") {
  let response;
  try {
    response = await fetch(`${API_URL}/api/studio/notifications${path}`, {
      method, headers: { Authorization: `Bearer ${token}` },
    });
  } catch {
    throw new Error("Unable to connect to the notification server. Please try again.");
  }
  const data = await response.json().catch(() => null);
  if (!response.ok) {
    if (response.status === 401) throw new Error("Your session has expired. Please sign in again.");
    if (response.status === 403) throw new Error("You do not have permission to view studio notifications.");
    throw new Error(data?.message || "Unable to load notifications. Please try again.");
  }
  return data;
}

export const getStudioNotifications = (token) => request(token);
export const getStudioUnreadCount = (token) => request(token, "/unread-count");
export const markStudioNotificationRead = (token, id) => request(token, `/${id}/read`, "PATCH");
