param(
    [switch]$Force,
    [switch]$ContinueAfterNodeInstall
)

Write-Output "=== Azul: Easy Install Script ==="

function Reload-PathFromRegistry {
    $machine = [System.Environment]::GetEnvironmentVariable('Path','Machine')
    $user    = [System.Environment]::GetEnvironmentVariable('Path','User')
    if ($machine -or $user) {
        $env:Path = ($machine + ';' + $user).TrimEnd(';')
    }
}

function Get-PowerShellExe {
    $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)
    if ($pwsh) { return $pwsh.Source }
    $ps = (Get-Command powershell -ErrorAction SilentlyContinue)
    if ($ps) { return $ps.Source }
    return $null
}

function Check-NodeInstalled {
    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($node) { return $true }
    return $false
}

function Find-RepoRoot([string]$start) {
    $dir = Get-Item $start
    while ($dir) {
        if ((Test-Path (Join-Path $dir.FullName 'package.json')) -or (Test-Path (Join-Path $dir.FullName '.git'))) {
            return $dir.FullName
        }
        $dir = $dir.Parent
    }
    return $start
}


if (-not $Force) {
    Write-Output "Are you sure you want to install Azul? (Y/N)"
    $response = Read-Host
    if ($response -ne 'Y' -and $response -ne 'y') {
        Write-Output "Installation aborted by user."
        exit
    }
} else {
    Write-Output "Running in non-interactive mode (-Force): skipping prompts."
}

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).ProviderPath }
$repoRoot = Find-RepoRoot $scriptDir

Reload-PathFromRegistry

# Check for Node.js installation
if (-not (Check-NodeInstalled)) {
    if (-not $Force) {
        Write-Output "Node.js / npm not detected on PATH. Install Node.js now? (Y/N)"
        $response = Read-Host
        if ($response -ne 'Y' -and $response -ne 'y') {
            Write-Output "Please install Node.js and re-run this script."
            exit 1
        }
    } else {
        Write-Output "Node.js not detected; auto-installing (non-interactive mode)."
    }

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Output "Installing Node.js via winget..."
        Start-Process winget -ArgumentList 'install','-e','--id','OpenJS.NodeJS' -Wait -NoNewWindow
    } else {
        Write-Output "winget not available. Please install Node.js from https://nodejs.org/ and re-run."
        exit 1
    }

    Reload-PathFromRegistry

    if (-not (Check-NodeInstalled)) {
        if (-not $ContinueAfterNodeInstall) {
            $psExe = Get-PowerShellExe
            if ($psExe) {
                Write-Output "Reopening PowerShell to pick up Node.js on PATH..."
                Start-Process $psExe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"$PSCommandPath",'-Force','-ContinueAfterNodeInstall' -Wait
                exit $LASTEXITCODE
            } else {
                Write-Output "Cannot locate PowerShell to relaunch. Please open a new shell and re-run this script."
                exit 1
            }
        } else {
            Write-Output "Node.js still not available after install. Please open a new shell and re-run."
            exit 1
        }
    } else {
        Write-Output "Node.js detected after installation. Continuing..."
    }
} else {
    Write-Output "Node.js detected. Skipping Node installation."
}

if (-not $Force) {
    Write-Output "Install dependencies and build Azul now? (Y/N)"
    $response = Read-Host
    if ($response -ne 'Y' -and $response -ne 'y') {
        Write-Output "Installation aborted by user."
        exit 0
    }
} else {
    Write-Output "Proceeding with dependency install and build (non-interactive mode)."
}

Push-Location $repoRoot
try {
    Write-Output "Installing dependencies (npm i)..."
    npm i

    Write-Output "Building Azul (npm run build)..."
    npm run build

    Write-Output "Installing Azul globally (npm install -g .)..."
    npm install -g .
} catch {
    Write-Error "Installation failed: $_"
    exit 1
} finally {
    Pop-Location
}

Write-Output "Azul installation complete!"
Write-Output "Try running 'azul --help' to get started."
Write-Output "If you want to update Azul later, pull the latest version and run this install script again."
Read-Host "(Press Enter to exit)"