@echo off
echo ===================================================
echo Checking Dependencies...
echo ===================================================

:: Check if python is already installed
where python >nul 2>nul
if errorlevel 1 goto needs_python

:: Check if dependencies are already installed
python -c "import websockets, msgpack" >nul 2>nul
if not errorlevel 1 goto all_installed

echo Python is installed but dependencies are missing.
goto install_deps

:all_installed
echo All dependencies (Python and packages) are already installed.
exit /b 0

:needs_python
echo Python not found. Installing Python...
winget install --id Python.Python.3 --silent --accept-package-agreements --accept-source-agreements
if errorlevel 1 goto python_install_failed

echo.
echo Python has been installed. Please restart your terminal and run this script again to install dependencies.
pause
exit /b 0

:python_install_failed
echo Failed to install Python via winget.
pause
exit /b 1

:install_deps
echo Installing dependencies...
python -m pip install --upgrade pip
pip install websockets msgpack
echo.
echo Dependencies installed successfully!
pause
exit /b 0
