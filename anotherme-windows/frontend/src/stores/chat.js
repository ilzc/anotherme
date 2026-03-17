import { defineStore } from 'pinia'
import { ref } from 'vue'
import api from '../api/index.js'

export const useChatStore = defineStore('chat', () => {
  const sessions = ref([])
  const currentSession = ref(null)
  const messages = ref([])
  const sending = ref(false)
  const error = ref(null)
  const streamingMessageId = ref(null)

  async function fetchSessions() {
    try {
      sessions.value = await api.GetChatSessions(100)
      error.value = null
    } catch (e) {
      console.error('Failed to fetch sessions:', e)
      error.value = 'Failed to fetch sessions: ' + e.message
    }
  }

  async function createSession() {
    try {
      const session = await api.CreateChatSession()
      await fetchSessions() // re-fetch to sync
      currentSession.value = session
      messages.value = []
      error.value = null
      return session
    } catch (e) {
      console.error('Failed to create session:', e)
      error.value = 'Failed to create session: ' + e.message
      return null
    }
  }

  async function selectSession(id) {
    currentSession.value = sessions.value.find(s => s.id === id) || null
    if (currentSession.value) {
      try {
        messages.value = await api.GetChatMessages(id)
      } catch (e) {
        console.error('Failed to fetch messages:', e)
        messages.value = []
      }
    }
  }

  async function sendMessage(text) {
    if (!currentSession.value || !text.trim()) return
    sending.value = true

    // 1. Add user message optimistically
    const optimisticMsg = {
      id: `temp-${Date.now()}`,
      role: 'user',
      content: text,
      timestamp: new Date().toISOString()
    }
    messages.value.push(optimisticMsg)

    // 2. Add placeholder AI message with streaming state
    const placeholderId = `streaming-${Date.now()}`
    const placeholderMsg = {
      id: placeholderId,
      role: 'assistant',
      content: '',
      timestamp: new Date().toISOString(),
      streaming: true
    }
    messages.value.push(placeholderMsg)
    streamingMessageId.value = placeholderId

    try {
      // 3. Call streaming API
      const result = await api.SendChatMessageStream(currentSession.value.id, text)

      // 4. Update placeholder with full content
      const idx = messages.value.findIndex(m => m.id === placeholderId)
      if (idx !== -1) {
        messages.value[idx] = {
          ...messages.value[idx],
          id: result.messageId,
          content: result.content,
          streaming: false,
          timestamp: new Date().toISOString()
        }
      }

      // Reload messages to get consistent state from backend
      messages.value = await api.GetChatMessages(currentSession.value.id)
      error.value = null
    } catch (e) {
      console.error('Failed to send message:', e)
      // Remove both the placeholder AI message and the optimistic user message
      messages.value = messages.value.filter(
        m => m.id !== placeholderId && m.id !== optimisticMsg.id
      )
      error.value = 'Failed to send message: ' + e.message
    } finally {
      sending.value = false
      streamingMessageId.value = null
    }
  }

  return {
    sessions,
    currentSession,
    messages,
    sending,
    error,
    streamingMessageId,
    fetchSessions,
    createSession,
    selectSession,
    sendMessage
  }
})
