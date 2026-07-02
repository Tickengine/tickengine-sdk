@echo off
echo ===================================================
echo Installing Python and SDK Dependencies...
echo ===================================================

:: Check if python is already installed
where python >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo Python not found. Installing Python...
    winget install --id Python.Python.3 --silent --show-progress --accept-package-agreements --accept-source-agreements
    echo.
    echo Python has been installed. Please restart your terminal and run this script again to install dependencies.
    pause
    exit /b
) else (
    echo Python is already installed.
)

echo Installing dependencies...
python -m pip install --upgrade pip
pip install websockets msgpack
echo.
echo Dependencies installed successfully!
pause
