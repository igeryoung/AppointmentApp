// Dashboard API Response Types

export interface DashboardStats {
  devices: DeviceStats;
  books: BookStats;
  events: EventStats;
  notes: NoteStats;
  drawings: DrawingStats;
  backups: BackupStats;
  sync: SyncStats;
}

export interface DeviceStats {
  total: number;
  active: number;
  inactive: number;
  devices: Device[];
}

export interface Device {
  id: string;
  deviceName: string;
  platform: string;
  registeredAt: string;
  lastSyncAt: string | null;
  isActive: boolean;
}

export interface BookStats {
  total: number;
  active: number;
  archived: number;
  byDevice: Record<string, number>;
  books: Book[];
}

export interface Book {
  id: number;
  deviceId: string;
  name: string;
  createdAt: string;
  updatedAt: string;
  archivedAt: string | null;
  eventCount: number;
  noteCount: number;
  drawingCount: number;
}

export interface EventStats {
  total: number;
  active: number;
  removed: number;
  byType: Record<string, number>;
  byBook: Record<number, number>;
  recent: Event[];
}

export interface Event {
  id: number;
  bookId: number;
  bookName?: string;
  deviceId: string;
  name: string;
  recordNumber: string;
  eventType: string; // Legacy single event type
  eventTypes: string; // JSON array of event types
  startTime: string;
  endTime: string | null;
  isRemoved: boolean;
  removalReason?: string | null;
  isChecked: boolean;
  hasNote: boolean;
  originalEventId?: number | null;
  newEventId?: number | null;
  version: number;
  createdAt: string;
  updatedAt: string;
}

export interface NoteStats {
  total: number;
  eventsWithNotes: number;
  eventsWithoutNotes: number;
  recentlyUpdated: Note[];
}

export interface Note {
  id: number;
  eventId: number;
  deviceId: string;
  pagesData: string; // JSON string: array of pages, each page is array of strokes
  strokesData?: string; // Legacy single-page data
  createdAt: string;
  updatedAt: string;
  version: number;
}

// Handwriting stroke types for rendering
export interface StrokePoint {
  dx: number;
  dy: number;
  pressure: number;
}

export interface Stroke {
  points: StrokePoint[];
  strokeWidth: number;
  color: number; // ARGB color as integer
  strokeType: 'pen' | 'highlighter';
}

export type NotePage = Stroke[];
export type NotePages = NotePage[];

export interface DrawingStats {
  total: number;
  byViewMode: {
    day: number;
    threeDay: number;
    week: number;
  };
  recent: Drawing[];
}

export interface Drawing {
  id: number;
  bookId: number;
  deviceId: string;
  date: string;
  viewMode: number;
  createdAt: string;
  updatedAt: string;
  version: number;
}

export interface BackupStats {
  total: number;
  totalSizeBytes: number;
  totalSizeMB: string;
  recentBackups: Backup[];
  restoredCount: number;
}

export interface Backup {
  id: number;
  bookId: number;
  bookName: string;
  backupName: string;
  backupType: string;
  sizeBytes: number;
  sizeMB: string;
  isFileBased: boolean;
  createdAt: string;
  restoredAt: string | null;
}

export interface SyncStats {
  totalOperations: number;
  successfulSyncs: number;
  failedSyncs: number;
  conflictCount: number;
  successRate: number;
  recentSyncs: SyncOperation[];
}

export interface SyncOperation {
  id: number;
  deviceId: string;
  deviceName: string;
  operation: string;
  tableName: string;
  status: string;
  changesCount: number;
  errorMessage: string | null;
  syncedAt: string;
}

// Authentication Types
export interface LoginCredentials {
  username: string;
  password: string;
}

export interface AuthResponse {
  success: boolean;
  token?: string;
  message?: string;
}

// Filter Types
export interface DateRangeFilter {
  startDate: string;
  endDate: string;
}

export interface DashboardFilters {
  dateRange?: DateRangeFilter;
  deviceId?: string;
  bookId?: number;
  searchQuery?: string;
}

export interface EventFilters {
  bookId?: number;
  name?: string;
  recordNumber?: string;
}
