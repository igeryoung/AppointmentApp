import React from 'react';

interface PageNavigationProps {
  currentPage: number;
  totalPages: number;
  onPrevious: () => void;
  onNext: () => void;
}

/**
 * Page navigation component for multi-page notes
 * Shows current page number and provides Previous/Next buttons
 */
export const PageNavigation: React.FC<PageNavigationProps> = ({
  currentPage,
  totalPages,
  onPrevious,
  onNext,
}) => {
  if (totalPages === 0) return null;

  return (
    <nav className="page-nav" aria-label="Note page navigation">
      <button
        onClick={onPrevious}
        disabled={currentPage === 0}
        className="btn btn-secondary btn-sm"
        aria-label="Previous page"
      >
        ← Previous
      </button>

      <span className="page-nav-indicator">
        Page {currentPage + 1} of {totalPages}
      </span>

      <button
        onClick={onNext}
        disabled={currentPage === totalPages - 1}
        className="btn btn-secondary btn-sm"
        aria-label="Next page"
      >
        Next →
      </button>
    </nav>
  );
};
