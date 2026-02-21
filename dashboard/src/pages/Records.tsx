import { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { RefreshCw, Search } from 'lucide-react';
import { dashboardAPI } from '../services/api';
import type { RecordSummary } from '../types';
import { parseServerDate } from '../utils/date';
import { formatShortId } from '../utils/id';

const PAGE_SIZE = 30;

export function Records() {
  const navigate = useNavigate();
  const [records, setRecords] = useState<RecordSummary[]>([]);
  const [totalRecords, setTotalRecords] = useState(0);
  const [currentPage, setCurrentPage] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchInput, setSearchInput] = useState('');
  const [searchQuery, setSearchQuery] = useState('');

  const loadRecords = useCallback(async (page: number, query: string) => {
    try {
      setLoading(true);
      setError(null);

      const filters = query ? { searchQuery: query } : undefined;
      const data = await dashboardAPI.getRecords(
        filters,
        { limit: PAGE_SIZE, offset: page * PAGE_SIZE },
      );

      if (data.total > 0 && page * PAGE_SIZE >= data.total) {
        setCurrentPage(Math.max(0, Math.ceil(data.total / PAGE_SIZE) - 1));
        return;
      }

      setRecords(data.records || []);
      setTotalRecords(data.total);
    } catch (err) {
      console.error('Failed to fetch records:', err);
      setError('Failed to load records. Please try again.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    const timeoutId = window.setTimeout(() => {
      const normalizedQuery = searchInput.trim();
      setSearchQuery(normalizedQuery);
      setCurrentPage(0);
    }, 300);

    return () => window.clearTimeout(timeoutId);
  }, [searchInput]);

  useEffect(() => {
    loadRecords(currentPage, searchQuery);
  }, [currentPage, searchQuery, loadRecords]);

  const totalPages = Math.max(1, Math.ceil(totalRecords / PAGE_SIZE));
  const hasPreviousPage = currentPage > 0;
  const hasNextPage = (currentPage + 1) * PAGE_SIZE < totalRecords;
  const pageStart = totalRecords === 0 ? 0 : currentPage * PAGE_SIZE + 1;
  const pageEnd = totalRecords === 0 ? 0 : Math.min(totalRecords, (currentPage + 1) * PAGE_SIZE);

  const handleRefresh = () => {
    loadRecords(currentPage, searchQuery);
  };

  const formatDateTime = (value?: string | null) => {
    const date = parseServerDate(value);
    if (!date) {
      return '-';
    }
    return date.toLocaleString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Records</h1>
        <p className="page-subtitle">View all records with record numbers and contact details</p>
      </div>

      <div className="toolbar">
        <div className="toolbar-section">
          <button onClick={handleRefresh} className="btn btn-primary btn-sm" disabled={loading}>
            <RefreshCw size={16} />
            {loading ? 'Loading...' : 'Refresh'}
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
              placeholder="Search by name, record number, phone, or ID..."
              className="input"
              value={searchInput}
              onChange={(e) => setSearchInput(e.target.value)}
              style={{ paddingLeft: '2.5rem' }}
            />
          </div>
        </div>
      </div>

      {error && (
        <div className="card" style={{ marginBottom: '1.5rem', backgroundColor: '#fef2f2', borderLeft: '4px solid #ef4444' }}>
          <div className="card-body" style={{ color: '#dc2626' }}>
            {error}
          </div>
        </div>
      )}

      <div className="card">
        <div className="card-header">
          <h2 className="card-title">All Records ({totalRecords})</h2>
        </div>
        <div className="card-body">
          {loading ? (
            <div className="loading">
              <div className="spinner"></div>
              <p>Loading records...</p>
            </div>
          ) : records.length === 0 ? (
            <div style={{ textAlign: 'center', padding: '3rem', color: '#6b7280' }}>
              No records found
            </div>
          ) : (
            <div className="table-container">
              <table>
                <thead>
                  <tr>
                    <th>ID</th>
                    <th>Name</th>
                    <th>Record #</th>
                    <th>Phone</th>
                    <th style={{ textAlign: 'center' }}>Events</th>
                    <th style={{ textAlign: 'center' }}>Note</th>
                    <th>Created</th>
                    <th>Updated</th>
                    <th style={{ textAlign: 'center' }}>Version</th>
                  </tr>
                </thead>
                <tbody>
                  {records.map((record) => (
                    <tr
                      key={record.recordUuid}
                      onClick={() => navigate(`/records/${record.recordUuid}`)}
                      style={{ cursor: 'pointer' }}
                    >
                      <td style={{ fontFamily: 'monospace', fontSize: '0.75rem' }}>
                        {formatShortId(record.recordUuid)}
                      </td>
                      <td style={{ fontWeight: '500' }}>{record.name || '-'}</td>
                      <td style={{ fontFamily: 'monospace', fontSize: '0.75rem' }}>
                        {record.recordNumber || '-'}
                      </td>
                      <td style={{ fontFamily: 'monospace', fontSize: '0.75rem' }}>
                        {record.phone || '-'}
                      </td>
                      <td style={{ textAlign: 'center' }}>{record.eventCount}</td>
                      <td style={{ textAlign: 'center' }}>
                        {record.hasNote ? (
                          <span className="badge badge-success">Yes</span>
                        ) : (
                          <span className="badge badge-warning">No</span>
                        )}
                      </td>
                      <td style={{ fontSize: '0.813rem' }}>{formatDateTime(record.createdAt)}</td>
                      <td style={{ fontSize: '0.813rem' }}>{formatDateTime(record.updatedAt)}</td>
                      <td style={{ textAlign: 'center' }}>{record.version}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          {!loading && totalRecords > 0 && (
            <div className="toolbar" style={{ marginTop: '1rem', padding: 0 }}>
              <div className="toolbar-section">
                <span style={{ color: '#6b7280', fontSize: '0.875rem' }}>
                  Showing {pageStart}-{pageEnd} of {totalRecords}
                </span>
              </div>
              <div className="toolbar-section">
                <button
                  onClick={() => setCurrentPage((page) => Math.max(0, page - 1))}
                  className="btn btn-secondary btn-sm"
                  disabled={!hasPreviousPage || loading}
                >
                  Previous
                </button>
                <span style={{ color: '#374151', fontSize: '0.875rem' }}>
                  Page {currentPage + 1} of {totalPages}
                </span>
                <button
                  onClick={() => setCurrentPage((page) => page + 1)}
                  className="btn btn-secondary btn-sm"
                  disabled={!hasNextPage || loading}
                >
                  Next
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
