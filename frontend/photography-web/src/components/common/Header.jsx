import "./Header.css";

function Header() {
  return (
    <header className="header">
      <div className="header-container">
        <div className="brand">
          <span className="brand-icon">✦</span>
          <span className="brand-name">Photography AI</span>
        </div>

        <nav className="nav">
          <a href="/">Home</a>
          <a href="/photographers">Photographers</a>
          <a href="/packages">Packages</a>
          <a href="/bookings">Bookings</a>
        </nav>

        <button className="header-button">Get Started</button>
      </div>
    </header>
  );
}

export default Header;
