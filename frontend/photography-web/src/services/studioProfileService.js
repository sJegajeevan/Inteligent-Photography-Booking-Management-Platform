const API_URL = (import.meta.env.VITE_API_URL || "").replace(/\/$/, "");

function isFormDataBody(body) {
  return body && Object.prototype.toString.call(body) === "[object FormData]";
}

function isFile(value) {
  return typeof File !== "undefined" && value instanceof File;
}

async function request(token, options = {}, allowNotFound = false) {
  let response;
  const headers = { Authorization: `Bearer ${token}`, ...options.headers };
  if (isFormDataBody(options.body)) {
    Object.keys(headers).filter((key) => key.toLowerCase() === "content-type").forEach((key) => delete headers[key]);
  } else {
    headers["Content-Type"] = "application/json";
  }
  try { response = await fetch(`${API_URL}/api/studio/profile`, { ...options, headers }); }
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
export const saveStudioProfile = (token, profile) => {
  const formData = new FormData();
  const fields = [
    ["StudioName", profile.studioName],
    ["Description", profile.description],
    ["Location", profile.location],
    ["Address", profile.address],
    ["Latitude", profile.latitude],
    ["Longitude", profile.longitude],
    ["ContactNumber", profile.contactNumber],
    ["Email", profile.email],
    ["ExperienceYears", profile.experienceYears],
    ["PhotographyTypes", profile.photographyTypes],
    ["StartingPrice", profile.startingPrice],
  ];
  fields.forEach(([key, value]) => formData.append(key, String(value ?? "")));
  if (isFile(profile.logoImage)) formData.append("LogoImage", profile.logoImage);
  if (isFile(profile.coverImage)) formData.append("CoverImage", profile.coverImage);
  return request(token, { method: "PUT", body: formData });
};
export const deleteStudioProfile = (token) => request(token, { method: "DELETE" });
