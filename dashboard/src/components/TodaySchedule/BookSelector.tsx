import React, { useState, useRef, useEffect } from 'react';
import { ChevronDown } from 'lucide-react';
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

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };

    if (isOpen) {
      document.addEventListener('mousedown', handleClickOutside);
    }

    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, [isOpen]);

  const handleToggleBook = (bookUuid: string) => {
    if (selectedBookUuids.includes(bookUuid)) {
      onChange(selectedBookUuids.filter((uuid) => uuid !== bookUuid));
    } else {
      onChange([...selectedBookUuids, bookUuid]);
    }
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
      ? 'Select books...'
      : selectedBooks.length === books.length
      ? 'All books'
      : selectedBooks.length === 1
      ? selectedBooks[0].name
      : `${selectedBooks.length} books selected`;

  return (
    <div ref={dropdownRef} style={{ position: 'relative', minWidth: '250px' }}>
      {/* Dropdown trigger */}
      <button
        onClick={() => setIsOpen(!isOpen)}
        style={{
          width: '100%',
          padding: '8px 12px',
          border: '1px solid #d1d5db',
          borderRadius: '6px',
          backgroundColor: 'white',
          cursor: 'pointer',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          fontSize: '14px',
          color: selectedBooks.length === 0 ? '#9ca3af' : '#1e293b',
          transition: 'border-color 0.2s',
        }}
        onMouseEnter={(e) => {
          e.currentTarget.style.borderColor = '#3b82f6';
        }}
        onMouseLeave={(e) => {
          e.currentTarget.style.borderColor = '#d1d5db';
        }}
      >
        <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {displayText}
        </span>
        <ChevronDown
          size={16}
          style={{
            marginLeft: '8px',
            flexShrink: 0,
            transform: isOpen ? 'rotate(180deg)' : 'rotate(0deg)',
            transition: 'transform 0.2s',
          }}
        />
      </button>

      {/* Dropdown menu */}
      {isOpen && (
        <div
          style={{
            position: 'absolute',
            top: 'calc(100% + 4px)',
            left: 0,
            right: 0,
            backgroundColor: 'white',
            border: '1px solid #d1d5db',
            borderRadius: '6px',
            boxShadow: '0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06)',
            zIndex: 1000,
            maxHeight: '300px',
            overflowY: 'auto',
          }}
        >
          {/* Action buttons */}
          <div
            style={{
              padding: '8px',
              borderBottom: '1px solid #e5e7eb',
              display: 'flex',
              gap: '8px',
            }}
          >
            <button
              onClick={handleSelectAll}
              style={{
                flex: 1,
                padding: '6px 12px',
                fontSize: '12px',
                border: '1px solid #d1d5db',
                borderRadius: '4px',
                backgroundColor: 'white',
                cursor: 'pointer',
                color: '#3b82f6',
                fontWeight: 500,
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.backgroundColor = '#eff6ff';
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.backgroundColor = 'white';
              }}
            >
              Select All
            </button>
            <button
              onClick={handleClearAll}
              style={{
                flex: 1,
                padding: '6px 12px',
                fontSize: '12px',
                border: '1px solid #d1d5db',
                borderRadius: '4px',
                backgroundColor: 'white',
                cursor: 'pointer',
                color: '#64748b',
                fontWeight: 500,
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.backgroundColor = '#f8fafc';
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.backgroundColor = 'white';
              }}
            >
              Clear All
            </button>
          </div>

          {/* Book list */}
          <div style={{ padding: '4px' }}>
            {books.length === 0 ? (
              <div
                style={{
                  padding: '16px',
                  textAlign: 'center',
                  color: '#9ca3af',
                  fontSize: '14px',
                }}
              >
                No books available
              </div>
            ) : (
              books.map((book) => {
                const isSelected = selectedBookUuids.includes(book.bookUuid);

                return (
                  <div
                    key={book.bookUuid}
                    onClick={() => handleToggleBook(book.bookUuid)}
                    style={{
                      padding: '8px 12px',
                      cursor: 'pointer',
                      borderRadius: '4px',
                      display: 'flex',
                      alignItems: 'center',
                      gap: '8px',
                      backgroundColor: isSelected ? '#eff6ff' : 'transparent',
                      transition: 'background-color 0.1s',
                    }}
                    onMouseEnter={(e) => {
                      if (!isSelected) {
                        e.currentTarget.style.backgroundColor = '#f8fafc';
                      }
                    }}
                    onMouseLeave={(e) => {
                      if (!isSelected) {
                        e.currentTarget.style.backgroundColor = 'transparent';
                      }
                    }}
                  >
                    {/* Checkbox */}
                    <div
                      style={{
                        width: '16px',
                        height: '16px',
                        border: isSelected ? '2px solid #3b82f6' : '2px solid #d1d5db',
                        borderRadius: '3px',
                        backgroundColor: isSelected ? '#3b82f6' : 'white',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        flexShrink: 0,
                      }}
                    >
                      {isSelected && (
                        <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
                          <path
                            d="M1 5L4 8L9 2"
                            stroke="white"
                            strokeWidth="2"
                            strokeLinecap="round"
                            strokeLinejoin="round"
                          />
                        </svg>
                      )}
                    </div>

                    {/* Book name */}
                    <span
                      style={{
                        fontSize: '14px',
                        color: '#1e293b',
                        fontWeight: isSelected ? 500 : 400,
                      }}
                    >
                      {book.name}
                    </span>

                    {/* Event count */}
                    <span
                      style={{
                        marginLeft: 'auto',
                        fontSize: '12px',
                        color: '#64748b',
                      }}
                    >
                      {book.eventCount} events
                    </span>
                  </div>
                );
              })
            )}
          </div>
        </div>
      )}
    </div>
  );
};
