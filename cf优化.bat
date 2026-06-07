@echo off
chcp 936 >nul
setlocal EnableDelayedExpansion

:: ==============================
:: 配置区
:: ==============================
set HOSTS_FILE=%SystemRoot%\System32\drivers\etc\hosts
set IP=104.21.17.63
set DOMAIN=dst.mx666.icu
set ENTRY=%IP% %DOMAIN%

:: ==============================
:: 管理员权限检测
:: ==============================
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo 请求管理员权限...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo ============================================
echo 正在优化 hosts 文件
echo ============================================

:: ==============================
:: 备份 hosts
:: ==============================
echo 正在备份 hosts 文件...
copy "%HOSTS_FILE%" "%HOSTS_FILE%.backup_%date:~0,4%%date:~5,2%%date:~8,2%_%time:~0,2%%time:~3,2%%time:~6,2%" >nul
if %errorLevel% equ 0 (
    echo [√] hosts 文件已备份
) else (
    echo [!] 备份失败，继续执行...
)

:: ==============================
:: 关键新增：删除已存在的 dst.mx666.icu
:: ==============================
echo 正在检测并清理旧记录...
findstr /C:"%DOMAIN%" "%HOSTS_FILE%" >nul 2>&1
if %errorLevel% equ 0 (
    echo 发现旧记录，正在删除...
    findstr /V /C:"%DOMAIN%" "%HOSTS_FILE%" > "%HOSTS_FILE%.tmp"
    move /Y "%HOSTS_FILE%.tmp" "%HOSTS_FILE%" >nul
    echo [√] 已删除旧的 %DOMAIN% 记录
) else (
    echo [√] 未发现旧记录
)

:: ==============================
:: 添加新的 hosts 记录
:: ==============================
echo 正在写入新记录...
echo. >> "%HOSTS_FILE%"
echo # Added by cf优化.bat on %date% %time% >> "%HOSTS_FILE%"
echo %ENTRY% >> "%HOSTS_FILE%"

if %errorLevel% equ 0 (
    echo [√] 成功添加 hosts 记录
    echo %ENTRY%

    echo 正在刷新 DNS 缓存...
    ipconfig /flushdns >nul
    if %errorLevel% equ 0 (
        echo [√] DNS 缓存已刷新
    ) else (
        echo [!] DNS 刷新失败
    )
) else (
    echo [×] 添加 hosts 记录失败
)

:: ==============================
:: 结束
:: ==============================
echo ============================================
echo 操作完成
echo ============================================
pause