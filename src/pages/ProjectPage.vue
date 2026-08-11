<template>
  <q-layout view="hHh lpR fFf">
    <AppHeader
      :title="project?.name || (notFound ? $t('projects.noAccessTitle') : '')"
      back
      back-to="/"
      :settings="!notFound"
    >
      <template v-if="!notFound" #actions>
        <q-btn flat round dense icon="group" color="white" @click="memberDialog = true" />
      </template>
      <template v-if="!notFound" #tabs>
        <q-tabs v-model="tab" align="justify" dense indicator-color="white" active-color="white">
          <q-tab name="chat" icon="forum">
            <div class="row items-center q-gutter-xs">
              <span>{{ $t('nav.chat') }}</span>
              <q-badge v-if="chatUnread > 0" color="negative" floating rounded>
                {{ chatUnread }}
              </q-badge>
            </div>
          </q-tab>
          <q-tab name="bugs" icon="bug_report">
            <div class="row items-center q-gutter-xs">
              <span>{{ $t('nav.bugs') }}</span>
              <q-badge v-if="notifStore.newBugs(projectId) > 0" color="negative" floating rounded>
                {{ notifStore.newBugs(projectId) }}
              </q-badge>
            </div>
          </q-tab>
          <q-tab name="ideas" icon="lightbulb">
            <div class="row items-center q-gutter-xs">
              <span>{{ $t('nav.ideas') }}</span>
              <q-badge v-if="notifStore.newIdeas(projectId) > 0" color="negative" floating rounded>
                {{ notifStore.newIdeas(projectId) }}
              </q-badge>
            </div>
          </q-tab>

          <q-tab name="tbi" icon="checklist">
            <div class="row items-center q-gutter-xs">
              <span>{{ $t('nav.tbi') }}</span>
              <q-badge v-if="notifStore.newTbi(projectId) > 0" color="negative" floating rounded>
                {{ notifStore.newTbi(projectId) }}
              </q-badge>
            </div>
          </q-tab>
        </q-tabs>
      </template>
    </AppHeader>

    <q-page-container>
      <div v-if="loading" class="flex flex-center q-pa-xl">
        <q-spinner size="40px" color="primary" />
      </div>

      <!-- RLS je ispravno odbio (projekt ne postoji ili nemaš pristup) — ovo
           je namjerno, ne kvar. Bez ovoga stranica ostane prazna i bez
           naslova, pa se ne razlikuje od stvarnog pada (B21b). -->
      <q-page v-else-if="notFound" class="flex flex-center column text-center q-pa-xl">
        <q-icon name="lock" size="48px" class="no-access-icon q-mb-md" />
        <div class="text-h6 q-mb-xs">{{ $t('projects.noAccessTitle') }}</div>
        <div class="text-body2 no-access-body q-mb-lg">{{ $t('projects.noAccessBody') }}</div>
        <q-btn color="primary" :label="$t('projects.backHome')" to="/" />
      </q-page>

      <q-tab-panels v-else v-model="tab" animated keep-alive>
        <q-tab-panel name="chat" class="q-pa-none">
          <ChatPage :project-id="projectId" />
        </q-tab-panel>
        <q-tab-panel name="ideas" class="q-pa-none">
          <IdeasPage :project-id="projectId" />
        </q-tab-panel>
        <q-tab-panel name="bugs" class="q-pa-none">
          <BugsPage :project-id="projectId" />
        </q-tab-panel>
        <q-tab-panel name="tbi" class="q-pa-none">
          <TbiPage :project-id="projectId" />
        </q-tab-panel>
      </q-tab-panels>
    </q-page-container>

    <MemberDialog v-if="!notFound" v-model="memberDialog" :project-id="projectId" />
  </q-layout>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useProjectsStore } from 'src/stores/projects'
import { useItemsStore } from 'src/stores/items'
import { useChatStore } from 'src/stores/chat'
import { useNotificationsStore } from 'src/stores/notifications'
import { useRealtime } from 'src/composables/useRealtime'
import { supabase } from 'src/boot/supabase'
import IdeasPage from './IdeasPage.vue'
import BugsPage from './BugsPage.vue'
import TbiPage from './TbiPage.vue'
import ChatPage from './ChatPage.vue'
import MemberDialog from 'src/components/shared/MemberDialog.vue'
import AppHeader from 'src/components/shared/AppHeader.vue'

const route = useRoute()
const router = useRouter()
const projectId = route.params.id

// I1: kartica živi u URL-u (route.params.tab), ne u lokalnom stanju — tako
// push deep-link (usePush.js) i običan klik na projekt prolaze isti put, i
// tab preživi refresh/dijeljeni link. Postavljanje ide kroz router.replace
// (ne push) da svaki dodir taba ne buši povijest natrag-gumba.
const tab = computed({
  get: () => route.params.tab || 'chat',
  set: (newTab) => {
    if (newTab === tab.value) return
    // Ručna promjena taba svjesno odbacuje query (item/channel deep-link) —
    // ta meta vrijedi samo za navigaciju KOJA je donijela deep-link, ne za
    // svaki idući klik na taj tab.
    router.replace(`/project/${projectId}/${newTab}`)
  },
})

// ProjectPage.vue - watch samo fetchUnread, ne markRead
watch(tab, async (newTab) => {
  if (newTab === 'chat') {
    await notifStore.fetchUnread()
  }
})

const memberDialog = ref(false)
const loading = ref(true)

const projectsStore = useProjectsStore()
const itemsStore = useItemsStore()
const chatStore = useChatStore()
let reactionsChannel = null
const notifStore = useNotificationsStore()

const project = computed(() => projectsStore.projects.find((p) => p.id === projectId))
const notFound = computed(() => !loading.value && !project.value)

const chatUnread = computed(
  () =>
    notifStore.threadUnread({ projectId, channel: 'main' }) +
    notifStore.threadUnread({ projectId, channel: 'offtopic' }),
)

const { setup, teardown } = useRealtime(projectId, {
  onMessage: async (p) => {
    // console.log('onMessage event:', p.event, p.payload.new?.id)
    await chatStore.handleIncoming(p)
    await notifStore.fetchUnread()
  },
  onItem: async (p) => {
    itemsStore.handleIncoming(p)
    await notifStore.fetchUnread()
  },
})

const messagesUpdateChannel = supabase
  .channel(`msg-update:${projectId}`)
  .on(
    'postgres_changes',
    {
      event: 'UPDATE',
      schema: 'public',
      table: 'messages',
    },
    async (payload) => {
      console.log('Message UPDATE:', payload.new?.id, payload.new?.body)
      await chatStore.handleIncoming({ event: 'UPDATE', payload })
    },
  )
  .subscribe()

onMounted(async () => {
  // Dubinski link preskače Home, pa popis projekata nikad nije dohvaćen — bez
  // ovoga nema naziva projekta ni članova za dodjelu, i stranica izgleda prazno
  // iako sadržaj postoji. Time se "nemam pristup" i "nije učitano" prestaju
  // doimati isto.
  const projectUnknown = !projectsStore.projects.some((p) => p.id === projectId)
  if (projectUnknown) await projectsStore.fetchProjects()
  loading.value = false

  // RLS je ispravno odbio ili projekt ne postoji — ne dohvaćaj ništa ostalo
  // (item/chat upiti bi ionako vratili prazno), predložak prikazuje notFound.
  if (!project.value) return

  await Promise.all([
    itemsStore.fetchItems(projectId),
    notifStore.fetchUnread(),
    chatStore.fetchMessages({ projectId, channel: 'main' }),
  ])
  setup()

  reactionsChannel = supabase
    .channel(`reactions:${projectId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'message_reactions',
      },
      async (payload) => {
        const msgId = payload.new?.message_id || payload.old?.message_id
        if (!msgId) return
        const reactions = await chatStore.fetchReactions([msgId])
        for (const key of Object.keys(chatStore.threads)) {
          const msg = chatStore.threads[key]?.find((m) => m.id === msgId)
          if (msg) {
            msg.reactions = reactions[msgId] ?? []
            break
          }
        }
      },
    )
    .subscribe()
})

onUnmounted(() => {
  teardown()
  if (reactionsChannel) supabase.removeChannel(reactionsChannel)
  if (messagesUpdateChannel) supabase.removeChannel(messagesUpdateChannel)
})
</script>

<style scoped>
.no-access-icon {
  color: var(--aarc-muted);
}
.no-access-body {
  color: var(--aarc-muted);
}
</style>
