@echo off
echo ===================================================
echo Running Python SDK (Calling install first)...
echo ===================================================

call install.cmd
if errorlevel 1 goto failed

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

:: Check if python is in PATH and working
python -c "import sys" >nul 2>nul
if errorlevel 1 goto no_python

echo.
echo Running Python SDK (tickbridge.py)...
if not exist config.json if exist ..\config.json (
    echo Using shared configuration file from parent directory: ..\config.json
    set TICKENGINE_CONFIG_FILE=..\config.json
)
set PYTHONUNBUFFERED=1
python tickbridge.py
if errorlevel 1 goto failed
goto end

:no_python
echo.
echo Python is not in the current session's PATH.
echo Please restart your terminal and run this script again.
pause
exit /b 1

:failed
echo.
echo Execution failed!
pause
exit /b 1

:end
pause
