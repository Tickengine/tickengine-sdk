@echo off
echo ===================================================
echo Running Rust SDK (Calling install first)...
echo ===================================================

call install.cmd
if errorlevel 1 goto failed

:: Find Visual Studio Installation Path and Activate Developer Environment
set VS_DIR=
set VSWHERE="%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist %VSWHERE% goto vsdevcmd_done

for /f "usebackq tokens=*" %%i in (`%VSWHERE% -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set VS_DIR=%%i

if "%VS_DIR%"=="" goto vsdevcmd_done
if not exist "%VS_DIR%\Common7\Tools\VsDevCmd.bat" goto vsdevcmd_done

echo Activating Visual Studio Developer Environment...
call "%VS_DIR%\Common7\Tools\VsDevCmd.bat" -arch=amd64

:vsdevcmd_done

:: Check if cargo is in PATH
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
