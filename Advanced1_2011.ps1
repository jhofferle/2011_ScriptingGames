# -----------------------------------------------------------------------------
# Script: Get-ProcessModuleVersion.ps1
# Author: Jason Hofferle
# Date: 04/04/2011
# Version: 1.0.0
# Comments:
#  This script is based around the Get-ProcessModuleVersion function. This
#  function was designed with the intent of using it with the pipeline to
#  generate the output specified in the event scenario.
#  This approach increases code reuse, while reducing complexity by
#  leveraging the flexibility of the PowerShell pipeline.
# -----------------------------------------------------------------------------

Function Get-ProcessModuleVersion
{
  [CmdletBinding()]
  Param
  (
    [Parameter(
    Position=0,
    ValueFromPipeLine=$true)]
    [String[]]
    $ComputerName = $Env:ComputerName,

    [String]
    $ProcessName = "Notepad",

    [String]
    $ModuleDescription = "Windows Spooler Driver",

    [String]
    $Log = ''
  )

  Process
  {
    $ScriptBlock = {
      Param(
        $Name=$ProcessName,
        $Description=$ModuleDescription)

      $modules = Get-Process -Module -Name $Name
      foreach ($module in $modules)
      {
        if ($module.Description -eq $Description)
          {
            # Add-Member used instead of hashtable to keep properties in order
            $customObject = New-Object PSObject
            $customObject | Add-Member NoteProperty Computer $Env:ComputerName
            $customObject | Add-Member NoteProperty ModuleName $module.ModuleName
            $customObject | Add-Member NoteProperty Size $module.Size
            $customObject | Add-Member NoteProperty FileName $module.FileName
            $customObject | Add-Member NoteProperty FileVersion $module.FileVersion

            Write-Output $customObject
          }
      }
    }

    Invoke-Command -ComputerName $ComputerName `
                   -ScriptBlock $ScriptBlock `
                   -ArgumentList $ProcessName,$ModuleDescription `
                   -HideComputerName `
                   -ErrorAction SilentlyContinue `
                   -ErrorVariable +err
  }

  End
  {
    if (($Log -ne '') -and (Test-Path $Log -IsValid))
    {
      foreach ($errEntry in $err)
      {
        Add-Content -Path $Log -Value $errEntry`r`n
      }
    }
  }

  <#
      .Synopsis
      Returns version information about modules used by a process.

      .Description
      The Get-ProcessModuleVersion function returns version information about
      modules used by a process. This function relies on PowerShell remoting.

      .parameter ComputerName
      Gets the module version information on the specified computers.
      The default is the local computer name.

      .parameter ProcessName
      Specifies the process to retrive module version information from.
      The default is the notepad process.

      .parameter ModuleDescription
      Specifies the name of the module to get version information about.
      The default is the Windows Spooler Driver module.

      .parameter Log
      Specifies a path and filename for errors to be logged.

      .Example
      Get-ProcessModuleVersion

      Description
      -----------
      This command gets infomation about the Windows Spooler Driver module
      running in the notepad process on the local computer.

      .Example
      Get-ProcessModuleVersion -ProcessName spoolsv -ModuleDescription "Windows SPINF"

      Description
      -----------
      This command gets infomation about the Windows SPINF module loaded by the
      spoolsv process on the local computer.

      .Example
      Get-ProcessModuleVersion -ComputerName dc1,dc2 -Log errors.txt

      Description
      -----------
      This command gets infomation about the Windows Spooler Driver module
      running in the notepad process on the computer DC1 and DC2, and logs
      errors to the errors.txt file in the current directory.
  #>
}

# Default usage for 2011 Scripting Games
Get-ProcessModuleVersion | ConvertTo-Csv -NoTypeInformation

# Usage for reading AD DS to retrieve the list of computers to query
# $ComputerList = ([ADSISearcher]"ObjectCategory=computer").FindAll() | ForEach-Object {$_.Properties.cn}
# Get-ProcessModuleVersion -ComputerName $ComputerList -Log errorLog.txt
