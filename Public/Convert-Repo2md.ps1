function Convert-Repo2md {
  <#
  .SYNOPSIS
    Converts a repository to a markdown file.
  .DESCRIPTION
    Provide a readable snapshot of the repository's structure and contents,
    considering ignore patterns specified in `.gitignore` and `.git/info/exclude` files,
    as well as user-defined include and exclude options.
  .LINK
    https://github.com/chadnpc/Repo2md/blob/main/Public/Convert-Repo2md.ps1
  .EXAMPLE
    Convert-Repo2md -Path "C:\path\to\repo" | Out-File "C:\path\to\output.md"
    Converts the repository at the specified path to a markdown file.
  #>
  [CmdletBinding(DefaultParameterSetName = "Path")]
  [OutputType([string])]
  param (
    # Specifies a path to the repo. Unlike the Path parameter, the value of the LiteralPath parameter is
    # used exactly as it is typed. No characters are interpreted as wildcards. If the path includes escape characters,
    # enclose it in single quotation marks. Single quotation marks tell Windows PowerShell not to interpret any
    # characters as escape sequences.
    [Parameter(Mandatory = $true,
      Position = 0,
      ParameterSetName = "LiteralPath",
      ValueFromPipeline = $false,
      HelpMessage = "Literal path to one or the repo.")]
    [Alias("lp")]
    [ValidateNotNullOrWhiteSpace()]
    [string]$LiteralPath,

    # Specifies a path to the repo.
    [Parameter(Mandatory = $true,
      Position = 0,
      ParameterSetName = "Path",
      ValueFromPipeline = $true,
      ValueFromPipelineByPropertyName = $true,
      HelpMessage = "Path to the repo.")]
    [Alias("p")]
    [ValidateNotNullOrEmpty()]
    [string]$Path
  )

  begin {
    # $moduledata = [PsModuleBase]::ReadModuledata("Repo2md")
    $workdir = [IO.Path]::Combine(((Get-Module Repo2md -ListAvailable -Verbose:$false).ModuleBase), 'Private')
  }

  process {
    Push-Location -Path $workdir
    if ((Get-Command cargo -ErrorAction SilentlyContinue)) {
      cargo run $([PsModuleBase]::GetUnResolvedPath($Path))
    } else {
      $pscmdlet.ThrowTerminatingError(
        [System.Management.Automation.ErrorRecord]::new(
          [System.Management.Automation.ItemNotFoundException]::new("cargo not found"),
          "Cargo_Not_Found",
          [System.Management.Automation.ErrorCategory]::ObjectNotFound,
          $null
        )
      )
    }
    Pop-Location
    $o_F = (ls $workdir *.md)[0].FullName
    if ($o_F -and ![string]::IsNullOrWhiteSpace($o_F)) {
      $content = [IO.File]::ReadAllText($o_F)
      Remove-Item $o_F -ErrorAction Stop
      return $content
    }
    $pscmdlet.ThrowTerminatingError(
      [System.Management.Automation.ErrorRecord]::new(
        [System.IO.InvalidDataException]::new("Failed to convert repo to md"),
        "Failed_to_convert_repo_to_md",
        [System.Management.Automation.ErrorCategory]::OperationStopped,
        $null
      )
    )
  }
}