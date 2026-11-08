@echo off
rem Builds pc-windows.exe and its tests into pc\build (Release), then runs the unit tests.
rem   pc\build.cmd            configure if needed, build, test
rem   pc\build.cmd clean      start again from nothing
setlocal
set HERE=%~dp0
if "%1"=="clean" rmdir /s /q "%HERE%build" 2>nul

rem A Visual Studio with C++ and its CMake (2022 or later), found by vswhere, which every install has.
set VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe
for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 Microsoft.VisualStudio.Component.VC.CMake.Project -property installationPath`) do set VSDIR=%%i
if not defined VSDIR for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set VSDIR=%%i
if not defined VSDIR (
  echo No Visual Studio with C++ found. Install Visual Studio 2022 or later with "Desktop development with C++".
  exit /b 1
)
call "%VSDIR%\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64 -no_logo || exit /b 1
rem VsDevCmd adds Visual Studio's own CMake and Ninja only when it finds vswhere on the PATH; add them if it did not.
where cmake >nul 2>nul || set "PATH=%VSDIR%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin;%PATH%"
where ninja >nul 2>nul || set "PATH=%VSDIR%\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja;%PATH%"

if not exist "%HERE%build\build.ninja" (
  cmake -S "%HERE%." -B "%HERE%build" -G Ninja -DCMAKE_BUILD_TYPE=Release || exit /b 1
)
cmake --build "%HERE%build" || exit /b 1
ctest --test-dir "%HERE%build" --output-on-failure || exit /b 1
echo.
echo Built: %HERE%build\pc-windows.exe
