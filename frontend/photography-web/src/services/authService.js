const API_URL = (import.meta.env.VITE_API_URL || "").replace(/\/$/, "");

async function request(path, body) {
  let response;
  try {
    response = await fetch(`${API_URL}/api/auth/${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  } catch {
    throw new Error("Unable to connect to the server. Please try again.");
  }

  let data = null;
  try {
    data = await response.json();
  } catch {
    // Some backend failures do not include a JSON response body.
  }

  if (!response.ok) {
    const validationMessage = data?.errors && Object.values(data.errors).flat().join(" ");
    throw new Error(validationMessage || data?.message || data?.title || "Authentication failed. Please check your details.");
  }

  return data;
}

export const login = (credentials) => request("login", credentials);
export const register = (details) => request("register", details);

export function logout() {
  localStorage.removeItem("authToken");
  localStorage.removeItem("authUser");
  sessionStorage.removeItem("authToken");
  sessionStorage.removeItem("authUser");
}