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
    ($_.FullName -notmatch "\\\.git") -and
    ($_.FullName -notmatch "\\\.vscode") -and
    # Exclude files with specified extensions
    ($excludeExtensions -notcontains $_.Extension)
}

# Copy the items to the root folder inside the temporary directory, preserving the directory structure
foreach ($item in $itemsToInclude) {
    # Calculate the relative path
    $relativePath = $item.FullName.Substring($source.Length)
    $relativePath = $relativePath.TrimStart('\', '/')
    
    # Build the destination path
    $destinationPath = Join-Path $rootFolder.FullName -ChildPath $relativePath

    if ($item.PSIsContainer) {
        New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
    } else {
        Copy-Item -Path $item.FullName -Destination $destinationPath -Force
    }
}

# Compress the root folder, including the directory structure using .NET ZipFile class
[System.IO.Compression.ZipFile]::CreateFromDirectory($rootFolder.FullName, $destination)

# Remove the temporary directory
Remove-Item -Path $tempDir.FullName -Recurse -Force

Write-Output "Zipping completed. The zip file is located at $destination"