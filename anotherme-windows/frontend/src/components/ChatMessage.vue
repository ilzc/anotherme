<script setup>
import { computed } from 'vue'

const props = defineProps({
  message: { type: Object, required: true },
  streaming: { type: Boolean, default: false }
})

const isUser = computed(() => props.message.role === 'user')

const time = computed(() => {
  const d = new Date(props.message.timestamp)
  return d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })
})

function escapeHtml(text) {
  const div = document.createElement('div')
  div.textContent = text
  return div.innerHTML
}

const formattedContent = computed(() => {
  if (!props.message.content) return ''
  // Escape HTML entities first to prevent XSS, then apply markdown-like formatting
  const escaped = escapeHtml(props.message.content)
  return escaped
    .replace(/\*\*(.*?)\*\*/g, '<strong class="text-white font-semibold">$1</strong>')
    .replace(/\n/g, '<br>')
})
</script>

<template>
  <div :class="['flex mb-4', isUser ? 'justify-end' : 'justify-start']">
    <div
      :class="[
        'max-w-[75%] rounded-2xl px-4 py-3 text-sm leading-relaxed',
        isUser
          ? 'bg-primary-600 text-white rounded-br-md'
          : 'bg-surface-700 text-gray-200 rounded-bl-md border border-gray-600'
      ]"
    >
      <!-- Streaming indicator -->
      <template v-if="streaming">
        <div v-if="formattedContent" v-html="formattedContent" />
        <div class="flex items-center gap-1.5 mt-2">
          <span class="text-xs text-gray-400">Thinking</span>
          <span class="flex gap-1">
            <span class="w-1.5 h-1.5 bg-accent-400 rounded-full animate-pulse" style="animation-delay: 0ms" />
            <span class="w-1.5 h-1.5 bg-accent-400 rounded-full animate-pulse" style="animation-delay: 300ms" />
            <span class="w-1.5 h-1.5 bg-accent-400 rounded-full animate-pulse" style="animation-delay: 600ms" />
          </span>
        </div>
      </template>

      <!-- Normal content -->
      <template v-else>
        <div v-html="formattedContent" />
        <p :class="['text-xs mt-2', isUser ? 'text-primary-200' : 'text-gray-500']">
          {{ time }}
        </p>
      </template>
    </div>
  </div>
</template>
