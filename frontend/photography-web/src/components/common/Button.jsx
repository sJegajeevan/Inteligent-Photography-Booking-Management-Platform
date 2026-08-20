import "./button.css";

function Button({ children, onClick, type = "button" }) {
  return (
    <button
      type={type}
      onClick={onClick}
      className="app-button"
    >
      {children}
    </button>
  );
}

export default Button;
