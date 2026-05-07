# <span><img src="/docs/assets/logo.png" alt="Azul Logo" height="30"></span> Azul Companion Plugin

## Installation

### Method 1: Automatic via Roblox Marketplace (Recommended)

1. Install the plugin automatically using the Roblox Plugin Marketplace: https://create.roblox.com/store/asset/79510309341601/Azul-Companion-Plugin

> If the plugin does not show up, follow the [troubleshooting steps](#troubleshooting).

### Method 2: Manual Install via Place File

1. Download the source code from the [Azul Companion Plugin](https://www.roblox.com/games/132762411481199/Azul-Companion-Plugin) place: (3 dots (⋯) > "Download")
2. Open the downloaded `.rbxlx` or `.rbxl` file in Roblox Studio
3. Right-click the `AzulCompanionPlugin` folder in `ReplicatedFirst` and select **"Save as Local Plugin"**
4. Restart Roblox Studio
5. The Azul icon should now appear in the toolbar

### Method 3: Build via Azul

You can use Azul to build the plugin directly from source code:

```ps1
cd plugin
azul build --from-sourcemap .\sourcemap.json
```

> [!NOTE]
> Note that, for now, you must first have **the plugin itself already installed** in Studio for this option to work.
>
> This is planned to change soon by allowing Azul to generate Model files (`rbxmx`) directly.

## Troubleshooting

### Plugin not showing up

Roblox is very particular about how plugins are installed. Sometimes, just "getting" the plugin from the marketplace isn't enough. Try the following steps:

1. Restart Roblox Studio
2. Open any game (or create a new one)
3. Go to **Toolbox** > **Inventory**<br/>
   ![alt text](../docs/assets/plugin/toolbox.png)
4. In the dropdown, select **My Plugins**
5. Locate the Azul Companion Plugin and click **Install**
6. The Azul icon should now appear in the toolbar

### Plugin not connecting

- Ensure the daemon is running (run `azul`)
- Check that `HttpService` is enabled:
  - Go to **Home** → **Game Settings** → **Security**
  - Enable **"Allow HTTP Requests"**
- Verify firewall isn't blocking port 8080

### Scripts not syncing

- Click "Toggle Sync" to reconnect
- Check the Output window for error messages
- Restart both the daemon and Studio
