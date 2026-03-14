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
      <span class="text-xs text-gray-500">{{ trait.evidenceCount }} evidence</span>
    </div>

    <div class="mb-2">
      <div class="flex items-center justify-between text-xs text-gray-400 mb-1">
        <span>Value</span>
        <span class="font-mono">{{ trait.value }}</span>
      </div>
      <ConfidenceBar :value="trait.value" />
    </div>

    <div class="mb-2">
      <div class="flex items-center justify-between text-xs text-gray-400 mb-1">
        <span>Confidence</span>
        <span class="font-mono">{{ trait.confidence }}%</span>
      </div>
      <ConfidenceBar :value="trait.confidence" color="bg-accent-500" height="h-1.5" :show-label="false" />
    </div>

    <p v-if="trait.description" class="text-xs text-gray-400 mt-3 leading-relaxed">
      {{ trait.description }}
    </p>
  </div>
</template>
