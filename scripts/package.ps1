param([switch]$CurseForgeReview)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$metadata=Get-Content -LiteralPath (Join-Path $projectRoot 'package.json') -Raw | ConvertFrom-Json
if($metadata.addonVersion -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid package version.'}
. (Join-Path $PSScriptRoot 'zip-files.ps1')
$source=Join-Path $projectRoot 'addon\ForeverWorkspace'
$files=@('ForeverWorkspace.toc','Geometry.lua','Layout.lua','Configuration.lua','Core.lua','Configurator.html','README.txt','CONFIGURATION.md','API.md','LICENSE-DECISION.txt','Assets/Peripheral.svg','Assets/Peripheral.png','Assets/Peripheral.tga')
if(Test-Path -LiteralPath (Join-Path $source 'LICENSE.txt')){
    $files=@($files | Where-Object {$_ -ne 'LICENSE-DECISION.txt'})+@('LICENSE.txt')
    if(Test-Path -LiteralPath (Join-Path $source 'ARTWORK-NOTICE.txt')){$files+=@('ARTWORK-NOTICE.txt')}
}
$stageRoot=Join-Path $projectRoot ('dist\stage-'+[Guid]::NewGuid().ToString('N'))
$stage=Join-Path $stageRoot 'ForeverWorkspace'
New-Item -ItemType Directory -Path $stage -Force | Out-Null
foreach($file in $files){
    $target=Join-Path $stage $file
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $source $file) -Destination $target
}
$readme=Join-Path $stage 'README.txt'
$readmeText=[IO.File]::ReadAllText($readme)
$linkBlock='(?s)\[PERIPHERAL_HELPER_LINK\].*?\[/PERIPHERAL_HELPER_LINK\]\r?\n?'
if($CurseForgeReview){
    $html=Join-Path $stage 'Configurator.html'
    $htmlText=[IO.File]::ReadAllText($html)
    $htmlText=[regex]::Replace($htmlText,'(?s)<details id="optionalHelper">.*?</details>','')
    [IO.File]::WriteAllText($html,$htmlText,[Text.UTF8Encoding]::new($false))
    $readmeText=[regex]::Replace($readmeText,$linkBlock,'')
    if($htmlText -match 'github\.com/[^"\s]+/releases' -or $readmeText -match 'github\.com/[^"\s]+/releases'){throw 'Helper download links are excluded from the CurseForge review build.'}
}else{$readmeText=$readmeText.Replace('[PERIPHERAL_HELPER_LINK]','').Replace('[/PERIPHERAL_HELPER_LINK]','')}
[IO.File]::WriteAllText($readme,$readmeText,[Text.UTF8Encoding]::new($false))
$geometry=Get-Content -LiteralPath (Join-Path $stage 'Geometry.lua') -Raw
if($geometry -notmatch 'FW\.Geometry = nil' -or $geometry -match 'FW\.Geometry\s*=\s*\{'){throw 'Only neutral geometry may be packaged.'}
$suffix=if($CurseForgeReview){'-curseforge-review.zip'}else{'-beta-addon-only.zip'}
$destination=Join-Path $projectRoot ('dist\Peripheral-'+$metadata.addonVersion+$suffix)
$zipFiles=[ordered]@{}
foreach($file in $files){$zipFiles['ForeverWorkspace/'+$file]=Join-Path $stage $file}
Write-FWZip -Destination $destination -Files $zipFiles
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead($destination)
try{
    $entries=@($zip.Entries | Where-Object {$_.Name} | ForEach-Object {if($_.FullName.Contains('\')){throw 'ZIP entries must use forward slashes.'};$_.FullName})
    foreach($entry in $entries){if(-not $entry.StartsWith('ForeverWorkspace/') -or $entry.Substring(17) -notin $files){throw ('Unexpected archive entry: '+$entry)}}
    if($entries.Count -ne $files.Count -or 'ForeverWorkspace/ForeverWorkspace.toc' -notin $entries){throw 'Addon package root/manifest is invalid.'}
    'Verified addon-only entries: '+$entries.Count
}finally{$zip.Dispose()}
$hasher=[Security.Cryptography.SHA256]::Create();$stream=[IO.File]::OpenRead($destination)
try{$hash=([BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-','')}finally{$stream.Dispose();$hasher.Dispose()}
'Package: '+$destination
'SHA256: '+$hash
