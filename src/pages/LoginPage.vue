<template>
  <q-layout view="hHh lpR fFf">
    <q-page-container>
      <q-page class="flex flex-center bg-grey-1">
        <q-card flat bordered style="width: 360px">
          <q-card-section class="text-center q-pb-none">
            <div class="text-h5 text-weight-bold text-primary">aarc</div>
            <div class="text-caption text-grey-6 q-mt-xs">
              {{ isLogin ? $t('auth.login') : $t('auth.register') }}
            </div>
          </q-card-section>

          <!-- G2: signUp() dok "Confirm email" čeka potvrdu ne vraća sesiju —
               nema koga prijaviti ni što stvarati (organizaciju), samo
               uputiti na mail. -->
          <q-card-section v-if="awaitingConfirmation" class="text-center q-gutter-sm">
            <q-icon name="mark_email_read" size="40px" color="primary" />
            <div class="text-body2">{{ $t('auth.checkEmail', { email: form.email }) }}</div>
            <q-btn
              flat
              color="primary"
              :label="$t('auth.backToLogin')"
              @click="awaitingConfirmation = false"
            />
          </q-card-section>

          <q-form v-else ref="formRef" @submit.prevent="submit">
            <q-card-section class="q-gutter-sm">
              <q-input
                v-if="!isLogin"
                v-model="form.fullName"
                :label="$t('auth.fullName')"
                outlined
                dense
                clearable
                :rules="[(v) => !!v?.trim() || $t('common.required')]"
              />
              <q-input
                v-model="form.email"
                :label="$t('auth.email')"
                type="email"
                outlined
                dense
                clearable
                :rules="[(v) => !!v || $t('common.required')]"
              />
              <q-input
                v-model="form.password"
                :label="$t('auth.password')"
                :type="showPass ? 'text' : 'password'"
                outlined
                dense
                clearable
                :rules="[(v) => !!v || $t('common.required')]"
              >
                <template #append>
                  <q-icon
                    :name="showPass ? 'visibility_off' : 'visibility'"
                    class="cursor-pointer"
                    @click="showPass = !showPass"
                  />
                </template>
              </q-input>

              <div class="text-right" v-if="isLogin">
                <q-btn
                  flat
                  dense
                  size="sm"
                  :label="$t('auth.forgotPassword')"
                  class="text-grey-6"
                  @click="promptForgotPassword"
                />
              </div>

              <div v-if="errorMsg" class="text-negative text-caption">
                {{ errorMsg }}
              </div>
            </q-card-section>

            <q-card-section class="q-pt-none q-gutter-sm">
              <q-btn
                type="submit"
                :label="isLogin ? $t('auth.loginBtn') : $t('auth.registerBtn')"
                color="primary"
                class="full-width"
                :loading="loading"
              />
              <q-btn
                :label="isLogin ? $t('auth.noAccount') : $t('auth.hasAccount')"
                flat
                class="full-width text-grey-6"
                @click="toggle"
              />
            </q-card-section>
          </q-form>
        </q-card>
      </q-page>
    </q-page-container>
  </q-layout>
</template>

<script setup>
import { ref, reactive } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useQuasar } from 'quasar'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from 'src/stores/auth'
import { useOrgsStore } from 'src/stores/orgs'

const router = useRouter()
const route = useRoute()
const $q = useQuasar()
const { t } = useI18n()
const authStore = useAuthStore()
const orgsStore = useOrgsStore()

const formRef = ref(null)
const isLogin = ref(true)
const showPass = ref(false)
const loading = ref(false)
const errorMsg = ref('')
const awaitingConfirmation = ref(false)

const form = reactive({
  fullName: '',
  // Stiže s /invite/:token kad korisnik nema račun ili nije prijavljen tom
  // adresom — pozivnica traži TOČNO tu adresu, pa je predispuna umjesto
  // prepisivanja smanjuje šansu za tipfeler koji bi accept_invitation svejedno
  // odbio.
  email: typeof route.query.email === 'string' ? route.query.email : '',
  password: '',
})

function toggle() {
  isLogin.value = !isLogin.value
  errorMsg.value = ''
}

function promptForgotPassword() {
  $q.dialog({
    title: t('auth.forgotPassword'),
    message: t('auth.forgotPasswordHint'),
    prompt: { model: form.email, type: 'email', label: t('auth.email') },
    cancel: true,
  }).onOk(async (email) => {
    if (!email?.trim()) return
    try {
      await authStore.requestPasswordReset(email.trim())
      $q.notify({ type: 'positive', message: t('auth.resetLinkSent', { email: email.trim() }) })
    } catch (e) {
      $q.notify({ type: 'negative', message: e.message })
    }
  })
}

async function submit() {
  errorMsg.value = ''
  const valid = await formRef.value.validate()
  if (!valid) return
  loading.value = true
  try {
    if (isLogin.value) {
      await authStore.login(form.email, form.password)
    } else {
      const { session } = await authStore.register(form.email, form.password, form.fullName)
      if (!session) {
        awaitingConfirmation.value = true
        return
      }
      // B23: bez pozivnice novi korisnik nema nijednu organizaciju. Preko
      // /invite/:token članstvo osigurava accept_invitation na
      // AcceptInvitePage (poslije ovog redirecta), pa se ovdje tada ništa
      // ne stvara — inače bi svaki pozvani dobio i suvišnu vlastitu org.
      const cameFromInvite =
        typeof route.query.redirect === 'string' && route.query.redirect.startsWith('/invite/')
      if (!cameFromInvite) {
        await orgsStore.createOrg(form.fullName)
      }
    }
    const redirect = typeof route.query.redirect === 'string' ? route.query.redirect : '/'
    router.push(redirect)
  } catch (e) {
    errorMsg.value = e.message
  } finally {
    loading.value = false
  }
}
</script>
