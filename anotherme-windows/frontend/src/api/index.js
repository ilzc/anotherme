// Demo mode: set VITE_DEMO=true to use mock data for screenshots/previews.
// Default: use real Wails bindings.
let api

if (import.meta.env.VITE_DEMO === 'true') {
  api = await import('./mock.js')
} else if (window.go?.main?.App) {
  // Wails runtime injects window.go at startup
  api = window.go.main.App
} else {
  // Fallback to mock when running outside Wails (e.g. npm run dev)
  console.warn('[AnotherMe] Wails runtime not detected, falling back to mock data')
  api = await import('./mock.js')
}

export default api
