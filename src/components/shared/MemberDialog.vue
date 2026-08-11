<template>
  <q-dialog v-model="open">
    <q-card style="min-width: 360px">
      <q-card-section class="row items-center">
        <div class="text-h6">{{ $t('projects.members') }}</div>
        <q-space />
        <q-btn flat round dense icon="close" v-close-popup />
      </q-card-section>

      <q-separator size="0.5rem" />

      <!-- Vidljivo cijeloj organizaciji: project_members ovdje više NIJE popis
           pristupa (B25) nego samo pretplata, pa uređivati ga kao "članove"
           zavarava (isti nalaz kao B20d). Popis se ne prikazuje — samo
           objašnjenje i vlastite postavke obavijesti niže. -->
      <q-card-section v-if="project?.visibility === 'org'" class="text-caption member-hint">
        {{ $t('projects.orgVisibleInfo') }}
      </q-card-section>

      <!-- Privatan projekt: project_members JEST pristup, popis je stvaran. -->
      <template v-else>
        <q-list separator>
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

            <q-item-section side>
              <q-btn v-if="canManage" flat round dense icon="more_vert" size="sm">
                <q-menu auto-close>
                  <q-list dense style="min-width: 200px">
                    <q-item
                      v-if="member.role !== 'owner'"
                      clickable
                      @click="setRole(member, 'owner')"
                    >
                      <q-item-section>{{ $t('projects.makeProjectOwner') }}</q-item-section>
                    </q-item>
                    <q-item
                      v-if="member.role === 'owner'"
                      clickable
                      @click="setRole(member, 'member')"
                    >
                      <q-item-section>{{ $t('projects.makeProjectMember') }}</q-item-section>
                    </q-item>
                    <q-separator />
                    <q-item clickable @click="confirmRemove(member)">
                      <q-item-section class="text-negative">{{
                        $t('projects.removeMemberTitle')
                      }}</q-item-section>
                    </q-item>
                  </q-list>
                </q-menu>
              </q-btn>
            </q-item-section>
          </q-item>
        </q-list>

        <!-- Dodaj člana — iz adresara organizacije, ne po e-mailu: project_members_insert
             (B12) svejedno odbija ikoga tko nije u organizaciji projekta, pa je
             biranje umjesto upisivanja i ispravnije i jednostavnije. Gost je
             namjerno u popisu — eksplicitan redak na privatnom projektu je
             jedini način da gost uopće dobije pristup nečemu. -->
        <q-card-section v-if="canManage" class="q-gutter-sm">
          <div class="text-subtitle2">{{ $t('projects.addMember') }}</div>
          <q-select
            :model-value="null"
            :options="pickableMembers"
            option-label="label"
            option-value="user_id"
            emit-value
            map-options
            outlined
            dense
            :label="$t('projects.pickMember')"
            :loading="adding"
            :disable="!pickableMembers.length"
            :hint="!pickableMembers.length ? $t('projects.noMoreMembers') : undefined"
            @update:model-value="addMember"
          />
        </q-card-section>
      </template>

      <!-- Vlastite postavke obavijesti — vrijede neovisno o vidljivosti, ali
           samo ako uopće postoji pretplata (B25) na koju se imaju što odnositi. -->
      <template v-if="myMembership">
        <q-separator size="0.5rem" />
        <q-card-section class="q-gutter-xs">
          <div class="text-subtitle2 q-mb-xs">{{ $t('notifications.prefsTitle') }}</div>
          <q-item tag="label" clickable dense class="q-px-none">
            <q-item-section side>
              <q-toggle
                :model-value="myMembership.badge_enabled !== false"
                size="sm"
                color="accent"
                @update:model-value="(v) => toggleBadge(v)"
              />
            </q-item-section>
            <q-item-section>{{ $t('notifications.badgeEnabled') }}</q-item-section>
          </q-item>
          <q-item
            v-for="pref in notifPrefs"
            :key="pref.field"
            tag="label"
            clickable
            dense
            class="q-px-none"
            :disable="myMembership.badge_enabled === false"
          >
            <q-item-section side>
              <q-toggle
                :model-value="myMembership[pref.field] !== false"
                size="sm"
                color="accent"
                :disable="myMembership.badge_enabled === false"
                @update:model-value="(v) => updateNotifPref(pref.field, v)"
              />
            </q-item-section>
            <q-item-section>{{ $t(pref.labelKey) }}</q-item-section>
          </q-item>
        </q-card-section>
      </template>
    </q-card>
  </q-dialog>
</template>

<script setup>
import { ref, computed, watch } from 'vue'
import { useProjectsStore } from 'src/stores/projects'
import { useOrgsStore } from 'src/stores/orgs'
import { useNotificationsStore } from 'src/stores/notifications'
import { useAuthStore } from 'src/stores/auth'
import { useQuasar } from 'quasar'
import { useI18n } from 'vue-i18n'
import { supabase } from 'src/boot/supabase'
import { useOfflineGuard } from 'src/composables/useOfflineGuard'
import { useConfirmDialog } from 'src/composables/useConfirmDialog'
import UserAvatar from './UserAvatar.vue'

const props = defineProps({
  modelValue: Boolean,
  projectId: { type: String, required: true },
})
const emit = defineEmits(['update:modelValue'])

const $q = useQuasar()
const { t } = useI18n()
const { blockedOffline } = useOfflineGuard()
const { confirmDestructive } = useConfirmDialog()
const projectsStore = useProjectsStore()
const orgsStore = useOrgsStore()
const notifStore = useNotificationsStore()
const authStore = useAuthStore()

const adding = ref(false)

const open = computed({
  get: () => props.modelValue,
  set: (v) => emit('update:modelValue', v),
})

const project = computed(() => projectsStore.projects.find((p) => p.id === props.projectId))
const members = computed(() => project.value?.project_members ?? [])
const myMembership = computed(() => members.value.find((m) => m.user_id === authStore.user?.id))

// Ista logika kao can_manage_project_members u bazi (B12): admin/owner
// organizacije, tvorac projekta, ili owner NA OVOM projektu. Računa se
// klijentski da se izbjegne dodatan RPC poziv samo za prikaz gumba — same
// akcije ionako ponovno provjerava poslužitelj.
const myOrgRole = computed(() => orgsStore.orgs.find((o) => o.id === project.value?.org_id)?.role)
const canManage = computed(() => {
  if (!project.value) return false
  if (['owner', 'admin'].includes(myOrgRole.value)) return true
  if (project.value.created_by === authStore.user?.id) return true
  return myMembership.value?.role === 'owner'
})

const pickableMembers = computed(() => {
  const already = new Set(members.value.map((m) => m.user_id))
  return orgsStore.members
    .filter((m) => !already.has(m.user_id))
    .map((m) => ({ user_id: m.user_id, label: m.profiles?.full_name ?? m.profiles?.email }))
})

watch(
  () => [open.value, project.value?.org_id],
  ([isOpen, orgId]) => {
    if (isOpen && orgId) orgsStore.fetchMembers(orgId)
  },
  { immediate: true },
)

async function addMember(userId) {
  if (!userId) return
  if (blockedOffline('common.offlineNoAction')) return
  adding.value = true
  try {
    await projectsStore.addProjectMember(props.projectId, userId)
    $q.notify({ type: 'positive', message: t('projects.addMember') })
  } catch (e) {
    $q.notify({ type: 'negative', message: e.message })
  } finally {
    adding.value = false
  }
}

async function confirmRemove(member) {
  if (blockedOffline()) return
  const ok = await confirmDestructive({
    title: t('projects.removeMemberTitle'),
    message: t('projects.removeMemberConfirm', { name: member.profiles?.full_name }),
  })
  if (!ok) return
  try {
    await projectsStore.removeMember(props.projectId, member.user_id)
  } catch (e) {
    $q.notify({ type: 'negative', message: e.message })
  }
}

async function setRole(member, role) {
  try {
    await projectsStore.setProjectMemberRole(props.projectId, member.user_id, role)
  } catch (e) {
    $q.notify({ type: 'negative', message: e.message })
  }
}

async function toggleBadge(enabled) {
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

.member-hint {
  color: var(--aarc-muted);
}
</style>
