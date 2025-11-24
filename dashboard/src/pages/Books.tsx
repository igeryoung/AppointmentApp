import { useState, useEffect } from 'react';
import { Search, Download, RefreshCw } from 'lucide-react';
import { dashboardAPI } from '../services/api';
import type { Book } from '../types';

export function Books() {
  const [books, setBooks] = useState<Book[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [showArchived, setShowArchived] = useState(false);

  const fetchBooks = async () => {
    try {
      setLoading(true);
      const data = await dashboardAPI.getBooks();
      setBooks(data.books || []);
    } catch (error) {
      console.error('Failed to fetch books:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchBooks();
  }, []);

  const filteredBooks = books.filter((book) => {
    const matchesSearch = book.name.toLowerCase().includes(searchQuery.toLowerCase());
    const matchesArchived = showArchived || !book.archivedAt;
    return matchesSearch && matchesArchived;
  });

  const handleExport = async () => {
    await dashboardAPI.exportData('books', 'csv', { searchQuery });
  };

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Books</h1>
        <p className="page-subtitle">Manage and monitor all appointment books</p>
      </div>

      <div className="toolbar">
        <div className="toolbar-section">
          <button onClick={fetchBooks} className="btn btn-primary btn-sm" disabled={loading}>
            <RefreshCw size={16} />
            Refresh
          </button>
          <button onClick={handleExport} className="btn btn-secondary btn-sm">
            <Download size={16} />
            Export
          </button>
        </div>

        <div className="toolbar-section">
          <div style={{ position: 'relative' }}>
            <Search
              size={16}
              style={{
                position: 'absolute',
                left: '0.75rem',
                top: '50%',
                transform: 'translateY(-50%)',
                color: '#6b7280',
              }}
            />
            <input
              type="text"
              placeholder="Search books..."
              className="input"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              style={{ paddingLeft: '2.5rem' }}
            />
          </div>

          <label style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.875rem' }}>
            <input
              type="checkbox"
              checked={showArchived}
              onChange={(e) => setShowArchived(e.target.checked)}
            />
            Show Archived
          </label>
        </div>
      </div>

      <div className="card">
        <div className="card-header">
          <h2 className="card-title">All Books ({filteredBooks.length})</h2>
        </div>
        <div className="card-body">
          {loading ? (
            <div className="loading">
              <div className="spinner"></div>
              <p>Loading books...</p>
            </div>
          ) : filteredBooks.length === 0 ? (
            <div style={{ textAlign: 'center', padding: '3rem', color: '#6b7280' }}>
              No books found
            </div>
          ) : (
            <div className="table-container">
              <table>
                <thead>
                  <tr>
                    <th>ID</th>
                    <th>Name</th>
                    <th>Device ID</th>
                    <th>Events</th>
                    <th>Notes</th>
                    <th>Drawings</th>
                    <th>Created</th>
                    <th>Status</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredBooks.map((book) => (
                    <tr key={book.bookUuid}>
                      <td style={{ fontFamily: 'monospace', fontSize: '0.75rem' }}>
                        {book.bookUuid.substring(0, 5)}
                      </td>
                      <td style={{ fontWeight: '500' }}>{book.name}</td>
                      <td style={{ fontFamily: 'monospace', fontSize: '0.75rem' }}>
                        {book.deviceId.substring(0, 8)}...
                      </td>
                      <td>{book.eventCount}</td>
                      <td>{book.noteCount}</td>
                      <td>{book.drawingCount}</td>
                      <td>{new Date(book.createdAt).toLocaleDateString()}</td>
                      <td>
                        {book.archivedAt ? (
                          <span className="badge badge-warning">Archived</span>
                        ) : (
                          <span className="badge badge-success">Active</span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
