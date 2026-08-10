<template>
  <q-layout view="hHh lpR fFf">
    <AppHeader :title="org?.name ?? $t('org.title')" back back-to="/" />

    <q-page-container>
      <q-page class="org-page q-pb-xl">
        <!-- Prebacivanje i nova organizacija — jedino mjesto za oboje otkad je
             zaglavlje na Homeu postalo čisti tekst. Prikazano uvijek, ne samo
             kad ih ima više, jer "+ Nova" mora ostati dostupan i s jednom. -->
        <div class="q-px-md q-pt-md">
          <div class="row q-gutter-xs items-center">
            <q-chip
              v-for="o in orgsStore.orgs"
              :key="o.id"
              clickable
              :outline="o.id !== orgsStore.currentId"
              :color="o.id === orgsStore.currentId ? 'primary' : undefined"
              :text-color="o.id === orgsStore.currentId ? 'white' : undefined"
              @click="switchOrg(o.id)"
            >
              {{ o.name }}
              <q-badge v-if="notifStore.orgUnread(o.id) > 0" color="negative" floating rounded />
            </q-chip>
            <q-chip clickable outline icon="add" @click="promptNewOrg">
              {{ $t('projects.newOrg') }}
            </q-chip>
          </div>
        </div>

        <!-- Naziv -->
        <div class="row items-center q-px-md q-pt-md q-mb-sm">
          <div class="text-h6 org-name">{{ org?.name }}</div>
          <q-btn
            v-if="orgsStore.isAdmin"
            flat
            round
            dense
            icon="edit"
            size="sm"
            class="q-ml-xs"
            @click="promptRename"
          />
        </div>
        <div class="text-caption org-role-caption q-px-md q-mb-md">
          {{ $t(`org.role.${orgsStore.currentRole}`) }}
        </div>

        <q-separator class="q-mx-md q-mb-md" />

        <!-- Članovi -->
        <div class="q-px-md q-mb-xs text-subtitle2 org-section-label">
          {{ $t('org.members') }} ({{ orgsStore.members.length }})
        </div>
        <q-list separator>
          <q-item v-for="member in orgsStore.members" :key="member.user_id">
            <q-item-section avatar class="member-avatar-section">
              <UserAvatar
                :avatar-url="member.profiles?.avatar_url"
                :full-name="member.profiles?.full_name"
                :size="36"
              />
            </q-item-section>

            <q-item-section>
              <q-item-label class="row items-center no-wrap q-gutter-xs">
                <q-badge :color="roleColor(member.role)" rounded class="role-badge">
                  {{ member.role?.[0]?.toUpperCase() }}
                  <q-tooltip>{{ $t(`org.role.${member.role}`) }}</q-tooltip>
                </q-badge>
                <span class="member-name">{{ member.profiles?.full_name }}</span>
              </q-item-label>
              <q-item-label caption class="member-email">{{ member.profiles?.email }}</q-item-label>
            </q-item-section>

            <q-item-section side>
              <q-btn v-if="canManage(member)" flat round dense icon="more_vert" size="sm">
                <q-menu auto-close>
                  <q-list dense style="min-width: 200px">
                    <q-item
                      v-if="member.role !== 'admin' && orgsStore.isAdmin"
                      clickable
                      @click="changeRole(member, 'admin')"
                    >
                      <q-item-section>{{ $t('org.makeAdmin') }}</q-item-section>
                    </q-item>
                    <q-item
                      v-if="member.role === 'admin' && orgsStore.isAdmin"
                      clickable
                      @click="changeRole(member, 'member')"
                    >
                      <q-item-section>{{ $t('org.makeMember') }}</q-item-section>
                    </q-item>
                    <q-item
                      v-if="orgsStore.isOwner"
                      clickable
                      @click="confirmTransferOwner(member)"
                    >
                      <q-item-section>{{ $t('org.makeOwner') }}</q-item-section>
                    </q-item>
                    <q-separator />
                    <q-item clickable @click="confirmRemove(member)">
                      <q-item-section class="text-negative">{{
                        $t('org.removeMember')
                      }}</q-item-section>
                    </q-item>
                  </q-list>
                </q-menu>
              </q-btn>
            </q-item-section>
          </q-item>
        </q-list>

        <!-- Pozivnice — čeka B21 (potvrda e-maila) -->
        <div v-if="orgsStore.isAdmin" class="q-px-md q-mt-md text-caption org-hint">
          {{ $t('org.invitesComingSoon') }}
        </div>

        <!-- Napusti organizaciju -->
        <div class="q-px-md q-mt-lg">
          <q-btn
            outline
            color="grey-6"
            icon="logout"
            :label="$t('org.leave')"
            class="full-width"
            @click="confirmLeave"
          />
        </div>

        <!-- Opasna zona -->
        <div v-if="orgsStore.isOwner" class="q-px-md q-mt-md">
          <q-card flat bordered class="border-negative">
            <q-card-section>
              <div class="text-subtitle2 text-negative q-mb-xs">{{ $t('org.dangerZone') }}</div>
              <q-btn
                color="negative"
                outline
                icon="delete_forever"
                :label="$t('org.deleteOrg')"
                @click="confirmDeleteOrg"
              />
            </q-card-section>
          </q-card>
        </div>
      </q-page>
    </q-page-container>
  </q-layout>
</template>

<script setup>
import { computed, onMounted, watch } from 'vue'
import { useRouter } from 'vue-router'
import { useQuasar } from 'quasar'
import { useI18n } from 'vue-i18n'
import { useOrgsStore } from 'src/stores/orgs'
import { useAuthStore } from 'src/stores/auth'
import { useNotificationsStore } from 'src/stores/notifications'
import AppHeader from 'src/components/shared/AppHeader.vue'
import UserAvatar from 'src/components/shared/UserAvatar.vue'

const router = useRouter()
const $q = useQuasar()
const { t } = useI18n()
const orgsStore = useOrgsStore()
const authStore = useAuthStore()
const notifStore = useNotificationsStore()

function switchOrg(orgId) {
  orgsStore.setCurrent(orgId)
}

function promptNewOrg() {
  $q.dialog({
    title: t('projects.newOrg'),
    prompt: { model: '', type: 'text', label: t('projects.orgNamePlaceholder') },
    cancel: true,
  }).onOk(async (name) => {
    if (!name?.trim()) return
    try {
      await orgsStore.createOrg(name)
    } catch (e) {
      $q.notify({ type: 'negative', message: e.message })
    }
  })
}

const org = computed(() => orgsStore.current)

function roleColor(role) {
  return { owner: 'primary', admin: 'accent', member: 'grey-6', guest: 'grey-4' }[role] ?? 'grey-6'
}

// Admin upravlja svima osim vlasnika (vlasništvo prenosi samo vlasnik, zasebna
// stavka u meniju); nitko ne upravlja samim sobom odavde — to je "Napusti".
function canManage(member) {
  if (member.user_id === authStore.user?.id) return false
  if (orgsStore.isOwner) return true
  return orgsStore.isAdmin && member.role !== 'owner' && member.role !== 'admin'
}

function promptRename() {
  $q.dialog({
    title: t('org.rename'),
    prompt: { model: org.value?.name ?? '', type: 'text' },
    cancel: true,
  }).onOk(async (name) => {
    if (!name?.trim()) return
    try {
      await orgsStore.renameOrg(org.value.id, name)
      $q.notify({ type: 'positive', message: t('settings.saved') })
    } catch (e) {
      $q.notify({ type: 'negative', message: e.message })
    }
  })
}

function changeRole(member, role) {
  orgsStore.setMemberRole(org.value.id, member.user_id, role).catch((e) => {
    $q.notify({ type: 'negative', message: e.message })
  })
}

function confirmTransferOwner(member) {
  $q.dialog({
    title: t('org.makeOwner'),
    message: t('org.transferOwnerConfirm', { name: member.profiles?.full_name }),
    ok: { label: t('common.confirm'), color: 'negative' },
    cancel: t('common.cancel'),
  }).onOk(() => changeRole(member, 'owner'))
}

function confirmRemove(member) {
  $q.dialog({
    title: t('org.removeMember'),
    message: t('org.removeMemberConfirm', { name: member.profiles?.full_name }),
    ok: { label: t('common.delete'), color: 'negative' },
    cancel: t('common.cancel'),
  }).onOk(async () => {
    try {
      await orgsStore.removeMember(org.value.id, member.user_id)
    } catch (e) {
      $q.notify({ type: 'negative', message: e.message })
    }
  })
}

function confirmLeave() {
  $q.dialog({
    title: t('org.leave'),
    message: t('org.leaveConfirm', { name: org.value?.name }),
    ok: { label: t('common.confirm'), color: 'negative' },
    cancel: t('common.cancel'),
  }).onOk(async () => {
    try {
      await orgsStore.removeMember(org.value.id, authStore.user.id)
      router.push('/')
    } catch (e) {
      // Najčešći uzrok: zadnji vlasnik (B13/B19) — poruka iz baze je već čitljiva.
      $q.notify({ type: 'negative', message: e.message })
    }
  })
}

function confirmDeleteOrg() {
  $q.dialog({
    title: t('org.deleteOrg'),
    message: t('org.deleteOrgConfirm', { name: org.value?.name }),
    ok: { label: t('common.delete'), color: 'negative' },
    cancel: t('common.cancel'),
  }).onOk(async () => {
    try {
      await orgsStore.deleteOrg(org.value.id)
      router.push('/')
    } catch (e) {
      $q.notify({ type: 'negative', message: e.message })
    }
  })
}

watch(
  () => orgsStore.currentId,
  (id) => {
    if (id) orgsStore.fetchMembers(id)
  },
  { immediate: true },
)

onMounted(() => {
  if (!orgsStore.orgs.length) orgsStore.fetchOrgs()
})
</script>

<style scoped>
.org-page {
  background: var(--aarc-bg) !important;
}

.org-name {
  color: var(--aarc-text);
}

.org-role-caption,
.org-hint,
.org-section-label {
  color: var(--aarc-muted);
}

.member-name,
.member-email {
  overflow-wrap: anywhere;
}

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
  font-size: 11px !important;
}

.member-avatar-section {
  min-width: 0;
  padding-right: 8px;
}

.border-negative {
  border-color: var(--q-negative) !important;
  border-radius: 16px !important;
  background: var(--aarc-surface) !important;
}
</style>
