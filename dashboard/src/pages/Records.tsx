import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { RefreshCw, Search } from 'lucide-react';
import { dashboardAPI } from '../services/api';
import type { RecordSummary } from '../types';
import { parseServerDate } from '../utils/date';
import { formatShortId } from '../utils/id';

export function Records() {
  const navigate = useNavigate();
  const [records, setRecords] = useState<RecordSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');

  const fetchRecords = async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await dashboardAPI.getRecords();
      setRecords(data.records || []);
    } catch (err) {
      console.error('Failed to fetch records:', err);
      setError('Failed to load records. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchRecords();
  }, []);

  const filteredRecords = useMemo(() => {
    const query = searchQuery.trim().toLowerCase();
    if (!query) {
      return records;
    }

    return records.filter((record) => {
      const name = record.name?.toLowerCase() ?? '';
      const recordNumber = record.recordNumber?.toLowerCase() ?? '';
      const phone = record.phone?.toLowerCase() ?? '';
      const uuid = record.recordUuid.toLowerCase();
      return (
        name.includes(query) ||
        recordNumber.includes(query) ||
        phone.includes(query) ||
        uuid.includes(query)
      );
    });
  }, [records, searchQuery]);

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
          <button onClick={fetchRecords} className="btn btn-primary btn-sm" disabled={loading}>
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
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
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
          <h2 className="card-title">All Records ({filteredRecords.length})</h2>
        </div>
        <div className="card-body">
          {loading ? (
            <div className="loading">
              <div className="spinner"></div>
              <p>Loading records...</p>
            </div>
          ) : filteredRecords.length === 0 ? (
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
                  {filteredRecords.map((record) => (
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
        </div>
      </div>
    </div>
  );
}
