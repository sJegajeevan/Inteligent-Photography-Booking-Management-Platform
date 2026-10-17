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

export const bookingStatusDetails = {
  Pending: { label: "Pending", explanation: "Waiting for the studio to review this request." },
  AIRecommended: { label: "AI Recommended", explanation: "A suggested booking option is ready for review." },
  AwaitingApproval: { label: "Awaiting Approval", explanation: "The booking is waiting for final approval." },
  Confirmed: { label: "Confirmed", explanation: "The booking is approved and scheduled." },
  Rejected: { label: "Rejected", explanation: "The booking will not go ahead." },
  Cancelled: { label: "Cancelled", explanation: "The booking has been cancelled." },
  Rescheduled: { label: "Rescheduled", explanation: "The booking time needs to be reviewed or updated." },
  Completed: { label: "Completed", explanation: "The scheduled shoot has been completed." },
  Unknown: { label: "Unknown", explanation: "The booking status could not be identified." },
};

export function getBookingStatusDetails(status) {
  return bookingStatusDetails[status] || bookingStatusDetails.Unknown;
}

export default function BookingStatusBadge({ status }) {
  const details = getBookingStatusDetails(status || "Unknown");
  return <span className={`booking-status-badge ${statusClassNames[status] || "unknown"}`} title={details.explanation} aria-label={`${details.label}: ${details.explanation}`}>{details.label}</span>;
}
