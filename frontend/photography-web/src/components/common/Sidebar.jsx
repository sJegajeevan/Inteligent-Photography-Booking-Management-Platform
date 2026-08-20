import { useState } from "react";
import "./Sidebar.css";

const defaultItems = [
	{
		id: "dashboard",
		label: "Dashboard",
		icon: (
			<svg viewBox="0 0 24 24" aria-hidden="true">
				<rect x="4" y="4" width="6" height="6" rx="1.2" />
				<rect x="14" y="4" width="6" height="6" rx="1.2" />
				<rect x="4" y="14" width="6" height="6" rx="1.2" />
				<rect x="14" y="14" width="6" height="6" rx="1.2" />
			</svg>
		),
	},
	{
		id: "users",
		label: "User",
		icon: (
			<svg viewBox="0 0 24 24" aria-hidden="true">
				<circle cx="12" cy="8" r="3.2" />
				<path d="M5.5 19.5c1.5-3 3.9-4.5 6.5-4.5s5 1.5 6.5 4.5" />
			</svg>
		),
	},
	{
		id: "messages",
		label: "Messages",
		icon: (
			<svg viewBox="0 0 24 24" aria-hidden="true">
				<path d="M5 6.8h14a2 2 0 0 1 2 2v6.4a2 2 0 0 1-2 2H10l-4.8 3v-3H5a2 2 0 0 1-2-2V8.8a2 2 0 0 1 2-2z" />
			</svg>
		),
	},
	{
		id: "files",
		label: "File Manager",
		icon: (
			<svg viewBox="0 0 24 24" aria-hidden="true">
				<path d="M4 8.5h16v10a1.6 1.6 0 0 1-1.6 1.6H5.6A1.6 1.6 0 0 1 4 18.5z" />
				<path d="M4 8.5V6.8A1.8 1.8 0 0 1 5.8 5h4.4l1.8 2h6a1.8 1.8 0 0 1 1.8 1.8v-.3" />
			</svg>
		),
	},
	{
		id: "settings",
		label: "Setting",
		icon: (
			<svg viewBox="0 0 24 24" aria-hidden="true">
				<circle cx="12" cy="12" r="3" />
				<path d="M12 4.5v2.1M12 17.4v2.1M19.5 12h-2.1M6.6 12H4.5M17.1 6.9l-1.5 1.5M8.4 15.6l-1.5 1.5M17.1 17.1l-1.5-1.5M8.4 8.4L6.9 6.9" />
			</svg>
		),
	},
];

function Sidebar({
	items = defaultItems,
	title = "Menu",
	defaultActive = "dashboard",
	defaultCollapsed = false,
	onItemSelect,
}) {
	const [isCollapsed, setIsCollapsed] = useState(defaultCollapsed);
	const [activeId, setActiveId] = useState(defaultActive);

	const handleSelect = (item) => {
		setActiveId(item.id);
		onItemSelect?.(item);
	};

	return (
		<aside className={`app-sidebar ${isCollapsed ? "collapsed" : ""}`.trim()}>
			<div className="app-sidebar-top">
				<div className="app-sidebar-brand" aria-label={title}>
					<span className="app-sidebar-brand-icon" aria-hidden="true">
						<svg viewBox="0 0 24 24">
							<path d="M12 3l8 4.5v9L12 21l-8-4.5v-9z" />
							<path d="M12 3v18M4 7.5l8 4.5 8-4.5M4 16.5l8-4.5 8 4.5" />
						</svg>
					</span>
					<span className="app-sidebar-brand-text">{title}</span>
				</div>

				<button
					type="button"
					className="app-sidebar-toggle"
					onClick={() => setIsCollapsed((prev) => !prev)}
					aria-label={isCollapsed ? "Expand sidebar" : "Collapse sidebar"}
					aria-expanded={!isCollapsed}
				>
					<svg viewBox="0 0 24 24" aria-hidden="true">
						<path d="M6 7h12M10 12h8M14 17h4" />
					</svg>
				</button>
			</div>

			<nav aria-label="Sidebar navigation">
				<ul className="app-sidebar-list">
					{items.map((item) => {
						const isActive = item.id === activeId;

						return (
							<li key={item.id} className="app-sidebar-item">
								<button
									type="button"
									className={`app-sidebar-link ${isActive ? "active" : ""}`.trim()}
									onClick={() => handleSelect(item)}
									aria-current={isActive ? "page" : undefined}
								>
									<span className="app-sidebar-link-icon">{item.icon}</span>
									<span className="app-sidebar-link-text">{item.label}</span>
								</button>
							</li>
						);
					})}
				</ul>
			</nav>
		</aside>
	);
}

export default Sidebar;
