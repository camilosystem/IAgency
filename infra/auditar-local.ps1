# auditar-local.ps1 — Qué tienes sin empujar en esta máquina.
#
# La auditoría del servidor no ve lo que vive solo en tu disco. Este script recorre
# los repositorios del WMS que tengas localmente y reporta las tres formas de perder
# trabajo: cambios sin commitear, commits sin empujar, y stashes olvidados.
#
# Uso, desde PowerShell, apuntando a la carpeta que contiene los repos:
#     .\auditar-local.ps1 -Raiz "C:\Users\Financial advisor\Pictures\WMS_DINAS"
#
# En el Mac usa auditar-local.sh, que hace lo mismo.

param(
    [Parameter(Mandatory = $true)]
    [string]$Raiz,
    [string]$Salida = "auditoria-local-$(Get-Date -Format 'yyyyMMdd-HHmmss').md"
)

if (-not (Test-Path $Raiz)) {
    Write-Error "No existe la carpeta: $Raiz"
    exit 1
}

$lineas = @()
$lineas += "# Auditoría local — $env:COMPUTERNAME"
$lineas += ""
$lineas += "Generada: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lineas += "Raíz: ``$Raiz``"
$lineas += ""
$lineas += "> Esto es lo que existe SOLO en esta máquina. Nada de lo que aparezca aquí"
$lineas += "> es visible para los agentes hasta que se empuje a GitHub."
$lineas += ""

$hallazgos = 0

Get-ChildItem -Path $Raiz -Directory | ForEach-Object {
    $repo = $_.FullName
    if (-not (Test-Path (Join-Path $repo ".git"))) { return }

    $nombre = $_.Name
    Write-Host "Revisando $nombre..."

    Push-Location $repo

    $rama     = (git rev-parse --abbrev-ref HEAD 2>$null)
    $sucio    = (git status --porcelain 2>$null)
    $sinPush  = (git log --oneline "@{u}..HEAD" 2>$null)
    $stashes  = (git stash list 2>$null)
    $subMal   = ""
    if (Test-Path (Join-Path $repo "contracts")) {
        $subMal = (git -C contracts status --porcelain 2>$null)
        $subTag = (git -C contracts describe --tags --exact-match 2>$null)
    }

    $tieneAlgo = $sucio -or $sinPush -or $stashes -or $subMal
    if ($tieneAlgo) { $script:hallazgos++ }

    $lineas += "## $nombre"
    $lineas += ""
    $lineas += "Rama actual: ``$rama``"
    $lineas += ""

    if ($sucio) {
        $lineas += "### Cambios sin commitear"
        $lineas += ""
        $lineas += '```'
        $lineas += $sucio
        $lineas += '```'
        $lineas += ""
    }

    if ($sinPush) {
        $lineas += "### Commits sin empujar"
        $lineas += ""
        $lineas += '```'
        $lineas += $sinPush
        $lineas += '```'
        $lineas += ""
    }

    if ($stashes) {
        $lineas += "### Stashes guardados"
        $lineas += ""
        $lineas += '```'
        $lineas += $stashes
        $lineas += '```'
        $lineas += ""
        $lineas += "Cada stash necesita un destino: se aplica, o se descarta anotando qué había."
        $lineas += ""
    }

    if ($subMal) {
        $lineas += "### AVISO — el submódulo contracts tiene cambios locales"
        $lineas += ""
        $lineas += '```'
        $lineas += $subMal
        $lineas += '```'
        $lineas += ""
        $lineas += "Esto suele significar que alguien copió un openapi.yaml descargado dentro"
        $lineas += "del repositorio consumidor en vez de mover el puntero del submódulo. Ya"
        $lineas += "pasó tres veces en este proyecto. El flujo correcto es publicar en"
        $lineas += "dinas-wms-contracts y mover el puntero, nunca copiar el archivo."
        $lineas += ""
    } elseif ($subTag) {
        $lineas += "Submódulo ``contracts`` en el tag ``$subTag`` y limpio."
        $lineas += ""
    }

    if (-not $tieneAlgo) {
        $lineas += "Sin hallazgos: todo commiteado y empujado."
        $lineas += ""
    }

    Pop-Location
}

$lineas += "---"
$lineas += ""
if ($hallazgos -eq 0) {
    $lineas += "**Ningún repositorio tiene trabajo sin empujar.** Esta máquina está al día."
} else {
    $lineas += "**$hallazgos repositorios tienen algo que solo existe aquí.** Cada hallazgo"
    $lineas += "necesita una decisión escrita: se integra, se descarta, o se queda con motivo."
}

$lineas | Out-File -FilePath $Salida -Encoding utf8
Write-Host ""
Write-Host "Informe escrito en: $Salida"
Write-Host "Repositorios con hallazgos: $hallazgos"
