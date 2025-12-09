Write-Output "=== Azul: Easy Install Script ==="

Write-Output "Are you sure you want to install Azul? (Y/N)"
$response = Read-Host
if ($response -ne 'Y' -and $response -ne 'y') {
    Write-Output "Installation aborted by user."
    exit
}

Write-Output "Have you already installed NPM? (Y/N)"
$response = Read-Host
if ($response -ne 'Y' -and $response -ne 'y') {
    Write-Output "Installing NPM..."
    Start-Process .\install-resources\install-npm.bat -Wait -NoNewWindow
}

Write-Output "Installing Azul dependencies..."
Start-Process .\install-resources\install-azul-dependencies.bat -Wait -NoNewWindow

Write-Output "Building & Installing Azul..."
Start-Process .\install-resources\install-azul.bat -Wait -NoNewWindow

Write-Output "Azul installation complete!"
Write-Output "Try running 'azul --help' to get started."