@echo off
rem WowSim - run WoW addons in a browser sandbox. Close this window to stop (saves SavedVariables).
cd /d "%~dp0"
"%USERPROFILE%\miniconda3\python.exe" -E server.py %*
pause
