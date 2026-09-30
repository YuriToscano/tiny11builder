#requires -Version 5.1
<#
.SYNOPSIS
Cria uma ISO Tiny11 normal por terminal ou pela interface tiny11gui.ps1.
.DESCRIPTION
Derivado do tiny11maker de ntdevlabs. Preserva a manutenção do Windows.
Execute no Windows PowerShell 5.1 de 64 bits, como administrador.
As opções padrão correspondem ao perfil Tiny11 original.
.EXAMPLE
.\tiny11maker.ps1 -ISO E -SCRATCH D
.EXAMPLE
.\tiny11maker.ps1 -IsoPath 'D:\Windows11.iso' -ImageIndex 6 -OutputIso 'D:\tiny11.iso'
.EXAMPLE
.\tiny11maker.ps1 -ConfigPath 'D:\config.json'
.NOTES
Contornar requisitos não garante suporte, desempenho ou atualizações.
O catálogo pode ser consultado sem construir uma imagem: -ListApplications.
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[c-zC-Z]$')][string]$ISO,
    [ValidatePattern('^[c-zC-Z]$')][string]$SCRATCH,
    [string]$IsoPath,
    [ValidateRange(0,999)][int]$ImageIndex = 0,
    [string]$WorkDirectory,
    [string]$OutputIso,
    [string]$ConfigPath,
    [string]$StatusPath,
    [switch]$InspectOnly,
    [switch]$ListApplications
)
$ErrorActionPreference = 'Stop'
# CATALOG_START
$packagePrefixes = 'AppUp.IntelManagementandSecurityStatus',
'Clipchamp.Clipchamp', 
'DolbyLaboratories.DolbyAccess',
'DolbyLaboratories.DolbyDigitalPlusDecoderOEM',
'Microsoft.BingNews',
'Microsoft.BingSearch',
'Microsoft.BingWeather',
'Microsoft.Copilot',
'Microsoft.Windows.CrossDevice',
'Microsoft.GamingApp',
'Microsoft.GetHelp',
'Microsoft.Getstarted',
'Microsoft.Microsoft3DViewer',
'Microsoft.MicrosoftOfficeHub',
'Microsoft.MicrosoftSolitaireCollection',
'Microsoft.MicrosoftStickyNotes',
'Microsoft.MixedReality.Portal',
'Microsoft.MSPaint',
'Microsoft.Office.OneNote',
'Microsoft.OfficePushNotificationUtility',
'Microsoft.OutlookForWindows',
'Microsoft.Paint',
'Microsoft.People',
'Microsoft.PowerAutomateDesktop',
'Microsoft.SkypeApp',
'Microsoft.StartExperiencesApp',
'Microsoft.Todos',
'Microsoft.Wallet',
'Microsoft.Windows.DevHome',
'Microsoft.Windows.Copilot',
'Microsoft.Windows.Teams',
'Microsoft.WindowsAlarms',
'Microsoft.WindowsCamera',
'microsoft.windowscommunicationsapps',
'Microsoft.WindowsFeedbackHub',
'Microsoft.WindowsMaps',
'Microsoft.WindowsSoundRecorder',
'Microsoft.WindowsTerminal',
'Microsoft.Xbox.TCUI',
'Microsoft.XboxApp',
'Microsoft.XboxGameOverlay',
'Microsoft.XboxGamingOverlay',
'Microsoft.XboxIdentityProvider',
'Microsoft.XboxSpeechToTextOverlay',
'Microsoft.YourPhone',
'Microsoft.ZuneMusic',
'Microsoft.ZuneVideo',
'MicrosoftCorporationII.MicrosoftFamily',
'MicrosoftCorporationII.QuickAssist',
'MSTeams',
'MicrosoftTeams', 
'Microsoft.WindowsTerminal',
'Microsoft.549981C3F5F10'
# CATALOG_END
$catalog = @($packagePrefixes | Select-Object -Unique | Sort-Object)
if ($ListApplications) { $catalog; return }
$options = @{
    RemoveApps = $catalog
    RemoveEdge = $true; RemoveOneDrive = $true
    BypassCPU = $true; BypassRAM = $true; BypassTPM = $true
    BypassSecureBoot = $true; BypassStorage = $true
    LocalAccount = $true; Optimize = $true; DisableTelemetry = $true
    DisableReservedStorage = $true; DisableDeviceEncryption = $true
}
if ($ConfigPath) {
    $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($name in @('IsoPath','ImageIndex','WorkDirectory','OutputIso')) {
        if ($config.PSObject.Properties.Name -contains $name) { Set-Variable -Name $name -Value $config.$name }
    }
    if ($config.PSObject.Properties.Name -contains 'Options') {
        foreach ($property in $config.Options.PSObject.Properties) {
            if (-not $options.ContainsKey($property.Name)) { throw "Opção desconhecida: $($property.Name)" }
            if ($property.Name -eq 'RemoveApps') {
                $selected = @($property.Value)
                foreach ($app in $selected) { if ($catalog -notcontains $app) { throw "Aplicativo desconhecido: $app" } }
                $options.RemoveApps = $selected
            } else {
                if ($property.Value -isnot [bool]) { throw "A opção $($property.Name) deve ser booleana." }
                $options[$property.Name] = $property.Value
            }
        }
    }
}
function Set-Stage([string]$Message) {
    Write-Host ("[{0}] {1}" -f (Get-Date -Format HH:mm:ss),$Message)
    if ($StatusPath) {
        $json = @{ Stage = $Message; Time = (Get-Date).ToString('o') } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($StatusPath,$json,[Text.Encoding]::UTF8)
    }
}
function Invoke-Native {
    param([string]$File,[string[]]$Arguments,[int[]]$SuccessCodes = @(0))
    $command = Get-Command $File -CommandType Application -ErrorAction Stop
    $previousPreference = $ErrorActionPreference
    try {
        # Native tools can write progress to stderr even when successful.
        $ErrorActionPreference = 'Continue'
        & $command.Source @Arguments 2>&1 | ForEach-Object { [string]$_ } | Out-Host
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if ($SuccessCodes -notcontains $code) { throw "$File terminou com código $code." }
}
function Set-RegistryValue([string]$path,[string]$name,[string]$type,[string]$value) {
    $path = $path -replace '(?i)^(HKLM|HKEY_LOCAL_MACHINE)\\z',("HKLM\" + $script:HivePrefix)
    Invoke-Native reg.exe @('add',$path,'/v',$name,'/t',$type,'/d',$value,'/f')
}
function Remove-RegistryValue([string]$path) {
    $path = $path -replace '(?i)^(HKLM|HKEY_LOCAL_MACHINE)\\z',("HKLM\" + $script:HivePrefix)
    & reg.exe query $path *> $null
    if ($LASTEXITCODE -eq 0) { Invoke-Native reg.exe @('delete',$path,'/f') }
}
function Close-Hives {
    foreach ($key in @($script:LoadedHives.ToArray())) {
        Invoke-Native reg.exe @('unload',("HKLM\" + $key))
        [void]$script:LoadedHives.Remove($key)
    }
}
function Open-Hives([bool]$SetupOnly) {
    $files = @{ SYSTEM='Windows\System32\config\SYSTEM' }
    if (-not $SetupOnly) {
        $files.SOFTWARE = 'Windows\System32\config\SOFTWARE'
        $files.NTUSER = 'Users\Default\ntuser.dat'
    }
    foreach ($name in $files.Keys) {
        $key = $script:HivePrefix + $name
        Invoke-Native reg.exe @('load',("HKLM\" + $key),(Join-Path $script:MountPath $files[$name]))
        [void]$script:LoadedHives.Add($key)
    }
}
function Apply-Bypasses {
    foreach ($name in @('CPU','RAM','TPM','SecureBoot','Storage')) {
        if ($options["Bypass$name"]) {
            Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' ("Bypass"+$name+"Check") REG_DWORD 1
        }
    }
    if ($options.BypassCPU -or $options.BypassTPM) {
        Set-RegistryValue 'HKLM\zSYSTEM\Setup\MoSetup' AllowUpgradesWithUnsupportedTPMOrCPU REG_DWORD 1
    }
}
function Remove-OfflinePath([string]$RelativePath) {
    $target = Join-Path $script:MountPath $RelativePath
    if (-not (Test-Path -LiteralPath $target)) { return }
    # No recursive takeown prompt (which varies with the Windows language).
    Invoke-Native takeown.exe @('/f',$target,'/a')
    Invoke-Native icacls.exe @($target,'/grant','*S-1-5-32-544:(F)','/T','/C')
    Remove-Item -LiteralPath $target -Recurse -Force
}
function Apply-Tweaks {
    # Original offline tweaks; independently controlled by the GUI.
if ($options.Optimize) {
    Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'OemPreInstalledAppsEnabled' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEnabled' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'ContentDeliveryAllowed' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\PolicyManager\current\device\Start' 'ConfigureStartPins' 'REG_SZ' '{"pinnedList": [{}]}'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'FeatureManagementEnabled' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEverEnabled' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SoftLandingEnabled' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContentEnabled' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-310093Enabled' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338393Enabled' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353694Enabled' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353696Enabled' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\PushToInstall' 'DisablePushToInstall' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\MRT' 'DontOfferThroughWUAU' 'REG_DWORD' '1'
    Remove-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\Subscriptions'
    Remove-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SuggestedApps'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 'REG_DWORD' '1'
}
if ($options.DisableReservedStorage) {
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' 'ShippedWithReserves' 'REG_DWORD' '0'
}
if ($options.DisableDeviceEncryption) {
    Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Control\BitLocker' 'PreventDeviceEncryption' 'REG_DWORD' '1'
}
if ($options.Optimize) {
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Chat' 'ChatIcon' 'REG_DWORD' '3'
    Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 'REG_DWORD' '0'
}
if ($options.RemoveEdge) {
    Remove-RegistryValue "HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge"
    Remove-RegistryValue "HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update"
}
if ($options.RemoveOneDrive) {
    Set-RegistryValue "HKLM\zSOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC" "REG_DWORD" "1"
}
if ($options.DisableTelemetry) {
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Input\TIPC' 'Enabled' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\dmwappushservice' 'Start' 'REG_DWORD' '4'
    ## Prevents installation of DevHome and Outlook
}
if ($options.Optimize) {
    if ($options.RemoveApps -contains 'Microsoft.OutlookForWindows') { Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' 'workCompleted' 'REG_DWORD' '1' }
    if ($options.RemoveApps -contains 'Microsoft.OutlookForWindows') { Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate' 'workCompleted' 'REG_DWORD' '1' }
    if ($options.RemoveApps -contains 'Microsoft.Windows.DevHome') { Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate' 'workCompleted' 'REG_DWORD' '1' }
    if ($options.RemoveApps -contains 'Microsoft.OutlookForWindows') { Remove-RegistryValue 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' }
    if ($options.RemoveApps -contains 'Microsoft.Windows.DevHome') { Remove-RegistryValue 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate' }
}
if (($options.RemoveApps -contains 'Microsoft.Copilot' -or $options.RemoveApps -contains 'Microsoft.Windows.Copilot')) {
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Edge' 'HubsSidebarEnabled' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 'REG_DWORD' '1'
}
if (($options.RemoveApps -contains 'MSTeams' -or $options.RemoveApps -contains 'MicrosoftTeams' -or $options.RemoveApps -contains 'Microsoft.Windows.Teams')) {
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Teams' 'DisableInstallation' 'REG_DWORD' '1'
}
if (($options.RemoveApps -contains 'Microsoft.OutlookForWindows')) {
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Mail' 'PreventRun' 'REG_DWORD' '1'
}
}
if ($env:OS -ne 'Windows_NT') { throw 'Execute este script no Windows.' }
if (-not [Environment]::Is64BitProcess) { throw 'Use o Windows PowerShell de 64 bits.' }
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Abra o Windows PowerShell como administrador ou execute tiny11gui.ps1.'
}
Import-Module Dism -ErrorAction Stop
$script:LoadedHives = New-Object 'System.Collections.Generic.List[string]'
$script:HivePrefix = 'Tiny11_' + [Guid]::NewGuid().ToString('N') + '_'
$script:MountPath = $null
$script:SessionRoot = $null
$mountedWim = $false
$ownedIso = $false
$transcript = $false
$partialIso = $null
try {
    if ($IsoPath) {
        $IsoPath = (Resolve-Path -LiteralPath $IsoPath).Path
        if ([IO.Path]::GetExtension($IsoPath) -ne '.iso') { throw 'Selecione um arquivo ISO.' }
        $isoObject = Get-DiskImage -ImagePath $IsoPath
        if (-not $isoObject.Attached) {
            $isoObject = Mount-DiskImage -ImagePath $IsoPath -PassThru
            $ownedIso = $true
        }
        $volume = @($isoObject | Get-Volume | Where-Object DriveLetter)
        if ($volume.Count -ne 1) { throw 'Não foi possível determinar a unidade da ISO.' }
        $source = "$($volume[0].DriveLetter):\"
    } else {
        if (-not $ISO) {
            if ($InspectOnly -or $ConfigPath) { throw 'Informe a ISO de origem.' }
            $ISO = Read-Host 'Letra da unidade da ISO montada (ex.: E)'
        }
        if ($ISO -notmatch '^[c-zC-Z]$') { throw 'Letra de unidade inválida.' }
        $source = $ISO + ':\'
    }
    $sourceImage = Join-Path $source 'sources\install.wim'
    if (-not (Test-Path -LiteralPath $sourceImage)) { $sourceImage = Join-Path $source 'sources\install.esd' }
    if (-not (Test-Path -LiteralPath $sourceImage) -or
        -not (Test-Path -LiteralPath (Join-Path $source 'sources\boot.wim'))) {
        throw 'A origem deve conter boot.wim e install.wim ou install.esd.'
    }
    $images = @(Get-WindowsImage -ImagePath $sourceImage)
    if ($InspectOnly) { $images | Select-Object ImageIndex,ImageName,ImageDescription; return }
    if (-not $ImageIndex) {
        if ($ConfigPath) { throw 'Selecione a edição do Windows.' }
        $images | Format-Table ImageIndex,ImageName | Out-Host
        $ImageIndex = [int](Read-Host 'Índice da edição')
    }
    if (@($images.ImageIndex) -notcontains $ImageIndex) { throw "Índice inválido: $ImageIndex" }
    if (-not $WorkDirectory) {
        if ($SCRATCH) { $WorkDirectory = $SCRATCH + ':\' } else { $WorkDirectory = $PSScriptRoot }
    }
    $WorkDirectory = [IO.Path]::GetFullPath($WorkDirectory)
    if ($WorkDirectory.StartsWith('\\')) { throw 'Use uma pasta temporária em disco local NTFS.' }
    if (-not $OutputIso) { $OutputIso = Join-Path $PSScriptRoot 'tiny11.iso' }
    $OutputIso = [IO.Path]::GetFullPath($OutputIso)
    if ([IO.Path]::GetExtension($OutputIso) -ne '.iso') { throw 'O destino deve terminar em .iso.' }
    if (Test-Path -LiteralPath $OutputIso) { throw 'A ISO de destino já existe. Escolha outro nome.' }
    if ($IsoPath -and $OutputIso -eq $IsoPath) { throw 'Origem e destino devem ser diferentes.' }
    $workDrive = Get-Volume -FilePath ([IO.Path]::GetPathRoot($WorkDirectory))
    if ($workDrive.FileSystem -ne 'NTFS') { throw 'A pasta temporária deve estar em um volume NTFS.' }
    if ($workDrive.SizeRemaining -lt 25GB) { throw 'Reserve pelo menos 25 GB livres no disco temporário.' }
    New-Item -ItemType Directory -Path $WorkDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path (Split-Path -Parent $OutputIso) -Force | Out-Null
    $script:SessionRoot = Join-Path $WorkDirectory ('tiny11_' + [Guid]::NewGuid().ToString('N'))
    $media = Join-Path $script:SessionRoot 'media'
    $script:MountPath = Join-Path $script:SessionRoot 'scratchdir'
    New-Item -ItemType Directory -Path $media,$script:MountPath -Force | Out-Null
    $log = $OutputIso + '.' + (Get-Date -Format yyyyMMdd_HHmmss) + '.log'
    Start-Transcript -Path $log | Out-Null
    $transcript = $true
    Set-Stage "Preparando imagem. Pasta de trabalho: $script:SessionRoot"
    # Official ADK first; upstream Microsoft symbol URL as fallback.
    $hostArch = $env:PROCESSOR_ARCHITECTURE
    $adk = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) "Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$hostArch\Oscdimg\oscdimg.exe"
    $oscdimg = Join-Path $PSScriptRoot 'oscdimg.exe'
    if (Test-Path -LiteralPath $adk) { $oscdimg = $adk }
    if (-not (Test-Path -LiteralPath $oscdimg)) {
        $oscdimg = Join-Path $script:SessionRoot 'oscdimg.exe'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri 'https://msdl.microsoft.com/download/symbols/oscdimg.exe/3D44737265000/oscdimg.exe' -OutFile $oscdimg
        $signature = Get-AuthenticodeSignature -LiteralPath $oscdimg
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
            throw 'A assinatura Microsoft do oscdimg baixado não foi validada. Use o ADK oficial.'
        }
    }
    $answer = Join-Path $PSScriptRoot 'autounattend.xml'
    if ($options.LocalAccount -and -not (Test-Path -LiteralPath $answer)) {
        throw 'Mantenha o autounattend.xml do repositório junto aos scripts.'
    }
    Set-Stage 'Copiando arquivos da mídia original'
    Copy-Item -Path (Join-Path $source '*') -Destination $media -Recurse -Force
    Get-ChildItem -LiteralPath $media -Recurse -File -Force | ForEach-Object { $_.IsReadOnly = $false }
    # Both WIM and ESD become a single-edition WIM at index 1.
    Set-Stage 'Exportando a edição selecionada'
    $workingWim = Join-Path $media 'sources\selected.wim'
    Export-WindowsImage -SourceImagePath $sourceImage -SourceIndex $ImageIndex -DestinationImagePath $workingWim -CompressionType Maximum -CheckIntegrity | Out-Host
    foreach ($name in @('install.wim','install.esd')) {
        $path = Join-Path $media "sources\$name"
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    $installWim = Join-Path $media 'sources\install.wim'
    Move-Item -LiteralPath $workingWim -Destination $installWim
    Set-Stage 'Montando Windows e removendo os aplicativos selecionados'
    Mount-WindowsImage -ImagePath $installWim -Index 1 -Path $script:MountPath -CheckIntegrity | Out-Host
    $mountedWim = $true
    $packages = @(Get-AppxProvisionedPackage -Path $script:MountPath)
    foreach ($package in $packages) {
        if ($options.RemoveApps -contains $package.DisplayName) {
            Set-Stage "Removendo $($package.DisplayName)"
            Remove-AppxProvisionedPackage -Path $script:MountPath -PackageName $package.PackageName | Out-Host
        }
    }
    if ($options.RemoveEdge) {
        foreach ($path in @('Program Files (x86)\Microsoft\Edge','Program Files (x86)\Microsoft\EdgeUpdate','Program Files (x86)\Microsoft\EdgeCore','Windows\System32\Microsoft-Edge-Webview')) { Remove-OfflinePath $path }
    }
    if ($options.RemoveOneDrive) {
        foreach ($path in @('Windows\System32\OneDriveSetup.exe','Windows\SysWOW64\OneDriveSetup.exe')) { Remove-OfflinePath $path }
    }
    if ($options.DisableTelemetry) {
        foreach ($task in @(
            'Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
            'Microsoft\Windows\Customer Experience Improvement Program',
            'Microsoft\Windows\Application Experience\ProgramDataUpdater',
            'Microsoft\Windows\Chkdsk\Proxy',
            'Microsoft\Windows\Windows Error Reporting\QueueReporting'
        )) {
            $taskPath = Join-Path $script:MountPath ("Windows\System32\Tasks\" + $task)
            if (Test-Path -LiteralPath $taskPath) { Remove-Item -LiteralPath $taskPath -Recurse -Force }
        }
    }
    Set-Stage 'Aplicando as opções no Registro da imagem'
    Open-Hives $false
    Apply-Bypasses
    Apply-Tweaks
    if ($options.LocalAccount) {
        Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' BypassNRO REG_DWORD 1
        # Adjust only the generated copy; the repository XML is untouched.
        [xml]$xml = Get-Content -LiteralPath $answer -Raw -Encoding UTF8
        $info = Get-WindowsImage -ImagePath $installWim -Index 1
        $arch = switch ([int]$info.Architecture) { 9 {'amd64'} 12 {'arm64'} default { throw 'Arquitetura da imagem não suportada.' } }
        foreach ($node in $xml.SelectNodes('//*[@processorArchitecture]')) { $node.SetAttribute('processorArchitecture',$arch) }
        foreach ($node in @($xml.DocumentElement.ChildNodes | Where-Object LocalName -eq 'component')) {
            $oobe = $xml.DocumentElement.ChildNodes | Where-Object { $_.LocalName -eq 'settings' -and $_.GetAttribute('pass') -eq 'oobeSystem' } | Select-Object -First 1
            $existing = $oobe.ChildNodes | Where-Object { $_.LocalName -eq 'component' -and $_.GetAttribute('name') -eq $node.GetAttribute('name') } | Select-Object -First 1
            if ($existing) {
                foreach ($child in @($node.ChildNodes)) { [void]$existing.AppendChild($child) }
                [void]$xml.DocumentElement.RemoveChild($node)
            } else { [void]$oobe.AppendChild($node) }
        }
        foreach ($metadata in $xml.SelectNodes('//*[local-name()="MetaData"]')) {
            if ($metadata.SelectSingleNode('*[local-name()="Key"]').InnerText -eq '/IMAGE/INDEX') {
                $metadata.SelectSingleNode('*[local-name()="Value"]').InnerText = '1'
            }
        }
        $xml.Save((Join-Path $media 'autounattend.xml'))
        $sysprep = Join-Path $script:MountPath 'Windows\System32\Sysprep'
        New-Item -ItemType Directory -Path $sysprep -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $media 'autounattend.xml') -Destination (Join-Path $sysprep 'autounattend.xml') -Force
    } else {
        $copiedAnswer = Join-Path $media 'autounattend.xml'
        if (Test-Path -LiteralPath $copiedAnswer) { Remove-Item -LiteralPath $copiedAnswer -Force }
    }
    Close-Hives
    Set-Stage 'Limpando componentes e salvando o Windows'
    Invoke-Native dism.exe @("/Image:$script:MountPath",'/Cleanup-Image','/StartComponentCleanup','/ResetBase') @(0,3010)
    Dismount-WindowsImage -Path $script:MountPath -Save -CheckIntegrity | Out-Host
    $mountedWim = $false
    Set-Stage 'Compactando a imagem'
    $compressed = Join-Path $media 'sources\install2.wim'
    Invoke-Native dism.exe @('/Export-Image',"/SourceImageFile:$installWim",'/SourceIndex:1',"/DestinationImageFile:$compressed",'/Compress:recovery','/CheckIntegrity')
    Remove-Item -LiteralPath $installWim -Force
    Move-Item -LiteralPath $compressed -Destination $installWim
    Set-Stage 'Aplicando contornos na imagem do instalador'
    $bootWim = Join-Path $media 'sources\boot.wim'
    Mount-WindowsImage -ImagePath $bootWim -Index 2 -Path $script:MountPath | Out-Host
    $mountedWim = $true
    Open-Hives $true
    Apply-Bypasses
    Close-Hives
    Dismount-WindowsImage -Path $script:MountPath -Save -CheckIntegrity | Out-Host
    $mountedWim = $false
    Set-Stage 'Gerando a ISO inicializável'
    $efi = Join-Path $media 'efi\microsoft\boot\efisys.bin'
    $bios = Join-Path $media 'boot\etfsboot.com'
    if (-not (Test-Path -LiteralPath $efi)) { throw 'Arquivo de inicialização UEFI ausente.' }
    $bootArg = "-bootdata:1#pEF,e,b$efi"
    if (Test-Path -LiteralPath $bios) { $bootArg = "-bootdata:2#p0,e,b$bios#pEF,e,b$efi" }
    $partialIso = $OutputIso + '.' + [Guid]::NewGuid().ToString('N') + '.partial'
    Invoke-Native $oscdimg @('-m','-o','-h','-u2','-udfver102',$bootArg,$media,$partialIso)
    if ((Get-Item -LiteralPath $partialIso).Length -lt 1MB) { throw 'A ISO gerada está vazia ou incompleta.' }
    [IO.File]::Move($partialIso,$OutputIso)
    $partialIso = $null
    Set-Stage "Concluído: $OutputIso"
} finally {
    $cleanupOK = $true
    try { Close-Hives } catch { $cleanupOK = $false; Write-Warning "Falha ao descarregar Registro: $_" }
    if ($mountedWim -and $cleanupOK) {
        try { Dismount-WindowsImage -Path $script:MountPath -Discard | Out-Host; $mountedWim = $false }
        catch { $cleanupOK = $false; Write-Warning "Falha ao desmontar: $_" }
    }
    if ($ownedIso) {
        try { Dismount-DiskImage -ImagePath $IsoPath | Out-Null }
        catch { Write-Warning "Não foi possível desmontar a ISO de origem: $_" }
    }
    if ($partialIso -and (Test-Path -LiteralPath $partialIso)) {
        Remove-Item -LiteralPath $partialIso -Force -ErrorAction SilentlyContinue
    }
    if ($transcript) { Stop-Transcript | Out-Null }
    if ($script:SessionRoot -and $cleanupOK -and -not $mountedWim) {
        Remove-Item -LiteralPath $script:SessionRoot -Recurse -Force -ErrorAction SilentlyContinue
    } elseif ($script:SessionRoot) { Write-Warning "Pasta preservada para recuperação: $script:SessionRoot" }
}
