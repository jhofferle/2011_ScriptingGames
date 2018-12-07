# -----------------------------------------------------------------------------
# Script: Get-SvcHostProcess.ps1
# Author: Jason Hofferle
# Date: 04/07/2011
# Version: 1.0.0
# Comments:
#  This script uses WMI to associate services with svchost processes. The
#  Get-SvcHostProcess function returns process objects with an additional
#  property containing the service objects running under that process. Various
#  PowerShell cmdlets can then be used to format the objects into the desired
#  reports. Although it was not required by the scenario, the function includes
#  a ComputerName parameter and can be run against remote systems.
# -----------------------------------------------------------------------------

Function Get-SvcHostProcess
{
    Param
    (
        [String]
        $ComputerName = $Env:ComputerName
    )

    # Using WMI because Get-Service and Get-Process do not return the
    # required properties

    $serviceList = Get-WmiObject -Class Win32_Service `
                                 -ComputerName $ComputerName `
                                 -Filter "ProcessId > 0" |
      Sort-Object ProcessId | Group-Object ProcessId

    $processList = Get-WmiObject -Class Win32_Process `
                                 -ComputerName $ComputerName  `
                                 -Filter "Name = 'svchost.exe'"

    foreach ($process in $processList)
    {
        # Find the group of services that match the current svchost ProcessId and
        # add that collection of services to the process object as a property

        $serviceGroup = $serviceList | Where-Object {$_.Name -eq $process.ProcessId}
        $process | Add-Member NoteProperty Services $serviceGroup.Group

        Write-Output $process
    }
}


# List all instances of SvcHost process
Get-SvcHostProcess |
    Sort-Object VirtualSize -Descending |
    Format-Table @{Label='VirtualSize(MB)'
                   Align='Right'
                   Expression={"{0:N2}" -f ($_.VirtualSize/1MB)}}, `

                 @{Label='WorkingSet(MB)'
                   Align='Right'
                   Expression={"{0:N2}" -f ($_.WorkingSetSize/1MB)}}, `

                 @{Label='PageFaults'
                   Align='Right'
                   Expression={"{0:N0}" -f $_.PageFaults}}, `

                 CommandLine -AutoSize


# List all services running in each SvcHost process
Get-SvcHostProcess |
    Select-Object VirtualSize -ExpandProperty Services |
    Sort-Object ProcessId |
    Format-Table ProcessId, VirtualSize, StartMode, State, Name -GroupBy PathName


# Export objects to a CSV file
Get-SvcHostProcess |
  Select-Object VirtualSize, PageFaults -ExpandProperty Services |
  Select-Object * -ExcludeProperty "__*" |
  Sort-Object ProcessId |
  Export-Csv report.csv -NoTypeInformation
