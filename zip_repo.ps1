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
    $destinationPath = Join-Path $rootFolder.FullName -ChildPath $item.FullName.Substring($source.Length + 1)
    if ($item.PSIsContainer) {
        New-Item -ItemType Directory -Path $destinationPath -Force
    } else {
        Copy-Item -Path $item.FullName -Destination $destinationPath -Force
    }
}

# Compress the temporary directory into a zip file
Compress-Archive -Path $rootFolder.FullName -DestinationPath $destination

# Remove the temporary directory
Remove-Item -Path $tempDir.FullName -Recurse -Force

Write-Output "Zipping completed. The zip file is located at $destination"