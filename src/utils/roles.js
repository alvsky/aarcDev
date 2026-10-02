// Boja oznake uloge — ista na ekranu organizacije i u popisu članova projekta.
export function roleColor(role) {
  return { owner: 'primary', admin: 'accent', member: 'grey-6', guest: 'grey-4' }[role] ?? 'grey-6'
}
