<script setup>
import ConfidenceBar from './ConfidenceBar.vue'

defineProps({
  trait: { type: Object, required: true }
})
</script>

<template>
  <div class="card hover:border-gray-600 transition-default">
    <div class="flex items-center justify-between mb-2">
      <h4 class="text-sm font-semibold text-white">{{ trait.dimension }}</h4>
      <span v-if="trait.evidenceCount" class="text-xs text-gray-500">{{ trait.evidenceCount }} evidence</span>
    </div>

    <div class="mb-2">
      <div class="flex items-center justify-between text-xs text-gray-400 mb-1">
        <span>Value</span>
        <span class="font-mono truncate ml-2 max-w-[200px]">{{ trait.value }}</span>
      </div>
      <!-- Only show value bar if value is numeric (mock mode) -->
      <ConfidenceBar v-if="typeof trait.value === 'number'" :value="trait.value" />
    </div>

    <div class="mb-2">
      <div class="flex items-center justify-between text-xs text-gray-400 mb-1">
        <span>Confidence</span>
        <span class="font-mono">{{ Math.round(trait.confidence >= 1 ? trait.confidence : trait.confidence * 100) }}%</span>
      </div>
      <ConfidenceBar :value="trait.confidence >= 1 ? trait.confidence : trait.confidence * 100" color="bg-accent-500" height="h-1.5" :show-label="false" />
    </div>

    <p v-if="trait.description" class="text-xs text-gray-400 mt-3 leading-relaxed">
      {{ trait.description }}
    </p>
  </div>
</template>
