import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vitest/config'

export default defineConfig({
  resolve: {
    // E1: čisti unit testovi (tests/unit) uvoze store/util module preko
    // src/... aliasa, isto kao i sama aplikacija (CLAUDE.md konvencija).
    // Ovaj config je odvojen od quasar.config.js (koje taj alias inače
    // postavlja preko Vitea za sam build), pa ga ovdje treba ponoviti.
    alias: {
      src: fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  test: {
    environment: 'node',
    // B17: integracijski testovi zovu pravi dev Supabase projekt (nema lokalnog
    // Supabase/Dockera u ovom repou), pa svaki test upravlja vlastitim mrežnim
    // pozivima — paralelno izvođenje samo množi rizik od preplitanja test
    // korisnika/orgova bez ikakve koristi na jednoj test datoteci.
    fileParallelism: false,
    testTimeout: 30000,
    hookTimeout: 30000,
  },
})
