const statusClassNames = {
  Pending: "pending",
  AIRecommended: "recommended",
  AwaitingApproval: "approval",
  Confirmed: "confirmed",
  Rejected: "rejected",
  Cancelled: "cancelled",
  Rescheduled: "rescheduled",
  Completed: "completed",
};

function readableStatus(status) {
  return status === "AIRecommended" ? "AI Recommended" : status === "AwaitingApproval" ? "Awaiting Approval" : status;
}

export default function BookingStatusBadge({ status }) {
  return <span className={`booking-status-badge ${statusClassNames[status] || "unknown"}`}>{readableStatus(status || "Unknown")}</span>;
}
