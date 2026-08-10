<template>
  <q-layout view="hHh lpR fFf">
    <!-- Naziv organizacije je sad čist tekst — prebacivanje i sve ostalo
         vezano uz organizaciju živi na jednom mjestu, na /org (kartica
         "Organizacija" u podnožju), umjesto razdvojeno između zaglavlja i
         podnožja. -->
    <AppHeader :title="orgsStore.current?.name ?? ''" settings>
      <template #left>
        <UserAvatar
          :avatar-url="authStore.profile?.avatar_url"
          :full-name="authStore.profile?.full_name"
          :size="40"
        />
      </template>
    </AppHeader>

    <q-page-container>
      <q-page class="home-page q-pb-xl">
        <!-- Pozdrav -->
        <div class="q-px-md q-pt-sm q-pb-md">
          <div class="text-h3 text-weight-bold home-greeting">{{ greeting }},</div>
          <div class="text-h3 text-weight-bold home-greeting">{{ firstName }}!</div>
        </div>

        <!-- Projekti -->
        <div class="q-px-md q-mb-lg">
          <div class="text-h6 text-weight-medium q-mb-md home-section-label">
            {{ $t('projects.title') }}
          </div>

          <div
            v-if="!orgProjects.length"
            class="text-center q-mt-xl"
            style="color: var(--aarc-muted)"
          >
            {{ $t('projects.noProjects') }}
          </div>

          <div class="project-list">
            <div
              v-for="project in orgProjects"
              :key="project.id"
              class="project-row cursor-pointer"
              :style="{
                background: `linear-gradient(120deg, ${project.color}26, var(--aarc-surface) 60%)`,
              }"
              @click="$router.push(`/project/${project.id}`)"
            >
              <!-- Obojena traka umjesto pune trake preko kartice — gušće, a
                   boja projekta i dalje odmah prepoznatljiva u dugom popisu. -->
              <div class="row-accent" :style="{ background: project.color }" />

              <div class="row-main">
                <div class="row items-center no-wrap">
                  <q-icon
                    v-if="project.visibility === 'private'"
                    name="lock"
                    size="12px"
                    class="lock-icon q-mr-xs"
                  >
                    <q-tooltip>{{ $t('projects.visibilityPrivate') }}</q-tooltip>
                  </q-icon>
                  <div class="row-title col ellipsis">{{ project.name }}</div>
                  <q-badge
                    v-if="notifStore.projectTotal(project.id) > 0"
                    color="negative"
                    rounded
                    class="q-ml-sm"
                  >
                    {{ notifStore.projectTotal(project.id) }}
                  </q-badge>
                </div>
                <div v-if="project.description" class="row-desc ellipsis">
                  {{ project.description }}
                </div>
                <div v-if="tbiProgress(project.id)" class="row items-center q-mt-xs no-wrap">
                  <q-linear-progress
                    :value="tbiProgress(project.id).percent"
                    color="accent"
                    track-color="grey-3"
                    rounded
                    class="col"
                    style="height: 4px"
                  />
                  <span class="row-progress-text q-ml-sm">
                    {{ tbiProgress(project.id).done }}/{{ tbiProgress(project.id).total }}
                  </span>
                </div>
              </div>

              <div class="row-side column items-end justify-between no-wrap">
                <q-btn flat dense round icon="more_vert" size="sm" color="grey" @click.stop>
                  <q-menu auto-close>
                    <q-list dense style="min-width: 140px">
                      <q-item clickable @click.stop="openDialog(project)">
                        <q-item-section side><q-icon name="edit" /></q-item-section>
                        <q-item-section>{{ $t('common.edit') }}</q-item-section>
                      </q-item>
                      <q-separator />
                      <q-item clickable @click.stop="confirmDelete(project)">
                        <q-item-section side
                          ><q-icon name="delete" color="negative"
                        /></q-item-section>
                        <q-item-section class="text-negative">{{
                          $t('common.delete')
                        }}</q-item-section>
                      </q-item>
                    </q-list>
                  </q-menu>
                </q-btn>
                <div class="row-avatars">
                  <UserAvatar
                    v-for="member in cardMembers(project).slice(0, 3)"
                    :key="member.user_id"
                    :avatar-url="member.profiles?.avatar_url"
                    :full-name="member.profiles?.full_name"
                    :size="26"
                    style="margin-left: -8px; border: 2px solid var(--aarc-surface)"
                  />
                </div>
              </div>
            </div>
          </div>
        </div>
      </q-page>
    </q-page-container>

    <!-- FAB — gost ne smije kreirati projekte (create_project RPC to i sam odbija) -->
    <q-page-sticky v-if="!orgsStore.isGuest" position="bottom-right" :offset="[20, 80]">
      <q-btn
        fab
        icon="add"
        style="
          background: linear-gradient(135deg, #007bff, #00d1ff);
          color: white;
          box-shadow: 0 4px 16px rgba(0, 209, 255, 0.4);
        "
        @click="openDialog()"
      />
    </q-page-sticky>

    <!-- Bottom Navigation -->
    <q-footer class="aarc-footer">
      <q-tabs
        v-model="activeTab"
        align="justify"
        active-color="accent"
        inactive-color="grey"
        indicator-color="transparent"
      >
        <q-tab name="home" icon="home" :label="$t('nav.projects')" />
        <!-- Jedina ulazna točka za sve vezano uz organizaciju — prebacivanje,
             novu organizaciju, adresar, postavke. Prije razdvojeno između
             zaglavlja i ove kartice; sad je jasno "sve o organizaciji je ovdje". -->
        <q-tab
          v-if="!orgsStore.isGuest"
          name="org"
          icon="domain"
          :label="$t('org.title')"
          @click="$router.push('/org')"
        >
          <q-badge v-if="otherOrgsUnread" color="negative" floating rounded />
        </q-tab>
        <q-tab
          name="profile"
          icon="person_outline"
          :label="$t('settings.profile')"
          @click="$router.push('/profile')"
        />
      </q-tabs>
    </q-footer>

    <ProjectDialog v-model="dialog" :project="activeProject" />
  </q-layout>
</template>

<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { useQuasar } from 'quasar'
import { useI18n } from 'vue-i18n'
import { useProjectsStore } from 'src/stores/projects'
import { useOrgsStore } from 'src/stores/orgs'
import { useNotificationsStore } from 'src/stores/notifications'
import { useAuthStore } from 'src/stores/auth'
import { useRealtime } from 'src/composables/useRealtime'
import AppHeader from 'src/components/shared/AppHeader.vue'
import UserAvatar from 'src/components/shared/UserAvatar.vue'
import { useOfflineGuard } from 'src/composables/useOfflineGuard'
import ProjectDialog from 'src/components/shared/ProjectDialog.vue'
import { useItemsStore } from 'src/stores/items'

const itemsStore = useItemsStore()
const $q = useQuasar()
const { t } = useI18n()
const projectsStore = useProjectsStore()
const orgsStore = useOrgsStore()
const notifStore = useNotificationsStore()
const { blockedOffline } = useOfflineGuard()
const authStore = useAuthStore()

const dialog = ref(false)
const activeProject = ref(null)
const activeTab = ref('home')
const realtimeCleanups = ref([])

// Home prikazuje TEKUĆU organizaciju, ne sve odjednom — miješanje badgeva
// nepovezanih timova bi značilo da nikad nisi siguran u kojem kontekstu radiš
// (docs/multi-tenancy.md § What this looks like on screen).
const orgProjects = computed(() =>
  projectsStore.projects.filter((p) => p.org_id === orgsStore.currentId),
)

const otherOrgsUnread = computed(() =>
  orgsStore.orgs.some((o) => o.id !== orgsStore.currentId && notifStore.orgUnread(o.id) > 0),
)

// Avatari na kartici: na projektu vidljivom organizaciji project_members je
// otkad postoji B25 samo pretplata, ne popis pristupa — prikazuje se adresar
// organizacije. Na privatnom projektu je project_members i dalje pravi popis
// (isti obrazac kao B20a).
function cardMembers(project) {
  if (project.visibility === 'org') {
    return orgsStore.members.filter((m) => m.role !== 'guest').slice(0, 5)
  }
  return project.project_members?.slice(0, 5) ?? []
}

const firstName = computed(() => {
  const name = authStore.profile?.full_name ?? authStore.user?.email ?? ''
  return name.split(' ')[0]
})

const greeting = computed(() => {
  const h = new Date().getHours()
  const lang = authStore.lang
  if (lang === 'hr') {
    if (h < 12) return 'Dobro jutro'
    if (h < 18) return 'Dobar dan'
    return 'Dobra večer'
  } else {
    if (h < 12) return 'Good morning'
    if (h < 18) return 'Good afternoon'
    return 'Good evening'
  }
})

const tbiProgress = (projectId) => {
  const items = itemsStore.tbi(projectId)
  if (!items.length) return null
  const done = items.filter((i) => i.stage === 'done').length
  return { done, total: items.length, percent: done / items.length }
}

function openDialog(project = null) {
  activeProject.value = project ? { ...project } : null
  dialog.value = true
}

function confirmDelete(project) {
  if (blockedOffline()) return
  $q.dialog({
    title: t('projects.delete'),
    message: project.name,
    ok: { label: t('common.delete'), color: 'negative' },
    cancel: t('common.cancel'),
  }).onOk(async () => {
    await projectsStore.deleteProject(project.id)
  })
}

// Adresar tekuće organizacije prati prebacivanje — i prvi dolazak (immediate),
// jer fetchOrgs() u onMounted može postaviti currentId prije nego se watch
// uopće stigne registrirati.
watch(
  () => orgsStore.currentId,
  (orgId) => {
    if (orgId) orgsStore.fetchMembers(orgId)
  },
  { immediate: true },
)

onMounted(async () => {
  realtimeCleanups.value.forEach((fn) => fn())
  realtimeCleanups.value = []

  await Promise.all([projectsStore.fetchProjects(), orgsStore.fetchOrgs()])

  // Fetch za sve projekte
  await Promise.all(projectsStore.projects.map((p) => itemsStore.fetchItems(p.id)))

  await notifStore.fetchUnread()

  for (const project of projectsStore.projects) {
    // onIdea/onBug su ostaci prije spajanja u jedinstvenu tablicu items (vidi
    // docs/item-model.md) — useRealtime ih ne prepoznaje, pa je realtime za
    // stavke na Homeu tiho bio mrtav otkad je items zamijenio ideas/bugs/tbi.
    const { setup, teardown } = useRealtime(project.id, {
      onMessage: async () => {
        await notifStore.fetchUnread()
      },
      onItem: async () => {
        await notifStore.fetchUnread()
      },
    })
    setup()
    realtimeCleanups.value.push(teardown)
  }
})

onUnmounted(() => {
  realtimeCleanups.value.forEach((fn) => fn())
  realtimeCleanups.value = []
})
</script>

<style scoped>
.aarc-header {
  background: var(--aarc-header) !important;
  border-bottom: 1px solid rgba(0, 209, 255, 0.1);
}

.home-page {
  background: var(--aarc-bg) !important;
}

.home-greeting {
  color: var(--aarc-text);
  font-size: 2.4rem !important;
  line-height: 1.2;
}

.home-section-label {
  color: var(--aarc-text);
}

.aarc-footer {
  background: var(--aarc-header) !important;
  border-top: 1px solid rgba(0, 209, 255, 0.15);
}

/* Okomit popis umjesto bočnog skrolanja — s puno projekata vertikalni prostor
   je jeftin (skrolaš dolje), horizontalni skriva stavke iz vidokruga. */
.project-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.project-row {
  display: flex;
  align-items: stretch;
  border-radius: 16px;
  border: 1px solid var(--aarc-border);
  box-shadow: 0 3px 12px rgba(0, 0, 0, 0.05);
  overflow: hidden;
  transition: box-shadow 0.2s;
}

.project-row:active {
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.08);
}

/* Obojena traka slijeva nosi identitet projekta u gušćem popisu — zamjena za
   punu traku preko vrha kartice, koja bi ovdje bila prevelika. */
.row-accent {
  width: 5px;
  flex-shrink: 0;
}

.row-main {
  flex: 1;
  min-width: 0;
  padding: 12px 14px;
}

.row-title {
  min-width: 0;
  font-size: 16px;
  font-weight: 700;
  color: var(--aarc-text);
}

.row-desc {
  color: var(--aarc-muted);
  font-size: 13px;
  margin-top: 2px;
}

.row-progress-text {
  color: var(--aarc-muted);
  font-size: 11px;
  flex-shrink: 0;
}

.row-side {
  flex-shrink: 0;
  padding: 6px 8px;
}

.row-avatars {
  display: flex;
  padding-right: 8px;
}

/* Na kartici projekta (--aarc-surface pozadina), ne u zaglavlju */
.lock-icon {
  color: var(--aarc-muted);
  flex-shrink: 0;
}
</style>
