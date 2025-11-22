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
    <div className="flex items-center justify-center gap-4 py-4">
      <button
        onClick={onPrevious}
        disabled={currentPage === 0}
        className="px-4 py-2 bg-blue-500 text-white rounded disabled:bg-gray-300 disabled:cursor-not-allowed hover:bg-blue-600"
      >
        ← Previous
      </button>

      <span className="text-sm font-medium">
        Page {currentPage + 1} of {totalPages}
      </span>

      <button
        onClick={onNext}
        disabled={currentPage === totalPages - 1}
        className="px-4 py-2 bg-blue-500 text-white rounded disabled:bg-gray-300 disabled:cursor-not-allowed hover:bg-blue-600"
      >
        Next →
      </button>
    </div>
  );
};
