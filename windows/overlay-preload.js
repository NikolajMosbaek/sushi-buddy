// The one thing the overlay asks of the app: take clicks while the mouse is over the sushi.
const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('sushiOverlay', {
  setOverSushi: over => ipcRenderer.send('overlay:over-sushi', over === true),
})
