const API_URL = (import.meta.env.VITE_API_URL || "").replace(/\/$/, "");

async function request(token, options = {}, allowNotFound = false) {
  let response;
  try { response = await fetch(`${API_URL}/api/studio/profile`, { ...options, headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", ...options.headers } }); }
  catch { throw new Error("Unable to connect to the server. Please try again."); }
  if (response.status === 204) return null;
  const data = await response.json().catch(() => null);
  if (response.status === 404 && allowNotFound) return null;
  if (!response.ok) {
    if (response.status === 401) throw new Error("Your session has expired. Please sign in again.");
    if (response.status === 403) throw new Error("Only a Studio account can manage a studio profile.");
    const validationMessage = data?.errors ? Object.values(data.errors).flat().join(" ") : "";
    throw new Error(validationMessage || data?.message || data?.title || "Unable to save the studio profile.");
  }
  return data;
}

export const getStudioProfile = (token) => request(token, {}, true);
export const saveStudioProfile = (token, profile) => request(token, { method: "PUT", body: JSON.stringify(profile) });
export const deleteStudioProfile = (token) => request(token, { method: "DELETE" });
