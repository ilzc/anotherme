<script setup>
import { ref, onMounted } from 'vue'
import { useAppStore } from '../stores/app'
import StatCard from '../components/StatCard.vue'
import ActivityItem from '../components/ActivityItem.vue'

const appStore = useAppStore()
const stats = ref(null)
const activities = ref([])
const snapshot = ref(null)
const loading = ref(true)
const error = ref(null)

async function loadData() {
  loading.value = true
  error.value = null
  try {
    const api = (await import('../api/index.js')).default
    const [s, a, sn] = await Promise.all([
      api.GetDashboardStats(),
      api.GetTodayActivities(10),
      api.GetPersonalitySnapshot().catch(() => null)
    ])
    stats.value = s
    activities.value = a
    snapshot.value = sn
    appStore.captureRunning = s.captureRunning
    appStore.captureCount = s.todayCaptureCount
  } catch (e) {
    error.value = 'Failed to load data: ' + e.message
  } finally {
    loading.value = false
  }
}

async function toggleCapture() {
  if (appStore.captureRunning) {
    await appStore.stopCapture()
  } else {
    await appStore.startCapture()
  }
}

onMounted(loadData)
</script>

<template>
  <div class="p-6">
    <h2 class="text-2xl font-bold text-white mb-6">Dashboard</h2>

    <!-- Error -->
    <div v-if="error" class="mb-4 p-3 bg-red-600/20 border border-red-600/50 rounded-lg text-red-400 text-sm">
      {{ error }}
    </div>

    <!-- Loading -->
    <div v-if="loading" class="flex items-center justify-center py-20">
      <div class="flex items-center gap-3 text-gray-400">
        <svg class="animate-spin w-5 h-5" viewBox="0 0 24 24" fill="none">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/>
        </svg>
        <span>Loading...</span>
      </div>
    </div>

    <template v-else-if="stats">
      <!-- Stats Cards -->
      <div class="grid grid-cols-2 xl:grid-cols-4 gap-4 mb-6">
        <StatCard
          label="Total Activities"
          :value="stats.totalActivities"
          color="primary"
          :icon="`<svg class='w-5 h-5' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2'><polyline points='22 12 18 12 15 21 9 3 6 12 2 12'/></svg>`"
        />
        <StatCard
          label="Today's Activities"
          :value="stats.todayActivities"
          color="green"
          :icon="`<svg class='w-5 h-5' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2'><circle cx='12' cy='12' r='10'/><polyline points='12 6 12 12 16 14'/></svg>`"
        />
        <StatCard
          label="Total Memories"
          :value="stats.totalMemories"
          color="purple"
          :icon="`<svg class='w-5 h-5' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2'><path d='M12 2a9 9 0 0 1 9 9c0 3.9-2.5 7.2-6 8.4M12 2a9 9 0 0 0-9 9c0 3.9 2.5 7.2 6 8.4M12 2v4m0 16v-4m0 0a4 4 0 1 0 0-8 4 4 0 0 0 0 8z'/></svg>`"
        />

        <!-- Capture Status Card -->
        <div class="card flex items-start gap-4">
          <div :class="[
            'w-10 h-10 rounded-lg flex items-center justify-center shrink-0',
            appStore.captureRunning ? 'bg-green-600/20 text-green-400' : 'bg-gray-600/20 text-gray-400'
          ]">
            <svg class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <circle cx="12" cy="12" r="10"/>
              <circle cx="12" cy="12" r="3"/>
            </svg>
          </div>
          <div class="min-w-0 flex-1">
            <p class="text-sm text-gray-400">Screen Capture</p>
            <p class="text-sm font-medium text-white mt-0.5">
              {{ appStore.captureRunning ? 'Running' : 'Stopped' }}
            </p>
            <button
              @click="toggleCapture"
              :disabled="appStore.loading"
              :class="[
                'mt-2 text-xs px-3 py-1 rounded-full font-medium transition-default',
                appStore.captureRunning
                  ? 'bg-red-600/20 text-red-400 hover:bg-red-600/30'
                  : 'bg-green-600/20 text-green-400 hover:bg-green-600/30'
              ]"
            >
              {{ appStore.captureRunning ? 'Stop' : 'Start' }}
            </button>
          </div>
        </div>
      </div>

      <!-- Main Content Grid -->
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Activity Timeline -->
        <div class="col-span-2">
          <h3 class="text-lg font-semibold text-white mb-4">Today's Activities</h3>
          <div class="card p-0 max-h-[500px] overflow-y-auto">
            <template v-if="activities.length">
              <ActivityItem
                v-for="act in activities"
                :key="act.id"
                :activity="act"
              />
            </template>
            <div v-else class="p-8 text-center text-gray-500">
              <p>No activity recorded today</p>
              <p class="text-xs mt-1">Activities will be recorded automatically once Screen Capture is started</p>
            </div>
          </div>
        </div>

        <!-- Personality Overview -->
        <div>
          <h3 class="text-lg font-semibold text-white mb-4">Personality Overview</h3>
          <div class="card">
            <template v-if="snapshot">
              <p class="text-sm text-gray-300 leading-relaxed mb-3">
                {{ snapshot?.summary?.slice(0, 150) || 'No summary available' }}...
              </p>
              <div v-if="snapshot?.keyTraits?.length" class="flex flex-wrap gap-1.5 mb-3">
                <span
                  v-for="trait in snapshot.keyTraits"
                  :key="trait"
                  class="badge bg-accent-500/20 text-accent-400"
                >
                  {{ trait }}
                </span>
              </div>
              <p v-if="snapshot?.version" class="text-xs text-gray-500">
                Version {{ snapshot.version }} &middot;
                Generated {{ snapshot.generatedAt ? new Date(snapshot.generatedAt).toLocaleDateString('en-US') : '' }}
              </p>
            </template>
            <div v-else class="text-center py-4">
              <p class="text-gray-500 text-sm">Gathering data</p>
              <p class="text-xs text-gray-600 mt-1">Please run Screen Capture for a while first</p>
            </div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
