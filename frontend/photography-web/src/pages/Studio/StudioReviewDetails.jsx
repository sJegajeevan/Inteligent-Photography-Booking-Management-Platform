import { useEffect, useState } from "react";
import { useAuth } from "../../context/useAuth";
import { getStudioReview } from "../../services/studioReviewsService";
import "./StudioReviews.css";

const dateFormatter = new Intl.DateTimeFormat("en-LK", { dateStyle: "long", timeStyle: "short" });

export default function StudioReviewDetails({ reviewId }) {
  const { token } = useAuth();
  const [attempt, setAttempt] = useState(0);
  const [state, setState] = useState({ loading: true, error: null, review: null });

  useEffect(() => {
    const controller = new AbortController();
    getStudioReview(token, reviewId, controller.signal)
      .then((review) => {
        if (!controller.signal.aborted) setState({ loading: false, error: null, review });
      })
      .catch((error) => {
        if (!controller.signal.aborted) setState({ loading: false, error, review: null });
      });
    return () => controller.abort();
  }, [token, reviewId, attempt]);

  const retry = () => {
    setState({ loading: true, error: null, review: null });
    setAttempt((value) => value + 1);
  };
  const { loading, error, review } = state;

  return <div className="reviews-page">
    <a href="/studio/reviews" className="reviews-back">← Back to Reviews</a>
    <section className="reviews-heading"><p>CLIENT EXPERIENCE</p><h1>Review Details</h1><span>Customer feedback for your studio.</span></section>
    {loading ? <section className="reviews-state" role="status">Loading review details…</section>
      : error ? <section className="reviews-state reviews-error" role="alert">
        <h2>{error.status === 404 ? "Review not found" : "Unable to load review details"}</h2>
        <p>{error.status === 404 ? "This review does not exist or is not available to your studio." : error.message}</p>
        <button type="button" onClick={retry}>Retry</button>
      </section>
      : <div className="reviews-detail-layout">
        <article className="reviews-card">
          <header><div className="reviews-customer">
            <span className="reviews-avatar" aria-hidden="true">{Array.from(review.customerName?.trim() || "")[0]?.toUpperCase() || "★"}</span>
            <div><h2>{review.customerName?.trim() || "Customer name unavailable"}</h2><span>Customer #{review.customerId}</span></div>
          </div></header>
          {review.customerEmail?.trim() && <p className="reviews-detail-email">{review.customerEmail}</p>}
          <div className="reviews-detail-rating">
            <span className="reviews-stars" role="img" aria-label={`${review.rating} out of 5 stars`}>
              {[1, 2, 3, 4, 5].map((star) => <span key={star} aria-hidden="true" className={star <= review.rating ? "filled" : ""}>★</span>)}
            </span><strong>{review.rating} / 5</strong>
          </div>
          <h3 className="reviews-detail-label">Review comment</h3>
          <p className="reviews-comment">{review.comment?.trim() || "No comment provided."}</p>
        </article>
        <section className="reviews-card">
          <h2 className="reviews-detail-title">Review information</h2>
          <dl className="reviews-details">
            <div><dt>Booking reference</dt><dd>#{review.bookingId}</dd></div>
            <div><dt>Created</dt><dd><time dateTime={review.createdAt}>{dateFormatter.format(new Date(review.createdAt))}</time></dd></div>
            <div><dt>Review reference</dt><dd>{review.id}</dd></div>
            <div><dt>Studio reference</dt><dd>{review.studioId}</dd></div>
          </dl>
        </section>
      </div>}
  </div>;
}
