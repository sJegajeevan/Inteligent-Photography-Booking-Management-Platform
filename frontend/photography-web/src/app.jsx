import { useState } from "react";
import Header from "./components/common/Header";
import Footer from "./components/common/Footer";
import Button from "./components/common/Button";
import Card from "./components/common/Card";
import AuthPage from "./pages/auth/AuthPage";
import StudioDashboard from "./pages/Studio/StudioDashboard";
import ProtectedRoute from "./components/auth/ProtectedRoute";
import { AuthProvider } from "./context/AuthContext";
import { useAuth } from "./context/useAuth";
import "./App.css";

const featureCards = [
  { number: "01", title: "Discover", text: "Browse a thoughtful collection of talented photographers." },
  { number: "02", title: "Match", text: "Use intelligent recommendations to find your perfect fit." },
  { number: "03", title: "Book", text: "Plan, reserve, and manage every detail with confidence." },
  { number: "04", title: "Capture", text: "Turn your best moments into images worth keeping." },
  { number: "05", title: "Relive", text: "Return to every story, beautifully delivered." },
];

function DashboardPlaceholder({ role }) {
  return <><Header /><main className="home-page"><section className="hero-section"><p className="eyebrow">SNAPSYNC AI</p><h1>{role} Dashboard</h1><p className="hero-copy">This workspace is ready for the next stage of the platform.</p><Button onClick={() => { window.location.href = "/"; }}>Return home</Button></section></main><Footer /></>;
}

function AppContent() {
  const [activeCard, setActiveCard] = useState(2);
  const { isAuthenticated, user } = useAuth();

  const path = window.location.pathname.replace(/\/+$/, "") || "/";
  const authenticatedRolePath = { studio: "/studio/dashboard", customer: "/customer", admin: "/admin" }[user?.role?.toLowerCase()];
  if (path === "/auth" && isAuthenticated && authenticatedRolePath) {
    window.location.replace(authenticatedRolePath);
    return null;
  }
  if (path === "/auth") return <AuthPage />;
  if (path === "/customer") return <ProtectedRoute allowedRoles={["Customer"]}><DashboardPlaceholder role="Customer" /></ProtectedRoute>;
  if (path === "/studio") {
    window.location.replace("/studio/dashboard");
    return null;
  }
  const studioPages = {
    "/studio/dashboard": "dashboard",
    "/studio/profile": "profile",
    "/studio/availability": "availability",
    "/studio/portfolio": "portfolio",
    "/studio/services": "services",
  };
  if (studioPages[path]) return <ProtectedRoute allowedRoles={["Studio"]}><StudioDashboard page={studioPages[path]} /></ProtectedRoute>;
  if (path.startsWith("/studio/")) {
    window.location.replace("/studio/dashboard");
    return null;
  }
  if (path === "/admin") return <ProtectedRoute allowedRoles={["Admin"]}><DashboardPlaceholder role="Admin" /></ProtectedRoute>;

  const getCardStyle = (index) => {
    const rawOffset = index - activeCard;
    const offset = rawOffset > 2 ? rawOffset - featureCards.length : rawOffset < -2 ? rawOffset + featureCards.length : rawOffset;
    const positions = {
      "-2": { x: "-285px", y: "32px", rotate: "-24deg", z: 1, scale: 0.92 },
      "-1": { x: "-145px", y: "10px", rotate: "-12deg", z: 2, scale: 0.97 },
      "0": { x: "0px", y: "-12px", rotate: "0deg", z: 5, scale: 1 },
      "1": { x: "145px", y: "10px", rotate: "12deg", z: 2, scale: 0.97 },
      "2": { x: "285px", y: "32px", rotate: "24deg", z: 1, scale: 0.92 },
    };
    const position = positions[String(offset)];
    return {
      "--card-x": position.x,
      "--card-y": position.y,
      "--card-rotate": position.rotate,
      "--card-scale": position.scale,
      zIndex: position.z,
    };
  };

  return (
    <>
      <Header />

      <main className="home-page">
        <section className="hero-section">
          <p className="eyebrow">FIND YOUR VISUAL STORY</p>
          <h1>Photography, made<br /><span>beautifully simple.</span></h1>
          <p className="hero-copy">Discover photographers and effortless booking experiences tailored to your most meaningful moments.</p>
          <Button onClick={() => { window.location.href = "/auth"; }}>Find your photographer</Button>
        </section>
        <section className="feature-grid" aria-label="Platform highlights">
          {featureCards.map((card, index) => (
            <Card
              key={card.number}
              className={index === activeCard ? "is-active" : ""}
              style={getCardStyle(index)}
              ariaLabel={`${card.title}: ${card.text}`}
              onClick={() => setActiveCard(index)}
            >
              <span className="feature-number">{card.number}</span>
              <h2>{card.title}</h2>
              <p>{card.text}</p>
            </Card>
          ))}
        </section>
      </main>

      <Footer />
    </>
  );
}

function App() {
  return <AuthProvider><AppContent /></AuthProvider>;
}

export default App;
