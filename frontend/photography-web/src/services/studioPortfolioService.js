const API_URL = (import.meta.env.VITE_API_URL || "").replace(/\/$/, "");

async function request(token, path = "", options = {}) {
  let response;
  const headers = new Headers(options.headers);
  headers.set("Authorization", `Bearer ${token}`);
  if (options.body instanceof FormData) headers.delete("Content-Type");
  try {
    response = await fetch(`${API_URL}/api/studio/portfolio${path}`, { ...options, headers });
  } catch { throw new Error("Unable to connect to the server. Please try again."); }
  if (response.status === 204) return null;
  const data = await response.json().catch(() => null);
  if (!response.ok) {
    const validationMessage = data?.errors ? Object.values(data.errors).flat().join(" ") : "";
    throw new Error(validationMessage || data?.message || data?.title || "Unable to process the portfolio request.");
  }
  return data;
}

function toFormData(item) {
  const data = new FormData();
  data.append("title", item.title);
  data.append("category", item.category);
  data.append("description", item.description || "");
  item.photos?.forEach((photo) => data.append("photos", photo));
  item.removedImageIds?.forEach((id) => data.append("removedImageIds", id));
  return data;
}

export function resolvePortfolioImageUrl(imageUrl) {
  if (!imageUrl) return "";
  if (/^(https?:|data:|blob:)/i.test(imageUrl)) return imageUrl;
  return `${API_URL}${imageUrl.startsWith("/") ? "" : "/"}${imageUrl}`;
}

export const getStudioPortfolio = (token) => request(token);
export const createPortfolioItem = (token, item) => request(token, "", { method: "POST", body: toFormData(item) });
export const updatePortfolioItem = (token, id, item) => request(token, `/${id}`, { method: "PUT", body: toFormData(item) });
export const deletePortfolioItem = (token, id) => request(token, `/${id}`, { method: "DELETE" });
