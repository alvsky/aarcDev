import { createRouter, createWebHashHistory } from 'vue-router'
import { useAuthStore } from 'src/stores/auth'

const routes = [
  {
    path: '/login',
    component: () => import('src/pages/LoginPage.vue'),
    meta: { public: true },
  },
  {
    path: '/',
    component: () => import('src/layouts/MainLayout.vue'),
    meta: { auth: true },
    children: [
      {
        path: '',
        component: () => import('src/pages/ProjectsPage.vue'),
      },
      {
        path: '/settings',
        component: () => import('src/pages/SettingsPage.vue'),
      },
      {
        path: '/profile',
        component: () => import('src/pages/ProfilePage.vue'),
        meta: { auth: true },
      },
      {
        path: '/project/:id',
        component: () => import('src/pages/ProjectPage.vue'),
        children: [
          { path: '', redirect: (to) => `/project/${to.params.id}/ideas` },
          { path: 'ideas', component: () => import('src/pages/IdeasPage.vue') },
          { path: 'bugs', component: () => import('src/pages/BugsPage.vue') },
          { path: 'tbi', component: () => import('src/pages/TbiPage.vue') },
          { path: 'chat', component: () => import('src/pages/ChatPage.vue') },
        ],
      },
    ],
  },
]

const router = createRouter({
  history: createWebHashHistory(),
  routes,
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  if (auth.user === null && !to.meta.public) {
    await auth.init()
  }
  if (!auth.user && !to.meta.public) return '/login'
  if (auth.user && to.path === '/login') return '/'
})

export default router
