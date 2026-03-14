import { createRouter, createWebHashHistory } from 'vue-router'

const routes = [
  {
    path: '/',
    name: 'Dashboard',
    component: () => import('./views/Dashboard.vue')
  },
  {
    path: '/chat',
    name: 'Chat',
    component: () => import('./views/Chat.vue')
  },
  {
    path: '/personality',
    name: 'Personality',
    component: () => import('./views/Personality.vue')
  },
  {
    path: '/memory',
    name: 'Memory',
    component: () => import('./views/Memory.vue')
  },
  {
    path: '/settings',
    name: 'Settings',
    component: () => import('./views/Settings.vue')
  }
]

const router = createRouter({
  history: createWebHashHistory(),
  routes
})

export default router
