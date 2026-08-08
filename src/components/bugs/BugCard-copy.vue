<template>
  <q-card flat bordered>
    <q-card-section class="q-pa-sm">
      <div class="row items-start no-wrap q-gutter-xs">
        <!-- Prioritet indikator -->
        <q-icon name="circle" :color="prioColor" size="10px" class="q-mt-xs flex-shrink-0" />

        <div class="col">
          <!-- Naslov + status badge -->
          <div class="row items-center q-gutter-xs">
            <span class="text-body2 text-weight-medium">{{ bug.title }}</span>
            <q-badge v-if="bug.status === 'promoted'" color="purple" outline>
              {{ $t('bugs.promotedLabel') }}
            </q-badge>
            <q-badge v-else-if="bug.status === 'confirmed'" color="warning" outline>
              {{ $t('bugs.status.confirmed') }}
            </q-badge>
          </div>

          <!-- Opis -->
          <div v-if="bug.description" class="text-caption text-grey-6 q-mt-xs ellipsis-2-lines">
            {{ bug.description }}
          </div>
          <ChatImage
            v-if="bug.screenshot_url"
            :path="bug.screenshot_url"
            :alt="bug.title"
            class="q-mt-sm"
          />
          <!-- Meta -->
          <div class="row items-center q-mt-sm q-gutter-sm text-caption text-grey-5">
            <q-icon name="person" size="12px" />
            <span>{{ bug.profiles?.full_name }}</span>
            <q-icon name="schedule" size="12px" />
            <span>{{ formatDate.relative(bug.created_at) }}</span>
          </div>
        </div>
        <!-- Inline status promjena -->
        <div class="q-mt-sm" v-if="bug.status !== 'promoted'">
          <q-select
            :model-value="bug.status"
            :options="statusOptions"
            emit-value
            map-options
            dense
            outlined
            style="max-width: 160px"
            :label="$t('common.status')"
            @update:model-value="(v) => $emit('status-change', v)"
          />
        </div>
        <!-- Akcije -->
        <div class="column items-center q-gutter-xs">
          <!-- Thread gumb s unread badge -->
          <q-btn
            flat
            round
            dense
            icon="forum"
            size="sm"
            color="grey-6"
            @click="$emit('open-thread')"
          >
            <q-badge v-if="unread > 0" color="negative" floating rounded>
              {{ unread }}
            </q-badge>
            <q-tooltip>{{ $t('bugs.discussion') }}</q-tooltip>
          </q-btn>

          <!-- Više opcija -->
          <q-btn flat round dense icon="more_vert" size="sm">
            <q-menu auto-close>
              <q-list dense style="min-width: 160px">
                <q-item clickable @click="$emit('edit')">
                  <q-item-section side><q-icon name="edit" /></q-item-section>
                  <q-item-section>{{ $t('common.edit') }}</q-item-section>
                </q-item>
                <q-separator />
                <q-item clickable @click="$emit('delete')">
                  <q-item-section side><q-icon name="delete" color="negative" /></q-item-section>
                  <q-item-section class="text-negative">{{ $t('common.delete') }}</q-item-section>
                </q-item>
              </q-list>
            </q-menu>
          </q-btn>
        </div>
      </div>
    </q-card-section>
  </q-card>
</template>

<script setup>
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useNotificationsStore } from 'src/stores/notifications'
import { useFormatDate } from 'src/composables/useFormatDate'
import ChatImage from 'src/components/chat/ChatImage.vue'

const props = defineProps({
  bug: { type: Object, required: true },
  projectId: { type: String, required: true },
})

defineEmits(['edit', 'delete', 'open-thread', 'status-change'])

const statusOptions = computed(() => [
  { label: t('bugs.status.open'), value: 'open' },
  { label: t('bugs.status.confirmed'), value: 'confirmed' },
  { label: t('bugs.status.resolved'), value: 'resolved' },
])

const { t } = useI18n()
const notifStore = useNotificationsStore()
const formatDate = useFormatDate()

const prioColor = computed(
  () =>
    ({
      high: 'negative',
      med: 'warning',
      low: 'positive',
    })[props.bug.priority] ?? 'grey',
)

const unread = computed(() =>
  notifStore.threadUnread({
    projectId: props.projectId,
    bugId: props.bug.id,
  }),
)
</script>
