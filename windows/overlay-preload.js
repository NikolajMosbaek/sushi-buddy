// What the overlay tells the app: take clicks while the mouse is over the sushi, and each pet.
const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('sushiOverlay', {
  setOverSushi: over => ipcRenderer.send('overlay:over-sushi', over === true),
  petted: () => ipcRenderer.send('overlay:petted'),
})
