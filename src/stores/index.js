import { defineStore } from '#q-app'
import { createPinia } from 'pinia'
import { piniaPersistPlugin } from './persist-plugin'

/*
 * If not building with SSR mode, you can
 * directly export the Store instantiation;
 *
 * The function below can be async too; either use
 * async/await or return a Promise which resolves
 * with the Store instance.
 */

export default defineStore((/* { ssrContext } */) => {
  const pinia = createPinia()

  // Offline-first: perzistencija storova s `persist` opcijom (docs/offline-first.md)
  pinia.use(piniaPersistPlugin)

  return pinia
})
