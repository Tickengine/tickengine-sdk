@echo off
echo ===================================================
echo Running Rust SDK (Calling install first)...
echo ===================================================

call install.cmd
if errorlevel 1 goto failed

:: Find vswhere.exe path safely using PowerShell to bypass cmd parenthesis/quoting bugs
set VSWHERE_EXE=
for /f "usebackq tokens=*" %%i in (`powershell -NoProfile -Command "Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'"`) do set VSWHERE_EXE=%%i

if "%VSWHERE_EXE%"=="" goto vsdevcmd_done
if not exist "%VSWHERE_EXE%" goto vsdevcmd_done

:: Find Visual Studio Installation Path using vswhere
set VS_DIR=
for /f "usebackq tokens=*" %%i in (`powershell -NoProfile -Command "& '%VSWHERE_EXE%' -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath"`) do set VS_DIR=%%i

if "%VS_DIR%"=="" goto vsdevcmd_done
if not exist "%VS_DIR%\Common7\Tools\VsDevCmd.bat" goto vsdevcmd_done

echo Activating Visual Studio Developer Environment...
echo Detected VS: %VS_DIR%
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
