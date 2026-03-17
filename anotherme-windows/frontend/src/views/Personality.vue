<script setup>
import { ref, computed, onMounted } from 'vue'
import { usePersonalityStore } from '../stores/personality'
import TraitCard from '../components/TraitCard.vue'

const personalityStore = usePersonalityStore()
const activeLayer = ref(1)

const layerTabs = [
  { num: 1, name: 'Behavioral Rhythm' },
  { num: 2, name: 'Knowledge Map' },
  { num: 3, name: 'Cognitive Style' },
  { num: 4, name: 'Expression Style' },
  { num: 5, name: 'Values' }
]

const currentTraits = computed(() => {
  return personalityStore.layers[activeLayer.value] || []
})

const hasData = computed(() => {
  return Object.values(personalityStore.layers).some(l => l.length > 0)
})

function selectLayer(num) {
  activeLayer.value = num
}

onMounted(async () => {
  await Promise.all([
    personalityStore.fetchAllLayers(),
    personalityStore.fetchSnapshot()
  ])
})
</script>

<template>
  <div class="p-6">
    <h2 class="text-2xl font-bold text-white mb-6">Personality Profile</h2>

    <!-- Loading -->
    <div v-if="personalityStore.loading && !hasData" class="flex items-center justify-center py-20">
      <div class="flex items-center gap-3 text-gray-400">
        <svg class="animate-spin w-5 h-5" viewBox="0 0 24 24" fill="none">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/>
        </svg>
        <span>Loading personality data...</span>
      </div>
    </div>

    <template v-else-if="hasData">
      <!-- Layer Tabs -->
      <div class="flex flex-wrap gap-1 mb-6 bg-surface-800 p-1 rounded-lg border border-gray-700 w-fit">
        <button
          v-for="tab in layerTabs"
          :key="tab.num"
          @click="selectLayer(tab.num)"
          :class="[
            'px-4 py-2 rounded-md text-sm font-medium transition-default',
            activeLayer === tab.num
              ? 'bg-primary-600 text-white'
              : 'text-gray-400 hover:text-white hover:bg-surface-700'
          ]"
        >
          <span class="text-xs opacity-60 mr-1">L{{ tab.num }}</span>
          {{ tab.name }}
        </button>
      </div>

      <!-- Traits Grid -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-8">
        <TraitCard
          v-for="trait in currentTraits"
          :key="trait.dimension"
          :trait="trait"
        />
      </div>

      <!-- Personality Snapshot -->
      <div v-if="personalityStore.snapshot" class="mt-8">
        <h3 class="text-lg font-semibold text-white mb-4">Personality Snapshot</h3>
        <div class="card">
          <p class="text-sm text-gray-300 leading-relaxed mb-4">
            {{ personalityStore.snapshot.summary }}
          </p>
          <div v-if="personalityStore.snapshot.keyTraits?.length" class="flex flex-wrap gap-2 mb-3">
            <span
              v-for="trait in personalityStore.snapshot.keyTraits"
              :key="trait"
              class="badge bg-accent-500/20 text-accent-400"
            >
              {{ trait }}
            </span>
          </div>
          <p class="text-xs text-gray-500">
            <template v-if="personalityStore.snapshot.version">Version {{ personalityStore.snapshot.version }} &middot; </template>
            Generated {{ new Date(personalityStore.snapshot.generatedAt).toLocaleString('en-US') }}
          </p>
        </div>
      </div>
    </template>

    <!-- Empty State -->
    <div v-else class="flex flex-col items-center justify-center py-20">
      <svg class="w-20 h-20 text-gray-700 mb-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1">
        <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/>
        <circle cx="12" cy="7" r="4"/>
      </svg>
      <p class="text-gray-400 text-lg mb-2">Gathering data</p>
      <p class="text-gray-600 text-sm">Please run Screen Capture for a while first</p>
    </div>
  </div>
</template>
