# -----------------------------------------------------------------------------
# Script: Get-SQLSatTwitterUsers
# Author: Jason Hofferle
# Date: 04/11/2011
# Version: 1.0.0
# Comments: This function uses System.Net.WebClient to query the SQL Saturday
#  website and parse the networking page for twitter usernames.
#
# -----------------------------------------------------------------------------

Function Get-SQLSatTwitterUsers
{
  [CmdletBinding()]
  Param
  (
    [Parameter(
    Position=0,
    ValueFromPipeLine=$true)]
    [int]
    $EventNumber = 70,

    [Parameter(
    Position=1)]
    [ValidateScript({Test-Path $_ -IsValid})]
    [string]
    $OutFile,

    [switch]
    $Quiet
  )

  Begin
  {
    $webClient = New-Object System.Net.WebClient
    $output = @()
  }

  Process
  {
    $url = "http://www.sqlsaturday.com/$EventNumber/networking.aspx"
    $pattern = 'href="http://www.twitter.com/'

    try
    {
      $result = $webClient.DownloadString($url).split()
    }
    catch
    {
      "Unable to contact SQL Saturday web site"
      return
    }

    $userName = $result | Select-String -Pattern $pattern |
      ForEach-Object {$_.Line.Substring($_.Line.LastIndexOf("/")+1) -replace '"',''}

    if (-NOT $Quiet)
    {
      Write-Output $userName
    }

    $output += $userName
  }

  End
  {
    if ($OutFile)
    {
      try
      {
        $output | Select-Object -Unique | Out-File -FilePath $OutFile -ErrorAction STOP
      }
      catch [UnauthorizedAccessException]
      {
        "Access denied writing to $OutFile"
      }
    }
  }

  <#
  .Synopsis
  Retrieves twitter usernames from the SQL Saturday website.

  .Description
  The Get-SQLSatTwitterUsers function accesses the networking page for the
  specified SQL Saturday event and returns a list of all twitter usernames.

  .parameter EventNumber
  Gets usernames for the specified Event Number.
  The default is event 70.

  .parameter OutFile
  Exports list of twitter usernames to the specified text file.
  The default is to not export to a file.

  .parameter Quiet
  Does not display console output.

  .Example
  Get-SQLSatTwitterUsers -OutFile twitter.txt

  Description
  -----------
  This command gets twitter usernames for SQL Saturday event #70 and
  exports those names to the twitter.txt file.

  .Example
  Get-SQLSatTwitterUsers -EventNumber 65

  Description
  -----------
  This command gets twitter usernames for SQL Saturday event #65 and
  displays those names in the console.

  .Example
  1..70 | Get-SQLSatTwitterUsers -OutFile twitter.txt -Quiet

  Description
  -----------
  This command gets twitter usernames for every SQL Saturday event from
  #1 through #70 and exports those usernames to the twitter.txt file without
  displaying console output.
  #>
}
