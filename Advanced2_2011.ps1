# -----------------------------------------------------------------------------
# Script: Get-ServiceDependency.ps1
# Author: Jason Hofferle
# Date: 04/05/2011
# Version: 1.0.0
# Comments:
#  This script uses the Get-ServiceDependency function to query for service
#  dependencies and flatten the information into a collection of custom
#  objects. Those objects can then be run through additional processing, or in
#  this case, formatted to reflect the output specified in the event scenario.
# -----------------------------------------------------------------------------

Function Get-ServiceDependency
{
  Param
  (
    [string]$ComputerName = $Env:ComputerName
  )

  Process
  {
    $ServiceCollection = @()
    $services = Get-Service -ComputerName $ComputerName |
      Where-Object {$_.Status -eq 'Running'}

    foreach ($service in $services)
    {
      foreach ($dependentService in $service.DependentServices)
      {
        $ServiceCollection += New-Object PSObject -Property @{
        ServiceName=$service.Name
        DependentServiceName=$dependentService.Name
        DependentServiceStatus=$dependentService.Status
        ComputerName=$ComputerName}
      }
    }

    Write-Output $ServiceCollection
  }
}

# Query AD DS for server names
$serverNames = ([ADSISearcher]"ObjectCategory=computer").FindAll() |
Where-Object {$_.properties.operatingsystem -like '*server*'} |
ForEach-Object {$_.Properties.cn}

# Alternative name list generation using AD Cmdlets
# $serverNames = Get-ADComputer -Filter "OperatingSystem -like '*server*'" |
# ForEach-Object {$_.Name}

$serverNames | ForEach-Object {Get-ServiceDependency -ComputerName $_} |
Group-Object ComputerName |
ForEach-Object {
  Write-Output $_.Name`r$(Get-Date)

  Format-Table DependentServiceName,DependentServiceStatus `
               -GroupBy Servicename `
               -InputObject $_.Group `
               -AutoSize

  # Write blank lines for separation between servers
  Write-Output $(("`r`n")*5)
}
