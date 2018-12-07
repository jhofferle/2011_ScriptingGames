# -----------------------------------------------------------------------------
# Script: Test-Win7Requirements
# Author: Jason Hofferle
# Date: 04/09/2011
# Version: 1.0.0
# Comments:
#  This script is based on the Test-Win7Requirements function. This function
#  uses WMI to check the processor, memory and free disk space to verify they
#  meet the requirements to run Windows 7. The dxdiag utility is used to
#  determine video card capabilities. The official Windows 7 requirements are
#  used as the default values to check against, but different values can be
#  specified through parameters.
# -----------------------------------------------------------------------------

Function Test-Win7Requirements
{
  [CmdletBinding()]
  Param
  (
    [Parameter(
    Position=0,
    ValueFromPipeLine=$true,
    ValueFromPipelineByPropertyName=$true)]
    [alias("CN","MachineName")]
    [String]
    $ComputerName = $ENV:ComputerName,

    [Switch]
    $SkipVideoCheck = $false,

    [long]
    $ClockSpeedRequirement = 1000,

    [long]
    $MemoryRequirement32bit = 1GB,

    [long]
    $MemoryRequirement64bit = 2GB,

    [long]
    $FreeSpaceRequirement32bit = 16GB,

    [long]
    $FreeSpaceRequirement64bit = 20GB,

    [double]
    $DDIVersionRequirement = 9.0,

    [double]
    $WDDMVersionRequirement = 1.0
  )

  Begin
  {
    # Maximum wait time and sleep time when waiting for remote dxdiag report
    Set-Variable -Name maxWaitTimeInSeconds -Value 30 -Option Constant
    Set-Variable -Name sleepIntervalInSeconds -Value 1 -Option Constant

    Write-Verbose "Clock Speed Required: $("{0:N2}" -f ($ClockSpeedRequirement/1000)) GHz"
    Write-Verbose "Memory Required for 32-bit: $("{0:N2}" -f ($MemoryRequirement32bit/1GB)) GB"
    Write-Verbose "Memory Required for 64-bit: $("{0:N2}" -f ($MemoryRequirement64bit/1GB)) GB"
    Write-Verbose "Free Disk Space Required for 32-bit: $("{0:N2}" -f ($FreeSpaceRequirement32bit/1GB)) GB"
    Write-Verbose "Free Disk Space Required for 64-bit: $("{0:N2}" -f ($FreeSpaceRequirement64bit/1GB)) GB"
    Write-Verbose "Device Driver Interface Version Required: $ddiVersionRequirement"
    Write-Verbose "Windows Display Driver Model Version Required: $wddmVersionRequirement"
  }

  Process
  {
    Write-Verbose "ComputerName: $ComputerName"
    Write-Verbose "SkipVideoCheck: $SkipVideoCheck"

    if (!(Test-Connection -ComputerName $ComputerName -Count 1 -Quiet))
    {
      Write-Warning "Could not connect to: $Computername"
      return
    }

    Write-Debug "Making WMI Queries"
    try
    {
      $wmiProcessor       = Get-WmiObject -Class Win32_Processor `
                                          -ComputerName $ComputerName `
                                          -ErrorAction STOP

      # The TotalPhysicalMemory property of Win32_ComputerSystem does not
      # return an accurate value
      $wmiPhysicalMemory  = Get-WmiObject -Class Win32_PhysicalMemory `
                                          -ComputerName $ComputerName `
                                          -ErrorAction STOP

      $wmiOperatingSystem = Get-WmiObject -Class Win32_OperatingSystem `
                                          -ComputerName $ComputerName `
                                          -ErrorAction STOP

      $wmiLogicalDisk     = Get-WmiObject -Class Win32_LogicalDisk -ComputerName $ComputerName `
                                          -Filter "DeviceID = `'$($wmiOperatingSystem.SystemDrive)`'" `
                                          -ErrorAction STOP
    }
    catch
    {
      Write-Warning "Unable to complete WMI queries on $ComputerName"
      return
    }

    $computer = New-Object PSObject -Property @{
      ComputerName        = $ComputerName
      AddressWidth        = $wmiProcessor.AddressWidth
      DataWidth           = $wmiProcessor.DataWidth
      MaxClockSpeed       = $wmiProcessor.MaxClockSpeed
      TotalPhysicalMemory = ($wmiPhysicalMemory | Measure-Object -Property Capacity -Sum).Sum
      FreeSpace           = $wmiLogicalDisk.FreeSpace
      MeetsClockSpeed     = $false
      MeetsRAM32          = $false
      MeetsRAM64          = $false
      MeetsSpace32        = $false
      MeetsSpace64        = $false
      MeetsVideo          = $false
      DDIVersion          = $null
      DriverModel         = $null
      DirectXSupport      = $false
      WDDMSupport         = $false
      Win7Ready           = $false
      Win7BestVersion     = $null
    }

    Write-Verbose "Clock Speed: $("{0:N2}" -f ($computer.MaxClockSpeed/1000)) GHz"
    Write-Verbose "Memory: $("{0:N2}" -f ($computer.TotalPhysicalMemory/1GB)) GB"
    Write-Verbose "Free Disk Space: $("{0:N2}" -f ($computer.FreeSpace/1GB)) GB"

    # Start of VideoCheck
    if (!$SkipVideoCheck)
    {
      $dxDiagArguments = "/whql:off "

      # If OS is 64-bit, run dxdiag with /64bit switch
      if ($computer.AddressWidth -eq 64)
      {
        $dxDiagArguments += "/64bit "
      }

      if ($ComputerName -eq $Env:ComputerName)
      {
        # Run dxdiag on local system and wait for process to end

        $tempFile = [System.IO.Path]::GetTempFileName()
        $tempFileUNC = $null

        $dxDiagArguments += "/x $tempFile"
        Write-Debug "Launching dxdiag.exe $dxDiagArguments"
        [System.Diagnostics.Process]::Start("dxdiag.exe", $dxDiagArguments) | Out-Null
        $dxDiagProcess = Get-Process -Name "dxdiag"
        $dxDiagProcess.WaitForExit()
      }
      else
      {
        # Run dxdiag on remote system and wait for file to appear

        $tempFile = "C:\dxdiag.xml"
        $dxDiagArguments += "/x $tempFile"
        $tempFile = "\\$ComputerName\c$\dxdiag.xml"

        Write-Debug "Launching dxdiag.exe $dxDiagArguments on remote computer"
        $result = ([wmiclass]"\\$ComputerName\root\cimv2:Win32_Process").create("dxdiag.exe $dxDiagArguments")

        if ($result.ReturnValue -eq 0)
        {
          Write-Verbose "Remote process dxdiag was sucessfully created."
        }
        else
        {
          Write-Warning "Error running dxdiag remotely. Return value was $($result.ReturnValue)"
          break
        }

        $waitTime = 0
        Do
        {
          Start-Sleep -Seconds $sleepIntervalInSeconds
          $waitTime += $sleepIntervalInSeconds
        }
        Until ((Test-Path $tempFile) -or ($waitTime -gt $maxWaitTimeInSeconds))
      }

      Write-Debug "Reading dxdiag results from $tempFile"
      try
      {
        [xml]$dxDiagResults = Get-Content $tempFile -ErrorAction STOP
      }
      catch
      {
        Write-Warning "Error reading $tempFile"
      }

      Write-Debug "Removing $tempFile"
      try
      {
        Remove-Item $tempFile -ErrorAction STOP
      }
      catch
      {
        Write-Warning "Unable to remove $tempFile"
      }

      $DDIVersion = $dxDiagResults.DxDiag.DisplayDevices.DisplayDevice.DDIVersion
      $driverModel = $dxDiagResults.DxDiag.DisplayDevices.DisplayDevice.DriverModel

      $computer.DDIVersion = $DDIVersion
      $computer.DriverModel = $driverModel

      Write-Verbose "DDIVersion: $($computer.DDIVersion)"
      Write-Verbose "DriverModel: $($computer.DriverModel)"

      try
      {
        if ([double]$computer.DDIVersion -ge $ddiVersionRequirement)
        {
          $computer.DirectXSupport = $true
        }

        if ([double]($computer.DriverModel -replace 'WDDM ','') -ge $wddmVersionRequirement)
        {
          $computer.WDDMSupport = $true
        }
      }
      catch
      {
        Write-Warning "Unable to determine if video card meets requirements"
      }
    }
    #End of VideoCheck

    # Check system specs against Win7 requirements
    if ($computer.MaxClockSpeed -ge $clockSpeedRequirement)
    {
      $computer.MeetsClockSpeed = $true
    }

    if ($computer.TotalPhysicalMemory -ge $memoryRequirement32bit)
    {
      $computer.MeetsRAM32 = $true
    }

    if ($computer.TotalPhysicalMemory -ge $memoryRequirement64bit)
    {
      $computer.MeetsRAM64 = $true
    }

    if ($computer.FreeSpace -ge $freeSpaceRequirement32bit)
    {
      $computer.MeetsSpace32 = $true
    }

    if ($computer.FreeSpace -ge $freeSpaceRequirement64bit)
    {
      $computer.MeetsSpace64 = $true
    }

    if (($computer.DirectXSupport) -and ($computer.WDDMSupport))
    {
      $computer.MeetsVideo = $true
    }

    if (($computer.MeetsClockSpeed) -and ($computer.MeetsRAM32) -and ($computer.MeetsSpace32))
    {
      if (($SkipVideoCheck) -or ($computer.MeetsVideo))
      {
        $computer.Win7Ready = $true
        $computer.Win7BestVersion = "x86"

        if (($computer.MeetsRAM64) -and ($computer.MeetsSpace64) -and ($computer.DataWidth -eq 64))
        {
          $computer.Win7BestVersion = "x64"
        }
      }
    }

    Write-Output $computer
  }

  <#
      .Synopsis
      Verifies if computer meets requirements for Windows 7.

      .Description
      The Test-Win7Requirements function checks processor speed, memory,
      free hard drive space and video card capabilities to determine if they
      meet specifications required to run Windows 7.

      .parameter ComputerName
      Gets the event information on the specified computer.
      The default is the local computer name.

      .parameter SkipVideoCheck
      Does not run dxdiag to determine if video card meets requirements.
      The default is to perform the video check.

      .parameter ClockSpeedRequirement
      Specifies the required processor speed to run Windows 7 in MHz.
      The default is 1000.

      .parameter MemoryRequirement32bit
      Specifies the RAM required to run 32-bit Windows 7.
      The default is 1GB.

      .parameter MemoryRequirement64bit
      Specifies the RAM required to run 64-bit Windows 7.
      The default is 2GB.

      .parameter FreeSpaceRequirement32bit
      Specifies the free space required on the system drive to run
      32-bit Windows 7.
      The default is 16GB.

      .parameter FreeSpaceRequirement64bit
      Specifies the free space required on the system drive to run
      64-bit Windows 7.
      The default is 20GB.

      .parameter DDIVersionRequirement
      Specifies the Device Driver Interface version required to run
      Windows 7.
      The default is 9.0 (DirectX 9).

      .parameter WDDMVersionRequirement
      Specifies the Windows Display Driver Model version required to run
      Windows 7.
      The default is 1.0.

      .Example
      Test-Win7Requirements

      Description
      -----------
      This command checks the local computer to determine if it can be
      upgraded to Windows 7.

      .Example
      Test-Win7Requirements -ComputerName WorkStation01

      Description
      -----------
      This command checks the computer WorkStation01 to determine if it
      can be upgraded to Windows 7.

      .Example
      Test-Win7Requirements -ComputerName WorkStation01 -SkipVideoCheck

      Description
      -----------
      This command checks the computer WorkStation01 to determine if it
      can be upgraded to Windows 7, but does not consider the video card
      capabilities.

      .Example
      Test-Win7Requirements -ClockSpeedRequirement 3000 -MemoryRequirement64bit 4GB

      Description
      -----------
      This command checks the local computer, but sets the minimum requirements to
      a 3 GHz processor and 4GB of RAM to run 64-bit Windows 7.
  #>
}

# Default usage for 2011 Scripting Games
Test-Win7Requirements
