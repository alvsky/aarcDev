<template>
  <q-expansion-item
    group="ideas"
    expand-separator
    :header-class="idea.promoted ? 'text-grey-5' : ''"
    :class="{ 'opacity-5': idea.promoted }"
    @update:model-value="(val) => val && onOpen()"
  >
    <template #header>
      <q-item-section avatar>
        <q-icon
          :name="idea.promoted ? 'check_circle' : 'lightbulb'"
          :color="idea.promoted ? 'positive' : 'accent'"
          size="20px"
        />
      </q-item-section>

      <q-item-section>
        <q-item-label :class="{ 'text-strike': idea.promoted }">
          {{ idea.title }}
          <!-- Novo indikator -->
          <q-badge
            v-if="idea.is_new"
            color="accent"
            class="q-ml-xs"
            style="font-size: 9px; padding: 2px 5px"
          >
            NEW
          </q-badge>
        </q-item-label>
        <q-item-label caption>
          <q-badge v-if="idea.promoted" color="purple" outline class="q-mr-xs">
            {{ $t('ideas.promotedLabel') }}
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
        <div v-if="idea.description" class="text-body2 q-mb-sm">
          {{ idea.description }}
        </div>

        <!-- Screenshot -->
        <ChatImage
          v-if="idea.screenshot_url"
          :path="idea.screenshot_url"
          :alt="idea.title"
          class="q-mb-sm"
        />

        <!-- Meta -->
        <div class="row items-center q-gutter-sm text-caption text-grey-5 q-mb-sm">
          <q-icon name="person" size="12px" />
          <span>{{ idea.profiles?.full_name }}</span>
          <q-icon name="schedule" size="12px" />
          <span>{{ formatDate.relative(idea.created_at) }}</span>
        </div>

        <!-- Akcije -->
        <div class="row q-gutter-xs">
          <q-btn
            v-if="!idea.promoted"
            flat
            dense
            icon="upload"
            size="sm"
            color="purple"
            :label="$t('ideas.promote')"
            @click="$emit('promote')"
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
import { useNotificationsStore } from 'src/stores/notifications'
import { useFormatDate } from 'src/composables/useFormatDate'
import ChatImage from 'src/components/chat/ChatImage.vue'
import { useIdeasStore } from 'src/stores/ideas'

const notifStore = useNotificationsStore()
const ideasStore = useIdeasStore()

async function onOpen() {
  if (!props.idea.is_new) return

  // Prvo ažuriraj lokalno
  const idx = ideasStore.ideas.findIndex((i) => i.id === props.idea.id)
  if (idx !== -1) ideasStore.ideas[idx].is_new = false

  // Pa spremi u bazu i osvježi badge
  await notifStore.markItemRead(props.idea.id, 'idea')
}

const props = defineProps({
  idea: { type: Object, required: true },
  projectId: { type: String, required: true },
})

defineEmits(['edit', 'delete', 'promote', 'open-thread'])

const formatDate = useFormatDate()

const unread = computed(() =>
  notifStore.threadUnread({ projectId: props.projectId, ideaId: props.idea.id }),
)

const messageCount = computed(() => props.idea.message_count ?? 0)
</script>
