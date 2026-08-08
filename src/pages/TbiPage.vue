<template>
  <q-page padding>
    <div class="row items-center q-mb-md">
      <div class="text-h6">{{ $t('tbi.title') }}</div>
      <q-space />
      <q-btn color="primary" icon="add" :label="$t('tbi.new')" @click="openDialog()" />
    </div>

    <!-- Filteri -->
    <div class="row q-gutter-sm q-mb-md">
      <q-select
        v-model="sourceFilter"
        :options="sourceOptions"
        :label="$t('tbi.source.label')"
        outlined
        dense
        emit-value
        map-options
        style="min-width: 140px"
      />
      <q-select
        v-model="statusFilter"
        :options="statusOptions"
        :label="$t('common.status')"
        outlined
        dense
        emit-value
        map-options
        style="min-width: 140px"
      />
    </div>

    <div v-if="!filtered.length" class="text-center text-grey-5 q-mt-xl">
      {{ $t('tbi.noItems') }}
    </div>

    <div class="q-gutter-sm">
      <TbiCard
        v-for="item in filtered"
        :key="item.id"
        :item="item"
        :project-id="projectId"
        :members="members"
        @edit="openDialog(item)"
        @delete="confirmDelete(item)"
        @mark-done="markDone(item)"
        @mark-undone="markUndone(item)"
        @assign="(userId) => assign(item.id, userId)"
        @open-thread="openThread(item)"
        @demote="confirmDemote(item)"
      />
    </div>

    <ItemDialog v-model="dialog" type="tbi" :item="activeItem" :project-id="projectId" />

    <!-- Thread chat — TBI prikazuje i poruke izvorne ideje/buga -->
    <ThreadDialog
      v-model="threadOpen"
      :title="threadItem?.title"
      :project-id="projectId"
      :tbi-id="threadItem?.id"
      :messages="combinedMessages"
      @close="onThreadClosed"
    />
  </q-page>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useQuasar } from 'quasar'
import { useI18n } from 'vue-i18n'
import { useTbiStore } from 'src/stores/tbi'
import { useChatStore } from 'src/stores/chat'
import { useNotificationsStore } from 'src/stores/notifications'
import { useProjectsStore } from 'src/stores/projects'
import { useOfflineGuard } from 'src/composables/useOfflineGuard'
import TbiCard from 'src/components/tbi/TbiCard.vue'
import ThreadDialog from 'src/components/chat/ThreadDialog.vue'
import { useIdeasStore } from 'src/stores/ideas'
import ItemDialog from 'src/components/shared/ItemDialog.vue'

const props = defineProps({ projectId: String })

const $q = useQuasar()
const { t } = useI18n()
const tbiStore = useTbiStore()
const chatStore = useChatStore()
const notifStore = useNotificationsStore()
const projectsStore = useProjectsStore()
const ideasStore = useIdeasStore()
const { blockedOffline } = useOfflineGuard()

const dialog = ref(false)
const activeItem = ref(null)
const threadOpen = ref(false)
const threadItem = ref(null)

const sourceFilter = ref('all')
const statusFilter = ref('all')

const sourceOptions = computed(() => [
  { label: t('common.all'), value: 'all' },
  { label: t('tbi.source.idea'), value: 'idea' },
  { label: t('tbi.source.bug'), value: 'bug' },
  { label: t('tbi.source.manual'), value: 'manual' },
])

const statusOptions = computed(() => [
  { label: t('common.all'), value: 'all' },
  { label: t('tbi.status.tbi'), value: 'tbi' },
  { label: t('tbi.status.in_progress'), value: 'in_progress' },
  { label: t('tbi.status.done'), value: 'done' },
])

const combinedMessages = computed(() => {
  if (!threadItem.value) return []

  const tbiKey = chatStore.threadKey({ projectId: props.projectId, tbiId: threadItem.value.id })
  const tbiMsgs = chatStore.threadMessages(tbiKey)

  let sourceMsgs = []
  if (threadItem.value.source_type === 'idea' && threadItem.value.idea_id) {
    const ideaKey = chatStore.threadKey({
      projectId: props.projectId,
      ideaId: threadItem.value.idea_id,
    })
    sourceMsgs = chatStore.threadMessages(ideaKey)
  } else if (threadItem.value.source_type === 'bug' && threadItem.value.bug_id) {
    const bugKey = chatStore.threadKey({
      projectId: props.projectId,
      bugId: threadItem.value.bug_id,
    })
    sourceMsgs = chatStore.threadMessages(bugKey)
  }

  // Spoji i sortiraj po vremenu
  return [...sourceMsgs, ...tbiMsgs].sort((a, b) => new Date(a.created_at) - new Date(b.created_at))
})

const members = computed(
  () => projectsStore.projects.find((p) => p.id === props.projectId)?.project_members ?? [],
)

const filtered = computed(() => {
  let items = tbiStore.items.filter((i) => i.project_id === props.projectId)
  if (sourceFilter.value !== 'all') {
    items = items.filter((i) => i.source_type === sourceFilter.value)
  }
  if (statusFilter.value !== 'all') {
    items = items.filter((i) => i.status === statusFilter.value)
  }
  // Gotove na kraj
  return [...items.filter((i) => i.status !== 'done'), ...items.filter((i) => i.status === 'done')]
})

function openDialog(item = null) {
  activeItem.value = item ? { ...item } : null
  dialog.value = true
}

async function openThread(item) {
  threadItem.value = item
  threadOpen.value = true

  // Učitaj TBI thread poruke
  await chatStore.fetchMessages({
    projectId: props.projectId,
    tbiId: item.id,
  })

  // Ako je promovirana ideja, učitaj i originalni idea thread
  if (item.source_type === 'idea' && item.idea_id) {
    await chatStore.fetchMessages({
      projectId: props.projectId,
      ideaId: item.idea_id,
    })
  }

  // Ako je promoviran bug, učitaj i originalni bug thread
  if (item.source_type === 'bug' && item.bug_id) {
    await chatStore.fetchMessages({
      projectId: props.projectId,
      bugId: item.bug_id,
    })
  }

  await notifStore.markRead({ projectId: props.projectId, tbiId: item.id })
}

async function onThreadClosed() {
  threadItem.value = null
  await tbiStore.fetchItems(props.projectId)
}

function confirmDemote(item) {
  if (blockedOffline()) return
  $q.dialog({
    title: t('ideas.demote'),
    message: item.title,
    ok: { label: t('common.confirm'), color: 'warning' },
    cancel: t('common.cancel'),
  }).onOk(async () => {
    await ideasStore.demoteFromTbi(item)
    await tbiStore.fetchItems(props.projectId)
    $q.notify({ type: 'positive', message: t('ideas.demote') })
  })
}
async function markDone(item) {
  if (blockedOffline('common.offlineNoAction')) return
  $q.dialog({
    title: t('tbi.markDone'),
    message: t('tbi.confirmDone'),
    ok: { label: t('common.confirm'), color: 'positive' },
    cancel: t('common.cancel'),
  }).onOk(async () => {
    await tbiStore.markDone(item.id)
    $q.notify({ type: 'positive', message: t('tbi.markDone') })
  })
}

async function markUndone(item) {
  if (blockedOffline('common.offlineNoAction')) return
  await tbiStore.markUndone(item.id)
  $q.notify({ type: 'positive', message: t('tbi.markUndone') })
}

function assign(itemId, userId) {
  if (blockedOffline('common.offlineNoAction')) return
  tbiStore.assignUser(itemId, userId)
}

function confirmDelete(item) {
  if (blockedOffline()) return
  $q.dialog({
    title: t('common.delete'),
    message: item.title,
    ok: { label: t('common.delete'), color: 'negative' },
    cancel: t('common.cancel'),
  }).onOk(async () => {
    await tbiStore.deleteItem(item.id)
    await tbiStore.fetchItems(props.projectId) // ← dodaj ovo
  })
}

onMounted(async () => {
  await tbiStore.fetchItems(props.projectId)
})
</script>
