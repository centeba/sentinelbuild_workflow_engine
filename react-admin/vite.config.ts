import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// The workflow-engine API is served under /api/v1. In dev we proxy it to the
// backend so the browser makes same-origin requests. Override with VITE_API_TARGET.
const API_TARGET = process.env.VITE_API_TARGET || "http://localhost:8000";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5175,
    proxy: {
      "/api": { target: API_TARGET, changeOrigin: true },
    },
  },
});
