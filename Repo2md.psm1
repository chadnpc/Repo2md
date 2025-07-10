#!/usr/bin/env pwsh
enum FileType {
  Text
  Binary
  SymbolicLink
}

class Repo2md {
  [string]$Repo
  [string[]]$Include
  [string[]]$Ignore

  Repo2md([string]$repo, [string[]]$include, [string[]]$ignore) {
    $this.Repo = $repo
    $this.Include = $include
    $this.Ignore = $ignore
  }
  [string] GenerateMarkdown() {
    return $this.GenerateMarkdown([IO.Path]::combine((Resolve-Path .).Path, ([IO.Path]::GetDirectoryName($this.repo) + '_repo2md.md')))
  }
  [string] GenerateMarkdown([string]$outputFile) {
    if (![IO.Directory]::Exists($this.Repo)) {
      throw [System.IO.DirectoryNotFoundException]::new("Repository path does not exist: $($this.Repo.Path)")
    }
    Write-Verbose "Repository Path: $($this.Repo.Path)"
    $gitignoreRules = $this.BuildGitIgnoreRules($this.Repo.Path)

    $walker = Get-ChildItem -Path $this.Repo.Path -Recurse -Directory -ErrorAction SilentlyContinue, $this.Repo.Path -Recurse -File -ErrorAction SilentlyContinue

    $output = New-Object System.Text.StringBuilder
    $output.AppendLine(('#' + " ``$(Split-Path -Leaf -Path $this.Repo.Path)``" + "`n"))

    Write-Progress -Activity "Traversing Repository" -Status "Starting..."

    $filteredEntries = @{}
    $itemCount = 0
    foreach ($item in $walker) {
      $itemCount++
    }
    $processedCount = 0

    foreach ($item in $walker) {
      $processedCount++
      $relativePath = $item.FullName.Substring($this.Repo.Path.Length).TrimStart([char]92) # Trim leading slash and convert to relative path
      Write-Progress -Activity "Traversing Repository" -Status "Processing: $relativePath" -PercentComplete (($processedCount / $itemCount) * 100)

      $isIgnored = $this.IsPathIgnored($relativePath, $gitignoreRules)
      $isIncluded = $this.IsPathIncluded($relativePath, $this.Include)

      if ($isIgnored -and !$isIncluded) {
        if ($item.PSIsContainer) {
          # Skip ignored directories - Get-ChildItem -Recurse already handles this partially but for clarity we keep this logic
          continue
        }
        continue
      }

      if ($item.PSIsContainer) {
        $dirEntries = @()
        foreach ($entry in Get-ChildItem -Path $item.FullName -ErrorAction SilentlyContinue) {
          $entryRelativePath = $entry.FullName.Substring($this.Repo.Path.Length).TrimStart([char]92)
          if (!$this.IsPathIgnored($entryRelativePath, $gitignoreRules)) {
            $dirEntries += $entry
          }
        }
        $filteredEntries[$item.FullName] = $dirEntries

        $dirName = $relativePath
        $headerLevel = ($relativePath -split '\\').Count + 2 # Assuming backslash as path separator in Windows, adjust if needed
        $output.AppendLine(('#' * $headerLevel + ' Directory `' + $dirName + "/` `n"))
        $output.AppendLine(('```' + "sh`n"))
        $ignoredDirs = [System.Collections.Generic.HashSet[string]]::new()
        $treeOutput = $this.GenerateTreeOutput($item.FullName, $filteredEntries, $ignoredDirs)
        $output.AppendLine($treeOutput)
        $output.AppendLine(('```' + "`n"))
      } else {
        # It's a file
        $fileType = $this.DetectFileType($item.FullName)
        if ($fileType -eq [FileType]::Text) {
          $sourceFile = $relativePath
          $output.AppendLine("### Source file: ``$sourceFile```n")

          $fileExtension = [System.IO.Path]::GetExtension($item.FullName).TrimStart('.')
          $codeBlockLang = switch ($fileExtension) {
            "rs" { "rust"; break }
            "md" { "markdown"; break }
            default { $fileExtension }
          }

          $output.AppendLine(('```' + $codeBlockLang + "`n"))
          try {
            $content = Get-Content -Path $item.FullName -Raw -ErrorAction Stop
            $output.AppendLine($content)
          } catch {
            Write-Warning "Failed to read file: $($item.FullName), error: $_"
            # $output.AppendLine("[Failed to read file contents]") # Optional placeholder
          }
          $output.AppendLine(('```' + "`n"))
        } elseif ($fileType -eq [FileType]::Binary) {
          Write-Warning "Binary file not ignored by .gitignore: $relativePath"
          # $output.AppendLine("Binary file ``$relativePath`` detected, consider adding it to .gitignore.`n") # Optional warning in output
        } elseif ($fileType -eq [FileType]::SymbolicLink) {
          Write-Warning "Symbolic link not ignored by .gitignore: $relativePath"
          # $output.AppendLine("Symbolic link ``$relativePath`` detected, consider adding it to .gitignore.`n") # Optional warning in output
        }
      }
    }
    Write-Progress -Activity "Traversing Repository" -Completed -Status "Completed!"
    [string]$output = ($output.ToString().TrimEnd("`n") + "`n")
    try {
      Set-Content -Path $outputFile -Value $output -Encoding UTF8 -ErrorAction Stop
      Write-Host "Markdown output written to: $outputFile"
    } catch {
      Write-Error "Failed to write output file: $outputFile, error: $_"
      return [string]::Empty
    }
    return $output
  }

  [string] GenerateTreeOutput([string]$dirPath, [Hashtable]$filteredEntries, [System.Collections.Generic.HashSet[string]]$ignoredDirs) {
    $output = New-Object System.Text.StringBuilder
    [void]$this.TreeRecursive($dirPath, 0, $filteredEntries, $ignoredDirs, ([ref]$output))
    return $output.ToString()
  }

  [string] TreeRecursive([string]$dirPath, [int]$level, [Hashtable]$filteredEntries, [System.Collections.Generic.HashSet[string]]$ignoredDirs, [ref]$output) {
    if (!$filteredEntries.ContainsKey($dirPath)) {
      return [string]::Empty
    }
    $entries = $filteredEntries[$dirPath]; $files = @(); $dirs = @()
    foreach ($entry in $entries) {
      if ($entry.PSIsContainer) {
        $dirs += $entry
      } else {
        $files += $entry
      }
    }

    $dirs = $dirs | Sort-Object Name
    $files = $files | Sort-Object Name

    for ($i = 0; $i -lt $dirs.Count; $i++) {
      $entry = $dirs[$i]
      $path = $entry.FullName
      if ($ignoredDirs.Contains($path)) {
        continue
      }
      $name = $entry.Name

      if ($i -eq $dirs.Count - 1 -and $files.Count -eq 0) {
        $prefix = "`-- "
      } else {
        $prefix = "|-- "
      }

      $output.Value.AppendLine(("    " * $level) + $prefix + "$name/")
      $this.TreeRecursive($path, $level + 1, $filteredEntries, $ignoredDirs, ([ref]$output))
    }

    for ($i = 0; $i -lt $files.Count; $i++) {
      $entry = $files[$i]
      $path = $entry.FullName
      if ($ignoredDirs.Contains($path)) {
        continue
      }
      $name = $entry.Name

      $fileType = $this.DetectFileType($path)
      $fileTypeStr = switch ($fileType) {
        [FileType]::Text { "[text]"; break }
        [FileType]::Binary { "[binary]"; break }
        [FileType]::SymbolicLink { "[symlink]"; break }
      }

      if ($i -eq $files.Count - 1) {
        $prefix = "`-- "
      } else {
        $prefix = "|-- "
      }
      $output.Value.AppendLine(("    " * $level) + $prefix + "$name    $fileTypeStr")
    }
    return $output.Value
  }

  [FileType] DetectFileType([string]$filePath) {
    if ((Test-Path -Path $filePath -PathType SymbolicLink)) {
      return [FileType]::SymbolicLink
    } else {
      try {
        Get-Content -Path $filePath -Encoding UTF8 -ErrorAction Stop | Out-Null
        return [FileType]::Text
      } catch {
        return [FileType]::Binary
      }
    }
  }

  [string[]] BuildGitIgnoreRules() {
    $gitignoreRules = @()

    # Add command-line ignore patterns
    foreach ($ignorePattern in $this.Ignore) {
      $pattern = $ignorePattern
      if ($pattern.EndsWith('/')) {
        $pattern += '**'
      }
      $gitignoreRules += $pattern
    }

    # Add .git/ to ignore list
    $gitignoreRules += ".git/**"

    # Add content of .gitignore
    $gitignorePath = Join-Path -Path $this.Repo -ChildPath ".gitignore"
    if (Test-Path -Path $gitignorePath) {
      $gitignoreRules += Get-Content -Path $gitignorePath -ErrorAction SilentlyContinue
    }

    # Add content of .git/info/exclude
    $excludePath = Join-Path -Path $this.Repo -ChildPath ".git/info/exclude"
    if (Test-Path -Path $excludePath) {
      $gitignoreRules += Get-Content -Path $excludePath -ErrorAction SilentlyContinue
    }
    return $gitignoreRules
  }

  [bool] IsPathIgnored([string]$relativePath, [string[]]$gitignoreRules) {
    foreach ($rule in $gitignoreRules) {
      if ([WildcardPattern]::new($rule, "IgnoreCase").IsMatch($relativePath)) {
        return $true
      }
    }
    return $false
  }

  [bool] IsPathIncluded([string]$relativePath, [string[]]$includePatterns) {
    if ($includePatterns -and $includePatterns.Count -gt 0) {
      foreach ($pattern in $includePatterns) {
        if ($relativePath.StartsWith($pattern)) {
          return $true
        }
      }
      return $false # If include patterns are provided, and none match, then it's not included.
    }
    return $false # No include patterns provided, so it's not considered explicitly included.
  }
}

$typestoExport = @(
  [Repo2md]
)
$TypeAcceleratorsClass = [PsObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
foreach ($Type in $typestoExport) {
  if ($Type.FullName -in $TypeAcceleratorsClass::Get.Keys) {
    $Message = @(
      "Unable to register type accelerator '$($Type.FullName)'"
      'Accelerator already exists.'
    ) -join ' - '

    [System.Management.Automation.ErrorRecord]::new(
      [System.InvalidOperationException]::new($Message),
      'TypeAcceleratorAlreadyExists',
      [System.Management.Automation.ErrorCategory]::InvalidOperation,
      $Type.FullName
    ) | Write-Debug
  }
}
# Add type accelerators for every exportable type.
foreach ($Type in $typestoExport) {
  $TypeAcceleratorsClass::Add($Type.FullName, $Type)
}
# Remove type accelerators when the module is removed.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
  foreach ($Type in $typestoExport) {
    $TypeAcceleratorsClass::Remove($Type.FullName)
  }
}.GetNewClosure();

$scripts = @();
$Public = Get-ChildItem "$PSScriptRoot/Public" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += Get-ChildItem "$PSScriptRoot/Private" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += $Public

foreach ($file in $scripts) {
  try {
    if ([string]::IsNullOrWhiteSpace($file.fullname)) { continue }
    . "$($file.fullname)"
  } catch {
    Write-Warning "Failed to import function $($file.BaseName): $_"
    $host.UI.WriteErrorLine($_)
  }
}

$Param = @{
  Function = $Public.BaseName
  Cmdlet   = '*'
  Alias    = '*'
  Verbose  = $false
}
Export-ModuleMember @Param
