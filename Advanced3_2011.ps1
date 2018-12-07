# -----------------------------------------------------------------------------
# Script: Get-LoggedEvents.ps1
# Author: Jason Hofferle
# Date: 04/06/2011
# Version: 1.0.0
# Comments: This script is based around the Get-LoggedEvent function. This
#  function was designed with the intent that gathering a list of computer
#  names and formatting output would be done by other cmdlets in the pipeline.
#  These type of tasks gain so much speed through PowerShell remoting that an
#  optional parameter was added that will use fan-out remoting instead of
#  querying each computer individually.
# -----------------------------------------------------------------------------

Function Get-LoggedEvent
{
  [CmdletBinding()]
  Param
  (
    [String[]]
    $ComputerName = $Env:ComputerName,

    [Int]
    $NumberOfEvents = 1,

    [Int]
    $NumberOfDays = 0,

    [Int]
    $EventID,

    [ValidateSet("Critical","Error","Warning","Informational")]
    [String]
    $Severity,

    [Switch]
    $UseRemoting = $false
  )

  Begin
  {
    # For converting human-friendly text to numbers used in query
    $LevelTable = @{
      Critical=1
      Error=2
      Warning=3
      Informational=4}

    # Specify a scriptblock that can be run locally, or passed to
    # Invoke-Command when using PowerShell remoting.
    $ScriptBlock = {

      Param
      (
        [String]$Name,
        [Int]$NumOfEvents,
        [Int]$NumOfDays,
        [Int]$ID,
        [Int]$Level
      )

      $filter = @{LogName=""}

      if ($ID)
      {
        $filter.Add("ID",$ID)
      }

      if ($Level)
      {
        $filter.Add("Level",$Level)
      }

      if (Test-Connection -ComputerName $Name -Count 1 -Quiet)
      {
        $logNames = Get-WinEvent -ComputerName $Name -ListLog * |
          Where-Object {$_.RecordCount -and $_.IsEnabled}

        foreach ($log in $lognames)
        {
          $filter.LogName = $log.LogName

          Get-WinEvent -ComputerName $Name `
                       -FilterHashTable $filter `
                       -MaxEvents $NumOfEvents `
                       -ErrorAction SilentlyContinue |
            Where-Object {$_.TimeCreated -ge (Get-Date).AddDays(-$NumOfDays).Date}
        }
      }
    }
  }

  Process
  {
    if ($UseRemoting)
    {
      # Pass the entire array of computer names to Invoke-Command
      Invoke-Command -ComputerName $ComputerName `
                     -ScriptBlock $ScriptBlock `
                     -ArgumentList 'localhost', `
                                   $NumberOfEvents, `
                                   $NumberOfDays, `
                                   $EventID, `
                                   $LevelTable[$Severity]
    }
    else
    {
        # Unwrap $ComputerName array and invoke the scriptblock for each computer
        foreach ($Name in $ComputerName)
        {
          &$ScriptBlock -Name $Name `
                        -NumOfEvents $NumberOfEvents `
                        -NumOfDays $NumberOfDays `
                        -ID $EventID `
                        -Level $LevelTable[$Severity]
        }
    }
  }
  <#
      .Synopsis
      Returns recent events from local and remote computers.

      .Description
      The Get-LoggedEvent function queries event logs and event trace logs and
      returns the most recent events from each log.

      .parameter ComputerName
      Gets the event information on the specified computers.
      The default is the local computer name.

      .parameter NumberOfEvents
      Specifies the number of events to return from each log.
      The default is to return only the latest event.

      .parameter NumberOfDays
      Specifies the number of past days to query for events.
      The default is 0, which only returns events logged today.

      .parameter EventID
      Gets only the events with the specified event ID.
      The default is all events.

      .parameter Severity
      Gets only the events with the specified Level. Valid values are Critical,
      Error, Warning and Informational.
      The default is all types.

      .parameter UseRemoting
      Instead of querying each computer individually, use PowerShell remoting
      to connect to the remote systems specified in the ComputerName property.
      The default is to not use remoting.

      .Example
      Get-LoggedEvent

      Description
      -----------
      This command gets the latest event from each event log on the local
      computer, if there have been events logged today.

      .Example
      Get-LoggedEvent -NumberOfEvents 10 -NumberOfDays 3 -Severity Warning

      Description
      -----------
      This command gets the latest 10 Warning events from each event log that
      have been logged in the last three days.

      .Example
      Get-LoggedEvent -ComputerName DC1,DC2,WIN7 -UseRemoting

      Description
      -----------
      This command gets event information from the three computers specified
      using PowerShell remoting.
  #>
}

# Query AD DS for server names
$serverNames = ([ADSISearcher]"ObjectCategory=computer").FindAll() |
Where-Object {$_.properties.operatingsystem -like '*server*'} |
ForEach-Object {$_.Properties.cn}

# Default usage for 2011 Scripting Games
Get-LoggedEvent -ComputerName $serverNames |
  Format-Table LogName, TimeCreated, ProviderName, Id, Message
