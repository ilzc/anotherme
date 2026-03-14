<script setup>
import { onMounted } from 'vue'
import { useAppStore } from './stores/app'
import Sidebar from './components/Sidebar.vue'
import FloatingAssistant from './components/FloatingAssistant.vue'

const appStore = useAppStore()

onMounted(() => {
  appStore.fetchCaptureStatus()
})
</script>

<template>
  <div class="flex h-screen overflow-hidden bg-surface-900">
    <!-- Sidebar -->
    <Sidebar />

    <!-- Main Content -->
    <main class="ml-[220px] flex-1 overflow-y-auto h-full">
      <router-view />
    </main>

    <!-- Floating Assistant Overlay -->
    <FloatingAssistant />
  </div>
</template>
