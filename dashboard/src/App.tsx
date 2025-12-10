import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { Sidebar } from './components/Sidebar';
import { Login } from './pages/Login';
import { Overview } from './pages/Overview';
import { TodayOverview } from './pages/TodayOverview';
import { Books } from './pages/Books';
import { EventsAndNotes } from './pages/EventsAndNotes';
import { EventDetail } from './pages/EventDetail';
import { Devices } from './pages/Devices';
import { dashboardAPI } from './services/api';
import './styles/index.css';

// Placeholder pages for other routes
const PlaceholderPage = ({ title }: { title: string }) => (
  <div>
    <div className="page-header">
      <h1 className="page-title">{title}</h1>
      <p className="page-subtitle">This page is under construction</p>
    </div>
    <div className="card">
      <div className="card-body" style={{ textAlign: 'center', padding: '3rem' }}>
        <p style={{ color: '#6b7280' }}>
          Detailed {title.toLowerCase()} monitoring view will be available soon.
        </p>
      </div>
    </div>
  </div>
);

function ProtectedRoute({ children }: { children: React.ReactNode }) {
  if (!dashboardAPI.isAuthenticated()) {
    return <Navigate to="/login" replace />;
  }
  return <>{children}</>;
}

function DashboardLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="dashboard-layout">
      <Sidebar />
      <main className="main-content">{children}</main>
    </div>
  );
}

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route
          path="/"
          element={
            <ProtectedRoute>
              <DashboardLayout>
                <Overview />
              </DashboardLayout>
            </ProtectedRoute>
          }
        />
        <Route
          path="/devices"
          element={
            <ProtectedRoute>
              <DashboardLayout>
                <Devices />
              </DashboardLayout>
            </ProtectedRoute>
          }
        />
        <Route
          path="/today"
          element={
            <ProtectedRoute>
              <DashboardLayout>
                <TodayOverview />
              </DashboardLayout>
            </ProtectedRoute>
          }
        />
        <Route
          path="/books"
          element={
            <ProtectedRoute>
              <DashboardLayout>
                <Books />
              </DashboardLayout>
            </ProtectedRoute>
          }
        />
        <Route
          path="/events"
          element={
            <ProtectedRoute>
              <DashboardLayout>
                <EventsAndNotes />
              </DashboardLayout>
            </ProtectedRoute>
          }
        />
        <Route
          path="/events/:eventId"
          element={
            <ProtectedRoute>
              <DashboardLayout>
                <EventDetail />
              </DashboardLayout>
            </ProtectedRoute>
          }
        />
        <Route
          path="/drawings"
          element={
            <ProtectedRoute>
              <DashboardLayout>
                <PlaceholderPage title="Drawings" />
              </DashboardLayout>
            </ProtectedRoute>
          }
        />
        <Route
          path="/backups"
          element={
            <ProtectedRoute>
              <DashboardLayout>
                <PlaceholderPage title="Backups" />
              </DashboardLayout>
            </ProtectedRoute>
          }
        />
        <Route
          path="/sync"
          element={
            <ProtectedRoute>
              <DashboardLayout>
                <PlaceholderPage title="Sync Logs" />
              </DashboardLayout>
            </ProtectedRoute>
          }
        />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  );
}

export default App;
