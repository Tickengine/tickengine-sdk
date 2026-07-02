@echo off
echo ===================================================
echo Installing Node.js and SDK Dependencies...
echo ===================================================

:: Check if node is already installed
where node >nul 2>nul
if not errorlevel 1 goto node_installed

echo Node.js not found. Installing Node.js LTS...
winget install --id OpenJS.NodeJS --silent --accept-package-agreements --accept-source-agreements
if errorlevel 1 goto node_install_failed

echo.
echo Node.js has been installed. Please restart your terminal and run this script again to install dependencies.
pause
exit /b 0

:node_install_failed
echo Failed to install Node.js via winget.
pause
exit /b 1

:node_installed
echo Node.js is already installed.

echo Installing dependencies...
npm install ws @msgpack/msgpack
npm install --save-dev @types/ws

echo.
echo Dependencies installed successfully!
pause
