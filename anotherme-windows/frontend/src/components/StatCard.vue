<script setup>
defineProps({
  icon: { type: String, default: '' },
  label: { type: String, required: true },
  value: { type: [String, Number], required: true },
  trend: { type: String, default: null },
  color: { type: String, default: 'primary' }
})

const colorMap = {
  primary: 'text-primary-400 bg-primary-600/20',
  green: 'text-green-400 bg-green-600/20',
  purple: 'text-purple-400 bg-purple-600/20',
  orange: 'text-orange-400 bg-orange-600/20',
  red: 'text-red-400 bg-red-600/20'
}
</script>

<template>
  <div class="card flex items-start gap-4">
    <div
      :class="['w-10 h-10 rounded-lg flex items-center justify-center shrink-0', colorMap[color] || colorMap.primary]"
    >
      <span v-html="icon" />
    </div>
    <div class="min-w-0">
      <p class="text-sm text-gray-400">{{ label }}</p>
      <p class="text-2xl font-bold text-white mt-0.5">{{ value }}</p>
      <p v-if="trend" class="text-xs text-gray-500 mt-1">{{ trend }}</p>
    </div>
  </div>
</template>
