# -----------------------------------------------------------------------------
# Script: New-LogFile
# Author: Jason Hofferle
# Date: 04/15/2011
# Version: 1.0.0
# Comments: The scenario described the need to add a logging routine to an
# existing script. I thought a good approach would be to create a function that
# returned the full path of the log file, or null if the file already existed.
# The function defaults to creating a log with the path and name outlined in
# the event, but that information can be modified through function parameters.
#
# -----------------------------------------------------------------------------

Function New-LogFile
{
  Param
  (
    # SpecialFolder validated against Environment.Specialfolder Enum
    [ValidateScript({([System.Environment+SpecialFolder] |
                     Get-Member -Static -MemberType Property |
                     ForEach-Object {$_.Name}) -contains $_})]
    [string]
    $SpecialFolder = "MyDocuments",

    [string]
    $LogDirectoryName = "HSGLogFiles",

    [string]
    $TimeStampFormat = "yyyyMMdd",

    [switch]
    $Force
  )

  # Try to get the path of the special folder specified.
  try
  {
    $rootPath = [System.Environment]::GetFolderpath($SpecialFolder)
  }
  catch
  {
    Write-Warning "Error getting folder path for $SpecialFolder"
    return
  }

  # Try to get the timestamp in the format specified.
  try
  {
    $timeStamp = Get-Date -Format $TimeStampFormat
  }
  catch
  {
    Write-Warning "Error getting Date for format $TimeStampFormat"
    return
  }

  $userName = $Env:UserName
  $logDirectory = "$rootPath\$LogDirectoryName"
  $logFile = "$logDirectory\$($timeStamp)_$userName.log"

  # Try to create the Log Directory if it does not already exist.
  if (-NOT (Test-Path $logDirectory))
  {
    try
    {
      New-Item -Path $logDirectory -ItemType Directory -ErrorAction STOP | Out-Null
    }
    catch
    {
      Write-Warning "Error creating directory $logDirectory"
    }
  }

  # Try to create the Log File if it does not already exist.
  if (-NOT (Test-Path $logFile))
  {
    try
    {
      # Return the full path if the file did not exist previously and
      # was successfully created.
      New-Item -Path $logFile -ItemType File -ErrorAction STOP | Out-Null
      return $logFile
    }
    catch
    {
      Write-Warning "Error creating file $logFile"
    }
  }
  else
  {
    if ($Force)
    {
      return $logFile
    }
  }

  <#

  .Synopsis
  Creates a log file based on the current date and username.

  .Description
  The New-LogFile function checks for the existance of a log file matching the
  default or specified parameters and returns null if the file exists.

  If the file does not exist, it is created along with any missing directories
  and returns the full path of the log file.

  .parameter SpecialFolder
  Uses the provided SpecialFolder directory as the base path for the log
  directory. The string provided is validated against the
  System.Environment.SpecialFolder Enumeration. The default value is the
  current user's MyDocuments folder.

  .parameter LogDirectoryName
  The subfolder under the SpecialFolder path to place the logfile.
  The default is HSGLogFiles.

  .parameter TimeStampFormat
  Specifies a valid datetimeformatinfo string used for the timestamp of the
  log file.
  The default is yyyyMMdd, which would be 20110131 for January 31, 2011.

  .parameter Force
  Forces the name of the log file to be returned, even if it already exists,
  but does not modify the file.

  .Example
  New-LogFile

  Description
  -----------
  This command attempts to create a new log file with the default parameters.
  If the log file was created successfully, the full path of the file is
  returned. If there was an error or the file already exists, it returns null.

  .Example
  New-LogFile -TimeStampFormat yyyyMMddHH

  Description
  -----------
  This command attempts to create a new log file with the hour added to the
  filename using a custom TimeStampFormat. This is useful if a unique log file
  for every hour was desired instead of every day.

  .Example
  New-LogFile -SpecialFolder LocalApplicationData -LogDirectoryName SCRIPTLOGS

  Description
  -----------
  This command attempts to create a new log file in the Local Application Data
  special folder, under the SCRIPTLOGS subdirectory.

  .Link
  http://msdn.microsoft.com/en-us/library/system.environment.specialfolder.aspx
  http://msdn.microsoft.com/en-us/library/system.globalization.datetimeformatinfo.aspx

  #>
}
