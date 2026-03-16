<script setup>
import { ref, onMounted, watch } from 'vue'
import MemoryCard from '../components/MemoryCard.vue'

const memories = ref([])
const memoryStats = ref(null)
const loading = ref(true)
const error = ref(null)

const keyword = ref('')
const category = ref('all')
const sortBy = ref('importance')

const categories = [
  { value: 'all', label: 'All' },
  { value: 'topic', label: 'Topic' },
  { value: 'intent', label: 'Intent' },
  { value: 'habit', label: 'Habit' },
  { value: 'opinion', label: 'Opinion' },
  { value: 'milestone', label: 'Milestone' }
]

const sortOptions = [
  { value: 'importance', label: 'By Importance' },
  { value: 'recency', label: 'By Recent Update' },
  { value: 'date', label: 'By Created Date' }
]

let searchTimer = null

async function loadMemories() {
  loading.value = true
  error.value = null
  try {
    const api = (await import('../api/index.js')).default
    const [mems, stats] = await Promise.all([
      api.GetMemories({
        keyword: keyword.value,
        category: category.value,
        sortBy: sortBy.value
      }),
      api.GetMemoryStats()
    ])
    memories.value = mems
    memoryStats.value = stats
  } catch (e) {
    error.value = 'Failed to load memory data: ' + e.message
  } finally {
    loading.value = false
  }
}

function onSearchInput() {
  clearTimeout(searchTimer)
  searchTimer = setTimeout(loadMemories, 300)
}

watch([category, sortBy], loadMemories)

onMounted(loadMemories)
</script>

<template>
  <div class="p-6">
    <h2 class="text-2xl font-bold text-white mb-6">Memory Bank</h2>

    <!-- Search & Filters -->
    <div class="mb-6 space-y-4">
      <!-- Search Bar -->
      <div class="relative">
        <svg class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/>
        </svg>
        <input
          v-model="keyword"
          @input="onSearchInput"
          type="text"
          placeholder="Search memory content or keywords..."
          class="input-field pl-10"
        />
      </div>

      <div class="flex flex-wrap items-center justify-between gap-2">
        <!-- Category Chips -->
        <div class="flex flex-wrap gap-2">
          <button
            v-for="cat in categories"
            :key="cat.value"
            @click="category = cat.value"
            :class="[
              'px-3 py-1.5 rounded-full text-xs font-medium transition-default',
              category === cat.value
                ? 'bg-primary-600 text-white'
                : 'bg-surface-800 text-gray-400 border border-gray-700 hover:border-gray-500'
            ]"
          >
            {{ cat.label }}
          </button>
        </div>

        <!-- Sort -->
        <select
          v-model="sortBy"
          class="input-field w-auto text-sm"
        >
          <option v-for="opt in sortOptions" :key="opt.value" :value="opt.value">
            {{ opt.label }}
          </option>
        </select>
      </div>
    </div>

    <!-- Stats Bar -->
    <div v-if="memoryStats" class="flex items-center gap-4 mb-4 text-sm text-gray-500">
      <span>{{ memoryStats.total }} memories total</span>
      <span>&middot;</span>
      <span>{{ memoryStats.pinned }} pinned</span>
      <span>&middot;</span>
      <span>Showing {{ memories.length }}</span>
    </div>

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

    <!-- Memory Grid -->
    <template v-else>
      <div v-if="memories.length" class="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-3 gap-4">
        <MemoryCard
          v-for="mem in memories"
          :key="mem.id"
          :memory="mem"
        />
      </div>

      <!-- Empty State -->
      <div v-else class="flex flex-col items-center justify-center py-20">
        <svg class="w-20 h-20 text-gray-700 mb-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1">
          <path d="M12 2a9 9 0 0 1 9 9c0 3.9-2.5 7.2-6 8.4M12 2a9 9 0 0 0-9 9c0 3.9 2.5 7.2 6 8.4M12 2v4m0 16v-4m0 0a4 4 0 1 0 0-8 4 4 0 0 0 0 8z"/>
        </svg>
        <p class="text-gray-400 text-lg mb-2">
          {{ keyword ? 'No matching memories found' : 'No memory data yet' }}
        </p>
        <p class="text-gray-600 text-sm">
          {{ keyword ? 'Try different keywords' : 'The system will automatically extract and accumulate memories from screen captures' }}
        </p>
      </div>
    </template>
  </div>
</template>
