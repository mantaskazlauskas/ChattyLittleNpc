# Load the necessary .NET assembly
Add-Type -AssemblyName System.IO.Compression.FileSystem

$source = (Get-Location).Path
$tocFile = "$source\ChattyLittleNpc.toc"
$excludeExtensions = @(".ps1", ".zip", ".gitignore", ".json")
$excludeFolders = @(".git", ".vscode")

# Read the .toc file and extract the version number
$version = Select-String -Path $tocFile -Pattern '## Version: (\d+\.\d+\.\d+)' | ForEach-Object { $_.Matches[0].Groups[1].Value }

# Set the destination zip file name with the version number
$destination = "..\ChattyLittleNpc_$version.zip"

# Create a temporary directory to hold the files to be zipped
$tempDir = New-Item -ItemType Directory -Path (Join-Path $env:TEMP "ChattyLittleNpc_$version")

# Create the root folder inside the temporary directory
$rootFolder = New-Item -ItemType Directory -Path (Join-Path $tempDir.FullName "ChattyLittleNpc")

# Ensure that the source path ends with a backslash
if (-not $source.EndsWith('\')) {
    $source += '\'
}

# Create a list of items to include in the zip
$itemsToInclude = Get-ChildItem -Path $source -Recurse | Where-Object {
    # Exclude .git and .vscode related files and folders
    -not ($excludeExtensions -contains $_.Extension) -and
    -not ($excludeFolders -contains $_.PSIsContainer -and $excludeFolders -contains $_.Name)
}

# Copy the items to the temporary directory
foreach ($item in $itemsToInclude) {
    $destinationPath = $item.FullName.Replace($source, "$rootFolder\")
    if ($item.PSIsContainer) {
        New-Item -ItemType Directory -Path $destinationPath -Force
    } else {
        Copy-Item -Path $item.FullName -Destination $destinationPath -Force
    }
}

# Create the zip file
[System.IO.Compression.ZipFile]::CreateFromDirectory($tempDir.FullName, $destination)

# Clean up the temporary directory
Remove-Item -Path $tempDir.FullName -Recurse -Force