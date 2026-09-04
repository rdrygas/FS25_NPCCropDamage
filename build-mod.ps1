# build-mod.ps1
#
# Uruchamiaj z katalogu głównego moda:
#   .\build-mod.ps1
#
# Przykład:
#   C:\Projects\FS25_AutoPipeLight
#   -> FS25_AutoPipeLight.zip
#   -> Documents\My Games\FarmingSimulator2025\mods

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Konfiguracja
# ---------------------------------------------------------------------------

# $ModsDirectory = Join-Path $env:USERPROFILE `
#     "Documents\My Games\FarmingSimulator2025\mods"

$ModsDirectory = "D:\Users\Robert\Documents\My Games\FarmingSimulator2025\mods"

$AllowedExtensions = @(
    ".lua",
    ".xml",
    ".md",
    ".dds"
)

# ---------------------------------------------------------------------------
# Ustalenie katalogu projektu i nazwy moda
# ---------------------------------------------------------------------------

$ProjectDirectory = (Get-Location).Path
$ModName = Split-Path $ProjectDirectory -Leaf

$TempZip = Join-Path $env:TEMP "$ModName.zip"
$DestinationZip = Join-Path $ModsDirectory "$ModName.zip"

Write-Host "Building mod: $ModName"
Write-Host "Source:       $ProjectDirectory"
Write-Host "Destination:  $DestinationZip"
Write-Host

# ---------------------------------------------------------------------------
# Sprawdzenie katalogu docelowego
# ---------------------------------------------------------------------------

if (-not (Test-Path $ModsDirectory)) {
    throw "Farming Simulator mods directory does not exist: $ModsDirectory"
}

# ---------------------------------------------------------------------------
# Zebranie plików
#
# Pomijamy:
#   - katalog .git
#   - wszystkie pliki wewnątrz .git
#   - pliki .gitignore, .gitattributes itd., ponieważ nie należą do
#     dozwolonych rozszerzeń
# ---------------------------------------------------------------------------

$Files = Get-ChildItem `
    -Path $ProjectDirectory `
    -Recurse `
    -File |
    Where-Object {
        $_.Extension.ToLowerInvariant() -in $AllowedExtensions -and
        $_.FullName -notmatch '[\\/]\.git([\\/]|$)'
    }

if (-not $Files) {
    throw "No LUA, XML or MD files found to package."
}

Write-Host "Files:"
foreach ($File in $Files) {
    $RelativePath = [System.IO.Path]::GetRelativePath(
        $ProjectDirectory,
        $File.FullName
    )

    Write-Host "  $RelativePath"
}

Write-Host

# ---------------------------------------------------------------------------
# Tworzenie tymczasowego katalogu
#
# Compress-Archive z listą pełnych ścieżek potrafi nie zachować struktury
# katalogów w sposób wygodny dla moda, dlatego najpierw odtwarzamy strukturę
# projektu w katalogu tymczasowym.
# ---------------------------------------------------------------------------

$TempDirectory = Join-Path `
    $env:TEMP `
    "$ModName-build-$([Guid]::NewGuid().ToString('N'))"

New-Item -ItemType Directory -Path $TempDirectory | Out-Null

try {
    foreach ($File in $Files) {
        $RelativePath = [System.IO.Path]::GetRelativePath(
            $ProjectDirectory,
            $File.FullName
        )

        $TargetFile = Join-Path $TempDirectory $RelativePath
        $TargetDirectory = Split-Path $TargetFile -Parent

        if (-not (Test-Path $TargetDirectory)) {
            New-Item `
                -ItemType Directory `
                -Path $TargetDirectory `
                -Force |
                Out-Null
        }

        Copy-Item `
            -Path $File.FullName `
            -Destination $TargetFile
    }

    # Usuń poprzednie tymczasowe ZIP, jeśli istnieje.
    if (Test-Path $TempZip) {
        Remove-Item $TempZip -Force
    }

    # -----------------------------------------------------------------------
    # Tworzenie ZIP-a
    #
    # Ważne:
    # Pakujemy ZAWARTOŚĆ katalogu tymczasowego, a nie sam katalog.
    # Dzięki temu modDesc.xml znajduje się bezpośrednio w głównym katalogu ZIP.
    # -----------------------------------------------------------------------

    Compress-Archive `
        -Path (Join-Path $TempDirectory "*") `
        -DestinationPath $TempZip `
        -CompressionLevel Optimal

    # Usuń poprzednią wersję moda.
    if (Test-Path $DestinationZip) {
        Write-Host "Replacing existing archive..."
        Remove-Item $DestinationZip -Force
    }

    Move-Item `
        -Path $TempZip `
        -Destination $DestinationZip

    Write-Host
    Write-Host "Build completed successfully."
    Write-Host "ZIP: $DestinationZip"
}
finally {
    # Sprzątanie katalogu roboczego nawet w przypadku błędu.
    if (Test-Path $TempDirectory) {
        Remove-Item `
            -Path $TempDirectory `
            -Recurse `
            -Force
    }

    if (Test-Path $TempZip) {
        Remove-Item $TempZip -Force
    }
}