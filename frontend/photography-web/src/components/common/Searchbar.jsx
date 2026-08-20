import { useRef, useState } from "react";
import "./Searchbar.css";

function Searchbar({
	value,
	onChange,
	onSearch,
	placeholder = "Search...",
	className = "",
}) {
	const inputRef = useRef(null);
	const [internalValue, setInternalValue] = useState("");
	const isControlled = value !== undefined;
	const inputValue = isControlled ? value : internalValue;

	const handleChange = (event) => {
		const nextValue = event.target.value;
		if (!isControlled) {
			setInternalValue(nextValue);
		}
		onChange?.(nextValue);
	};

	const handleSubmit = (event) => {
		event.preventDefault();
		onSearch?.(inputValue.trim());
	};

	const handleClear = () => {
		if (!isControlled) {
			setInternalValue("");
		}
		onChange?.("");
		onSearch?.("");
		inputRef.current?.focus();
	};

	return (
		<form
			className={`searchbar-wrap ${className}`.trim()}
			role="search"
			onSubmit={handleSubmit}
			aria-label="Search"
		>
			<button
				type="submit"
				className="searchbar-icon-btn"
				aria-label="Run search"
			>
				<svg viewBox="0 0 24 24" aria-hidden="true">
					<circle cx="11" cy="11" r="7" />
					<path d="M20 20l-4.1-4.1" />
				</svg>
			</button>

			<input
				ref={inputRef}
				className="searchbar-input"
				type="search"
				value={inputValue}
				onChange={handleChange}
				placeholder={placeholder}
				aria-label="Search input"
			/>

			<button
				type="button"
				className="searchbar-clear-btn"
				onClick={handleClear}
				aria-label="Clear search"
				disabled={!inputValue}
			>
				<svg viewBox="0 0 24 24" aria-hidden="true">
					<path d="M7 7l10 10M17 7L7 17" />
				</svg>
			</button>
		</form>
	);
}

export default Searchbar;
