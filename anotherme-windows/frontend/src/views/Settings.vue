<script setup>
import { ref, onMounted } from 'vue'
import { useAppStore } from '../stores/app'

const appStore = useAppStore()
const loading = ref(true)
const saving = ref(false)
const error = ref(null)
const successMsg = ref(null)

// Language
const language = ref('')
const languageOptions = [
  { value: '', label: 'Auto (System)' },
  { value: 'Chinese', label: '中文' },
  { value: 'English', label: 'English' },
  { value: 'Japanese', label: '日本語' },
  { value: 'Korean', label: '한국어' },
  { value: 'French', label: 'Français' },
  { value: 'German', label: 'Deutsch' },
  { value: 'Spanish', label: 'Español' },
]

// AI Model
const providerName = ref('')
const endpoint = ref('')
const apiKey = ref('')
const modelName = ref('')
const showApiKey = ref(false)
const testingConnection = ref(false)
const connectionResult = ref(null)

// Capture
const captureMode = ref('smart')
const intervalSeconds = ref(300)
const dailyLimit = ref(200)

// Blacklist
const blacklist = ref([])
const newBlacklistItem = ref('')
const blacklistDirty = ref(false)

// Data
const dataStats = ref(null)
const exporting = ref(false)
const exportFormat = ref('json')

const captureModes = [
  { value: 'interval', label: 'Timed Capture' },
  { value: 'event', label: 'Event-Triggered' },
  { value: 'smart', label: 'Smart Capture' }
]

const exportFormats = [
  { value: 'minimal', label: 'Minimal Text' },
  { value: 'card', label: 'Card Format' },
  { value: 'json', label: 'JSON' },
  { value: 'archive', label: 'Full Archive' }
]

function formatInterval(seconds) {
  if (seconds < 60) return `${seconds}s`
  return `${Math.round(seconds / 60)} min`
}

async function loadSettings() {
  loading.value = true
  try {
    const api = (await import('../api/index.js')).default
    const [settings, stats] = await Promise.all([
      api.GetSettings(),
      api.GetDataStats()
    ])
    language.value = settings.language || ''
    providerName.value = settings.ai.providerName
    endpoint.value = settings.ai.endpoint
    apiKey.value = settings.ai.apiKey
    modelName.value = settings.ai.modelName
    captureMode.value = settings.capture.mode
    intervalSeconds.value = settings.capture.intervalSeconds
    dailyLimit.value = settings.capture.dailyLimit
    blacklist.value = settings.blacklist
    blacklistDirty.value = false
    dataStats.value = stats
  } catch (e) {
    error.value = 'Failed to load settings: ' + e.message
  } finally {
    loading.value = false
  }
}

async function saveSettings() {
  saving.value = true
  error.value = null
  successMsg.value = null
  try {
    const api = (await import('../api/index.js')).default
    await api.SaveSettings({
      language: language.value,
      ai: {
        providerName: providerName.value,
        endpoint: endpoint.value,
        apiKey: apiKey.value,
        modelName: modelName.value
      },
      capture: {
        mode: captureMode.value,
        intervalSeconds: intervalSeconds.value,
        dailyLimit: dailyLimit.value
      },
      blacklist: blacklist.value
    })
    blacklistDirty.value = false
    successMsg.value = 'Settings saved'
    setTimeout(() => { successMsg.value = null }, 3000)
  } catch (e) {
    error.value = 'Failed to save: ' + e.message
  } finally {
    saving.value = false
  }
}

async function testConnection() {
  testingConnection.value = true
  connectionResult.value = null
  try {
    const api = (await import('../api/index.js')).default
    connectionResult.value = await api.TestAIConnection(endpoint.value, apiKey.value, modelName.value)
  } catch (e) {
    connectionResult.value = { success: false, message: e.message }
  } finally {
    testingConnection.value = false
  }
}

async function addBlacklistItem() {
  const item = newBlacklistItem.value.trim()
  if (!item || blacklist.value.includes(item)) return
  blacklist.value.push(item)
  newBlacklistItem.value = ''
  blacklistDirty.value = true
}

function removeBlacklistItem(item) {
  blacklist.value = blacklist.value.filter(i => i !== item)
  blacklistDirty.value = true
}

async function toggleCapture() {
  if (appStore.captureRunning) {
    await appStore.stopCapture()
  } else {
    await appStore.startCapture()
  }
}

async function exportPersonality() {
  exporting.value = true
  try {
    const api = (await import('../api/index.js')).default
    const result = await api.ExportPersonality(exportFormat.value)
    if (result.success) {
      successMsg.value = result.message
      setTimeout(() => { successMsg.value = null }, 5000)
    }
  } catch (e) {
    error.value = 'Export failed: ' + e.message
  } finally {
    exporting.value = false
  }
}

onMounted(loadSettings)
</script>

<template>
  <div class="p-6 max-w-4xl">
    <h2 class="text-2xl font-bold text-white mb-6">Settings</h2>

    <!-- Notifications -->
    <div v-if="error" class="mb-4 p-3 bg-red-600/20 border border-red-600/50 rounded-lg text-red-400 text-sm flex items-center justify-between">
      <span>{{ error }}</span>
      <button @click="error = null" class="text-red-400 hover:text-red-300">&times;</button>
    </div>
    <div v-if="successMsg" class="mb-4 p-3 bg-green-600/20 border border-green-600/50 rounded-lg text-green-400 text-sm">
      {{ successMsg }}
    </div>

    <!-- Loading -->
    <div v-if="loading" class="flex items-center justify-center py-20">
      <div class="flex items-center gap-3 text-gray-400">
        <svg class="animate-spin w-5 h-5" viewBox="0 0 24 24" fill="none">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/>
        </svg>
        <span>Loading settings...</span>
      </div>
    </div>

    <template v-else>
      <div class="space-y-8">

        <!-- AI Response Language -->
        <section class="card">
          <h3 class="text-lg font-semibold text-white mb-4 flex items-center gap-2">
            <svg class="w-5 h-5 text-blue-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/>
            </svg>
            AI Response Language
          </h3>

          <div>
            <label class="block text-sm text-gray-400 mb-1">Language</label>
            <select v-model="language" class="input-field w-48">
              <option v-for="opt in languageOptions" :key="opt.value" :value="opt.value">
                {{ opt.label }}
              </option>
            </select>
            <p class="text-xs text-gray-500 mt-2">Controls the language used in AI analysis results and chat responses. "Auto" follows system language.</p>
          </div>
        </section>

        <!-- AI Model Configuration -->
        <section class="card">
          <h3 class="text-lg font-semibold text-white mb-4 flex items-center gap-2">
            <svg class="w-5 h-5 text-primary-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M12 2a9 9 0 0 1 9 9c0 3.9-2.5 7.2-6 8.4M12 2a9 9 0 0 0-9 9c0 3.9 2.5 7.2 6 8.4M12 2v4m0 16v-4m0 0a4 4 0 1 0 0-8 4 4 0 0 0 0 8z"/>
            </svg>
            AI Model Configuration
          </h3>

          <div class="space-y-4">
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div>
                <label class="block text-sm text-gray-400 mb-1">Provider</label>
                <input v-model="providerName" class="input-field" placeholder="e.g. OpenAI" />
              </div>
              <div>
                <label class="block text-sm text-gray-400 mb-1">Model Name</label>
                <input v-model="modelName" class="input-field" placeholder="e.g. gpt-4o" />
              </div>
            </div>

            <div>
              <label class="block text-sm text-gray-400 mb-1">API Endpoint</label>
              <input v-model="endpoint" class="input-field" placeholder="https://api.openai.com/v1" />
            </div>

            <div>
              <label class="block text-sm text-gray-400 mb-1">API Key</label>
              <div class="relative">
                <input
                  v-model="apiKey"
                  :type="showApiKey ? 'text' : 'password'"
                  class="input-field pr-10"
                  placeholder="sk-..."
                />
                <button
                  @click="showApiKey = !showApiKey"
                  class="absolute right-3 top-1/2 -translate-y-1/2 text-gray-500 hover:text-gray-300"
                >
                  <svg v-if="showApiKey" class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/>
                    <line x1="1" y1="1" x2="23" y2="23"/>
                  </svg>
                  <svg v-else class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/>
                  </svg>
                </button>
              </div>
            </div>

            <div class="flex items-center gap-3">
              <button
                @click="testConnection"
                :disabled="testingConnection"
                class="btn-secondary flex items-center gap-2"
              >
                <svg v-if="testingConnection" class="animate-spin w-4 h-4" viewBox="0 0 24 24" fill="none">
                  <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
                  <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/>
                </svg>
                <span>{{ testingConnection ? 'Testing...' : 'Test Connection' }}</span>
              </button>
              <span
                v-if="connectionResult"
                :class="connectionResult.success ? 'text-green-400' : 'text-red-400'"
                class="text-sm"
              >
                {{ connectionResult.message }}
              </span>
            </div>
          </div>
        </section>

        <!-- Capture Settings -->
        <section class="card">
          <h3 class="text-lg font-semibold text-white mb-4 flex items-center gap-2">
            <svg class="w-5 h-5 text-green-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="3"/>
            </svg>
            Capture Settings
          </h3>

          <div class="space-y-4">
            <div>
              <label class="block text-sm text-gray-400 mb-1">Capture Mode</label>
              <select v-model="captureMode" class="input-field">
                <option v-for="mode in captureModes" :key="mode.value" :value="mode.value">
                  {{ mode.label }}
                </option>
              </select>
            </div>

            <div>
              <label class="block text-sm text-gray-400 mb-1">
                Capture Interval: {{ formatInterval(intervalSeconds) }}
              </label>
              <input
                v-model.number="intervalSeconds"
                type="range"
                min="30"
                max="600"
                step="30"
                class="w-full accent-primary-500"
              />
              <div class="flex justify-between text-xs text-gray-600">
                <span>30s</span>
                <span>10 min</span>
              </div>
            </div>

            <div>
              <label class="block text-sm text-gray-400 mb-1">Daily Limit</label>
              <input v-model.number="dailyLimit" type="number" class="input-field w-32" min="10" max="1000" />
            </div>

            <div class="flex items-center gap-4 pt-2">
              <label class="text-sm text-gray-400">Capture Status:</label>
              <button
                @click="toggleCapture"
                :disabled="appStore.loading"
                :class="[
                  'relative inline-flex h-6 w-11 items-center rounded-full transition-colors duration-200',
                  appStore.captureRunning ? 'bg-green-600' : 'bg-gray-600'
                ]"
              >
                <span
                  :class="[
                    'inline-block h-4 w-4 transform rounded-full bg-white transition-transform duration-200',
                    appStore.captureRunning ? 'translate-x-6' : 'translate-x-1'
                  ]"
                />
              </button>
              <span class="text-sm" :class="appStore.captureRunning ? 'text-green-400' : 'text-gray-500'">
                {{ appStore.captureRunning ? 'Running' : 'Stopped' }}
              </span>
            </div>
          </div>
        </section>

        <!-- Blacklist -->
        <section class="card">
          <h3 class="text-lg font-semibold text-white mb-4 flex items-center gap-2">
            <svg class="w-5 h-5 text-red-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <circle cx="12" cy="12" r="10"/><line x1="4.93" y1="4.93" x2="19.07" y2="19.07"/>
            </svg>
            Blocklist Management
          </h3>

          <div class="space-y-3">
            <div class="flex gap-2">
              <input
                v-model="newBlacklistItem"
                @keydown.enter="addBlacklistItem"
                class="input-field"
                placeholder="Enter process name (e.g. Password.exe)"
              />
              <button @click="addBlacklistItem" class="btn-primary shrink-0">Add</button>
            </div>

            <div class="flex flex-wrap gap-2">
              <span
                v-for="item in blacklist"
                :key="item"
                class="inline-flex items-center gap-1.5 px-3 py-1.5 bg-surface-900 border border-gray-700 rounded-lg text-sm text-gray-300"
              >
                {{ item }}
                <button
                  @click="removeBlacklistItem(item)"
                  class="text-gray-500 hover:text-red-400 transition-default"
                >
                  &times;
                </button>
              </span>
            </div>

            <p v-if="!blacklist.length" class="text-sm text-gray-500">No blocklist items</p>
            <p v-if="blacklistDirty" class="text-xs text-yellow-400 mt-2">* Blocklist modified. Click "Save All Settings" at the bottom to apply changes</p>
          </div>
        </section>

        <!-- Data Management -->
        <section class="card">
          <h3 class="text-lg font-semibold text-white mb-4 flex items-center gap-2">
            <svg class="w-5 h-5 text-purple-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/>
            </svg>
            Data Management
          </h3>

          <div class="space-y-4">
            <!-- Export -->
            <div>
              <label class="block text-sm text-gray-400 mb-2">Export Personality Data</label>
              <div class="flex items-center gap-3">
                <select v-model="exportFormat" class="input-field w-40">
                  <option v-for="fmt in exportFormats" :key="fmt.value" :value="fmt.value">
                    {{ fmt.label }}
                  </option>
                </select>
                <button
                  @click="exportPersonality"
                  :disabled="exporting"
                  class="btn-secondary"
                >
                  {{ exporting ? 'Exporting...' : 'Export' }}
                </button>
              </div>
            </div>

            <!-- Stats -->
            <div v-if="dataStats" class="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-2">
              <div class="bg-surface-900 rounded-lg p-3">
                <p class="text-xs text-gray-500">Database Path</p>
                <p class="text-sm text-gray-300 truncate mt-0.5">{{ dataStats.dbPath }}</p>
              </div>
              <div class="bg-surface-900 rounded-lg p-3">
                <p class="text-xs text-gray-500">Database Size</p>
                <p class="text-sm text-gray-300 mt-0.5">{{ dataStats.dbSize }}</p>
              </div>
              <div class="bg-surface-900 rounded-lg p-3">
                <p class="text-xs text-gray-500">Activity Records</p>
                <p class="text-sm text-gray-300 mt-0.5">{{ dataStats.activitiesCount }}</p>
              </div>
              <div class="bg-surface-900 rounded-lg p-3">
                <p class="text-xs text-gray-500">Memory Entries</p>
                <p class="text-sm text-gray-300 mt-0.5">{{ dataStats.memoriesCount }}</p>
              </div>
            </div>
          </div>
        </section>

        <!-- Save Button -->
        <div class="flex justify-end pb-6">
          <button
            @click="saveSettings"
            :disabled="saving"
            class="btn-primary px-8 flex items-center gap-2"
          >
            <svg v-if="saving" class="animate-spin w-4 h-4" viewBox="0 0 24 24" fill="none">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/>
            </svg>
            <span>{{ saving ? 'Saving...' : 'Save All Settings' }}</span>
          </button>
        </div>

      </div>
    </template>
  </div>
</template>
