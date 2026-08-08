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

          <q-card-section class="q-gutter-sm">
            <q-input
              v-if="!isLogin"
              v-model="form.fullName"
              :label="$t('auth.fullName')"
              outlined
              dense
              :rules="[(v) => !!v || $t('common.required')]"
            />
            <q-input
              v-model="form.email"
              :label="$t('auth.email')"
              type="email"
              outlined
              dense
              :rules="[(v) => !!v || $t('common.required')]"
            />
            <q-input
              v-model="form.password"
              :label="$t('auth.password')"
              :type="showPass ? 'text' : 'password'"
              outlined
              dense
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

            <div v-if="errorMsg" class="text-negative text-caption">
              {{ errorMsg }}
            </div>
          </q-card-section>

          <q-card-section class="q-pt-none q-gutter-sm">
            <q-btn
              :label="isLogin ? $t('auth.loginBtn') : $t('auth.registerBtn')"
              color="primary"
              class="full-width"
              :loading="loading"
              @click="submit"
            />
            <q-btn
              :label="isLogin ? $t('auth.noAccount') : $t('auth.hasAccount')"
              flat
              class="full-width text-grey-6"
              @click="toggle"
            />
          </q-card-section>
        </q-card>
      </q-page>
    </q-page-container>
  </q-layout>
</template>

<script setup>
import { ref, reactive } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from 'src/stores/auth'

const router = useRouter()
const authStore = useAuthStore()

const isLogin = ref(true)
const showPass = ref(false)
const loading = ref(false)
const errorMsg = ref('')

const form = reactive({
  fullName: '',
  email: '',
  password: '',
})

function toggle() {
  isLogin.value = !isLogin.value
  errorMsg.value = ''
}

async function submit() {
  errorMsg.value = ''
  loading.value = true
  try {
    if (isLogin.value) {
      await authStore.login(form.email, form.password)
    } else {
      await authStore.register(form.email, form.password, form.fullName)
    }
    router.push('/')
  } catch (e) {
    errorMsg.value = e.message
  } finally {
    loading.value = false
  }
}
</script>
