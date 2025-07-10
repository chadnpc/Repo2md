function Convert-Repo2md {
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
    cargo run $([PsModuleBase]::GetUnResolvedPath($Path))
    Pop-Location
    $o_F = (ls $workdir *.md)[0].FullName
    if ($o_F -and ![string]::IsNullOrWhiteSpace($o_F)) {
      $content = [IO.File]::ReadAllText($o_F)
      Remove-Item $o_F -ErrorAction Stop
      return $content
    }
    throw "Failed to convert repo to md"
  }
}