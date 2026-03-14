<script setup>
import { computed } from 'vue'

const props = defineProps({
  memory: { type: Object, required: true }
})

const categoryConfig = {
  topic: { label: 'Topic', class: 'bg-blue-600/20 text-blue-400' },
  intent: { label: 'Intent', class: 'bg-green-600/20 text-green-400' },
  habit: { label: 'Habit', class: 'bg-purple-600/20 text-purple-400' },
  opinion: { label: 'Opinion', class: 'bg-orange-600/20 text-orange-400' },
  milestone: { label: 'Milestone', class: 'bg-yellow-600/20 text-yellow-400' }
}

const category = computed(() => categoryConfig[props.memory.category] || categoryConfig.topic)

const dateStr = computed(() => {
  const d = new Date(props.memory.createdAt)
  return d.toLocaleDateString('en-US', { month: '2-digit', day: '2-digit' })
})

const importanceStars = computed(() => {
  const stars = Math.round(props.memory.importance / 20)
  return stars
})
</script>

<template>
  <div class="card hover:border-gray-600 transition-default">
    <div class="flex items-start justify-between mb-2">
      <span :class="['badge', category.class]">{{ category.label }}</span>
      <div class="flex items-center gap-2">
        <span v-if="memory.isPinned" class="text-yellow-500 text-sm" title="Pinned">\u{1F4CC}</span>
        <span class="text-xs text-gray-500">{{ dateStr }}</span>
      </div>
    </div>

    <p class="text-sm text-gray-200 leading-relaxed mb-3">{{ memory.content }}</p>

    <div class="flex flex-wrap gap-1.5 mb-3">
      <span
        v-for="kw in memory.keywords"
        :key="kw"
        class="text-xs text-gray-400 bg-surface-900 px-2 py-0.5 rounded"
      >
        {{ kw }}
      </span>
    </div>

    <div class="flex items-center justify-between text-xs text-gray-500">
      <div class="flex items-center gap-0.5">
        <span
          v-for="i in 5"
          :key="i"
          :class="i <= importanceStars ? 'text-yellow-500' : 'text-gray-700'"
        >
          \u2605
        </span>
      </div>
      <span>{{ memory.accessCount }} accesses</span>
    </div>
  </div>
</template>
