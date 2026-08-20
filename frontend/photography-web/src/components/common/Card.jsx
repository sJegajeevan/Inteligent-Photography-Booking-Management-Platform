import "./card.css";

function Card({ children, className = "", onClick, style, ariaLabel }) {
  const isInteractive = typeof onClick === "function";

  return (
    <div
      className={`app-card ${className}`.trim()}
      style={style}
      role={isInteractive ? "button" : undefined}
      tabIndex={isInteractive ? 0 : undefined}
      aria-label={ariaLabel}
      onClick={onClick}
      onKeyDown={(event) => {
        if (isInteractive && (event.key === "Enter" || event.key === " ")) {
          event.preventDefault();
          onClick(event);
        }
      }}
    >
      {children}
    </div>
  );
}

export default Card;
