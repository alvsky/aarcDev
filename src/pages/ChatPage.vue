<template>
  <q-page class="column no-wrap" style="height: 0">
    <q-tabs
      v-model="channel"
      dense
      align="left"
      class="q-px-md col-auto"
      indicator-color="primary"
      @update:model-value="switchChannel"
    >
      <q-tab name="main" icon="forum">
        <div class="row items-center q-gutter-xs">
          <span>{{ $t('chat.channels.main') }}</span>
          <q-badge
            v-if="notifStore.threadUnread({ projectId, channel: 'main' }) > 0"
            color="negative"
            rounded
          >
            {{ notifStore.threadUnread({ projectId, channel: 'main' }) }}
          </q-badge>
        </div>
      </q-tab>

      <q-tab name="offtopic" icon="coffee">
        <div class="row items-center q-gutter-xs">
          <span>{{ $t('chat.channels.offtopic') }}</span>
          <q-badge
            v-if="notifStore.threadUnread({ projectId, channel: 'offtopic' }) > 0"
            color="negative"
            rounded
          >
            {{ notifStore.threadUnread({ projectId, channel: 'offtopic' }) }}
          </q-badge>
        </div>
      </q-tab>
    </q-tabs>

    <q-separator />

    <ChatPanel
      ref="chatPanelRef"
      class="col"
      :project-id="projectId"
      :channel="channel"
      @scrolled-to-bottom="onMessagesRead"
    />
  </q-page>
</template>

<script setup>
import { ref, onMounted, onActivated, nextTick } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useChatStore } from 'src/stores/chat'
import { useNotificationsStore } from 'src/stores/notifications'
import ChatPanel from 'src/components/chat/ChatPanel.vue'

const props = defineProps({ projectId: String })

const router = useRouter()
const route = useRoute()
const chatStore = useChatStore()
const notifStore = useNotificationsStore()
// I1/I2: ?channel=... u adresi (npr. iz push notifikacije) bira početni
// kanal umjesto uvijek 'main'; query se odmah čisti da se refresh/dijeljeni
// link ne otvara stalno na istom mjestu.
const channel = ref(route.query.channel === 'offtopic' ? 'offtopic' : 'main')
if (route.query.channel) router.replace({ query: {} })

const chatPanelRef = ref(null)

async function loadChannel(ch) {
  await chatStore.fetchMessages({ projectId: props.projectId, channel: ch })
  await notifStore.markRead({ projectId: props.projectId, channel: ch })
  await notifStore.fetchUnread()
  // Scroll nakon što su poruke učitane
  await nextTick()
  chatPanelRef.value?.scrollToBottom()
}

async function onMessagesRead() {
  await notifStore.markRead({ projectId: props.projectId, channel: channel.value })
  await notifStore.fetchUnread()
}

async function switchChannel(ch) {
  channel.value = ch
  await loadChannel(ch)
}

onMounted(async () => {
  await loadChannel(channel.value)
})

onActivated(async () => {
  await loadChannel(channel.value)
})
</script>
