@echo off
cd /d "%~dp0..\..\.."
py -3 -m tools.content.pipeline tick
