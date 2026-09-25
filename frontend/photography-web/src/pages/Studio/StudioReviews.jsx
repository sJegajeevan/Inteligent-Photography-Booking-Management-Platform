import { useEffect, useState } from "react";
import { useAuth } from "../../context/useAuth";
import { getStudioReviews } from "../../services/studioReviewsService";
import "./StudioReviews.css";

const dateFormatter = new Intl.DateTimeFormat("en-LK", {
  day: "numeric", month: "short", year: "numeric",
});

function Stars({ rating }) {
  return <span className="reviews-stars" role="img" aria-label={`${rating} out of 5 stars`}>
    {[1, 2, 3, 4, 5].map((star) => <span key={star} aria-hidden="true" className={star <= rating ? "filled" : ""}>★</span>)}
  </span>;
}

function ReviewCard({ review }) {

  const name = review.customerName?.trim();
  return <article className="reviews-card">
    <header>
      <div className="reviews-customer"><span className="reviews-avatar" aria-hidden="true">{name ? Array.from(name)[0].toUpperCase() : "★"}</span>
        <div><h2>{name || "Customer name unavailable"}</h2><span>Booking #{review.bookingId}</span></div>
      </div>
      <time dateTime={review.createdAt}>{dateFormatter.format(new Date(review.createdAt))}</time>
    </header>
    <Stars rating={review.rating} />
    <p className="reviews-comment collapsed">{review.comment?.trim() || "No comment provided."}</p>
    <footer><button type="button" onClick={() => window.location.assign(`/studio/reviews/${encodeURIComponent(review.id)}`)}>View Details</button></footer>
  </article>;
}

export default function StudioReviews() {
  const { token } = useAuth();
  const [attempt, setAttempt] = useState(0);
  const [state, setState] = useState({ loading: true, error: "", reviews: [] });

  useEffect(() => {
    const controller = new AbortController();
    getStudioReviews(token, controller.signal)
      .then((reviews) => {
        if (!controller.signal.aborted) setState({ loading: false, error: "", reviews });
      })
      .catch((error) => {
        if (!controller.signal.aborted) setState({ loading: false, error: error.message, reviews: [] });
      });
    return () => controller.abort();
  }, [token, attempt]);

  const retry = () => {
    setState({ loading: true, error: "", reviews: [] });
    setAttempt((value) => value + 1);
  };
  const { loading, error, reviews } = state;
  const average = reviews.length ? reviews.reduce((sum, review) => sum + review.rating, 0) / reviews.length : null;

  return <div className="reviews-page">
    <section className="reviews-heading"><p>CLIENT EXPERIENCES</p><h1>Customer Reviews</h1><span>Feedback from the customers who trusted your studio with their moments.</span></section>
    {loading ? <section className="reviews-state" role="status"><span className="dashboard-loading-pulse" /> Loading reviews…</section>
      : error ? <section className="reviews-state reviews-error" role="alert"><h2>Unable to load reviews</h2><p>{error}</p><button type="button" onClick={retry}>Retry</button></section>
      : !reviews.length ? <section className="reviews-state"><span className="reviews-empty-icon" aria-hidden="true">☆</span><h2>No reviews yet</h2><p>Reviews will appear here when customers share feedback on completed bookings.</p></section>
      : <>
        <section className="reviews-summary" aria-label="Rating summary">
          <div><span>AVERAGE RATING</span><p><strong>{average.toFixed(1)}</strong> / 5</p><small>From {reviews.length} customer {reviews.length === 1 ? "review" : "reviews"}</small></div>
          <div className="reviews-distribution">{[5, 4, 3, 2, 1].map((rating) => {
            const count = reviews.filter((review) => review.rating === rating).length;
            return <div key={rating}><span>{rating} <span aria-hidden="true">★</span></span><progress max={reviews.length} value={count} aria-label={`${rating} stars: ${count} reviews`} /><span>{count}</span></div>;
          })}</div>
        </section>
        <div className="reviews-list">{reviews.map((review) => <ReviewCard key={review.id} review={review} />)}</div>
      </>}
  </div>;
}
