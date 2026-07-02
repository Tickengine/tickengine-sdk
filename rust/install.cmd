@echo off
echo ===================================================
echo Checking Dependencies...
echo ===================================================

:: Check if cargo/rustc is already installed
where cargo >nul 2>nul
if errorlevel 1 goto needs_rust

:: Check if C++ Build Tools are already installed
set VSWHERE="%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if exist %VSWHERE% (
    %VSWHERE% -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 >nul 2>nul
    if not errorlevel 1 goto all_installed
)
if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC" goto all_installed
if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC" goto all_installed
if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\Professional\VC\Tools\MSVC" goto all_installed
if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\Enterprise\VC\Tools\MSVC" goto all_installed

goto needs_cpp

:all_installed
echo All dependencies (Rust and C++ Build Tools) are already installed.
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
echo Installing Visual Studio Build Tools (C++ Workload)...
winget install --id Microsoft.VisualStudio.2022.BuildTools --silent --accept-package-agreements --accept-source-agreements --override "--passive --locale en-US --add Microsoft.VisualStudio.Workload.VCTools"
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
echo C++ Build Tools installed successfully. Please restart your terminal/PC to apply PATH changes.
pause
exit /b 0
