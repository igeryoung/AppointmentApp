import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Backend server configuration
// Update this to match your server's SERVER_PORT setting in ../.env
// Default with SSL: https://localhost:8443
// Custom port (8080): https://localhost:8080
const BACKEND_URL = process.env.VITE_BACKEND_URL || 'https://localhost:8080';

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
    proxy: {
      '/api': {
        target: BACKEND_URL,
        changeOrigin: true,
        secure: false, // Allow self-signed certificates in development
      },
    },
  },
})
