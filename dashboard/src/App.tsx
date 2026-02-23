import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { Sidebar } from './components/Sidebar';
import { Login } from './pages/Login';
import { TodayOverview } from './pages/TodayOverview';
import { Books } from './pages/Books';
import { Records } from './pages/Records';
import { RecordDetail } from './pages/RecordDetail';
import { EventsAndNotes } from './pages/EventsAndNotes';
import { EventDetail } from './pages/EventDetail';
import { Devices } from './pages/Devices';
import { dashboardAPI } from './services/api';
import './styles/index.css';

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
              <Navigate to="/today" replace />
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
          path="/records"
          element={
            <ProtectedRoute>
              <DashboardLayout>
                <Records />
              </DashboardLayout>
            </ProtectedRoute>
          }
        />
        <Route
          path="/records/:recordUuid"
          element={
            <ProtectedRoute>
              <DashboardLayout>
                <RecordDetail />
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
        <Route path="*" element={<Navigate to="/today" replace />} />
      </Routes>
    </BrowserRouter>
  );
}

export default App;
