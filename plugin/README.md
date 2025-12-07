# Roblox Studio Plugin Installation

## Method 1: Auto-Install (Recommended)

_A published version of the plugin will soon be available on the Roblox Library._

## Method 2: Manual Install

1. Open Roblox Studio
2. Go to **Plugins** → **Plugins Folder**
3. Copy the entire `plugin` folder to the opened location
4. Restart Roblox Studio

## Troubleshooting

### Plugin not connecting

- Ensure the daemon is running (`npm run dev`)
- Check that HttpService is enabled:
  - Go to **Home** → **Game Settings** → **Security**
  - Enable **"Allow HTTP Requests"**
- Verify firewall isn't blocking port 8080

### Scripts not syncing

- Click "Toggle Sync" to reconnect
- Check the Output window for error messages
- Restart both the daemon and Studio

### GUID conflicts

If you're getting GUID conflicts, clear all GUIDs:

```lua
-- Run this in the Command Bar
for _, desc in ipairs(game:GetDescendants()) do
    if desc:GetAttribute("StudioSyncGUID") then
        desc:SetAttribute("StudioSyncGUID", nil)
    end
end
```

## Features

- ✅ **Real-time sync**: Changes in Studio instantly update files
- ✅ **Bi-directional**: Edit files externally and see changes in Studio
- ✅ **Automatic GUID tracking**: Never manually manage instance IDs
- ✅ **Reconnect support**: Automatically reconnects if daemon restarts
- ✅ **Safe syncing**: Only syncs scripts, not the entire DataModel
