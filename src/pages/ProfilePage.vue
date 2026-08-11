<template>
  <q-layout view="hHh lpR fFf">
    <AppHeader :title="$t('settings.profile')" back settings />

    <q-page-container>
      <q-page class="profile-page q-pb-xl">
        <!-- Logout — na vrhu i malen: pri dnu je znao ostati nevidljiv ispod
             popisa projekata na dužim ekranima. -->
        <div class="row justify-end q-px-md q-pt-sm">
          <q-btn
            flat
            dense
            size="sm"
            color="grey-6"
            icon="logout"
            :label="$t('auth.logout')"
            @click="logout"
          />
        </div>

        <!-- Avatar -->
        <div class="column items-center q-pt-xl q-pb-lg">
          <div class="avatar-upload cursor-pointer">
            <UserAvatar
              :avatar-url="authStore.profile?.avatar_url"
              :full-name="authStore.profile?.full_name"
              :size="100"
              class="profile-avatar"
            />
            <div class="avatar-upload-badge">
              <q-spinner v-if="uploadingAvatar" size="16px" color="white" />
              <q-icon v-else name="photo_camera" size="16px" color="white" />
            </div>
            <q-menu>
              <q-list dense style="min-width: 180px">
                <q-item clickable v-close-popup @click="triggerAvatarPicker">
                  <q-item-section side><q-icon name="photo_camera" /></q-item-section>
                  <q-item-section>{{ $t('settings.avatarChange') }}</q-item-section>
                </q-item>
                <q-item
                  v-if="authStore.profile?.avatar_url"
                  clickable
                  v-close-popup
                  @click="removeAvatar"
                >
                  <q-item-section side><q-icon name="close" color="negative" /></q-item-section>
                  <q-item-section class="text-negative">{{
                    $t('settings.avatarRemove')
                  }}</q-item-section>
                </q-item>
              </q-list>
            </q-menu>
          </div>
          <input
            ref="avatarInput"
            type="file"
            accept="image/*"
            class="hidden"
            @change="onAvatarSelected"
          />
          <div class="text-h6 text-weight-bold q-mt-md profile-name">
            {{ authStore.profile?.full_name }}
          </div>
          <div class="text-caption profile-muted q-mt-xs">
            {{ authStore.user?.email }}
          </div>
        </div>

        <q-separator class="q-mx-md q-mb-lg" />

        <!-- Statistike -->
        <div class="row q-px-md q-gutter-md q-mb-lg">
          <q-card flat bordered class="col stat-card">
            <q-card-section class="text-center q-pa-md">
              <div class="text-h5 text-weight-bold stat-number">{{ stats.projects }}</div>
              <div class="text-caption profile-muted">{{ $t('projects.title') }}</div>
            </q-card-section>
          </q-card>
          <q-card flat bordered class="col stat-card">
            <q-card-section class="text-center q-pa-md">
              <div class="text-h5 text-weight-bold stat-number">{{ stats.ideas }}</div>
              <div class="text-caption profile-muted">{{ $t('ideas.title') }}</div>
            </q-card-section>
          </q-card>
          <q-card flat bordered class="col stat-card">
            <q-card-section class="text-center q-pa-md">
              <div class="text-h5 text-weight-bold stat-number">{{ stats.bugs }}</div>
              <div class="text-caption profile-muted">{{ $t('bugs.title') }}</div>
            </q-card-section>
          </q-card>
        </div>

        <!-- Edit profila -->
        <div class="q-px-md q-mb-md">
          <q-card flat bordered class="profile-card">
            <q-card-section>
              <div class="text-subtitle2 q-mb-sm profile-name">{{ $t('settings.profile') }}</div>
              <div class="q-gutter-sm">
                <q-input
                  v-model="form.full_name"
                  :label="$t('settings.fullName')"
                  outlined
                  dense
                  clearable
                />
                <q-input
                  :model-value="authStore.user?.email"
                  :label="$t('auth.email')"
                  outlined
                  dense
                  readonly
                />
              </div>
            </q-card-section>
            <q-card-actions align="right">
              <q-btn
                color="primary"
                :label="$t('settings.save')"
                :loading="savingProfile"
                @click="saveProfile"
              />
            </q-card-actions>
          </q-card>
        </div>

        <!-- Promjena lozinke -->
        <div class="q-px-md q-mb-md">
          <q-card flat bordered class="profile-card">
            <q-card-section>
              <div class="text-subtitle2 q-mb-sm profile-name">
                {{ $t('settings.changePassword') }}
              </div>
              <div class="q-gutter-sm">
                <q-input
                  v-model="passwordForm.current"
                  :label="$t('settings.currentPassword')"
                  :type="showCurrent ? 'text' : 'password'"
                  outlined
                  dense
                  clearable
                  autocomplete="current-password"
                >
                  <template #append>
                    <q-icon
                      :name="showCurrent ? 'visibility_off' : 'visibility'"
                      class="cursor-pointer"
                      @click="showCurrent = !showCurrent"
                    />
                  </template>
                </q-input>
                <q-input
                  v-model="passwordForm.next"
                  :label="$t('settings.newPassword')"
                  :type="showNext ? 'text' : 'password'"
                  outlined
                  dense
                  clearable
                  autocomplete="new-password"
                >
                  <template #append>
                    <q-icon
                      :name="showNext ? 'visibility_off' : 'visibility'"
                      class="cursor-pointer"
                      @click="showNext = !showNext"
                    />
                  </template>
                </q-input>
                <q-input
                  v-model="passwordForm.confirm"
                  :label="$t('settings.confirmPassword')"
                  :type="showConfirm ? 'text' : 'password'"
                  outlined
                  dense
                  clearable
                  autocomplete="new-password"
                >
                  <template #append>
                    <q-icon
                      :name="showConfirm ? 'visibility_off' : 'visibility'"
                      class="cursor-pointer"
                      @click="showConfirm = !showConfirm"
                    />
                  </template>
                </q-input>
              </div>
            </q-card-section>
            <q-card-actions align="right">
              <q-btn
                color="primary"
                :label="$t('settings.changePassword')"
                :loading="changingPassword"
                :disable="!passwordForm.current || !passwordForm.next || !passwordForm.confirm"
                @click="changePassword"
              />
            </q-card-actions>
          </q-card>
        </div>

        <!-- Projekti -->
        <div class="q-px-md q-mb-md">
          <div class="text-subtitle2 text-weight-medium profile-name q-mb-sm">
            {{ $t('projects.title') }}
          </div>
          <q-list separator>
            <q-item
              v-for="project in projectsStore.projects"
              :key="project.id"
              clickable
              class="project-item"
              @click="$router.push(`/project/${project.id}`)"
            >
              <q-item-section avatar>
                <div class="project-dot" :style="{ background: project.color }" />
              </q-item-section>
              <q-item-section>
                <q-item-label class="profile-name text-weight-medium">{{
                  project.name
                }}</q-item-label>
                <q-item-label caption class="profile-muted">{{ memberRole(project) }}</q-item-label>
              </q-item-section>
              <q-item-section side>
                <q-icon name="chevron_right" color="grey" />
              </q-item-section>
            </q-item>
          </q-list>
        </div>

        <!-- Brisanje accounta -->
        <div class="q-px-md">
          <q-card flat bordered class="border-negative">
            <q-card-section>
              <div class="text-subtitle2 text-negative q-mb-xs">
                {{ $t('settings.deleteAccount') }}
              </div>
              <div class="text-caption profile-muted q-mb-sm">
                {{ $t('settings.deleteAccountConfirm') }}
              </div>
              <q-btn
                color="negative"
                outline
                icon="delete_forever"
                :label="$t('settings.deleteAccount')"
                :loading="deleting"
                @click="confirmDelete"
              />
            </q-card-section>
          </q-card>
        </div>
      </q-page>
    </q-page-container>
  </q-layout>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useQuasar } from 'quasar'
import { useI18n } from 'vue-i18n'
import AppHeader from 'src/components/shared/AppHeader.vue'
import UserAvatar from 'src/components/shared/UserAvatar.vue'
import { useAuthStore } from 'src/stores/auth'
import { useProjectsStore } from 'src/stores/projects'
import { useItemsStore } from 'src/stores/items'
import { useImageUpload } from 'src/composables/useImageUpload'
import { useConfirmDialog } from 'src/composables/useConfirmDialog'
import { discardReplacedScreenshot } from 'src/utils/screenshots'
import { removeCachedImage } from 'src/utils/imageCache'
import { supabase } from 'src/boot/supabase'

const router = useRouter()
const $q = useQuasar()
const { t } = useI18n()
const { confirmDestructive } = useConfirmDialog()
const authStore = useAuthStore()
const projectsStore = useProjectsStore()
const itemsStore = useItemsStore()
const { uploadImage } = useImageUpload()

const savingProfile = ref(false)
const changingPassword = ref(false)
const passwordForm = ref({ current: '', next: '', confirm: '' })
const showCurrent = ref(false)
const showNext = ref(false)
const showConfirm = ref(false)
const deleting = ref(false)
const avatarInput = ref(null)
const uploadingAvatar = ref(false)

const form = ref({
  full_name: authStore.profile?.full_name ?? '',
})

onMounted(() => {
  form.value.full_name = authStore.profile?.full_name ?? ''
})

const stats = computed(() => ({
  projects: projectsStore.projects.length,
  ideas: itemsStore.items.filter((i) => i.kind === 'idea').length,
  bugs: itemsStore.items.filter((i) => i.kind === 'bug').length,
}))

const memberRole = (project) => {
  const member = project.project_members?.find((m) => m.user_id === authStore.user?.id)
  return member?.role === 'owner' ? 'Owner' : 'Member'
}

function triggerAvatarPicker() {
  if (uploadingAvatar.value) return
  avatarInput.value?.click()
}

async function onAvatarSelected(e) {
  const file = e.target.files[0]
  e.target.value = ''
  if (!file) return

  uploadingAvatar.value = true
  try {
    const previousPath = authStore.profile?.avatar_url
    const uploaded = await uploadImage(file, { maxWidth: 256, quality: 0.7, bucket: 'avatars' })
    await authStore.updateProfile({ avatar_url: uploaded.path })
    await discardReplacedScreenshot(previousPath, uploaded.path, 'avatars')
    $q.notify({ type: 'positive', message: t('settings.saved') })
  } catch (err) {
    $q.notify({ type: 'negative', message: err.message })
  } finally {
    uploadingAvatar.value = false
  }
}

async function removeAvatar() {
  const previousPath = authStore.profile?.avatar_url
  if (!previousPath) return

  uploadingAvatar.value = true
  try {
    await authStore.updateProfile({ avatar_url: null })
    await supabase.storage.from('avatars').remove([previousPath])
    await removeCachedImage(previousPath)
    $q.notify({ type: 'positive', message: t('settings.saved') })
  } catch (err) {
    $q.notify({ type: 'negative', message: err.message })
  } finally {
    uploadingAvatar.value = false
  }
}

async function saveProfile() {
  savingProfile.value = true
  try {
    await authStore.updateProfile({ full_name: form.value.full_name })
    $q.notify({ type: 'positive', message: t('settings.saved') })
  } catch (e) {
    $q.notify({ type: 'negative', message: e.message })
  } finally {
    savingProfile.value = false
  }
}

async function changePassword() {
  if (passwordForm.value.next !== passwordForm.value.confirm) {
    $q.notify({ type: 'negative', message: t('settings.passwordMismatch') })
    return
  }
  if (passwordForm.value.next.length < 6) {
    $q.notify({ type: 'negative', message: t('settings.passwordTooShort') })
    return
  }

  changingPassword.value = true
  try {
    await authStore.changePassword(passwordForm.value.current, passwordForm.value.next)
    passwordForm.value = { current: '', next: '', confirm: '' }
    $q.notify({ type: 'positive', message: t('settings.passwordChanged') })
  } catch (e) {
    // Supabase sam vraća čitljivu grešku za pogrešnu trenutnu lozinku
    // (current_password ide izravno u updateUser(), vidi auth.js) — nema
    // više našeg posrednog signInWithPassword koraka da bismo je sami
    // prevodili.
    $q.notify({ type: 'negative', message: e.message })
  } finally {
    changingPassword.value = false
  }
}

async function logout() {
  await authStore.logout()
  router.push('/login')
}

async function confirmDelete() {
  const ok = await confirmDestructive({
    title: t('settings.deleteAccount'),
    message: t('settings.deleteAccountConfirm'),
    okLabel: t('common.confirm'),
  })
  if (!ok) return

  deleting.value = true
  try {
    await authStore.deleteAccount()
    router.push('/login')
    $q.notify({ type: 'positive', message: t('settings.deleteAccountSuccess') })
  } catch (e) {
    if (e.type === 'sole_owner') {
      $q.notify({
        type: 'warning',
        message: t('settings.deleteAccountWarn', { projects: e.projects.join(', ') }),
        timeout: 5000,
      })
    } else if (e.message?.includes('barem jednog vlasnika')) {
      // B19: guard_last_org_owner (server trigger) baca čitljivu poruku, ali
      // hrvatsku i izvan i18n-a — bez ovoga bi engleski korisnik vidio sirov
      // hrvatski tekst iz baze. Provjera na projekte (soleOwned, iznad) ne
      // hvata ovo jer gleda project_members, ne org_members — zadnji vlasnik
      // organizacije prođe taj predček, pa ga uhvati tek trigger na serveru.
      $q.notify({ type: 'warning', message: t('settings.deleteAccountLastOwner'), timeout: 5000 })
    } else {
      $q.notify({ type: 'negative', message: e.message })
    }
  } finally {
    deleting.value = false
  }
}
</script>

<style scoped>
.aarc-header {
  background: var(--aarc-header) !important;
}

.hidden {
  display: none;
}

.avatar-upload {
  position: relative;
}

/* box-shadow umjesto border — pravi border ulazi u box-model i remeti
   Quasarov interni width/height: inherit lanac unutar q-avatara (sadržaj
   i img prestanu biti točno centrirani unutar kruga). box-shadow je čisto
   vizualan, ne dira dimenzije, pa je ista stvar bez te posljedice. */
.profile-avatar {
  box-shadow: 0 0 0 3px var(--aarc-accent);
}

.avatar-upload-badge {
  position: absolute;
  right: 0;
  bottom: 0;
  width: 28px;
  height: 28px;
  border-radius: 50%;
  background: var(--aarc-accent);
  display: flex;
  align-items: center;
  justify-content: center;
  border: 2px solid var(--aarc-bg);
}

.profile-page {
  background: var(--aarc-bg) !important;
}

.profile-name {
  color: var(--aarc-text);
}
.profile-muted {
  color: var(--aarc-muted);
}

.stat-card {
  border-radius: 12px !important;
  border-color: var(--aarc-border) !important;
  background: var(--aarc-surface) !important;
}

.stat-number {
  color: var(--aarc-primary);
}

.profile-card {
  border-radius: 16px !important;
  border-color: var(--aarc-border) !important;
  background: var(--aarc-surface) !important;
}

.project-item {
  background: var(--aarc-surface);
  border-radius: 8px;
}

.project-dot {
  width: 12px;
  height: 12px;
  border-radius: 50%;
}

.border-negative {
  border-color: var(--q-negative) !important;
  border-radius: 16px !important;
  background: var(--aarc-surface) !important;
}
</style>
