<script setup>
import { ref, onMounted, nextTick, watch } from 'vue'
import { useChatStore } from '../stores/chat'
import ChatMessage from '../components/ChatMessage.vue'

const chatStore = useChatStore()
const inputText = ref('')
const messagesContainer = ref(null)

async function handleSend() {
  const text = inputText.value.trim()
  if (!text || chatStore.sending) return

  // Auto-create session if none selected
  if (!chatStore.currentSession) {
    await chatStore.createSession()
    if (!chatStore.currentSession) return // creation failed
  }

  inputText.value = ''
  await chatStore.sendMessage(text)
  scrollToBottom()
}

function handleKeydown(e) {
  if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
    e.preventDefault()
    handleSend()
  }
}

function scrollToBottom() {
  nextTick(() => {
    if (messagesContainer.value) {
      messagesContainer.value.scrollTop = messagesContainer.value.scrollHeight
    }
  })
}

watch(() => chatStore.messages.length, scrollToBottom)

function formatDate(dateStr) {
  const d = new Date(dateStr)
  return d.toLocaleDateString('en-US', { month: '2-digit', day: '2-digit' })
}

onMounted(async () => {
  await chatStore.fetchSessions()
  if (chatStore.sessions.length > 0) {
    await chatStore.selectSession(chatStore.sessions[0].id)
    scrollToBottom()
  }
})
</script>

<template>
  <div class="flex h-full">
    <!-- Session List Panel -->
    <div class="w-[240px] xl:w-[280px] shrink-0 border-r border-gray-700 flex flex-col bg-surface-800/50">
      <div class="p-4 border-b border-gray-700">
        <button @click="chatStore.createSession()" class="btn-primary w-full flex items-center justify-center gap-2">
          <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/>
          </svg>
          <span>New Chat</span>
        </button>
      </div>

      <div class="flex-1 overflow-y-auto">
        <button
          v-for="session in chatStore.sessions"
          :key="session.id"
          @click="chatStore.selectSession(session.id)"
          :class="[
            'w-full text-left px-4 py-3 border-b border-gray-700/50 transition-default',
            chatStore.currentSession?.id === session.id
              ? 'bg-primary-600/10 border-l-2 border-l-primary-500'
              : 'hover:bg-surface-700/50'
          ]"
        >
          <p class="text-sm font-medium text-white truncate">{{ session.title }}</p>
          <p class="text-xs text-gray-500 mt-1">{{ formatDate(session.lastMessageAt || session.createdAt) }}</p>
        </button>

        <div v-if="!chatStore.sessions.length" class="p-6 text-center text-gray-500 text-sm">
          No chat history
        </div>
      </div>
    </div>

    <!-- Chat Panel -->
    <div class="flex-1 flex flex-col">
      <!-- Chat Header -->
      <div class="h-14 border-b border-gray-700 flex items-center px-6">
        <h3 class="text-sm font-medium text-white">
          {{ chatStore.currentSession?.title || 'Select or start a new chat' }}
        </h3>
      </div>

      <!-- Error Banner -->
      <div v-if="chatStore.error" class="mx-6 mt-3 p-3 bg-red-600/20 border border-red-600/50 rounded-lg text-red-400 text-sm flex items-center justify-between">
        <span>{{ chatStore.error }}</span>
        <button @click="chatStore.error = null" class="text-red-400 hover:text-red-300">&times;</button>
      </div>

      <!-- Messages -->
      <div ref="messagesContainer" class="flex-1 overflow-y-auto p-6">
        <template v-if="chatStore.currentSession">
          <div v-if="!chatStore.messages.length" class="flex items-center justify-center h-full">
            <div class="text-center text-gray-500">
              <svg class="w-16 h-16 mx-auto mb-4 opacity-30" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1">
                <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
              </svg>
              <p>Start chatting with your digital twin</p>
              <p class="text-xs mt-1 text-gray-600">Based on your behavioral data and memories, AI will respond from your perspective</p>
            </div>
          </div>
          <ChatMessage
            v-for="msg in chatStore.messages"
            :key="msg.id"
            :message="msg"
            :streaming="msg.streaming === true || msg.id === chatStore.streamingMessageId"
          />
        </template>
        <div v-else class="flex items-center justify-center h-full text-gray-500">
          <p>Select a chat from the left, or start a new one</p>
        </div>
      </div>

      <!-- Input Area -->
      <div class="border-t border-gray-700 p-4">
        <div class="flex gap-3">
          <textarea
            v-model="inputText"
            @keydown="handleKeydown"
            :disabled="chatStore.sending"
            placeholder="Type a message... (Ctrl+Enter to send)"
            rows="2"
            class="input-field resize-none flex-1"
          />
          <button
            @click="handleSend"
            :disabled="!inputText.trim() || chatStore.sending"
            class="btn-primary self-end px-6"
          >
            <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <line x1="22" y1="2" x2="11" y2="13"/><polygon points="22 2 15 22 11 13 2 9 22 2"/>
            </svg>
          </button>
        </div>
        <p class="text-xs text-gray-600 mt-2">Ctrl + Enter to send</p>
      </div>
    </div>
  </div>
</template>
