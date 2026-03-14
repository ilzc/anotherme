<script setup>
import { computed } from 'vue'

const props = defineProps({
  value: { type: Number, required: true, validator: v => v >= 0 && v <= 100 },
  showLabel: { type: Boolean, default: true },
  height: { type: String, default: 'h-2' },
  color: { type: String, default: null }
})

const barColor = computed(() => {
  if (props.color) return props.color
  if (props.value >= 80) return 'bg-green-500'
  if (props.value >= 60) return 'bg-blue-500'
  if (props.value >= 40) return 'bg-yellow-500'
  return 'bg-red-500'
})
</script>

<template>
  <div class="flex items-center gap-2">
    <div :class="['flex-1 bg-surface-900 rounded-full overflow-hidden', height]">
      <div
        :class="['h-full rounded-full transition-all duration-500', barColor]"
        :style="{ width: value + '%' }"
      />
    </div>
    <span v-if="showLabel" class="text-xs text-gray-400 w-10 text-right font-mono">
      {{ value }}%
    </span>
  </div>
</template>
