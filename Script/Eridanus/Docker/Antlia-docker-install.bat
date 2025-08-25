@echo off
set IMAGE=zhende1113/antlia
set CONTAINER_NAME=antlia
set HOST_DIR=%cd%\Antlia-Docker
set CONTAINER_DIR=/app/bot

echo === Antlia Docker 部署脚本 (Windows) ===

:: 检查 docker
docker --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [错误] 未检测到 Docker，请先安装 Docker Desktop
    pause
    exit /b
)

if not exist "%HOST_DIR%" mkdir "%HOST_DIR%"

echo [信息] 拉取镜像 %IMAGE%...
docker pull %IMAGE%

echo [信息] 生成管理脚本 Antlia-docker.bat
(
echo @echo off
echo set IMAGE=zhende1113/antlia
echo set CONTAINER_NAME=antlia
echo set HOST_DIR=%%cd%%\Antlia-Docker
echo set CONTAINER_DIR=/app/bot
echo.
echo if "%%1"=="start" (
echo    docker run -dit --name %%CONTAINER_NAME%% -v "%%HOST_DIR%%:%%CONTAINER_DIR%%" %%IMAGE%%
echo ) else if "%%1"=="stop" (
echo    docker stop %%CONTAINER_NAME%%
echo ) else if "%%1"=="exec" (
echo    docker exec -it %%CONTAINER_NAME%% cmd
echo ) else if "%%1"=="run" (
echo    docker exec -it %%CONTAINER_NAME%% bash /app/start.sh
echo ) else (
echo    echo 用法: Antlia-docker.bat ^<start^|stop^|exec^|run^>
echo )
) > Antlia-docker.bat

echo [完成] 部署成功，使用 Antlia-docker.bat 管理容器
pause
