param(
    [string]$PhpPath = 'C:\laragon\bin\php\php-8.3.30-Win32-vs16-x64\php.exe'
)

Set-Location -LiteralPath (Join-Path $PSScriptRoot 'public')
& $PhpPath -d extension=pdo_pgsql -d extension=mongodb -S 127.0.0.1:8000 (Join-Path $PSScriptRoot 'vendor\laravel\framework\src\Illuminate\Foundation\resources\server.php')
