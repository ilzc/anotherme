<script setup>
import { computed } from 'vue'

const props = defineProps({
  activity: { type: Object, required: true }
})

const time = computed(() => {
  const d = new Date(props.activity.timestamp)
  return d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })
})

const categoryConfig = {
  work: { label: 'Work', class: 'bg-blue-600/20 text-blue-400' },
  learning: { label: 'Learning', class: 'bg-green-600/20 text-green-400' },
  social: { label: 'Social', class: 'bg-purple-600/20 text-purple-400' },
  creative: { label: 'Creative', class: 'bg-orange-600/20 text-orange-400' },
  entertainment: { label: 'Entertainment', class: 'bg-pink-600/20 text-pink-400' }
}

const engagementConfig = {
  deep_focus: { label: 'Deep Focus', class: 'text-green-400' },
  active_work: { label: 'Active Work', class: 'text-blue-400' },
  browsing: { label: 'Browsing', class: 'text-gray-400' }
}

const category = computed(() => categoryConfig[props.activity.activityCategory] || categoryConfig.work)
const engagement = computed(() => engagementConfig[props.activity.engagementLevel] || engagementConfig.browsing)

const appIcon = computed(() => {
  const icons = {
    'VS Code': '{ }',
    'Chrome': '\u25ce',
    'WeChat': '\u2709',
    'Terminal': '>_',
    'Figma': '\u25c7',
    'Notion': '\u25a1'
  }
  return icons[props.activity.appName] || '\u25cb'
})
</script>

<template>
  <div class="flex items-start gap-4 py-3 px-4 rounded-lg hover:bg-surface-700/50 transition-default group">
    <!-- Time -->
    <div class="text-sm text-gray-500 font-mono w-12 shrink-0 pt-0.5">{{ time }}</div>

    <!-- Timeline dot -->
    <div class="flex flex-col items-center shrink-0 pt-1">
      <div class="w-2 h-2 rounded-full bg-primary-500" />
      <div class="w-px flex-1 bg-gray-700 mt-1" />
    </div>

    <!-- Content -->
    <div class="flex-1 min-w-0 pb-2">
      <div class="flex items-center gap-2 mb-1">
        <span class="text-sm font-mono text-gray-400 bg-surface-900 px-1.5 py-0.5 rounded">{{ appIcon }}</span>
        <span class="text-sm font-medium text-white">{{ activity.appName }}</span>
        <span :class="['badge', category.class]">{{ category.label }}</span>
        <span :class="['text-xs', engagement.class]">{{ engagement.label }}</span>
      </div>
      <p class="text-sm text-gray-300 truncate">{{ activity.contentSummary }}</p>
      <div class="flex gap-1.5 mt-1.5">
        <span
          v-for="topic in activity.topics"
          :key="topic"
          class="text-xs text-gray-500 bg-surface-900 px-1.5 py-0.5 rounded"
        >
          {{ topic }}
        </span>
      </div>
    </div>
  </div>
</template>
