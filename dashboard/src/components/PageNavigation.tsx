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
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '1rem', padding: '1rem 0' }}>
      <button
        onClick={onPrevious}
        disabled={currentPage === 0}
        className="btn btn-secondary btn-sm"
      >
        ← Previous
      </button>

      <span style={{ fontSize: '0.875rem', fontWeight: '500' }}>
        Page {currentPage + 1} of {totalPages}
      </span>

      <button
        onClick={onNext}
        disabled={currentPage === totalPages - 1}
        className="btn btn-secondary btn-sm"
      >
        Next →
      </button>
    </div>
  );
};
