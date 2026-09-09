const API_URL = (import.meta.env.VITE_API_URL || "").replace(/\/$/, "");
async function request(token, path = "", options = {}) {
  const headers = new Headers(options.headers); headers.set("Authorization", `Bearer ${token}`);
  try { const response = await fetch(`${API_URL}/api/studio/packages${path}`, { ...options, headers }); if (response.status === 204) return null; const data = await response.json().catch(() => null); if (!response.ok) throw new Error(Object.values(data?.errors || {}).flat().join(" ") || data?.message || "Unable to process the package request."); return data; } catch (error) { if (error instanceof TypeError) throw new Error("Unable to connect to the server. Please try again.", { cause: error }); throw error; }
}
function formData(item) {
  const data = new FormData();
  const numericFields = [
    ["basePrice", "BasePrice", 0.01, 9999999999.99, false, "Base price must be greater than zero."],
    ["durationHours", "DurationHours", 0.01, 999.99, false, "Duration must be greater than zero."],
    ["numberOfPhotographers", "NumberOfPhotographers", 1, 100, true, "Enter a valid number of photographers."],
    ["editedPhotoCount", "EditedPhotoCount", 0, 1000000, true, "Enter a valid edited photo count."],
    ["extraHourRate", "ExtraHourRate", 0, 9999999999.99, false, "Enter a valid extra hour rate."],
    ["additionalPhotographerRate", "AdditionalPhotographerRate", 0, 9999999999.99, false, "Enter a valid additional photographer rate."],
  ];
  for (const [key, property, min, max, integer, message] of numericFields) {
    const raw = item[key];
    const value = Number(raw);
    if (raw == null || String(raw).trim() === "" || !Number.isFinite(value) || value < min || value > max || (integer && !Number.isInteger(value))) {
      throw new Error(message);
    }
    data.append(property, String(value));
  }
  for (const [key, property] of [["name", "Name"], ["description", "Description"], ["status", "Status"]]) data.append(property, item[key] ?? "");
  for (const [key, property] of [["albumIncluded", "AlbumIncluded"], ["videoIncluded", "VideoIncluded"]]) data.append(property, String(Boolean(item[key])));
  (item.serviceIds || []).forEach((id) => data.append("ServiceIds", id));
  if (item.coverImage) data.append("CoverImage", item.coverImage);
  return data;
}
export const getPhotographyPackages = (token) => request(token);
export const getPhotographyPackage = (token, id) => request(token, `/${id}`);
export const createPhotographyPackage = (token, item) => request(token, "", { method: "POST", body: formData(item) });
export const updatePhotographyPackage = (token, id, item) => request(token, `/${id}`, { method: "PUT", body: formData(item) });
export const deletePhotographyPackage = (token, id) => request(token, `/${id}`, { method: "DELETE" });
export const calculatePackagePrice = (token, id, requestBody) => request(token, `/${id}/calculate-price`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(requestBody) });
export const resolvePackageImageUrl = (url) => !url || /^(https?:|data:|blob:)/i.test(url) ? url : `${API_URL}${url.startsWith("/") ? "" : "/"}${url}`;
