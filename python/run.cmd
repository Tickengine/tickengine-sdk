@echo off
echo ===================================================
echo Running Python SDK (Calling install first)...
echo ===================================================

call install.cmd
if errorlevel 1 goto failed

:: Check if python is in PATH
where python >nul 2>nul
if errorlevel 1 (
    echo.
    echo Python is not in the current session's PATH.
    echo Please restart your terminal and run this script again.
    pause
    exit /b 1
)

echo.
echo Running Python SDK (tickbridge.py)...
python tickbridge.py
if errorlevel 1 goto failed
goto end

:failed
echo.
echo Execution failed!
pause
exit /b 1

:end
pause
