const API_URL = (import.meta.env.VITE_API_URL || "").replace(/\/$/, "");

async function request(token, path = "", options = {}) {
  let response;
  try {
    response = await fetch(`${API_URL}/api/studio/availability${path}`, {
      ...options,
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", ...options.headers },
    });
  } catch { throw new Error("Unable to connect to the server. Please try again."); }
  if (response.status === 204) return null;
  const data = await response.json().catch(() => null);
  if (!response.ok) {
    const validationMessage = data?.errors ? Object.values(data.errors).flat().join(" ") : "";
    throw new Error(validationMessage || data?.message || data?.title || "Unable to process the availability request.");
  }
  return data;
}

export const getStudioAvailability = (token) => request(token);
const normalizeTime = (value) => {
  if (!value) return null;
  return /^\d{2}:\d{2}$/.test(value) ? `${value}:00` : value;
};
const serializeAvailability = (values) => ({
  ...values,
  startTime: normalizeTime(values.startTime),
  endTime: normalizeTime(values.endTime),
});

export const createStudioAvailability = (token, values) => request(token, "", { method: "POST", body: JSON.stringify(serializeAvailability(values)) });
export const updateStudioAvailability = (token, id, values) => request(token, `/${id}`, { method: "PUT", body: JSON.stringify(serializeAvailability(values)) });
export const deleteStudioAvailability = (token, id) => request(token, `/${id}`, { method: "DELETE" });
