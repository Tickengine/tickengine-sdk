@echo off
echo ===================================================
echo Installing Rust and C++ Build Tools for Windows...
echo ===================================================

:: Check if cargo/rustc is already installed
where cargo >nul 2>nul
if not errorlevel 1 (
    echo Rust is already installed.
) else (
    echo Installing Rust (rustup)...
    curl -sLO https://win.rustup.rs/x86_64/rustup-init.exe
    if errorlevel 1 (
        echo Failed to download rustup-init.exe
        pause
        exit /b 1
    )
    rustup-init.exe -y --default-toolchain stable
    del rustup-init.exe
    echo Rust has been installed. Please restart your terminal to reload PATH.
)

:: Install Build Tools if needed
echo Installing Visual Studio Build Tools (C++ Workload)...
winget install --id Microsoft.VisualStudio.2022.BuildTools --silent --accept-package-agreements --accept-source-agreements --override "--passive --locale en-US --add Microsoft.VisualStudio.Workload.VCTools"
if errorlevel 1 (
    echo Winget install failed. Trying standalone installer...
    curl -sLO https://aka.ms/vs/17/release/vs_buildtools.exe
    if not errorlevel 1 (
        vs_buildtools.exe --quiet --wait --norestart --nocache --installPath "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools" --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended
        del vs_buildtools.exe
    ) else (
        echo Failed to download Visual Studio Build Tools.
    )
)

echo.
echo Installation completed. Please restart your terminal/PC to apply PATH changes.
pause
