const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 800,
    height: 600,
    backgroundColor: '#111111',
    darkTheme: true,
    autoHideMenuBar: true,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });

  mainWindow.loadFile(path.join(__dirname, 'index.html'));
}

app.whenReady().then(() => {
  createWindow();

  // Sender Function: Strictly follows Chromium Native Messaging protocol
  function sendMessageToExtension(msg) {
    const jsonString = JSON.stringify(msg);
    const jsonBuffer = Buffer.from(jsonString, 'utf8');
    const headerBuffer = Buffer.alloc(4);
    headerBuffer.writeUInt32LE(jsonBuffer.length, 0);
    process.stdout.write(headerBuffer);
    process.stdout.write(jsonBuffer);
  }

  let inputBuffer = Buffer.alloc(0);

  // Chrome Native Messaging Protocol Decoder
  process.stdin.on('data', (chunk) => {
    inputBuffer = Buffer.concat([inputBuffer, chunk]);

    while (inputBuffer.length >= 4) {
      const length = inputBuffer.readUInt32LE(0);
      if (inputBuffer.length >= 4 + length) {
        const messageBuffer = inputBuffer.subarray(4, 4 + length);
        inputBuffer = inputBuffer.subarray(4 + length);

        try {
          const message = JSON.parse(messageBuffer.toString('utf8'));
          
          // Step 2: Auto-respond to satisfy the extension's RequestManager queue
          if (message.id) {
            sendMessageToExtension({ id: message.id, result: "ok" });
          }

          if (mainWindow && mainWindow.webContents) {
            mainWindow.webContents.send('download-intercepted', message);
          }
        } catch (e) {
          console.error("Failed to parse native message: ", e);
        }
      } else {
        break; // Wait for the rest of the message
      }
    }
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
