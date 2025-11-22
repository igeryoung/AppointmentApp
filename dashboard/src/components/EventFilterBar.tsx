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
    <div className="bg-white p-4 rounded-lg shadow-sm border border-gray-200 mb-4">
      <div className="flex flex-col gap-4">
        <h3 className="text-lg font-semibold text-gray-700">Filters</h3>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {/* Book Filter */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Book
            </label>
            <select
              value={filters.bookId || ''}
              onChange={handleBookChange}
              disabled={loading}
              className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
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
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Patient Name
            </label>
            <input
              type="text"
              value={filters.name || ''}
              onChange={handleNameChange}
              placeholder="Search by name..."
              className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>

          {/* Record Number Filter */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Record Number
            </label>
            <input
              type="text"
              value={filters.recordNumber || ''}
              onChange={handleRecordNumberChange}
              placeholder="Search by record number..."
              className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>
        </div>

        {/* Clear Filters Button */}
        {hasFilters && (
          <div className="flex justify-end">
            <button
              onClick={handleClear}
              className="px-4 py-2 text-sm bg-gray-200 text-gray-700 rounded hover:bg-gray-300"
            >
              Clear Filters
            </button>
          </div>
        )}
      </div>
    </div>
  );
};
