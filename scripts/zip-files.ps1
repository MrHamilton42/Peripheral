function Write-FWZip {
    param([string]$Destination,[System.Collections.IDictionary]$Files)
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    # Explicit ZIP entry names use '/', independently of the Windows host.
    if([IO.File]::Exists($Destination)){[IO.File]::Delete($Destination)}
    $archive=[IO.Compression.ZipFile]::Open($Destination,[IO.Compression.ZipArchiveMode]::Create)
    try{
        foreach($entryName in @($Files.Keys | Sort-Object)){
            if($entryName.Contains('\') -or $entryName.StartsWith('/') -or $entryName.Contains('..')){throw 'Unsafe archive entry name.'}
            $entry=$archive.CreateEntry($entryName,[IO.Compression.CompressionLevel]::Optimal)
            $inputStream=[IO.File]::OpenRead($Files[$entryName]);$outputStream=$entry.Open()
            try{$inputStream.CopyTo($outputStream)}finally{$inputStream.Dispose();$outputStream.Dispose()}
        }
    }finally{$archive.Dispose()}
}
