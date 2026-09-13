import { useAuth } from "../../context/useAuth";

const roleRoutes = { studio: "/studio", customer: "/customer", admin: "/admin" };

function ProtectedRoute({ children, allowedRoles }) {
  const { isAuthenticated, user } = useAuth();

  if (!isAuthenticated) {
    window.location.replace("/auth");
    return null;
  }

  const normalizedRole = typeof user?.role === "string" ? user.role.toLowerCase() : "";
  const hasAllowedRole = !allowedRoles || allowedRoles.some((role) => role.toLowerCase() === normalizedRole);
  if (!hasAllowedRole) {
    window.location.replace(roleRoutes[normalizedRole] || "/auth");
    return null;
  }

  return children;
}

export default ProtectedRoute;
