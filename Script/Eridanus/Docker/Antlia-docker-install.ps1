$IMAGE = "zhende1113/antlia"
$CONTAINER_NAME = "antlia"
$HOST_DIR = "$PWD\Antlia-Docker"
$CONTAINER_DIR = "/app/bot"

Write-Output "=== Antlia Docker 部署脚本 (PowerShell) ==="

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Output "[错误] 未检测到 Docker，请先安装 Docker Desktop"
    exit
}

if (-not (Test-Path $HOST_DIR)) {
    New-Item -ItemType Directory -Path $HOST_DIR | Out-Null
}

docker pull $IMAGE

$manageScript = @"
param(
    [string]`$action
)

`$IMAGE = "zhende1113/antlia"
`$CONTAINER_NAME = "antlia"
`$HOST_DIR = "$PWD\Antlia-Docker"
`$CONTAINER_DIR = "/app/bot"

switch (`$action) {
    "start" { docker run -dit --name `$CONTAINER_NAME -v "`$HOST_DIR:`$CONTAINER_DIR" `$IMAGE }
    "stop"  { docker stop `$CONTAINER_NAME }
    "exec"  { docker exec -it `$CONTAINER_NAME powershell }
    "run"   { docker exec -it `$CONTAINER_NAME bash /app/bot/start.sh }
    default { Write-Output "用法: .\Antlia-docker.ps1 <start|stop|exec|run>" }
}
"@

Set-Content -Path "Antlia-docker.ps1" -Value $manageScript -Encoding UTF8
Write-Output "[完成] 部署成功，使用 .\Antlia-docker.ps1 管理容器"
