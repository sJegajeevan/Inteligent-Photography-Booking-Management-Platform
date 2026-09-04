import "./Header.css";
import { useAuth } from "../../context/useAuth";

function Header({ showPublicNavigation = true, studioNavigation = null, studioAccount = null }) {
  const { isAuthenticated, logout } = useAuth();
  const handleLogout = () => {
    logout();
    window.location.replace("/auth");
  };

  return (
    <header className={`header${studioNavigation ? " studio-header" : ""}`}>
      <div className={`header-container${studioNavigation ? " studio-header-container" : ""}`}>
        <div className="brand">
          <span className="brand-icon">✦</span>
          <span className="brand-name">Photography AI</span>
        </div>

        {showPublicNavigation && <nav className="nav">
          <a href="/">Home</a>
          <a href="/photographers">Photographers</a>
          <a href="/packages">Packages</a>
          <a href="/bookings">Bookings</a>
        </nav>}

        {studioNavigation && <div className="studio-header-navigation">{studioNavigation}</div>}

        {studioAccount}

        {isAuthenticated
          ? <button className="header-button header-logout" type="button" onClick={handleLogout}>Logout</button>
          : <button className="header-button" type="button" onClick={() => { window.location.href = "/auth"; }}>Get Started</button>}
      </div>
    </header>
  );
}

export default Header;
