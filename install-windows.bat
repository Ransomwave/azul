@echo off

echo Azul: Install Script

echo Press any key to continue...
pause > nul

echo Installing Node.js...
winget install -e --id OpenJS.NodeJS

echo Installing dependencies...
npm i .

echo Installing 'Azul' command globally...
npm install -g
