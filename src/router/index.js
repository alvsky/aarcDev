import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from 'src/stores/auth'

const routes = [
  {
    path: '/login',
    component: () => import('src/pages/LoginPage.vue'),
    meta: { public: true },
  },
  {
    // Javno namjerno: pozvana osoba u pravilu nema sesiju kad prvi put otvori
    // link. Stranica sama grana na prijavljen/neprijavljen (vidi
    // AcceptInvitePage.vue) — vlastiti q-layout, izvan MainLayouta.
    path: '/invite/:token',
    component: () => import('src/pages/AcceptInvitePage.vue'),
    meta: { public: true },
  },
  {
    // G1: stiže se ovamo eksplicitnim router.push iz auth.js (PASSWORD_RECOVERY
    // event), ne izravno iz Supabaseovog linka — vidi komentar ondje zašto.
    // public: true jer recovery sesija tehnički JEST auth.user, ali ne
    // oslanjamo se na to (guard ionako pušta kroz ako je auth.user postavljen).
    path: '/reset-password',
    component: () => import('src/pages/ResetPasswordPage.vue'),
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
        path: '/org',
        component: () => import('src/pages/OrgPage.vue'),
        meta: { auth: true },
      },
      {
        // I1: kartica je dio adrese (bez toga se ne da linkati/deep-linkati na
        // konkretan tab). Nema djece-ruta koje bi renderao vue-router — ProjectPage
        // i dalje sam crta q-tabs + keep-alive panele (isti razlog kao prije: gubitak
        // keep-alivea preko pravog nested router-viewa nije vrijedio prepravke), samo
        // čita/piše :tab kroz svoj v-model. Izostavljen :tab → zadano 'chat'.
        path: '/project/:id/:tab(chat|bugs|ideas|tbi)?',
        component: () => import('src/pages/ProjectPage.vue'),
      },
    ],
  },
]

const router = createRouter({
  history: createWebHistory(),
  routes,
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  if (auth.user === null && !to.meta.public) {
    await auth.init()
  }
  if (!auth.user && !to.meta.public) return '/login'
  // redirect čuva /invite/:token kroz prijavu/registraciju umjesto da uvijek
  // odbaci na Home (vidi AcceptInvitePage → goToLogin).
  if (auth.user && to.path === '/login') {
    return typeof to.query.redirect === 'string' ? to.query.redirect : '/'
  }
})

export default router
