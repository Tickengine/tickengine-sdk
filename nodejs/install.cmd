@echo off
echo ===================================================
echo Checking Dependencies...
echo ===================================================

:: Check if node is already installed
where node >nul 2>nul
if errorlevel 1 goto needs_node

:: Check if node_modules dependencies are already installed
if exist node_modules\ws if exist node_modules\@msgpack\msgpack if exist node_modules\ts-node goto all_installed

echo Node.js is installed but dependencies are missing.
goto install_deps

:all_installed
echo All dependencies (Node.js and packages) are already installed.
exit /b 0

:needs_node
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

:install_deps
echo Installing dependencies...
npm install ws @msgpack/msgpack
npm install --save-dev @types/ws typescript ts-node
echo.
echo Dependencies installed successfully!
pause
exit /b 0
