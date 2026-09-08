const API_URL = (import.meta.env.VITE_API_URL || "").replace(/\/$/, "");

async function request(token, packageId, path = "", options = {}) {
  const headers = new Headers(options.headers);
  headers.set("Authorization", `Bearer ${token}`);
  headers.set("Content-Type", "application/json");
  const response = await fetch(`${API_URL}/api/studio/packages/${packageId}/addons${path}`, { ...options, headers });
  if (response.status === 204) return null;
  const data = await response.json().catch(() => null);
  if (!response.ok) throw new Error(Object.values(data?.errors || {}).flat().join(" ") || data?.message || "Unable to process the add-on request.");
  return data;
}

export const getPackageAddons = (token, packageId) => request(token, packageId);
export const createPackageAddon = (token, packageId, addon) => request(token, packageId, "", { method: "POST", body: JSON.stringify(addon) });
export const updatePackageAddon = (token, packageId, addonId, addon) => request(token, packageId, `/${addonId}`, { method: "PUT", body: JSON.stringify(addon) });
export const deletePackageAddon = (token, packageId, addonId) => request(token, packageId, `/${addonId}`, { method: "DELETE" });
