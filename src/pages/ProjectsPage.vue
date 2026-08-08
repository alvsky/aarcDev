<template>
  <q-layout view="hHh lpR fFf">
    <AppHeader settings>
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
            v-if="!projectsStore.projects.length"
            class="text-center q-mt-xl"
            style="color: var(--aarc-muted)"
          >
            {{ $t('projects.noProjects') }}
          </div>

          <div class="scroll-row">
            <div
              v-for="project in projectsStore.projects"
              :key="project.id"
              class="project-card-h cursor-pointer"
              @click="$router.push(`/project/${project.id}`)"
            >
              <!-- Color bar na vrhu kartice -->
              <div class="card-color-bar" :style="{ background: project.color }" />

              <!-- Header kartice -->
              <div class="row items-start no-wrap q-mt-md q-mb-md">
                <div class="col">
                  <div class="card-title ellipsis-2-lines">{{ project.name }}</div>
                  <div v-if="project.description" class="card-desc q-mt-xs ellipsis">
                    {{ project.description }}
                  </div>
                </div>
                <q-btn flat dense round icon="more_vert" size="md" color="grey" @click.stop>
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
              </div>

              <!-- Progress -->
              <div v-if="tbiProgress(project.id)" class="q-mb-md">
                <div class="row items-center q-mb-sm">
                  <span class="card-desc">
                    {{ tbiProgress(project.id).done }}/{{ tbiProgress(project.id).total }} završeno
                  </span>
                  <q-space />
                  <q-badge v-if="notifStore.projectTotal(project.id) > 0" color="negative" rounded>
                    {{ notifStore.projectTotal(project.id) }}
                  </q-badge>
                </div>
                <q-linear-progress
                  :value="tbiProgress(project.id).percent"
                  color="accent"
                  track-color="grey-3"
                  rounded
                  style="height: 6px"
                />
              </div>

              <!-- Članovi -->
              <div class="row items-center q-mt-md">
                <UserAvatar
                  v-for="member in project.project_members?.slice(0, 5)"
                  :key="member.user_id"
                  :avatar-url="member.profiles?.avatar_url"
                  :full-name="member.profiles?.full_name"
                  :size="60"
                  style="margin-right: -12px; border: 2px solid var(--aarc-surface)"
                />
                <q-space />
                <q-badge
                  v-if="!tbiProgress(project.id) && notifStore.projectTotal(project.id) > 0"
                  color="negative"
                  rounded
                >
                  {{ notifStore.projectTotal(project.id) }}
                </q-badge>
              </div>
            </div>
          </div>
        </div>

        <!-- Tim -->
        <div class="q-px-md q-mb-xl" v-if="allMembers.length">
          <div class="text-h6 text-weight-medium q-mb-lg home-section-label">
            {{ $t('projects.members') }}
          </div>
          <div class="row q-gutter-lg">
            <div v-for="member in allMembers" :key="member.id" class="column items-center">
              <UserAvatar
                :avatar-url="member.avatar_url"
                :full-name="member.full_name"
                :size="80"
                style="border: 3px solid var(--aarc-border)"
              />
              <div class="member-name q-mt-sm">
                {{ member.full_name?.split(' ')[0] }}
              </div>
            </div>
          </div>
        </div>
      </q-page>
    </q-page-container>

    <!-- FAB -->
    <q-page-sticky position="bottom-right" :offset="[20, 80]">
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
        <!-- <q-tab name="projects" icon="folder_open" label="Projekti" /> -->
        <q-tab name="team" icon="group" label="Tim" />
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
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useQuasar } from 'quasar'
import { useI18n } from 'vue-i18n'
import { useProjectsStore } from 'src/stores/projects'
import { useNotificationsStore } from 'src/stores/notifications'
import { useTbiStore } from 'src/stores/tbi'
import { useAuthStore } from 'src/stores/auth'
import { useRealtime } from 'src/composables/useRealtime'
import AppHeader from 'src/components/shared/AppHeader.vue'
import UserAvatar from 'src/components/shared/UserAvatar.vue'
import { useOfflineGuard } from 'src/composables/useOfflineGuard'
import ProjectDialog from 'src/components/shared/ProjectDialog.vue'
import { useIdeasStore } from 'src/stores/ideas'
import { useBugsStore } from 'src/stores/bugs'

const ideasStore = useIdeasStore()
const bugsStore = useBugsStore()
const tbiStore = useTbiStore()
const $q = useQuasar()
const { t } = useI18n()
const projectsStore = useProjectsStore()
const notifStore = useNotificationsStore()
const { blockedOffline } = useOfflineGuard()
const authStore = useAuthStore()

const dialog = ref(false)
const activeProject = ref(null)
const activeTab = ref('home')
const realtimeCleanups = ref([])

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

const allMembers = computed(() => {
  const seen = new Set()
  const members = []
  for (const project of projectsStore.projects) {
    for (const m of project.project_members ?? []) {
      if (!seen.has(m.user_id) && m.profiles) {
        seen.add(m.user_id)
        members.push({ id: m.user_id, ...m.profiles })
      }
    }
  }
  return members
})

const tbiProgress = (projectId) => {
  const items = tbiStore.items.filter((i) => i.project_id === projectId)
  if (!items.length) return null
  const done = items.filter((i) => i.status === 'done').length
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

onMounted(async () => {
  realtimeCleanups.value.forEach((fn) => fn())
  realtimeCleanups.value = []

  await projectsStore.fetchProjects()

  // Fetch za sve projekte
  await Promise.all(
    projectsStore.projects.map((p) =>
      Promise.all([
        ideasStore.fetchIdeas(p.id),
        bugsStore.fetchBugs(p.id),
        tbiStore.fetchItems(p.id),
      ]),
    ),
  )

  await notifStore.fetchUnread()

  for (const project of projectsStore.projects) {
    const { setup, teardown } = useRealtime(project.id, {
      onMessage: async () => {
        await notifStore.fetchUnread()
      },
      onIdea: async () => {
        await notifStore.fetchUnread()
      },
      onBug: async () => {
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

.scroll-row {
  display: flex;
  gap: 16px;
  overflow-x: auto;
  padding-bottom: 12px;
  scrollbar-width: none;
}
.scroll-row::-webkit-scrollbar {
  display: none;
}

.card-color-bar {
  height: 5px;
  border-radius: 4px;
  width: 100%;
}

.project-card-h {
  flex: 0 0 85vw;
  max-width: 380px;
  background: var(--aarc-surface);
  border-radius: 20px;
  padding: 20px 24px 24px;
  border: 1px solid var(--aarc-border);
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.06);
  transition: box-shadow 0.2s;
}

.project-card-h:active {
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
}

.card-title {
  font-size: 22px;
  font-weight: 700;
  color: var(--aarc-text);
  line-height: 1.3;
}

.card-desc {
  color: var(--aarc-muted);
  font-size: 15px;
}

.member-name {
  color: var(--aarc-muted);
  font-size: 14px;
  text-align: center;
  font-weight: 500;
}
</style>
