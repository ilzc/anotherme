<script setup>
import { useRouter, useRoute } from 'vue-router'
import { useAppStore } from '../stores/app'

const router = useRouter()
const route = useRoute()
const appStore = useAppStore()

const navItems = [
  {
    name: 'Dashboard',
    path: '/',
    icon: `<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/></svg>`
  },
  {
    name: 'Chat',
    path: '/chat',
    icon: `<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>`
  },
  {
    name: 'Personality',
    path: '/personality',
    icon: `<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>`
  },
  {
    name: 'Memory',
    path: '/memory',
    icon: `<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2a9 9 0 0 1 9 9c0 3.9-2.5 7.2-6 8.4M12 2a9 9 0 0 0-9 9c0 3.9 2.5 7.2 6 8.4M12 2v4m0 16v-4m0 0a4 4 0 1 0 0-8 4 4 0 0 0 0 8z"/></svg>`
  },
  {
    name: 'Settings',
    path: '/settings',
    icon: `<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"/></svg>`
  }
]

function navigate(path) {
  router.push(path)
}

function isActive(path) {
  return route.path === path
}
</script>

<template>
  <aside class="fixed left-0 top-0 h-full w-[220px] bg-surface-800 border-r border-gray-700 flex flex-col z-50">
    <!-- Logo -->
    <div class="px-5 py-6 border-b border-gray-700">
      <h1 class="text-xl font-bold text-white tracking-wide">AnotherMe</h1>
      <p class="text-xs text-gray-500 mt-1">Your Digital Twin</p>
    </div>

    <!-- Navigation -->
    <nav class="flex-1 py-4 px-3 space-y-1">
      <button
        v-for="item in navItems"
        :key="item.path"
        @click="navigate(item.path)"
        :class="[
          'w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-default',
          isActive(item.path)
            ? 'bg-primary-600/20 text-primary-400'
            : 'text-gray-400 hover:bg-surface-700 hover:text-white'
        ]"
      >
        <span v-html="item.icon" />
        <span>{{ item.name }}</span>
      </button>
    </nav>

    <!-- Capture Status -->
    <div class="px-4 py-4 border-t border-gray-700">
      <div class="flex items-center gap-2">
        <span
          :class="[
            'w-2 h-2 rounded-full',
            appStore.captureRunning ? 'bg-green-500 animate-pulse' : 'bg-gray-500'
          ]"
        />
        <span class="text-xs text-gray-400">
          {{ appStore.captureRunning ? 'Capture Running' : 'Capture Stopped' }}
        </span>
      </div>
      <p class="text-xs text-gray-500 mt-1">
        Today's captures: {{ appStore.captureCount }}
      </p>
    </div>
  </aside>
</template>
