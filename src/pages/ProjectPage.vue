<template>
  <q-layout view="hHh lpR fFf">
    <AppHeader :title="project?.name" back back-to="/" settings>
      <template #actions>
        <q-btn flat round dense icon="group" color="white" @click="memberDialog = true" />
      </template>
      <template #tabs>
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
      <q-tab-panels v-model="tab" animated keep-alive>
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

    <MemberDialog v-model="memberDialog" :project-id="projectId" />
  </q-layout>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { useRoute } from 'vue-router'
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
const projectId = route.params.id
const tab = ref('chat')

// ProjectPage.vue - watch samo fetchUnread, ne markRead
watch(tab, async (newTab) => {
  if (newTab === 'chat') {
    await notifStore.fetchUnread()
  }
})

const memberDialog = ref(false)

const projectsStore = useProjectsStore()
const itemsStore = useItemsStore()
const chatStore = useChatStore()
let reactionsChannel = null
const notifStore = useNotificationsStore()

const project = computed(() => projectsStore.projects.find((p) => p.id === projectId))

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
