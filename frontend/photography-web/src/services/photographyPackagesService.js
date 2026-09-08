const API_URL = (import.meta.env.VITE_API_URL || "").replace(/\/$/, "");
async function request(token, path = "", options = {}) {
  const headers = new Headers(options.headers); headers.set("Authorization", `Bearer ${token}`);
  try { const response = await fetch(`${API_URL}/api/studio/packages${path}`, { ...options, headers }); if (response.status === 204) return null; const data = await response.json().catch(() => null); if (!response.ok) throw new Error(Object.values(data?.errors || {}).flat().join(" ") || data?.message || "Unable to process the package request."); return data; } catch (error) { if (error instanceof TypeError) throw new Error("Unable to connect to the server. Please try again.", { cause: error }); throw error; }
}
function formData(item) { const data = new FormData(); ["name", "description", "basePrice", "extraHourRate", "additionalPhotographerRate", "durationHours", "numberOfPhotographers", "editedPhotoCount", "status"].forEach((key) => data.append(key, item[key] ?? "")); ["albumIncluded", "videoIncluded"].forEach((key) => data.append(key, String(Boolean(item[key])))); (item.serviceIds || []).forEach((id) => data.append("serviceIds", id)); if (item.coverImage) data.append("coverImage", item.coverImage); return data; }
export const getPhotographyPackages = (token) => request(token);
export const getPhotographyPackage = (token, id) => request(token, `/${id}`);
export const createPhotographyPackage = (token, item) => request(token, "", { method: "POST", body: formData(item) });
export const updatePhotographyPackage = (token, id, item) => request(token, `/${id}`, { method: "PUT", body: formData(item) });
export const deletePhotographyPackage = (token, id) => request(token, `/${id}`, { method: "DELETE" });
export const calculatePackagePrice = (token, id, requestBody) => request(token, `/${id}/calculate-price`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(requestBody) });
export const resolvePackageImageUrl = (url) => !url || /^(https?:|data:|blob:)/i.test(url) ? url : `${API_URL}${url.startsWith("/") ? "" : "/"}${url}`;
