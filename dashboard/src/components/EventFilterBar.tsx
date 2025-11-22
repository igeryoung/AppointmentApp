import React, { useState, useEffect } from 'react';
import type { EventFilters, Book } from '../types';
import { dashboardAPI } from '../services/api';

interface EventFilterBarProps {
  filters: EventFilters;
  onFiltersChange: (filters: EventFilters) => void;
}

/**
 * Filter bar for events list
 * Allows filtering by book, patient name, and record number
 */
export const EventFilterBar: React.FC<EventFilterBarProps> = ({
  filters,
  onFiltersChange,
}) => {
  const [books, setBooks] = useState<Book[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadBooks();
  }, []);

  const loadBooks = async () => {
    try {
      const response = await dashboardAPI.getBooks();
      setBooks(response.books || []);
    } catch (error) {
      console.error('Failed to load books:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleBookChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
    const value = e.target.value;
    onFiltersChange({
      ...filters,
      bookId: value ? parseInt(value) : undefined,
    });
  };

  const handleNameChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    onFiltersChange({
      ...filters,
      name: e.target.value || undefined,
    });
  };

  const handleRecordNumberChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    onFiltersChange({
      ...filters,
      recordNumber: e.target.value || undefined,
    });
  };

  const handleClear = () => {
    onFiltersChange({});
  };

  const hasFilters = filters.bookId || filters.name || filters.recordNumber;

  return (
    <div className="card" style={{ marginBottom: '1.5rem' }}>
      <div className="card-header">
        <h3 className="card-title">Filters</h3>
        {hasFilters && (
          <button onClick={handleClear} className="btn btn-secondary btn-sm">
            Clear Filters
          </button>
        )}
      </div>
      <div className="card-body">
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(250px, 1fr))', gap: '1rem' }}>
          {/* Book Filter */}
          <div>
            <label style={{ display: 'block', marginBottom: '0.5rem', fontSize: '0.875rem', fontWeight: '500' }}>
              Book
            </label>
            <select
              value={filters.bookId || ''}
              onChange={handleBookChange}
              disabled={loading}
              style={{
                width: '100%',
                padding: '0.5rem 0.75rem',
                border: '1px solid #e5e7eb',
                borderRadius: '0.375rem',
                fontSize: '0.875rem',
              }}
            >
              <option value="">All Books</option>
              {books.map((book) => (
                <option key={book.id} value={book.id}>
                  {book.name}
                </option>
              ))}
            </select>
          </div>

          {/* Patient Name Filter */}
          <div>
            <label style={{ display: 'block', marginBottom: '0.5rem', fontSize: '0.875rem', fontWeight: '500' }}>
              Patient Name
            </label>
            <input
              type="text"
              value={filters.name || ''}
              onChange={handleNameChange}
              placeholder="Search by name..."
              className="input"
            />
          </div>

          {/* Record Number Filter */}
          <div>
            <label style={{ display: 'block', marginBottom: '0.5rem', fontSize: '0.875rem', fontWeight: '500' }}>
              Record Number
            </label>
            <input
              type="text"
              value={filters.recordNumber || ''}
              onChange={handleRecordNumberChange}
              placeholder="Search by record number..."
              className="input"
            />
          </div>
        </div>
      </div>
    </div>
  );
};
