@echo off
echo ===================================================
echo Installing Node.js and SDK Dependencies...
echo ===================================================

:: Check if node is already installed
where node >nul 2>nul
if errorlevel 1 (
    echo Node.js not found. Installing Node.js LTS...
    winget install --id OpenJS.NodeJS --silent --accept-package-agreements --accept-source-agreements
    if errorlevel 1 (
        echo Failed to install Node.js via winget.
        pause
        exit /b 1
    )
    echo.
    echo Node.js has been installed. Please restart your terminal and run this script again to install dependencies.
    pause
    exit /b
) else (
    echo Node.js is already installed.
)

echo Installing dependencies...
npm install ws @msgpack/msgpack
npm install --save-dev @types/ws typescript ts-node

echo.
echo Dependencies installed successfully!
pause
