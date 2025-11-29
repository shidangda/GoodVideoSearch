@echo off
REM ============================================================================
REM 数据库迁移脚本 - Windows 版本
REM 从本地 Windows MySQL 迁移到云服务器
REM 
REM 使用方法：
REM   1. 编辑脚本，配置服务器信息
REM   2. 双击运行或在 CMD 中执行
REM ============================================================================

setlocal enabledelayedexpansion

REM ============================================================================
REM 配置区域 - 请根据实际情况修改
REM ============================================================================

REM 本地数据库配置
set LOCAL_DB_USER=goodvideo_user
set LOCAL_DB_NAME=goodvideo_archive
set LOCAL_DB_HOST=127.0.0.1
set LOCAL_DB_PORT=3306

REM 服务器信息
set REMOTE_USER=ubuntu
set REMOTE_HOST=106.52.243.103
set REMOTE_DB_USER=goodvideo_user
set REMOTE_DB_NAME=goodvideo_archive

REM 迁移选项
set BACKUP_FILE=backup_%date:~0,4%%date:~5,2%%date:~8,2%_%time:~0,2%%time:~3,2%%time:~6,2%.sql
set BACKUP_FILE=%BACKUP_FILE: =0%
set USE_COMPRESSION=false
set MIGRATE_COVERS=true

REM ============================================================================
REM 主流程
REM ============================================================================

echo.
echo ==========================================
echo 数据库迁移工具 - Windows 本地 ^> 云服务器
echo ==========================================
echo.

REM 检查 mysqldump 是否可用
where mysqldump >nul 2>&1
if %errorlevel% neq 0 (
    echo [错误] 未找到 mysqldump 命令
    echo 请安装 MySQL 客户端工具，或将其添加到 PATH 环境变量
    echo 下载地址: https://dev.mysql.com/downloads/mysql/
    pause
    exit /b 1
)

REM 检查 scp 是否可用（需要安装 OpenSSH 或使用 WinSCP）
where scp >nul 2>&1
if %errorlevel% neq 0 (
    echo [警告] 未找到 scp 命令
    echo 请安装 OpenSSH 客户端（Windows 10 1809+ 自带）
    echo 或使用 WinSCP 手动上传文件
    echo.
    set USE_SCP=false
) else (
    set USE_SCP=true
)

REM 1. 检查本地数据库连接
echo [信息] 检查本地数据库连接...
mysql -u %LOCAL_DB_USER% -h %LOCAL_DB_HOST% -P %LOCAL_DB_PORT% -e "USE %LOCAL_DB_NAME%;" 2>nul
if %errorlevel% neq 0 (
    echo [错误] 无法连接本地数据库，请检查配置
    pause
    exit /b 1
)
echo [成功] 本地数据库连接正常

REM 2. 导出数据库
echo.
echo [信息] 正在导出数据库...
echo 请输入本地数据库密码:
mysqldump -u %LOCAL_DB_USER% -p ^
    -h %LOCAL_DB_HOST% ^
    -P %LOCAL_DB_PORT% ^
    --single-transaction ^
    --routines ^
    --triggers ^
    --add-drop-table ^
    %LOCAL_DB_NAME% > %BACKUP_FILE%

if %errorlevel% neq 0 (
    echo [错误] 数据库导出失败
    pause
    exit /b 1
)
echo [成功] 数据库已导出: %BACKUP_FILE%

REM 3. 上传到服务器
if "%USE_SCP%"=="true" (
    echo.
    echo [信息] 正在上传到服务器...
    echo 请输入服务器密码:
    scp %BACKUP_FILE% %REMOTE_USER%@%REMOTE_HOST%:~/
    if %errorlevel% neq 0 (
        echo [错误] 上传失败
        pause
        exit /b 1
    )
    echo [成功] 文件已上传到服务器
) else (
    echo.
    echo [信息] 请手动上传文件到服务器:
    echo   文件: %BACKUP_FILE%
    echo   目标: %REMOTE_USER%@%REMOTE_HOST%:~/GoodVideoSearch/
    echo.
    echo 可以使用以下工具:
    echo   - WinSCP: https://winscp.net/
    echo   - FileZilla: https://filezilla-project.org/
    echo.
    pause
)

REM 4. 在服务器上导入数据库
echo.
echo [信息] 正在导入到服务器数据库...
echo 请输入服务器密码和数据库密码:
ssh %REMOTE_USER%@%REMOTE_HOST% "mysql -u %REMOTE_DB_USER% -p %REMOTE_DB_NAME% < ~/%BACKUP_FILE%"

if %errorlevel% neq 0 (
    echo [警告] 导入可能失败，请手动检查
) else (
    echo [成功] 数据库已导入到服务器
)

REM 5. 迁移封面图片（如果启用）
if "%MIGRATE_COVERS%"=="true" (
    if exist "data\covers" (
        echo.
        echo [信息] 正在迁移封面图片...
        
        REM 打包封面目录（需要安装 7-Zip 或 WinRAR）
        where 7z >nul 2>&1
        if %errorlevel% equ 0 (
            7z a -tzip covers.zip data\covers\ >nul
            if "%USE_SCP%"=="true" (
                scp covers.zip %REMOTE_USER%@%REMOTE_HOST%:~/
                ssh %REMOTE_USER%@%REMOTE_HOST% "cd ~/GoodVideoSearch && unzip -o ~/covers.zip && rm ~/covers.zip"
                del covers.zip
            ) else (
                echo [信息] 请手动上传 covers.zip 到服务器
            )
        ) else (
            echo [警告] 未找到 7-Zip，跳过封面图片压缩
            echo 请手动上传 data\covers 目录
        )
    )
)

REM 6. 清理临时文件
echo.
echo [信息] 清理临时文件...
del %BACKUP_FILE% 2>nul

echo.
echo [成功] ==========================================
echo [成功] 迁移完成！
echo [成功] ==========================================
echo.
echo [信息] 下一步：
echo   1. 在服务器上重启应用: pm2 restart goodvideosearch
echo   2. 检查应用日志: pm2 logs goodvideosearch
echo   3. 访问应用验证功能
echo.
pause





