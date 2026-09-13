const API_URL = (import.meta.env.VITE_API_URL || "").replace(/\/$/, "");

async function request(token, path = "", options = {}) {
  let response;
  try {
    response = await fetch(`${API_URL}/api/studio/services${path}`, {
      ...options,
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", ...options.headers },
    });
  } catch {
    throw new Error("Unable to connect to the server. Please try again.");
  }
  if (response.status === 204) return null;
  const data = await response.json().catch(() => null);
  if (!response.ok) {
    const validationMessage = data?.errors ? Object.values(data.errors).flat().join(" ") : "";
    throw new Error(validationMessage || data?.message || data?.title || "Unable to process the service request.");
  }
  return data;
}

export const getStudioServices = (token) => request(token);
export const createStudioService = (token, service) => request(token, "", { method: "POST", body: JSON.stringify(service) });
export const updateStudioService = (token, id, service) => request(token, `/${id}`, { method: "PUT", body: JSON.stringify(service) });
export const deleteStudioService = (token, id) => request(token, `/${id}`, { method: "DELETE" });
