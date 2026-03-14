import { defineStore } from 'pinia'
import { ref } from 'vue'

export const usePersonalityStore = defineStore('personality', () => {
  const layers = ref({ 1: [], 2: [], 3: [], 4: [], 5: [] })
  const snapshot = ref(null)
  const loading = ref(false)

  async function fetchAllLayers() {
    loading.value = true
    try {
      const api = (await import('../api/index.js')).default
      const result = await api.GetAllPersonalityLayers()
      layers.value = result
    } catch (e) {
      console.error('Failed to fetch personality layer data:', e)
    } finally {
      loading.value = false
    }
  }

  async function fetchLayer(n) {
    loading.value = true
    try {
      const api = (await import('../api/index.js')).default
      const result = await api.GetPersonalityLayer(n)
      layers.value[n] = result
    } catch (e) {
      console.error(`Failed to fetch Layer ${n} data:`, e)
    } finally {
      loading.value = false
    }
  }

  async function fetchSnapshot() {
    try {
      const api = (await import('../api/index.js')).default
      snapshot.value = await api.GetPersonalitySnapshot()
    } catch (e) {
      console.error('Failed to fetch personality snapshot:', e)
    }
  }

  return {
    layers,
    snapshot,
    loading,
    fetchAllLayers,
    fetchLayer,
    fetchSnapshot
  }
})
