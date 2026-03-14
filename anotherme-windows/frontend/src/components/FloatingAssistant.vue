<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue'
import { useChatStore } from '../stores/chat'

const chatStore = useChatStore()

// ─── Bubble Position ─────────────────────────────────────
const STORAGE_KEY = 'floatingAssistantPos'
const defaultPos = { x: window.innerWidth - 72, y: window.innerHeight - 72 }

function loadPosition() {
  try {
    const saved = localStorage.getItem(STORAGE_KEY)
    if (saved) {
      const pos = JSON.parse(saved)
      return constrainToWindow(pos)
    }
  } catch {}
  return { ...defaultPos }
}

function constrainToWindow(pos) {
  return {
    x: Math.max(0, Math.min(pos.x, window.innerWidth - 48)),
    y: Math.max(0, Math.min(pos.y, window.innerHeight - 48))
  }
}

const position = ref(loadPosition())
const showPanel = ref(false)
const quickInput = ref('')
const isDragging = ref(false)
const dragOffset = ref({ x: 0, y: 0 })
const didDrag = ref(false)

// ─── Panel Position ──────────────────────────────────────
const panelPosition = computed(() => {
  const panelW = 320
  const panelH = 384
  let x = position.value.x - panelW + 24
  let y = position.value.y - panelH - 8

  // Keep panel within viewport
  if (x < 8) x = 8
  if (x + panelW > window.innerWidth - 8) x = window.innerWidth - panelW - 8
  if (y < 8) {
    y = position.value.y + 56
  }
  if (y + panelH > window.innerHeight - 8) {
    y = window.innerHeight - panelH - 8
  }

  return { left: x + 'px', top: y + 'px' }
})

// ─── Recent Messages ────────────────────────────────────
const recentMessages = computed(() => {
  const msgs = chatStore.messages || []
  return msgs.slice(-4)
})

// ─── Drag Logic ─────────────────────────────────────────
function startDrag(e) {
  if (e.button !== 0) return
  isDragging.value = true
  didDrag.value = false
  dragOffset.value = {
    x: e.clientX - position.value.x,
    y: e.clientY - position.value.y
  }
  document.addEventListener('mousemove', onDrag)
  document.addEventListener('mouseup', stopDrag)
  e.preventDefault()
}

function onDrag(e) {
  if (!isDragging.value) return
  didDrag.value = true
  position.value = constrainToWindow({
    x: e.clientX - dragOffset.value.x,
    y: e.clientY - dragOffset.value.y
  })
}

function stopDrag() {
  if (isDragging.value) {
    isDragging.value = false
    localStorage.setItem(STORAGE_KEY, JSON.stringify(position.value))
    document.removeEventListener('mousemove', onDrag)
    document.removeEventListener('mouseup', stopDrag)
  }
}

function togglePanel() {
  // Only toggle if we didn't drag
  if (didDrag.value) {
    didDrag.value = false
    return
  }
  showPanel.value = !showPanel.value
}

// ─── Quick Send ──────────────────────────────────────────
async function sendQuick() {
  const text = quickInput.value.trim()
  if (!text || chatStore.sending) return

  // Ensure there's a session
  if (!chatStore.currentSession) {
    await chatStore.createSession()
    if (!chatStore.currentSession) return
  }

  quickInput.value = ''
  await chatStore.sendMessage(text)
}

// ─── Window Resize ───────────────────────────────────────
function onResize() {
  position.value = constrainToWindow(position.value)
}

onMounted(() => {
  window.addEventListener('resize', onResize)
})

onBeforeUnmount(() => {
  window.removeEventListener('resize', onResize)
  document.removeEventListener('mousemove', onDrag)
  document.removeEventListener('mouseup', stopDrag)
})

function formatMsgTime(ts) {
  const d = new Date(ts)
  return d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })
}
</script>

<template>
  <!-- Draggable floating bubble -->
  <div
    class="fixed z-50 select-none"
    :style="{ left: position.x + 'px', top: position.y + 'px' }"
    @mousedown="startDrag"
  >
    <button
      @click="togglePanel"
      :class="[
        'w-12 h-12 rounded-full flex items-center justify-center shadow-lg transition-all duration-200',
        'bg-accent-500 hover:bg-accent-400 text-white',
        'hover:scale-110 active:scale-95',
        chatStore.sending ? 'animate-pulse' : ''
      ]"
    >
      <!-- Brain icon -->
      <svg class="w-6 h-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
        <path d="M12 2a7 7 0 0 1 7 7c0 2.38-1.19 4.47-3 5.74V17a2 2 0 0 1-2 2h-4a2 2 0 0 1-2-2v-2.26C6.19 13.47 5 11.38 5 9a7 7 0 0 1 7-7z" />
        <path d="M9 21h6" />
        <path d="M10 17v4" />
        <path d="M14 17v4" />
        <path d="M12 2v4" />
        <path d="M8 6l2 2" />
        <path d="M16 6l-2 2" />
      </svg>
    </button>

    <!-- Notification dot when sending -->
    <span
      v-if="chatStore.sending"
      class="absolute -top-0.5 -right-0.5 w-3 h-3 bg-green-400 rounded-full border-2 border-surface-900 animate-ping"
    />
  </div>

  <!-- Chat popup panel -->
  <Teleport to="body">
    <div
      v-if="showPanel"
      class="fixed z-40 w-80 rounded-xl bg-surface-800 shadow-2xl border border-gray-700 flex flex-col"
      style="height: 384px;"
      :style="panelPosition"
    >
      <!-- Header -->
      <div class="p-3 border-b border-gray-700 flex items-center justify-between shrink-0">
        <span class="text-sm font-medium text-white">Quick Chat</span>
        <button
          @click="showPanel = false"
          class="w-6 h-6 flex items-center justify-center rounded text-gray-400 hover:text-white hover:bg-surface-600 transition-colors"
        >
          <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" />
          </svg>
        </button>
      </div>

      <!-- Messages area -->
      <div class="flex-1 overflow-y-auto p-3 space-y-2">
        <template v-if="recentMessages.length">
          <div
            v-for="msg in recentMessages"
            :key="msg.id"
            :class="[
              'text-xs leading-relaxed rounded-lg px-3 py-2',
              msg.role === 'user'
                ? 'bg-primary-600/20 text-primary-200 ml-6'
                : 'bg-surface-700 text-gray-300 mr-6'
            ]"
          >
            <p class="line-clamp-3">{{ msg.content }}</p>
            <p class="text-gray-500 text-[10px] mt-1">{{ formatMsgTime(msg.timestamp) }}</p>
          </div>
        </template>
        <div v-else class="flex items-center justify-center h-full text-gray-500 text-xs">
          <p>No recent messages</p>
        </div>

        <!-- Streaming indicator in panel -->
        <div v-if="chatStore.sending" class="flex items-center gap-1.5 px-3 py-2 bg-surface-700 rounded-lg mr-6">
          <span class="text-xs text-gray-400">Thinking</span>
          <span class="flex gap-1">
            <span class="w-1.5 h-1.5 bg-accent-400 rounded-full animate-pulse" style="animation-delay: 0ms" />
            <span class="w-1.5 h-1.5 bg-accent-400 rounded-full animate-pulse" style="animation-delay: 300ms" />
            <span class="w-1.5 h-1.5 bg-accent-400 rounded-full animate-pulse" style="animation-delay: 600ms" />
          </span>
        </div>
      </div>

      <!-- Quick input -->
      <div class="p-3 border-t border-gray-700 shrink-0">
        <input
          v-model="quickInput"
          @keyup.enter="sendQuick"
          :disabled="chatStore.sending"
          placeholder="Say something..."
          class="input-field w-full text-sm"
        />
      </div>
    </div>
  </Teleport>
</template>
