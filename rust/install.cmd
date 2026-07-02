@echo off
echo ===================================================
echo Installing Rust and C++ Build Tools for Windows...
echo ===================================================

:: Check if cargo/rustc is already installed
where cargo >nul 2>nul
if %ERRORLEVEL% equ 0 (
    echo Rust is already installed.
) else (
    echo Installing Rust (rustup)...
    curl -sLO https://win.rustup.rs/x86_64/rustup-init.exe
    rustup-init.exe -y --default-toolchain stable
    del rustup-init.exe
    echo Rust has been installed. Please restart your terminal to reload PATH.
)

:: Install Build Tools if needed
echo Installing Visual Studio Build Tools (C++ Workload)...
winget install --id Microsoft.VisualStudio.2022.BuildTools --silent --show-progress --accept-package-agreements --accept-source-agreements --override "--passive --locale en-US --add Microsoft.VisualStudio.Workload.VCTools"
if %ERRORLEVEL% neq 0 (
    echo Winget install failed. Trying standalone installer...
    curl -sLO https://aka.ms/vs/17/release/vs_buildtools.exe
    vs_buildtools.exe --quiet --wait --norestart --nocache --installPath "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools" --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended
    del vs_buildtools.exe
)

echo.
echo Installation completed. Please restart your terminal/PC to apply PATH changes.
pause
