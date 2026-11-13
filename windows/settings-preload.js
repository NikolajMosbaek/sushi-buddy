// What the Settings page may ask of the app.
const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('sushiSettings', {
  get: () => ipcRenderer.invoke('settings:get'),
  set: (key, value) => ipcRenderer.invoke('settings:set', key, value),
  act: action => ipcRenderer.invoke('settings:action', action),
  signals: () => ipcRenderer.invoke('settings:signals'),
  usagePreview: () => ipcRenderer.invoke('settings:usage-preview'),
  onState: listener => ipcRenderer.on('settings:state', (_event, state) => listener(state)),
})
