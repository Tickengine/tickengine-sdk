@echo off
echo ===================================================
echo Checking Dependencies...
echo ===================================================

:: Auto-detect Python install paths if not in PATH
python -c "import sys" >nul 2>nul
if errorlevel 1 (
    for /d %%d in ("%LocalAppData%\Programs\Python\Python*") do (
        if exist "%%d\python.exe" set "PATH=%%d;%%d\Scripts;%PATH%"
    )
    for /d %%d in ("%ProgramFiles%\Python\Python*") do (
        if exist "%%d\python.exe" set "PATH=%%d;%%d\Scripts;%PATH%"
    )
    for /d %%d in ("%ProgramFiles%\Python*") do (
        if exist "%%d\python.exe" set "PATH=%%d;%%d\Scripts;%PATH%"
    )
)

:: Check if python is already installed and working
python -c "import sys" >nul 2>nul
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
winget install --id Python.Python.3.12 --silent --accept-package-agreements --accept-source-agreements
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
python -m pip install websockets msgpack
echo.
echo Dependencies installed successfully!
pause
exit /b 0
