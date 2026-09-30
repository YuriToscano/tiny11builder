#requires -Version 5.1
<#
.SYNOPSIS
GUI em português para o Tiny11 normal (PowerShell 5.1, 64 bits).
.DESCRIPTION
Mantenha os dois scripts e autounattend.xml na mesma pasta.
Execute: powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\tiny11gui.ps1
A elevação é automática; não há módulos externos ou cancelamento forçado.
#>
[CmdletBinding()]
param([ValidateSet('Inspect','Build')][string]$Worker,[string]$JobDirectory)
$ErrorActionPreference='Stop'
$maker=Join-Path $PSScriptRoot 'tiny11maker.ps1'
if($Worker) {
    [Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
    $resultPath=Join-Path $JobDirectory 'result.json'
    try {
        $requestPath=Join-Path $JobDirectory 'request.json'
        if($Worker -eq 'Inspect') {
            $request=Get-Content -LiteralPath $requestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $result=@{Success=$true;Images=@(& $maker -IsoPath $request.IsoPath -InspectOnly)}
        } else {
            & $maker -ConfigPath $requestPath -StatusPath (Join-Path $JobDirectory 'status.json')
            $result=@{Success=$true}
        }
        $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
        exit 0
    } catch {
        [Console]::Error.WriteLine(($_ | Out-String))
        @{Success=$false;Error=$_.Exception.Message}|ConvertTo-Json|Set-Content -LiteralPath $resultPath -Encoding UTF8
        exit 1
    }
}
if($env:OS -ne 'Windows_NT') {throw 'Execute a interface no Windows.'}
if(-not [Environment]::Is64BitOperatingSystem) {throw 'A interface requer Windows de 64 bits.'}
$principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$admin=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$psExe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
if(-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {
    $psExe=Join-Path $env:WINDIR 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
}
if(-not $admin -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5 -or [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $quoted=$PSCommandPath.Replace("'","''")
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("& '$quoted'"))
    $launch=@{FilePath=$psExe;ArgumentList=@('-NoProfile','-ExecutionPolicy','Bypass','-STA','-EncodedCommand',$encoded)}
    if(-not $admin) {$launch.Verb='RunAs'}
    Start-Process @launch | Out-Null
    return
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
foreach($file in @($maker,$PSCommandPath)) {
    if(-not(Test-Path -LiteralPath $file)) {throw "Arquivo ausente: $file"}
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
    if($errors.Count) {throw "Erro de sintaxe: $($errors[0].Message)"}
}
$script:Job=$null;$script:LoadedIso=$null;$script:LastOutput=$null;$script:Readers=@()
$optionControls=@{}
$nl=[Environment]::NewLine
$form=New-Object Windows.Forms.Form
$form.Text='Tiny11 Builder | Interface em português'
$form.StartPosition='CenterScreen';$form.Size=New-Object Drawing.Size(980,750)
$form.MinimumSize=New-Object Drawing.Size(820,650)
$form.Font=New-Object Drawing.Font('Segoe UI',10);$form.AutoScaleMode='Dpi'
$root=New-Object Windows.Forms.TableLayoutPanel
$root.Dock='Fill';$root.Padding=New-Object Windows.Forms.Padding(16);$root.ColumnCount=1;$root.RowCount=5
foreach($spec in @(@('Absolute',50),@('Percent',100),@('Absolute',35),@('Absolute',18),@('Absolute',45))) {
    [void]$root.RowStyles.Add((New-Object Windows.Forms.RowStyle($spec[0],$spec[1])))
}
$form.Controls.Add($root)
$title=New-Object Windows.Forms.Label
$title.Text='Selecione a imagem do Windows, personalize as opções e crie sua ISO.'
$title.Dock='Fill';$root.Controls.Add($title,0,0)
$tabs=New-Object Windows.Forms.TabControl;$tabs.Dock='Fill';$root.Controls.Add($tabs,0,1)
function New-Page([string]$Text) {
    $page=New-Object Windows.Forms.TabPage;$page.Text=$Text
    $page.Padding=New-Object Windows.Forms.Padding(12);[void]$tabs.TabPages.Add($page);return $page
}
$inputPage=New-Page 'Imagem e destino';$appPage=New-Page 'Aplicativos'
$optionPage=New-Page 'Opções';$logPage=New-Page 'Execução e logs';$helpPage=New-Page 'Como usar'
$paths=New-Object Windows.Forms.TableLayoutPanel
$paths.Dock='Top';$paths.AutoSize=$true;$paths.ColumnCount=3
[void]$paths.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',155)))
[void]$paths.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))
[void]$paths.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',115)))
$inputPage.Controls.Add($paths)
function New-Path([string]$Text,[int]$Row) {
    $label=New-Object Windows.Forms.Label;$label.Text=$Text;$label.AutoSize=$true
    $label.Margin=New-Object Windows.Forms.Padding(0,8,4,8);$paths.Controls.Add($label,0,$Row)
    $box=New-Object Windows.Forms.TextBox;$box.Dock='Fill';$paths.Controls.Add($box,1,$Row)
    $button=New-Object Windows.Forms.Button;$button.Text='Selecionar...';$button.Dock='Fill';$paths.Controls.Add($button,2,$Row)
    return @{Box=$box;Button=$button}
}
$iso=New-Path 'ISO original' 0;$work=New-Path 'Pasta temporária' 1;$output=New-Path 'ISO de destino' 2
$work.Box.Text=$env:SystemDrive+'\Tiny11Work'
$output.Box.Text=Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'tiny11.iso'
$edition=New-Object Windows.Forms.ComboBox
$edition.Dock='Fill';$edition.DropDownStyle='DropDownList';$edition.DisplayMember='Label';$paths.Controls.Add($edition,1,3)
$inspect=New-Object Windows.Forms.Button
$inspect.Text='Ler edições';$inspect.Dock='Fill';$paths.Controls.Add($inspect,2,3)
$note=New-Object Windows.Forms.Label;$note.AutoSize=$true
$note.Text="Pasta temporária: disco local NTFS e pelo menos 25 GB livres.$($nl)Escolha um destino que ainda não exista."
$note.Margin=New-Object Windows.Forms.Padding(0,20,0,0);$paths.Controls.Add($note,1,4)
$iso.Button.Add_Click({
    $d=New-Object Windows.Forms.OpenFileDialog;$d.Filter='Imagem ISO (*.iso)|*.iso'
    if($d.ShowDialog() -eq 'OK') {$iso.Box.Text=$d.FileName};$d.Dispose()
})
$work.Button.Add_Click({
    $d=New-Object Windows.Forms.FolderBrowserDialog;$d.Description='Pasta temporária em disco NTFS'
    if($d.ShowDialog() -eq 'OK') {$work.Box.Text=$d.SelectedPath};$d.Dispose()
})
$output.Button.Add_Click({
    $d=New-Object Windows.Forms.SaveFileDialog;$d.Filter='Imagem ISO (*.iso)|*.iso';$d.DefaultExt='iso';$d.FileName='tiny11.iso'
    if($d.ShowDialog() -eq 'OK') {$output.Box.Text=$d.FileName};$d.Dispose()
})
$iso.Box.Add_TextChanged({$script:LoadedIso=$null;$edition.Items.Clear()})
$appLayout=New-Object Windows.Forms.TableLayoutPanel
$appLayout.Dock='Fill';$appLayout.ColumnCount=1;$appLayout.RowCount=3
foreach($spec in @(@('Absolute',55),@('Percent',100),@('Absolute',40))) {
    [void]$appLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle($spec[0],$spec[1])))
}
$appPage.Controls.Add($appLayout)
$appNote=New-Object Windows.Forms.Label;$appNote.Dock='Fill'
$appNote.Text="Marcado = remover. Desmarcado = preservar.$($nl)Catálogo do Tiny11: aplicativos ausentes na ISO são ignorados."
$appLayout.Controls.Add($appNote,0,0)
$apps=New-Object Windows.Forms.CheckedListBox;$apps.Dock='Fill';$apps.CheckOnClick=$true;$apps.DisplayMember='Label'
$appLayout.Controls.Add($apps,0,1)
$friendlyNames=@{
 'Microsoft.GetHelp'='Obter Ajuda'; 'Microsoft.Getstarted'='Introdução'
 'Microsoft.MicrosoftSolitaireCollection'='Paciência Microsoft'; 'Microsoft.MicrosoftStickyNotes'='Notas Autoadesivas'
 'Microsoft.WindowsAlarms'='Relógio e Alarmes'; 'Microsoft.WindowsCamera'='Câmera'
 'Microsoft.WindowsFeedbackHub'='Hub de Comentários'; 'Microsoft.WindowsMaps'='Mapas'
 'Microsoft.WindowsSoundRecorder'='Gravador de Som'; 'Microsoft.YourPhone'='Vincular ao Celular'
 'Microsoft.ZuneMusic'='Media Player / Música'; 'Microsoft.ZuneVideo'='Filmes e TV'
 'microsoft.windowscommunicationsapps'='Email e Calendário'; 'Microsoft.People'='Pessoas'
 'MicrosoftCorporationII.QuickAssist'='Assistência Rápida'; 'Microsoft.BingNews'='Notícias'
 'Microsoft.BingWeather'='Clima'; 'Microsoft.WindowsTerminal'='Windows Terminal'
 'Microsoft.549981C3F5F10'='Cortana'; 'Microsoft.OutlookForWindows'='Novo Outlook'
 'Microsoft.Paint'='Paint'; 'Microsoft.MSPaint'='Paint 3D'; 'Microsoft.Todos'='Microsoft To Do'
 'Microsoft.PowerAutomateDesktop'='Power Automate'; 'Microsoft.Windows.DevHome'='Dev Home'
 'Microsoft.GamingApp'='Xbox'; 'MSTeams'='Microsoft Teams'
}
foreach($id in @(& $maker -ListApplications)) {
    $label=$id -replace '^MicrosoftCorporationII\.','' -replace '^Microsoft\.',''
    if($friendlyNames.ContainsKey($id)) {$label=$friendlyNames[$id]}
    [void]$apps.Items.Add([pscustomobject]@{Id=$id;Label="$label  [$id]"},$true)
}
$selection=New-Object Windows.Forms.FlowLayoutPanel;$selection.Dock='Fill'
$all=New-Object Windows.Forms.Button;$all.Text='Marcar todos';$all.AutoSize=$true
$none=New-Object Windows.Forms.Button;$none.Text='Desmarcar todos';$none.AutoSize=$true
$selection.Controls.AddRange(@($all,$none));$appLayout.Controls.Add($selection,0,2)
$all.Add_Click({for($i=0;$i -lt $apps.Items.Count;$i++) {$apps.SetItemChecked($i,$true)}})
$none.Add_Click({for($i=0;$i -lt $apps.Items.Count;$i++) {$apps.SetItemChecked($i,$false)}})
$checks=New-Object Windows.Forms.FlowLayoutPanel;$checks.Dock='Fill'
$checks.FlowDirection='TopDown';$checks.WrapContents=$false;$checks.AutoScroll=$true;$optionPage.Controls.Add($checks)
$labels=[ordered]@{
 RemoveEdge='Remover Edge e WebView (pode afetar aplicativos dependentes)'
 RemoveOneDrive='Remover OneDrive'
 BypassRAM='Contornar verificação de memória RAM mínima'
 BypassCPU='Contornar verificação de processador compatível'
 BypassTPM='Contornar verificação de TPM'
 BypassSecureBoot='Contornar verificação de Secure Boot'
 BypassStorage='Contornar verificação de armazenamento mínimo'
 LocalAccount='Aplicar configuração para conta local e instalação compacta'
 Optimize='Aplicar ajustes originais de sugestões, anúncios e menu Iniciar'
 DisableTelemetry='Reduzir telemetria pelas políticas originais do Tiny11'
 DisableReservedStorage='Desabilitar armazenamento reservado'
 DisableDeviceEncryption='Desabilitar criptografia automática do dispositivo'
}
foreach($key in $labels.Keys) {
    $check=New-Object Windows.Forms.CheckBox;$check.Text=$labels[$key];$check.AutoSize=$true;$check.Checked=$true
    $check.Margin=New-Object Windows.Forms.Padding(3,5,3,5);$checks.Controls.Add($check);$optionControls[$key]=$check
}
$log=New-Object Windows.Forms.RichTextBox;$log.Dock='Fill';$log.ReadOnly=$true;$log.WordWrap=$false
$log.Font=New-Object Drawing.Font('Consolas',9);$logPage.Controls.Add($log)
$help=New-Object Windows.Forms.RichTextBox;$help.Dock='Fill';$help.ReadOnly=$true
$help.Text=@'
1. Selecione a ISO original, uma pasta temporária e a ISO de destino.
2. Clique em Ler edições e escolha a edição desejada.
3. Em Aplicativos, desmarque os itens que deseja preservar.
4. Em Opções, revise os ajustes. Os padrões seguem o Tiny11 original.
5. Clique em Criar ISO e acompanhe Execução e logs.

Mantenha os dois scripts e autounattend.xml na mesma pasta.
A ISO original e destinos existentes não são substituídos.
Apenas uma edição é incluída na ISO final, no índice 1.

Não há cancelamento forçado: interromper o DISM pode deixar imagens montadas.
O fechamento fica bloqueado durante a operação. Em falha, a limpeza é tentada.
Se a desmontagem falhar, a pasta é preservada para recuperação e informada no log.

Contornos não adicionam instruções à CPU, memória ou espaço, nem garantem
suporte ou atualizações. Conta local depende do instalador da versão utilizada.
Logs: %LOCALAPPDATA%\Tiny11GUI e junto à ISO de destino.
O oscdimg vem do ADK, da pasta dos scripts ou do endereço Microsoft usado
pelo projeto original (com verificação de assinatura). Nenhum módulo é instalado.

Terminal (Windows PowerShell como administrador):
.\tiny11maker.ps1 -ISO E -SCRATCH D
.\tiny11maker.ps1 -IsoPath 'D:\Windows11.iso' -ImageIndex 6 -OutputIso 'D:\tiny11.iso'
'@
$helpPage.Controls.Add($help)
$status=New-Object Windows.Forms.Label;$status.Dock='Fill';$status.Text='Pronto. Selecione a ISO e leia as edições.';$root.Controls.Add($status,0,2)
$progress=New-Object Windows.Forms.ProgressBar;$progress.Dock='Fill';$root.Controls.Add($progress,0,3)
$buttons=New-Object Windows.Forms.FlowLayoutPanel;$buttons.Dock='Fill';$buttons.FlowDirection='RightToLeft'
$build=New-Object Windows.Forms.Button;$build.Text='Criar ISO';$build.AutoSize=$true
$openOutput=New-Object Windows.Forms.Button;$openOutput.Text='Abrir pasta da ISO';$openOutput.AutoSize=$true;$openOutput.Enabled=$false
$openLogs=New-Object Windows.Forms.Button;$openLogs.Text='Abrir logs';$openLogs.AutoSize=$true;$openLogs.Enabled=$false
$buttons.Controls.AddRange(@($build,$openOutput,$openLogs));$root.Controls.Add($buttons,0,4)
$openOutput.Add_Click({if($script:LastOutput) {Start-Process explorer.exe -ArgumentList ('"'+(Split-Path -Parent $script:LastOutput)+'"')}})
$openLogs.Add_Click({if($script:Job) {Start-Process explorer.exe -ArgumentList ('"'+$script:Job.Directory+'"')}})
function Set-Busy([bool]$Busy) {
    $inputPage.Enabled=-not $Busy;$appPage.Enabled=-not $Busy;$optionPage.Enabled=-not $Busy;$build.Enabled=-not $Busy
    if($Busy) {$progress.Style='Marquee'} else {$progress.Style='Blocks';$progress.Value=0}
}
function Start-Worker([string]$Mode,[hashtable]$Request) {
    if($script:Job -and -not $script:Job.Process.HasExited) {throw 'Já há uma operação em execução.'}
    foreach($reader in $script:Readers) {$reader.Dispose()};$script:Readers=@()
    $directory=Join-Path (Join-Path $env:LOCALAPPDATA 'Tiny11GUI') ((Get-Date -Format yyyyMMdd_HHmmss)+'_'+[Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $Request|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $directory 'request.json') -Encoding UTF8
    $self=$PSCommandPath.Replace("'","''");$jobPath=$directory.Replace("'","''")
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("& '$self' -Worker '$Mode' -JobDirectory '$jobPath'"))
    $process=Start-Process -FilePath $psExe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-NonInteractive','-STA','-EncodedCommand',$encoded) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $directory 'stdout.log') -RedirectStandardError (Join-Path $directory 'stderr.log')
    $script:Job=@{Process=$process;Directory=$directory;Mode=$Mode;Iso=$Request.IsoPath;Output=$Request.OutputIso;Handled=$false}
    Set-Busy $true;$openLogs.Enabled=$true;$log.Clear();$tabs.SelectedTab=$logPage
    foreach($name in @('stdout.log','stderr.log')) {
        $stream=[IO.File]::Open((Join-Path $directory $name),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        $script:Readers+=New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8,$true)
    }
    $status.Text=if($Mode -eq 'Inspect') {'Lendo edições da ISO...'} else {'Iniciando construção...'}
}
$inspect.Add_Click({
    try {
        if(-not(Test-Path -LiteralPath $iso.Box.Text -PathType Leaf)) {throw 'Selecione uma ISO existente.'}
        Start-Worker Inspect @{IsoPath=$iso.Box.Text}
    } catch {[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Falha ao ler ISO')}
})
$build.Add_Click({
    try {
        if(-not $script:LoadedIso -or $script:LoadedIso -ne $iso.Box.Text -or -not $edition.SelectedItem) {throw 'Leia as edições e selecione uma delas.'}
        if(-not $work.Box.Text.Trim() -or -not $output.Box.Text.Trim()) {throw 'Informe a pasta temporária e o destino.'}
        if(Test-Path -LiteralPath $output.Box.Text) {throw 'O destino já existe. Escolha outro nome.'}
        $choices=@{RemoveApps=@($apps.CheckedItems | ForEach-Object {$_.Id})}
        foreach($key in $optionControls.Keys) {$choices[$key]=[bool]$optionControls[$key].Checked}
        $openOutput.Enabled=$false
        Start-Worker Build @{IsoPath=$iso.Box.Text;ImageIndex=[int]$edition.SelectedItem.Index;WorkDirectory=$work.Box.Text;OutputIso=$output.Box.Text;Options=$choices}
    } catch {[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Falha ao iniciar')}
})
$timer=New-Object Windows.Forms.Timer;$timer.Interval=600
$timer.Add_Tick({
    if(-not $script:Job -or $script:Job.Handled) {return}
    try {
        foreach($reader in $script:Readers) {
            $text=$reader.ReadToEnd()
            if($text) {
                $log.AppendText($text)
                if($log.TextLength -gt 200000) {$log.Text=$log.Text.Substring($log.TextLength-150000)}
                $log.SelectionStart=$log.TextLength;$log.ScrollToCaret()
            }
        }
        $statusFile=Join-Path $script:Job.Directory 'status.json'
        if(Test-Path -LiteralPath $statusFile) {
            try {$status.Text=(Get-Content -LiteralPath $statusFile -Raw -Encoding UTF8 | ConvertFrom-Json).Stage} catch {}
        }
        if(-not $script:Job.Process.HasExited) {return}
        $script:Job.Handled=$true;Set-Busy $false
        $resultFile=Join-Path $script:Job.Directory 'result.json'
        if(-not(Test-Path -LiteralPath $resultFile)) {throw 'Processo encerrado sem resultado. Consulte os logs.'}
        $result=Get-Content -LiteralPath $resultFile -Raw -Encoding UTF8|ConvertFrom-Json
        if(-not $result.Success -or $script:Job.Process.ExitCode -ne 0) {throw $result.Error}
        if($script:Job.Mode -eq 'Inspect') {
            $edition.Items.Clear()
            foreach($image in @($result.Images)) {[void]$edition.Items.Add([pscustomobject]@{Label="$($image.ImageIndex) — $($image.ImageName)";Index=$image.ImageIndex})}
            if($edition.Items.Count -eq 0) {throw 'Nenhuma edição encontrada.'}
            $edition.SelectedIndex=0;$script:LoadedIso=$script:Job.Iso
            $status.Text='Edições carregadas. Revise as opções e clique em Criar ISO.';$tabs.SelectedTab=$inputPage
        } else {
            $script:LastOutput=[IO.Path]::GetFullPath($script:Job.Output)
            if(-not(Test-Path -LiteralPath $script:LastOutput)) {throw 'A ISO final não foi encontrada.'}
            $openOutput.Enabled=$true;$status.Text='ISO criada com sucesso.'
            [void][Windows.Forms.MessageBox]::Show("ISO criada:$($nl)$script:LastOutput",'Concluído')
        }
        foreach($reader in $script:Readers) {$reader.Dispose()};$script:Readers=@()
    } catch {
        if($script:Job.Process.HasExited) {
            $script:Job.Handled=$true;Set-Busy $false
            foreach($reader in $script:Readers) {$reader.Dispose()};$script:Readers=@()
        }
        $status.Text='Falha. Consulte os logs.'
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Falha na operação')
    }
})
$form.Add_FormClosing({
    param($sender,$eventArgs)
    if($script:Job -and -not $script:Job.Process.HasExited) {
        $eventArgs.Cancel=$true
        [void][Windows.Forms.MessageBox]::Show('Aguarde a conclusão para evitar interromper uma imagem montada.','Operação em andamento')
    }
})
$timer.Start()
try {[void]$form.ShowDialog()} finally {
    $timer.Stop();$timer.Dispose()
    foreach($reader in $script:Readers) {$reader.Dispose()}
    $form.Dispose()
}
