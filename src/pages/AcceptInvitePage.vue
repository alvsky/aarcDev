<template>
  <q-layout view="hHh lpR fFf">
    <q-page-container>
      <q-page class="flex flex-center bg-grey-1 q-pa-md">
        <q-card flat bordered style="width: 380px">
          <q-card-section class="text-center q-pb-none">
            <div class="text-h5 text-weight-bold text-primary">aarc</div>
            <div class="text-caption text-grey-6 q-mt-xs">{{ $t('invite.title') }}</div>
          </q-card-section>

          <q-card-section v-if="loading" class="flex flex-center q-pa-lg">
            <q-spinner size="32px" color="primary" />
          </q-card-section>

          <q-card-section v-else-if="!invite" class="text-center">
            <q-icon name="link_off" size="40px" color="grey-5" class="q-mb-sm" />
            <div class="text-body2 text-grey-7">{{ $t('invite.notFound') }}</div>
          </q-card-section>

          <template v-else>
            <q-card-section>
              <div class="text-body1 q-mb-xs">
                {{
                  $t('invite.invitedTo', {
                    org: invite.org_name,
                    role: $t(`org.role.${invite.role}`),
                  })
                }}
              </div>
            </q-card-section>

            <!-- Nije prijavljen: mora se prijaviti/registrirati TOČNO onom
                 adresom na koju je pozivnica poslana — accept_invitation to
                 provjerava na poslužitelju, ovdje samo objašnjavamo unaprijed. -->
            <q-card-section v-if="!authStore.user" class="q-gutter-sm">
              <div class="text-caption text-grey-7">
                {{ $t('invite.loginToJoin', { email: invite.email }) }}
              </div>
              <q-btn
                color="primary"
                class="full-width"
                :label="$t('invite.login')"
                @click="goToLogin"
              />
            </q-card-section>

            <!-- Prijavljen, ali drugom adresom -->
            <q-card-section v-else-if="!emailMatches" class="q-gutter-sm">
              <div class="text-caption text-negative">
                {{
                  $t('invite.wrongAccount', {
                    invited: invite.email,
                    current: authStore.user.email,
                  })
                }}
              </div>
              <q-btn
                outline
                color="primary"
                class="full-width"
                :label="$t('invite.logoutAndSwitch')"
                @click="logoutAndSwitch"
              />
            </q-card-section>

            <!-- Prijavljen, ispravna adresa -->
            <q-card-section v-else class="q-gutter-sm">
              <q-btn
                color="primary"
                class="full-width"
                :label="$t('invite.accept')"
                :loading="accepting"
                @click="accept"
              />
            </q-card-section>
          </template>
        </q-card>
      </q-page>
    </q-page-container>
  </q-layout>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useQuasar } from 'quasar'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from 'src/stores/auth'
import { useOrgsStore } from 'src/stores/orgs'

const route = useRoute()
const router = useRouter()
const $q = useQuasar()
const { t } = useI18n()
const authStore = useAuthStore()
const orgsStore = useOrgsStore()

const loading = ref(true)
const accepting = ref(false)
const invite = ref(null)

const emailMatches = computed(
  () => authStore.user?.email?.toLowerCase() === invite.value?.email?.toLowerCase(),
)

function goToLogin() {
  // Token ostaje u URL-u kroz redirect param — nakon prijave/registracije
  // LoginPage se vraća točno ovamo umjesto na Home, pa se pregled ponovno
  // učita i sad zna da je korisnik prijavljen.
  router.push({ path: '/login', query: { redirect: route.fullPath, email: invite.value?.email } })
}

async function logoutAndSwitch() {
  await authStore.logout()
  goToLogin()
}

async function accept() {
  accepting.value = true
  try {
    await orgsStore.acceptInvitation(route.params.token)
    $q.notify({ type: 'positive', message: t('invite.accepted', { org: invite.value.org_name }) })
    router.push('/')
  } catch (e) {
    $q.notify({ type: 'negative', message: e.message })
  } finally {
    accepting.value = false
  }
}

onMounted(async () => {
  try {
    invite.value = await orgsStore.getInvitationPreview(route.params.token)
  } finally {
    loading.value = false
  }
})
</script>
