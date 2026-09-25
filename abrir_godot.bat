@echo off
cd /d "%~dp0."
set "GODOT=D:\proyectos luis\descarggas\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
if exist "%GODOT%" (
  start "" "%GODOT%" --path "%~dp0."
) else (
  where godot >nul 2>nul
  if %errorlevel%==0 (
    start "" godot --path "%~dp0."
  ) else (
    echo No se encontro Godot ni en "%GODOT%" ni en el PATH.
    echo Instalalo de https://godotengine.org y luego abre project.godot
    pause
  )
)
