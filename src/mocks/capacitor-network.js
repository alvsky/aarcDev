export const Network = {
  getStatus: async () => ({ connected: true, connectionType: 'wifi' }),
  addListener: async () => ({ remove: async () => {} }),
}
