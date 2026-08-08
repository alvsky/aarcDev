<template>
  <q-page padding>
    <div class="row items-center q-mb-md">
      <div class="text-h6">{{ $t('ideas.title') }}</div>
      <q-space />
      <q-btn color="primary" icon="add" :label="$t('ideas.new')" @click="openDialog()" />
    </div>

    <div v-if="!ideasStore.ideas.length" class="text-center text-grey-5 q-mt-xl">
      {{ $t('ideas.noIdeas') }}
    </div>

    <div class="q-gutter-sm">
      <q-list>
        <IdeaCard
          v-for="idea in ideasStore.ideas.filter((i) => i.project_id === projectId && !i.promoted)"
          :key="idea.id"
          :idea="idea"
          :project-id="projectId"
          @edit="openDialog(idea)"
          @delete="confirmDelete(idea)"
          @promote="confirmPromote(idea)"
          @open-thread="openThread(idea)"
        />
      </q-list>
    </div>

    <!-- Dialog nova/edit ideja -->
    <ItemDialog v-model="dialog" type="idea" :item="activeIdea" :project-id="projectId" />

    <!-- Thread chat -->
    <ThreadDialog
      v-model="threadOpen"
      :title="threadIdea?.title"
      :project-id="projectId"
      :idea-id="threadIdea?.id"
      @close="onThreadClosed"
    />
  </q-page>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useQuasar } from 'quasar'
import { useI18n } from 'vue-i18n'
import { useIdeasStore } from 'src/stores/ideas'
import { useChatStore } from 'src/stores/chat'
import { useNotificationsStore } from 'src/stores/notifications'
import { useOfflineGuard } from 'src/composables/useOfflineGuard'
import IdeaCard from 'src/components/ideas/IdeaCard.vue'
import ThreadDialog from 'src/components/chat/ThreadDialog.vue'
import ItemDialog from 'src/components/shared/ItemDialog.vue'

const props = defineProps({ projectId: String })

const $q = useQuasar()
const { t } = useI18n()
const ideasStore = useIdeasStore()
const chatStore = useChatStore()
const notifStore = useNotificationsStore()
const { blockedOffline } = useOfflineGuard()

const dialog = ref(false)
const activeIdea = ref(null)
const threadOpen = ref(false)
const threadIdea = ref(null)

function openDialog(idea = null) {
  activeIdea.value = idea ? { ...idea } : null
  dialog.value = true
}

async function openThread(idea) {
  threadIdea.value = idea
  threadOpen.value = true
  await chatStore.fetchMessages({
    projectId: props.projectId,
    ideaId: idea.id,
  })
  await notifStore.markRead({
    projectId: props.projectId,
    ideaId: idea.id,
  })
}

async function onThreadClosed() {
  threadIdea.value = null
  await ideasStore.fetchIdeas(props.projectId)
}

function confirmDelete(idea) {
  if (blockedOffline()) return
  $q.dialog({
    title: t('common.delete'),
    message: idea.title,
    ok: { label: t('common.delete'), color: 'negative' },
    cancel: t('common.cancel'),
  }).onOk(async () => {
    await ideasStore.deleteIdea(idea.id)
  })
}

function confirmPromote(idea) {
  if (blockedOffline('common.offlineNoAction')) return
  $q.dialog({
    title: t('ideas.promote'),
    message: t('ideas.confirmPromote'),
    ok: { label: t('common.confirm'), color: 'primary' },
    cancel: t('common.cancel'),
  }).onOk(async () => {
    await ideasStore.promoteToTbi(idea)
    $q.notify({ type: 'positive', message: t('ideas.promote') })
  })
}

onMounted(async () => {
  await ideasStore.fetchIdeas(props.projectId)
})
</script>
