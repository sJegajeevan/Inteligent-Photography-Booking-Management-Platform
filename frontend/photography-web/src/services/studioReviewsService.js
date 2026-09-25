const API_URL = (import.meta.env.VITE_API_URL || "").replace(/\/$/, "");

async function requestReviews(token, path, signal) {
  if (!token) throw new Error("Please sign in to view your studio reviews.");
  let response;
  try {
    response = await fetch(`${API_URL}/api/studio/reviews${path}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
      signal,
    });
  } catch (error) {
    if (error.name === "AbortError") throw error;
    throw new Error("Unable to connect to the review server. Please try again.");
  }
  const data = await response.json().catch(() => null);
  if (!response.ok) {
    if (response.status === 404) throw reviewNotFound();
    if (response.status === 401) throw new Error("Your session has expired. Please sign in again.");
    if (response.status === 403) throw new Error("You do not have permission to view studio reviews.");
    throw new Error(response.status >= 500
      ? "The review server is unavailable. Please try again later."
      : data?.message || "Unable to load reviews. Please try again.");
  }
  return data;
}

function reviewNotFound() {
  const error = new Error("Review was not found.");
  error.status = 404;
  return error;
}

function invalidReview(review) {
  return (
    !review || typeof review.id !== "string" || !review.id.trim() ||
    !Number.isInteger(review.rating) || review.rating < 1 || review.rating > 5 ||
    !Number.isInteger(review.bookingId) || review.bookingId < 1 ||
    (review.customerName != null && typeof review.customerName !== "string") ||
    (review.comment != null && typeof review.comment !== "string") ||
    typeof review.createdAt !== "string" || !Number.isFinite(Date.parse(review.createdAt))
  );
}

export async function getStudioReviews(token, signal) {
  const data = await requestReviews(token, "", signal);
  if (!Array.isArray(data) || data.some(invalidReview))
    throw new Error("The server returned invalid review data. Please try again.");
  return data;
}

export async function getStudioReview(token, reviewId, signal) {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(reviewId))
    throw reviewNotFound();
  const data = await requestReviews(token, `/${encodeURIComponent(reviewId)}`, signal);
  if (invalidReview(data) || data.id.toLowerCase() !== reviewId.toLowerCase() ||
      !Number.isInteger(data.customerId) || data.customerId < 1 ||
      typeof data.studioId !== "string" ||
      (data.customerEmail != null && typeof data.customerEmail !== "string"))
    throw new Error("The server returned invalid review details. Please try again.");
  return data;
}
