@echo off
echo ===================================================
echo Checking Dependencies...
echo ===================================================

:: Check if cargo/rustc is already installed
where cargo >nul 2>nul
if errorlevel 1 goto needs_rust

:: Check if C++ Build Tools and Windows SDK are already installed
set HAS_MSVC=0
if exist "%ProgramFiles%\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC" set HAS_MSVC=1
if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC" set HAS_MSVC=1
if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Professional\VC\Tools\MSVC" set HAS_MSVC=1
if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Enterprise\VC\Tools\MSVC" set HAS_MSVC=1
if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC" set HAS_MSVC=1
if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC" set HAS_MSVC=1
if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\Professional\VC\Tools\MSVC" set HAS_MSVC=1
if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\Enterprise\VC\Tools\MSVC" set HAS_MSVC=1

set HAS_SDK=0
if exist "%ProgramFiles%\Windows Kits\10\Lib" set HAS_SDK=1
if exist "%ProgramFiles(x86)%\Windows Kits\10\Lib" set HAS_SDK=1

if %HAS_MSVC% equ 0 goto needs_cpp
if %HAS_SDK% equ 0 goto needs_cpp
goto all_installed

:all_installed
echo All dependencies (Rust, C++ Build Tools, and Windows SDK) are already installed.
exit /b 0

:needs_rust
echo Installing Rust (rustup)...
curl -sLO https://win.rustup.rs/x86_64/rustup-init.exe
if errorlevel 1 goto rust_download_failed

rustup-init.exe -y --default-toolchain stable
del rustup-init.exe
echo Rust has been installed. Please restart your terminal/PC to reload PATH.
pause
exit /b 0

:rust_download_failed
echo Failed to download rustup-init.exe. Please install Rust manually.
pause
exit /b 1

:needs_cpp
echo Installing/Updating Visual Studio Build Tools with C++ workload and Windows SDK...

:: Find installer tools
set VSWHERE_EXE=
for /f "usebackq tokens=*" %%i in (`powershell -NoProfile -Command "Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'"`) do set VSWHERE_EXE=%%i
set VS_INSTALLER=
for /f "usebackq tokens=*" %%i in (`powershell -NoProfile -Command "Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vs_installer.exe'"`) do set VS_INSTALLER=%%i

if not exist "%VS_INSTALLER%" goto no_vs_installer

echo Existing Visual Studio installation detected.
echo Modifying installation to add C++ Workload and Windows SDK...
set VS_DIR=
if exist "%VSWHERE_EXE%" (
    for /f "usebackq tokens=*" %%i in (`powershell -NoProfile -Command "& '%VSWHERE_EXE%' -latest -products * -property installationPath"`) do set VS_DIR=%%i
)
if "%VS_DIR%"=="" goto no_vs_dir

echo Target directory: "%VS_DIR%"
powershell -NoProfile -Command "Start-Process -FilePath '%VS_INSTALLER%' -ArgumentList 'modify --installPath \"%VS_DIR%\" --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive --norestart' -Verb RunAs -Wait"
goto cpp_install_done

:no_vs_dir
:no_vs_installer
winget install --id Microsoft.VisualStudio.2022.BuildTools --silent --accept-package-agreements --accept-source-agreements --override "--passive --locale en-US --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
if not errorlevel 1 goto cpp_install_done

echo Winget install failed. Trying standalone installer...
curl -sLO https://aka.ms/vs/17/release/vs_buildtools.exe
if errorlevel 1 goto download_failed

vs_buildtools.exe --quiet --wait --norestart --nocache --installPath "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools" --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended
del vs_buildtools.exe
goto cpp_install_done

:download_failed
echo Failed to download Visual Studio Build Tools.
pause
exit /b 1

:cpp_install_done
echo.
echo C++ Build Tools/Windows SDK installed successfully. Please restart your terminal/PC to apply PATH changes.
pause
exit /b 0
