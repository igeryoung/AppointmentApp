import React, { useEffect, useId, useRef, useState } from 'react';
import { Check, ChevronDown } from 'lucide-react';
import { Book } from '../../types';

interface BookSelectorProps {
  books: Book[];
  selectedBookUuids: string[];
  onChange: (selectedUuids: string[]) => void;
}

export const BookSelector: React.FC<BookSelectorProps> = ({
  books,
  selectedBookUuids,
  onChange,
}) => {
  const [isOpen, setIsOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);
  const menuId = useId();

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };

    const handleEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setIsOpen(false);
      }
    };

    if (isOpen) {
      document.addEventListener('mousedown', handleClickOutside);
      document.addEventListener('keydown', handleEscape);
    }

    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
      document.removeEventListener('keydown', handleEscape);
    };
  }, [isOpen]);

  const handleToggleBook = (bookUuid: string) => {
    if (selectedBookUuids.includes(bookUuid)) {
      onChange(selectedBookUuids.filter((uuid) => uuid !== bookUuid));
      return;
    }

    onChange([...selectedBookUuids, bookUuid]);
  };

  const handleSelectAll = () => {
    onChange(books.map((book) => book.bookUuid));
  };

  const handleClearAll = () => {
    onChange([]);
  };

  const selectedBooks = books.filter((book) => selectedBookUuids.includes(book.bookUuid));
  const displayText =
    selectedBooks.length === 0
      ? 'Select books'
      : selectedBooks.length === books.length
      ? 'All books selected'
      : selectedBooks.length === 1
      ? selectedBooks[0].name
      : `${selectedBooks.length} books selected`;
  const pillText = books.length === 0 ? '0' : `${selectedBooks.length}/${books.length}`;

  return (
    <div ref={dropdownRef} className="today-book-selector">
      <button
        type="button"
        className="today-book-selector__trigger"
        onClick={() => setIsOpen((previous) => !previous)}
        aria-expanded={isOpen}
        aria-controls={menuId}
      >
        <span className="today-book-selector__display">{displayText}</span>
        <span className="today-book-selector__pill">{pillText}</span>
        <ChevronDown className={`today-book-selector__chevron ${isOpen ? 'is-open' : ''}`} size={16} />
      </button>

      {isOpen && (
        <div id={menuId} className="today-book-selector__menu" role="listbox" aria-multiselectable="true">
          <div className="today-book-selector__actions">
            <button
              type="button"
              className="today-book-selector__action today-book-selector__action--primary"
              onClick={handleSelectAll}
            >
              Select all
            </button>
            <button
              type="button"
              className="today-book-selector__action"
              onClick={handleClearAll}
            >
              Clear
            </button>
          </div>

          <div className="today-book-selector__list">
            {books.length === 0 ? (
              <div className="today-book-selector__empty">No books available</div>
            ) : (
              books.map((book) => {
                const isSelected = selectedBookUuids.includes(book.bookUuid);

                return (
                  <button
                    key={book.bookUuid}
                    type="button"
                    className={`today-book-selector__item ${isSelected ? 'is-selected' : ''}`}
                    onClick={() => handleToggleBook(book.bookUuid)}
                    aria-pressed={isSelected}
                  >
                    <span className="today-book-selector__checkbox" aria-hidden="true">
                      {isSelected && <Check size={12} strokeWidth={3} />}
                    </span>
                    <span className="today-book-selector__book-name">{book.name}</span>
                    <span className="today-book-selector__event-count">{book.eventCount}</span>
                  </button>
                );
              })
            )}
          </div>
        </div>
      )}
    </div>
  );
};
