import axios, { AxiosInstance } from 'axios';
import type {
  DashboardStats,
  AuthResponse,
  LoginCredentials,
  DashboardFilters,
  RecordSummary,
  Event,
  Note,
  EventFilters,
  RecordFilters,
} from '../types';
import { parseEventTypes } from '../utils/event';

type RawEvent = Omit<Event, 'eventTypes'> & {
  eventTypes?: string | string[] | null;
};

class DashboardAPI {
  private client: AxiosInstance;
  private token: string | null = null;

  constructor() {
    this.client = axios.create({
      baseURL: '/api/dashboard',
      headers: {
        'Content-Type': 'application/json',
      },
    });

    // Load token from localStorage
    this.token = localStorage.getItem('dashboardToken');
    if (this.token) {
      this.setAuthHeader(this.token);
    }

    // Add response interceptor for auth errors
    this.client.interceptors.response.use(
      (response) => response,
      (error) => {
        if (error.response?.status === 401) {
          this.logout();
          window.location.href = '/login';
        }
        return Promise.reject(error);
      }
    );
  }

  private setAuthHeader(token: string) {
    this.client.defaults.headers.common['Authorization'] = `Bearer ${token}`;
  }

  private normalizeEvent(event: RawEvent | Event): Event {
    return {
      ...event,
      eventTypes: parseEventTypes(event.eventTypes),
    };
  }

  private normalizeEvents(events: Array<RawEvent | Event> = []): Event[] {
    return events.map((event) => this.normalizeEvent(event));
  }

  // Authentication
  async login(credentials: LoginCredentials): Promise<AuthResponse> {
    const response = await this.client.post<AuthResponse>('/auth/login', credentials);
    if (response.data.success && response.data.token) {
      this.token = response.data.token;
      localStorage.setItem('dashboardToken', this.token);
      this.setAuthHeader(this.token);
    }
    return response.data;
  }

  logout() {
    this.token = null;
    localStorage.removeItem('dashboardToken');
    delete this.client.defaults.headers.common['Authorization'];
  }

  isAuthenticated(): boolean {
    return this.token !== null;
  }

  // Dashboard Data
  async getStats(filters?: DashboardFilters): Promise<DashboardStats> {
    const response = await this.client.get<DashboardStats>('/stats', {
      params: filters,
    });
    const stats = response.data;
    stats.events.recent = this.normalizeEvents(stats.events.recent);
    return stats;
  }

  async getDevices(filters?: DashboardFilters) {
    const response = await this.client.get('/devices', { params: filters });
    return response.data;
  }

  async getBooks(filters?: DashboardFilters) {
    const response = await this.client.get('/books', { params: filters });
    return response.data;
  }

  async getRecords(filters?: RecordFilters): Promise<{ records: RecordSummary[] }> {
    const response = await this.client.get<{ records: RecordSummary[] }>('/records', { params: filters });
    return response.data;
  }

  async getEvents(filters?: DashboardFilters) {
    const response = await this.client.get('/events', { params: filters });
    return response.data;
  }

  async getNotes(filters?: DashboardFilters) {
    const response = await this.client.get('/notes', { params: filters });
    return response.data;
  }

  async getDrawings(filters?: DashboardFilters) {
    const response = await this.client.get('/drawings', { params: filters });
    return response.data;
  }

  async getBackups(filters?: DashboardFilters) {
    const response = await this.client.get('/backups', { params: filters });
    return response.data;
  }

  async getSyncLogs(filters?: DashboardFilters) {
    const response = await this.client.get('/sync-logs', { params: filters });
    return response.data;
  }

  // Events & Notes - New Endpoints
  async getFilteredEvents(filters: EventFilters): Promise<{ events: Event[] }> {
    // Always include 'list' param to tell backend we want the events list, not stats
    const params = { ...filters, list: true };
    const response = await this.client.get<{ events: RawEvent[] }>('/events', { params });
    return {
      events: this.normalizeEvents(response.data.events),
    };
  }

  async getEventDetail(eventId: string): Promise<Event> {
    const response = await this.client.get<RawEvent>(`/events/${eventId}`);
    return this.normalizeEvent(response.data);
  }

  async getEventNote(eventId: string): Promise<Note> {
    const response = await this.client.get<Note>(`/events/${eventId}/note`);
    return response.data;
  }

  // Export functionality
  async exportData(endpoint: string, format: 'csv' | 'json', filters?: DashboardFilters) {
    const response = await this.client.get(`/${endpoint}/export`, {
      params: { ...filters, format },
      responseType: 'blob',
    });

    // Create download link
    const url = window.URL.createObjectURL(new Blob([response.data]));
    const link = document.createElement('a');
    link.href = url;
    link.setAttribute('download', `${endpoint}-export-${Date.now()}.${format}`);
    document.body.appendChild(link);
    link.click();
    link.remove();
  }
}

export const dashboardAPI = new DashboardAPI();
