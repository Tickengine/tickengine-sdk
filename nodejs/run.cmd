@echo off
echo ===================================================
echo Running Node.js SDK (Calling install first)...
echo ===================================================

call install.cmd
if errorlevel 1 goto failed

:: Check if node is in PATH
where node >nul 2>nul
if errorlevel 1 goto no_node

echo.
echo Running Node.js SDK (tickbridge.ts)...
npx ts-node tickbridge.ts
if errorlevel 1 goto failed
goto end

:no_node
echo.
echo Node.js is not in the current session's PATH.
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
