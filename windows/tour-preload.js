// What the tour may ask of the app.
const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('sushiTourApp', {
  settings: () => ipcRenderer.invoke('tour:settings'),
  set: (key, value) => ipcRenderer.invoke('tour:set', key, value),
  copyInstall: () => ipcRenderer.invoke('tour:copy-install'),
  done: () => ipcRenderer.send('tour:done'),
  setOverSushi: over => ipcRenderer.send('overlay:over-sushi', over === true),
  onReact: listener => ipcRenderer.on('tour:react', () => listener()),
})
