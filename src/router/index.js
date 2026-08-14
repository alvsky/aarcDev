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
    // G1: guard niže preusmjerava ovamo čim vidi ?code= u adresi, izravno,
    // bez čekanja na auth event (bio nepouzdan — vidi commit povijest).
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
        path: '/about',
        component: () => import('src/pages/AboutPage.vue'),
      },
      {
        path: '/privacy',
        component: () => import('src/pages/PrivacyPage.vue'),
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
  // G1: ?code=... u adresi znači da smo TEK stigli s recovery (ili bilo
  // kojeg drugog PKCE) linka — odvedi izravno na /reset-password, ne čekaj
  // da se sesija sama uspostavi pa da nas events.js preusmjeri. Prijašnja
  // verzija (čekanje na PASSWORD_RECOVERY event) ovisila je o redoslijedu
  // između router guarda i async razmjene koda — nepouzdano, znalo završiti
  // na praznoj `/?code=...` adresi bez ikakvog preusmjeravanja.
  if (to.query.code && to.path !== '/reset-password') {
    return { path: '/reset-password', query: to.query }
  }

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
