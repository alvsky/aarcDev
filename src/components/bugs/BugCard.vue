<template>
  <q-expansion-item
    group="bugs"
    :class="{ 'opacity-5': bug.status === 'closed' }"
    expand-separator
    :header-class="bug.status === 'closed' ? 'text-grey-5' : ''"
    @update:model-value="(val) => val && onOpen()"
  >
    <template #header>
      <q-item-section avatar>
        <q-icon :name="statusIcon(bug.status)" :color="statusColor(bug.status)" size="20px" />
      </q-item-section>

      <q-item-section>
        <q-item-label :class="{ 'text-strike': bug.status === 'closed' }">
          {{ bug.title }}
          <!-- Novo indikator -->
          <q-badge
            v-if="bug.is_new"
            color="accent"
            class="q-ml-xs"
            style="font-size: 9px; padding: 2px 5px"
          >
            NEW
          </q-badge>
        </q-item-label>
        <q-item-label caption>
          <q-badge :color="prioColor(bug.priority)" outline class="q-mr-xs">
            {{ $t(`bugs.priority.${bug.priority}`) }}
          </q-badge>
          <q-badge :color="statusColor(bug.status)" outline>
            {{ $t(`bugs.status.${bug.status}`) }}
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
        <div v-if="bug.description" class="text-body2 q-mb-sm">
          {{ bug.description }}
        </div>

        <!-- Screenshot -->
        <ChatImage
          v-if="bug.screenshot_url"
          :path="bug.screenshot_url"
          :alt="bug.title"
          class="q-mb-sm"
        />

        <!-- Meta -->
        <div class="row items-center q-gutter-sm text-caption text-grey-5 q-mb-sm">
          <q-icon name="person" size="12px" />
          <span>{{ bug.profiles?.full_name }}</span>
          <q-icon name="schedule" size="12px" />
          <span>{{ formatDate.relative(bug.created_at) }}</span>
        </div>

        <!-- Inline promjena statusa i prioriteta -->
        <div v-if="bug.status !== 'promoted'" class="row q-col-gutter-sm q-mb-sm">
          <div class="col-6">
            <q-select
              :model-value="bug.status"
              :label="$t('common.status')"
              :options="statusOptions"
              outlined
              dense
              emit-value
              map-options
              @update:model-value="(v) => $emit('status-change', v)"
            />
          </div>
          <div class="col-6">
            <q-select
              :model-value="bug.priority"
              :label="$t('common.priority')"
              :options="priorityOptions"
              outlined
              dense
              emit-value
              map-options
              @update:model-value="(v) => $emit('priority-change', v)"
            />
          </div>
        </div>

        <!-- Akcije -->
        <div class="row q-gutter-xs">
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
import { useNotificationsStore } from 'src/stores/notifications'
import { useFormatDate } from 'src/composables/useFormatDate'
import ChatImage from 'src/components/chat/ChatImage.vue'
import { useBugsStore } from 'src/stores/bugs'

const { t } = useI18n()
const notifStore = useNotificationsStore()
const bugsStore = useBugsStore()

async function onOpen() {
  if (!props.bug.is_new) return

  // Prvo ažuriraj lokalno
  const idx = bugsStore.bugs.findIndex((b) => b.id === props.bug.id)
  if (idx !== -1) bugsStore.bugs[idx].is_new = false

  // Pa spremi u bazu i osvježi badge
  await notifStore.markItemRead(props.bug.id, 'bug')
}
const messageCount = computed(() => props.bug.message_count ?? 0)

const props = defineProps({
  bug: { type: Object, required: true },
  projectId: { type: String, required: true },
})

defineEmits(['edit', 'delete', 'open-thread', 'status-change', 'priority-change'])

const formatDate = useFormatDate()

const statusOptions = computed(() => [
  { label: t('bugs.status.open'), value: 'open' },
  { label: t('bugs.status.in_progress'), value: 'in_progress' },
  { label: t('bugs.status.testing'), value: 'testing' },
  { label: t('bugs.status.closed'), value: 'closed' },
])

const priorityOptions = computed(() => [
  { label: t('bugs.priority.low'), value: 'low' },
  { label: t('bugs.priority.med'), value: 'med' },
  { label: t('bugs.priority.high'), value: 'high' },
])

const unread = computed(() =>
  notifStore.threadUnread({ projectId: props.projectId, bugId: props.bug.id }),
)

const statusIcon = (s) =>
  ({
    open: 'radio_button_unchecked',
    in_progress: 'pending',
    testing: 'science',
    closed: 'check_circle',
  })[s] ?? 'radio_button_unchecked'

const statusColor = (s) =>
  ({
    open: 'grey',
    in_progress: 'warning',
    testing: 'info',
    closed: 'positive',
  })[s] ?? 'grey'

const prioColor = (p) =>
  ({
    high: 'negative',
    med: 'warning',
    low: 'positive',
  })[p] ?? 'grey'
</script>
