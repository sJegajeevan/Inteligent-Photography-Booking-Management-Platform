import { createContext, useState } from "react";
import { login as loginRequest, logout as logoutRequest, register as registerRequest } from "../services/authService";

export const AuthContext = createContext(null);

function isUsableJwt(token) {
  if (typeof token !== "string") return false;
  const parts = token.split(".");
  if (parts.length !== 3) return false;

  try {
    const payload = JSON.parse(atob(parts[1].replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(parts[1].length / 4) * 4, "=")));
    return typeof payload.exp === "number" && payload.exp * 1000 > Date.now();
  } catch {
    return false;
  }
}

function clearStoredAuth(storage) {
  storage.removeItem("authToken");
  storage.removeItem("authUser");
}

function readStoredAuth() {
  for (const storage of [sessionStorage, localStorage]) {
    const token = storage.getItem("authToken");
    const userValue = storage.getItem("authUser");
    if (!token && !userValue) continue;

    if (!token || !userValue || !isUsableJwt(token)) {
      clearStoredAuth(storage);
      continue;
    }

    try {
      const user = JSON.parse(userValue);
      if (!user || typeof user !== "object" || typeof user.role !== "string") throw new Error("Invalid stored user");
      return { token, user };
    } catch {
      clearStoredAuth(storage);
    }
  }

  return { token: null, user: null };
}

export function AuthProvider({ children }) {
  const [{ token, user }, setAuth] = useState(readStoredAuth);

  const login = async (credentials, rememberMe = false) => {
    const response = await loginRequest(credentials);
    const storage = rememberMe ? localStorage : sessionStorage;
    const otherStorage = rememberMe ? sessionStorage : localStorage;
    otherStorage.removeItem("authToken");
    otherStorage.removeItem("authUser");
    storage.setItem("authToken", response.token);
    storage.setItem("authUser", JSON.stringify(response.user));
    setAuth({ token: response.token, user: response.user });
    return response;
  };

  const register = (details) => registerRequest(details);

  const logout = () => {
    logoutRequest();
    setAuth({ token: null, user: null });
  };

  return (
    <AuthContext.Provider value={{ user, token, isAuthenticated: Boolean(token && user), login, register, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

