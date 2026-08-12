<template>
  <q-layout view="hHh lpR fFf">
    <q-page-container>
      <q-page class="flex flex-center bg-grey-1">
        <q-card flat bordered style="width: 360px">
          <q-card-section class="text-center q-pb-none">
            <div class="text-h5 text-weight-bold text-primary">aarc</div>
            <div class="text-caption text-grey-6 q-mt-xs">{{ $t('auth.resetPassword') }}</div>
          </q-card-section>

          <q-card-section v-if="done" class="text-center q-gutter-sm">
            <q-icon name="check_circle" size="40px" color="positive" />
            <div class="text-body2">{{ $t('auth.resetPasswordDone') }}</div>
          </q-card-section>

          <q-form v-else ref="formRef" @submit.prevent="submit">
            <q-card-section class="q-gutter-sm">
              <q-input
                v-model="password"
                :label="$t('settings.newPassword')"
                :type="showPass ? 'text' : 'password'"
                outlined
                dense
                clearable
                autocomplete="new-password"
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
              <q-input
                v-model="confirm"
                :label="$t('settings.confirmPassword')"
                :type="showPass ? 'text' : 'password'"
                outlined
                dense
                clearable
                autocomplete="new-password"
                :rules="[(v) => !!v || $t('common.required')]"
              />

              <div v-if="errorMsg" class="text-negative text-caption">
                {{ errorMsg }}
              </div>
            </q-card-section>

            <q-card-section class="q-pt-none">
              <q-btn
                type="submit"
                :label="$t('auth.resetPassword')"
                color="primary"
                class="full-width"
                :loading="loading"
              />
            </q-card-section>
          </q-form>
        </q-card>
      </q-page>
    </q-page-container>
  </q-layout>
</template>

<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from 'src/stores/auth'

const router = useRouter()
const { t } = useI18n()
const authStore = useAuthStore()

const formRef = ref(null)
const password = ref('')
const confirm = ref('')
const showPass = ref(false)
const loading = ref(false)
const errorMsg = ref('')
const done = ref(false)

async function submit() {
  errorMsg.value = ''
  const valid = await formRef.value.validate()
  if (!valid) return
  if (password.value !== confirm.value) {
    errorMsg.value = t('settings.passwordMismatch')
    return
  }
  if (password.value.length < 6) {
    errorMsg.value = t('settings.passwordTooShort')
    return
  }

  loading.value = true
  try {
    await authStore.confirmPasswordReset(password.value)
    done.value = true
    setTimeout(() => router.push('/'), 2000)
  } catch (e) {
    errorMsg.value = e.message
  } finally {
    loading.value = false
  }
}
</script>
