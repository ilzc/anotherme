import { defineStore } from 'pinia'
import { ref } from 'vue'

export const useAppStore = defineStore('app', () => {
  const captureRunning = ref(false)
  const captureCount = ref(0)
  const loading = ref(false)
  const error = ref(null)

  async function startCapture() {
    loading.value = true
    error.value = null
    try {
      const api = (await import('../api/index.js')).default
      await api.StartCapture()
      captureRunning.value = true
    } catch (e) {
      error.value = 'Failed to start capture: ' + e.message
    } finally {
      loading.value = false
    }
  }

  async function stopCapture() {
    loading.value = true
    error.value = null
    try {
      const api = (await import('../api/index.js')).default
      await api.StopCapture()
      captureRunning.value = false
    } catch (e) {
      error.value = 'Failed to stop capture: ' + e.message
    } finally {
      loading.value = false
    }
  }

  async function fetchCaptureStatus() {
    try {
      const api = (await import('../api/index.js')).default
      const status = await api.GetCaptureStatus()
      captureRunning.value = status.running
      captureCount.value = status.count
    } catch (e) {
      error.value = 'Failed to get capture status: ' + e.message
    }
  }

  return {
    captureRunning,
    captureCount,
    loading,
    error,
    startCapture,
    stopCapture,
    fetchCaptureStatus
  }
})
