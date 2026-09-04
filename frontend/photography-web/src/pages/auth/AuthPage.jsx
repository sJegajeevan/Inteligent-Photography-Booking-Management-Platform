import { useState } from "react";
import Header from "../../components/common/Header";
import Footer from "../../components/common/Footer";
import Button from "../../components/common/Button";
import Card from "../../components/common/Card";
import { useAuth } from "../../context/useAuth";
import "./auth.css";

const emptyRegistration = { fullName: "", email: "", password: "", confirmPassword: "", role: "" };

function AuthPage() {
  const { login, register } = useAuth();
  const [mode, setMode] = useState("login");
  const [loginForm, setLoginForm] = useState({ email: "", password: "", rememberMe: false });
  const [registerForm, setRegisterForm] = useState(emptyRegistration);
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);
  const [errors, setErrors] = useState({});
  const [message, setMessage] = useState("");
  const [messageType, setMessageType] = useState("");
  const [isLoading, setIsLoading] = useState(false);

  const switchMode = (nextMode) => {
    setMode(nextMode);
    setErrors({});
    setMessage("");
    setMessageType("");
  };

  const updateLogin = (event) => {
    const { name, value, checked, type } = event.target;
    setLoginForm((current) => ({ ...current, [name]: type === "checkbox" ? checked : value }));
    setErrors((current) => ({ ...current, [name]: "" }));
    setMessage("");
  };

  const updateRegister = (event) => {
    const { name, value } = event.target;
    setRegisterForm((current) => ({ ...current, [name]: value }));
    setErrors((current) => ({ ...current, [name]: "" }));
    setMessage("");
  };

  const validate = () => {
    const nextErrors = {};
    const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    const form = mode === "login" ? loginForm : registerForm;

    if (!emailPattern.test(form.email.trim())) nextErrors.email = "Enter a valid email address.";
    if (!form.password) nextErrors.password = "Password is required.";

    if (mode === "register") {
      if (!form.fullName.trim()) nextErrors.fullName = "Full name is required.";
      if (form.password && form.password.length < 8) nextErrors.password = "Password must be at least 8 characters.";
      if (form.confirmPassword !== form.password) nextErrors.confirmPassword = "Passwords must match.";
      if (!form.role) nextErrors.role = "Choose an account role.";
    }
    return nextErrors;
  };

  const handleSubmit = async (event) => {
    event.preventDefault();
    if (isLoading) return;

    const nextErrors = validate();
    setErrors(nextErrors);
    if (Object.keys(nextErrors).length) return;

    setIsLoading(true);
    setMessage("");
    try {
      if (mode === "register") {
        await register({
          fullName: registerForm.fullName.trim(),
          email: registerForm.email.trim(),
          password: registerForm.password,
          role: registerForm.role,
        });
        setRegisterForm(emptyRegistration);
        setMode("login");
        setMessageType("success");
        setMessage("Registration successful. Please login.");
      } else {
        const response = await login(
          { email: loginForm.email.trim(), password: loginForm.password },
          loginForm.rememberMe
        );
        const role = response.user?.role?.toLowerCase();
        window.location.href = role === "studio" ? "/studio/dashboard" : role === "admin" ? "/admin" : "/customer";
      }
    } catch (error) {
      setMessageType("error");
      setMessage(error.message || "Authentication failed. Please try again.");
    } finally {
      setIsLoading(false);
    }
  };

  const fieldError = (name) => errors[name] && <p className="field-error">{errors[name]}</p>;
  const isLogin = mode === "login";

  return (
    <>
      <Header />
      <main className="auth-page">
        <section className="auth-stage">
          <div className="auth-brand" aria-hidden="true">
            <div className="auth-brand-orbit" />
            <p>SnapSync AI</p>
          </div>

          <Card className="auth-card">
            <div className="auth-card-heading">
              <div>
                <p className="auth-kicker">PHOTOGRAPHY PLATFORM</p>
                <h1>{isLogin ? "Sign in to continue" : "Create your account"}</h1>
              </div>
            </div>

            <div className="auth-tabs" role="tablist" aria-label="Authentication mode">
              <button
                type="button"
                role="tab"
                aria-selected={isLogin}
                className={isLogin ? "is-active" : ""}
                onClick={() => switchMode("login")}
              >
                Login
              </button>
              <button
                type="button"
                role="tab"
                aria-selected={!isLogin}
                className={!isLogin ? "is-active" : ""}
                onClick={() => switchMode("register")}
              >
                Register
              </button>
            </div>

            <form className="auth-form" onSubmit={handleSubmit} noValidate>
              {!isLogin && (
                <>
                  <label htmlFor="auth-full-name">Full name</label>
                  <input
                    id="auth-full-name"
                    name="fullName"
                    value={registerForm.fullName}
                    onChange={updateRegister}
                    autoComplete="name"
                    placeholder="Enter your full name"
                  />
                  {fieldError("fullName")}
                </>
              )}

              <label htmlFor="auth-email">Email address</label>
              <input
                id="auth-email"
                name="email"
                type="email"
                value={isLogin ? loginForm.email : registerForm.email}
                onChange={isLogin ? updateLogin : updateRegister}
                autoComplete="email"
                placeholder="you@example.com"
              />
              {fieldError("email")}

              <label htmlFor="auth-password">Password</label>
              <div className="password-field">
                <input
                  id="auth-password"
                  name="password"
                  type={showPassword ? "text" : "password"}
                  value={isLogin ? loginForm.password : registerForm.password}
                  onChange={isLogin ? updateLogin : updateRegister}
                  autoComplete={isLogin ? "current-password" : "new-password"}
                  placeholder={isLogin ? "Enter your password" : "At least 8 characters"}
                />
                <button
                  type="button"
                  className="password-toggle"
                  onClick={() => setShowPassword((visible) => !visible)}
                  aria-label={showPassword ? "Hide password" : "Show password"}
                >
                  {showPassword ? "Hide" : "Show"}
                </button>
              </div>
              {fieldError("password")}

              {!isLogin && (
                <>
                  <label htmlFor="auth-confirm-password">Confirm password</label>
                  <div className="password-field">
                    <input
                      id="auth-confirm-password"
                      name="confirmPassword"
                      type={showConfirmPassword ? "text" : "password"}
                      value={registerForm.confirmPassword}
                      onChange={updateRegister}
                      autoComplete="new-password"
                      placeholder="Repeat your password"
                    />
                    <button
                      type="button"
                      className="password-toggle"
                      onClick={() => setShowConfirmPassword((visible) => !visible)}
                      aria-label={showConfirmPassword ? "Hide password confirmation" : "Show password confirmation"}
                    >
                      {showConfirmPassword ? "Hide" : "Show"}
                    </button>
                  </div>
                  {fieldError("confirmPassword")}

                  <label htmlFor="auth-role">Account role</label>
                  <select id="auth-role" name="role" value={registerForm.role} onChange={updateRegister}>
                    <option value="">Select a role</option>
                    <option value="Customer">Customer</option>
                    <option value="Studio">Studio</option>
                  </select>
                  {fieldError("role")}
                </>
              )}

              {isLogin && (
                <div className="field-label-row">
                  <label className="checkbox-label">
                    <input
                      name="rememberMe"
                      type="checkbox"
                      checked={loginForm.rememberMe}
                      onChange={updateLogin}
                    />
                    <span>Remember me</span>
                  </label>
                  <a href="/forgot-password">Forgot password?</a>
                </div>
              )}

              {message && (
                <p className={`auth-message ${messageType}`} role={messageType === "error" ? "alert" : "status"}>
                  {message}
                </p>
              )}

              <Button type="submit">
                {isLoading ? (isLogin ? "Signing in..." : "Creating account...") : (isLogin ? "Login" : "Create account")}
              </Button>
            </form>

            <p className="auth-switch">
              {isLogin ? "Don't have an account? " : "Already have an account? "}
              <button type="button" onClick={() => switchMode(isLogin ? "register" : "login")}>
                {isLogin ? "Register" : "Login"}
              </button>
            </p>
          </Card>
        </section>
      </main>
      <Footer />
    </>
  );
}

export default AuthPage;
