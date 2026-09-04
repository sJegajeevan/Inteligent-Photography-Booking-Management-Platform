function Pagination({ currentPage, totalPages, onPageChange }) {
  if (totalPages <= 1) return null;

  return (
    <nav className="pagination" aria-label="Pagination">
      <button className="pagination-direction" type="button" onClick={() => onPageChange(currentPage - 1)} disabled={currentPage === 1}><span aria-hidden="true">‹</span> Previous</button>
      <div className="pagination-pages">
        {Array.from({ length: totalPages }, (_, index) => index + 1).map((page) => (
          <button
            type="button"
            key={page}
            className={page === currentPage ? "active" : ""}
            aria-current={page === currentPage ? "page" : undefined}
            onClick={() => onPageChange(page)}
          >{page}</button>
        ))}
      </div>
      <button className="pagination-direction" type="button" onClick={() => onPageChange(currentPage + 1)} disabled={currentPage === totalPages}>Next <span aria-hidden="true">›</span></button>
    </nav>
  );
}

export default Pagination;
