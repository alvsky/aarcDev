<template>
  <q-expansion-item
    group="tbi"
    expand-separator
    :class="{ 'opacity-5': item.status === 'done' }"
    :header-class="item.status === 'done' ? 'text-grey-5' : ''"
    @update:model-value="(val) => val && onOpen()"
  >
    <template #header>
      <q-item-section avatar>
        <q-checkbox
          :model-value="item.status === 'done'"
          @update:model-value="(v) => (v ? $emit('mark-done') : $emit('mark-undone'))"
          dense
          @click.stop
        />
      </q-item-section>

      <q-item-section>
        <q-item-label :class="{ 'text-strike': item.status === 'done' }">
          {{ item.title }}
          <!-- Novo indikator -->
          <q-badge
            v-if="item.is_new"
            color="accent"
            class="q-ml-xs"
            style="font-size: 9px; padding: 2px 5px"
          >
            NEW
          </q-badge>
        </q-item-label>
        <q-item-label caption>
          <q-badge :color="sourceColor(item.source_type)" outline class="q-mr-xs">
            {{ $t(`tbi.source.${item.source_type}`) }}
          </q-badge>
          <q-badge :color="prioColor(item.priority)" class="q-mr-xs">
            {{ $t(`tbi.priority.${item.priority}`) }}
          </q-badge>
          <q-badge :color="statusColor(item.status)" outline>
            {{ $t(`tbi.status.${item.status}`) }}
          </q-badge>
        </q-item-label>
      </q-item-section>

      <q-item-section side>
        <div class="row items-center q-gutter-xs">
          <q-btn
            flat
            round
            dense
            icon="forum"
            size="sm"
            color="grey-6"
            @click.stop="$emit('open-thread')"
          >
            <q-badge v-if="unread > 0" color="negative" floating rounded>
              {{ unread }}
            </q-badge>
          </q-btn>
          <div
            v-if="messageCount > 0"
            class="text-caption"
            style="color: var(--aarc-muted); font-size: 10px"
          >
            {{ messageCount }}
          </div>
        </div>
      </q-item-section>
    </template>

    <!-- Expanded sadržaj -->
    <q-card flat class="q-mx-md q-mb-sm">
      <q-card-section class="q-pa-sm">
        <!-- Opis -->
        <div v-if="item.description" class="text-body2 q-mb-sm">
          {{ item.description }}
        </div>

        <!-- Screenshot -->
        <ChatImage
          v-if="item.screenshot_url"
          :path="item.screenshot_url"
          :alt="item.title"
          class="q-mb-sm"
        />

        <!-- Status i dodjela -->
        <div class="row q-gutter-sm q-mb-sm">
          <q-select
            :model-value="item.status"
            :options="statusOptions"
            emit-value
            map-options
            dense
            outlined
            style="min-width: 130px"
            :label="$t('common.status')"
            @update:model-value="(v) => updateStatus(v)"
          />
          <q-select
            :model-value="item.assignee_id"
            :options="memberOptions"
            emit-value
            map-options
            dense
            outlined
            clearable
            style="min-width: 130px"
            :label="$t('tbi.assignee')"
            @update:model-value="(v) => $emit('assign', v)"
          />
        </div>

        <!-- Assignee + completed info -->
        <div class="row items-center q-gutter-sm text-caption text-grey-5 q-mb-sm">
          <q-icon name="person" size="12px" />
          <span>{{ item.profiles?.full_name }}</span>
          <q-icon name="schedule" size="12px" />
          <span>{{ formatDate.relative(item.created_at) }}</span>
          <template v-if="item.assignee">
            <q-icon name="assignment_ind" size="12px" />
            <span>{{ item.assignee?.full_name }}</span>
          </template>
          <template v-if="item.completed_at">
            <q-icon name="check_circle" size="12px" color="positive" />
            <span>{{ formatDate.smart(item.completed_at) }}</span>
          </template>
        </div>

        <!-- Akcije -->

        <div class="row q-gutter-xs">
          <q-btn
            v-if="item.source_type === 'idea'"
            flat
            dense
            icon="undo"
            size="sm"
            color="warning"
            :label="$t('ideas.demote')"
            @click="$emit('demote')"
          />
          <q-btn
            flat
            dense
            icon="edit"
            size="sm"
            :label="$t('common.edit')"
            @click="$emit('edit')"
          />
          <q-btn
            flat
            dense
            icon="delete"
            size="sm"
            color="negative"
            :label="$t('common.delete')"
            @click="$emit('delete')"
          />
        </div>
      </q-card-section>
    </q-card>
  </q-expansion-item>
</template>

<script setup>
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useTbiStore } from 'src/stores/tbi'
import { useNotificationsStore } from 'src/stores/notifications'
import { useFormatDate } from 'src/composables/useFormatDate'
import ChatImage from 'src/components/chat/ChatImage.vue'

const notifStore = useNotificationsStore()
const tbiStore = useTbiStore()

async function onOpen() {
  if (!props.item.is_new) return

  // Prvo ažuriraj lokalno
  const idx = tbiStore.items.findIndex((i) => i.id === props.item.id)
  if (idx !== -1) tbiStore.items[idx].is_new = false

  // Pa spremi u bazu i osvježi badge
  await notifStore.markItemRead(props.item.id, 'tbi')
}

const props = defineProps({
  item: { type: Object, required: true },
  projectId: { type: String, required: true },
  members: { type: Array, default: () => [] },
})

defineEmits(['edit', 'delete', 'mark-done', 'mark-undone', 'assign', 'open-thread', 'demote'])

const { t } = useI18n()
const formatDate = useFormatDate()
// const chatStore = useChatStore()

const memberOptions = computed(() =>
  props.members.map((m) => ({
    label: m.profiles?.full_name ?? m.profiles?.email,
    value: m.user_id,
  })),
)

const statusOptions = computed(() => [
  { label: t('tbi.status.tbi'), value: 'tbi' },
  { label: t('tbi.status.in_progress'), value: 'in_progress' },
  { label: t('tbi.status.done'), value: 'done' },
])

const unread = computed(() =>
  notifStore.threadUnread({ projectId: props.projectId, tbiId: props.item.id }),
)

const messageCount = computed(() => {
  console.log('TBI messageCount for', props.item.title, ':', props.item.message_count)
  return props.item.message_count ?? 0
})
const sourceColor = (s) => ({ idea: 'purple', bug: 'negative', manual: 'grey-6' })[s] ?? 'grey'
const prioColor = (p) => ({ high: 'negative', med: 'warning', low: 'positive' })[p] ?? 'grey'
const statusColor = (s) => ({ tbi: 'grey', in_progress: 'warning', done: 'positive' })[s] ?? 'grey'

async function updateStatus(status) {
  if (status === 'done') {
    await tbiStore.markDone(props.item.id)
  } else {
    await tbiStore.updateItem(props.item.id, { status })
  }
}
</script>
