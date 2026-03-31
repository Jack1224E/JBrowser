const { ipcRenderer } = require('electron');

const statusContainer = document.getElementById('status-container');
const connectionDropdown = document.getElementById('max-connections');

ipcRenderer.on('download-intercepted', (event, payload) => {
  if (!payload || !payload.url) return;
  
  const filename = payload.filename || 'download.bin';
  statusContainer.className = 'downloading-text';
  statusContainer.innerText = `[Aria2c] Intercepted: ${filename}\nSending to engine...`;

  const headers = [];
  if (payload.cookies) headers.push(`Cookie: ${payload.cookies}`);
  if (payload.referer) headers.push(`Referer: ${payload.referer}`);
  if (payload.userAgent) headers.push(`User-Agent: ${payload.userAgent}`);

  const maxConnections = connectionDropdown.value;

  const rpcPayload = {
    jsonrpc: "2.0",
    id: "pir-bridge-" + Date.now().toString(),
    method: "aria2.addUri",
    params: [
      [payload.url],
      {
        "header": headers,
        "max-connection-per-server": maxConnections,
        "split": maxConnections,
        "out": payload.filename ? payload.filename : undefined
      }
    ]
  };

  fetch('http://127.0.0.1:6800/jsonrpc', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(rpcPayload)
  }).then(res => res.json())
    .then(data => {
      console.log('aria2 response:', data);
      if (data.id && data.result) {
          statusContainer.innerText = `🚀 DOWNLOADING: ${filename}\n(GID: ${data.result})\nConnections: ${maxConnections}`;
      } else if (data.error) {
          statusContainer.innerText = `❌ ENGINE ERROR: ${filename}\n(Error: ${data.error.message})`;
      }
    })
    .catch(err => {
      console.error('aria2 fetch error:', err);
      statusContainer.innerText = `❌ SYSTEM FAILURE: Could not connect to aria2c RPC server on port 6800. Is the engine running?`;
    });
});
