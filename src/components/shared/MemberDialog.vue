<template>
  <q-dialog v-model="open">
    <q-card style="min-width: 360px">
      <q-card-section class="row items-center">
        <div class="text-h6">{{ $t('projects.members') }}</div>
        <q-space />
        <q-btn flat round dense icon="close" v-close-popup />
      </q-card-section>

      <q-separator size="0.5rem" />

      <!-- Lista članova -->
      <q-list separator>
        <!-- U listi članova, pored svakog -->
        <q-item v-for="member in members" :key="member.user_id">
          <q-item-section avatar class="member-avatar-section">
            <UserAvatar
              :avatar-url="member.profiles?.avatar_url"
              :full-name="member.profiles?.full_name"
              :size="32"
            />
          </q-item-section>

          <q-item-section>
            <q-item-label class="row items-center no-wrap q-gutter-xs">
              <q-badge
                :color="member.role === 'owner' ? 'primary' : 'grey-5'"
                rounded
                class="role-badge"
              >
                {{ member.role?.[0]?.toUpperCase() }}
                <q-tooltip>{{ member.role }}</q-tooltip>
              </q-badge>
              <span class="member-name">{{ member.profiles?.full_name }}</span>
            </q-item-label>
            <q-item-label caption class="member-email">{{ member.profiles?.email }}</q-item-label>
          </q-item-section>

          <!-- Akcije jedna ispod druge u uskom side stupcu -->
          <q-item-section side top class="column items-end q-gutter-xs">
            <!-- Sve notifikacijske postavke (uklj. badge on/off) žive u ovom meniju -->
            <q-btn
              v-if="member.user_id === authStore.user?.id"
              flat
              round
              dense
              icon="tune"
              size="sm"
            >
              <q-tooltip>{{ $t('notifications.prefsTitle') }}</q-tooltip>
              <q-menu>
                <q-list dense style="min-width: 220px">
                  <q-item-label header>{{ $t('notifications.prefsTitle') }}</q-item-label>
                  <q-item tag="label" clickable>
                    <q-item-section side>
                      <q-toggle
                        :model-value="member.badge_enabled !== false"
                        size="sm"
                        color="accent"
                        @update:model-value="(v) => toggleBadge(member, v)"
                      />
                    </q-item-section>
                    <q-item-section>{{ $t('notifications.badgeEnabled') }}</q-item-section>
                  </q-item>
                  <q-separator />
                  <q-item
                    v-for="pref in notifPrefs"
                    :key="pref.field"
                    tag="label"
                    clickable
                    :disable="member.badge_enabled === false"
                  >
                    <q-item-section side>
                      <q-toggle
                        :model-value="member[pref.field] !== false"
                        size="sm"
                        color="accent"
                        :disable="member.badge_enabled === false"
                        @update:model-value="(v) => updateNotifPref(pref.field, v)"
                      />
                    </q-item-section>
                    <q-item-section>{{ $t(pref.labelKey) }}</q-item-section>
                  </q-item>
                </q-list>
              </q-menu>
            </q-btn>
            <q-btn
              v-if="isOwner && member.user_id !== authStore.user.id"
              flat
              round
              dense
              icon="close"
              size="xs"
              color="negative"
              @click="removeMember(member)"
            />
          </q-item-section>
        </q-item>
      </q-list>
      <q-separator size="0.5rem" />
      <!-- Dodaj člana -->
      <q-card-section v-if="isOwner" class="q-gutter-sm">
        <div class="text-subtitle2">{{ $t('projects.addMember') }}</div>
        <div class="row q-gutter-sm">
          <q-input
            v-model="newEmail"
            :label="$t('auth.email')"
            outlined
            dense
            class="col"
            @keydown.enter="addMember"
          />
          <q-btn color="primary" icon="person_add" :loading="adding" @click="addMember" />
        </div>
        <div v-if="errorMsg" class="text-negative text-caption">
          {{ errorMsg }}
        </div>
      </q-card-section>
    </q-card>
  </q-dialog>
</template>

<script setup>
import { ref, computed } from 'vue'
import { useProjectsStore } from 'src/stores/projects'
import { useNotificationsStore } from 'src/stores/notifications'
import { useAuthStore } from 'src/stores/auth'
import { useQuasar } from 'quasar'
import { useI18n } from 'vue-i18n'
import { supabase } from 'src/boot/supabase'
import { useOfflineGuard } from 'src/composables/useOfflineGuard'
import UserAvatar from './UserAvatar.vue'

const props = defineProps({
  modelValue: Boolean,
  projectId: { type: String, required: true },
})
const emit = defineEmits(['update:modelValue'])

const $q = useQuasar()
const { t } = useI18n()
const { blockedOffline } = useOfflineGuard()
const projectsStore = useProjectsStore()
const notifStore = useNotificationsStore()
const authStore = useAuthStore()

const newEmail = ref('')
const adding = ref(false)
const errorMsg = ref('')

const open = computed({
  get: () => props.modelValue,
  set: (v) => emit('update:modelValue', v),
})

const project = computed(() => projectsStore.projects.find((p) => p.id === props.projectId))

const members = computed(() => project.value?.project_members ?? [])
const isOwner = computed(() =>
  members.value.some((m) => m.user_id === authStore.user?.id && m.role === 'owner'),
)

async function addMember() {
  if (!newEmail.value.trim()) return
  if (blockedOffline('common.offlineNoAction')) return
  errorMsg.value = ''
  adding.value = true
  try {
    await projectsStore.addMember(props.projectId, newEmail.value.trim())
    newEmail.value = ''
    $q.notify({ type: 'positive', message: t('projects.addMember') })
  } catch (e) {
    errorMsg.value = e.message
  } finally {
    adding.value = false
  }
}

async function removeMember(member) {
  if (blockedOffline()) return
  $q.dialog({
    title: t('common.delete'),
    message: member.profiles?.full_name,
    ok: { label: t('common.delete'), color: 'negative' },
    cancel: t('common.cancel'),
  }).onOk(async () => {
    await projectsStore.removeMember(props.projectId, member.user_id)
  })
}

async function toggleBadge(member, enabled) {
  if (blockedOffline('common.offlineNoAction')) return
  await supabase
    .from('project_members')
    .update({ badge_enabled: enabled })
    .eq('project_id', props.projectId)
    .eq('user_id', authStore.user.id)

  await projectsStore.fetchProjects()
  await notifStore.fetchUnread()
}

const notifPrefs = [
  { field: 'notif_messages', labelKey: 'notifications.prefMessages' },
  { field: 'notif_ideas', labelKey: 'notifications.prefIdeas' },
  { field: 'notif_bugs', labelKey: 'notifications.prefBugs' },
  { field: 'notif_tbi', labelKey: 'notifications.prefTbi' },
]

async function updateNotifPref(field, enabled) {
  if (blockedOffline('common.offlineNoAction')) return
  await supabase
    .from('project_members')
    .update({ [field]: enabled })
    .eq('project_id', props.projectId)
    .eq('user_id', authStore.user.id)

  await projectsStore.fetchProjects()
  await notifStore.fetchUnread()
}
</script>

<style scoped>
/* Email je jedan token bez razmaka — bez ovoga se ne lomi nego razvlači red
   preko drugih sekcija umjesto da se prelomi u novi red. */
.member-name,
.member-email {
  overflow-wrap: anywhere;
}

/* Red bedž+ime je no-wrap: ime mora smjeti stisnuti ispod svoje "prirodne"
   širine da se skrati, inače bi opet gurao side stupac i preklapao se. */
.member-name {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.role-badge {
  flex-shrink: 0;
  min-width: 18px;
  justify-content: center;
}

.member-email {
  /* app.scss postavlja .q-item__label { font-size: var(--aarc-font-size) !important },
     pa i ovdje treba !important da bi uopće nešto promijenilo. */
  font-size: 11px !important;
}

/* Uža avatar sekcija ostavlja više prostora imenu/emailu. */
.member-avatar-section {
  min-width: 0;
  padding-right: 8px;
}
</style>
