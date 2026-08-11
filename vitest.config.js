import { defineConfig } from 'vitest/config'

export default defineConfig({
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
