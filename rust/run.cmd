@echo off
echo ===================================================
echo Running Rust SDK (Calling install first)...
echo ===================================================

call install.cmd
if errorlevel 1 goto failed

:: Check if cargo is in PATH (in case it was just installed and PATH wasn't reloaded)
where cargo >nul 2>nul
if errorlevel 1 goto no_cargo

echo.
echo Running Rust SDK in release mode...
cargo run --release
if errorlevel 1 goto failed
goto end

:no_cargo
echo.
echo Rust (cargo) is not in the current session's PATH.
echo Please restart your terminal/PC and run this script again.
pause
exit /b 1

:failed
echo.
echo Execution failed!
pause
exit /b 1

:end
pause
