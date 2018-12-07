# -----------------------------------------------------------------------------
# Script: Get-TwitterUser
# Author: Jason Hofferle
# Date: 04/13/2011
# Version: 1.0.0
# Comments: The Get-TwitterUser function accesses the networking page for the
# specified SQL Saturday event and returns a list of all twitter users that can
# be exported to a CSV file. This CSV can then be used to resolve Names to
# twitter screen names or vice versa. The function can also access the Twitter
# API, allowing twitter to be queried for additional information on SQL Saturday
# attendees, or for retrieving information about any Twitter screen name.
# Information returned from twitter is cached locally in a separate csv to
# eliminate the need to repeatedly request the same information.
#
# -----------------------------------------------------------------------------

Function Get-TwitterUser
{
  [CmdletBinding(DefaultParameterSetname='QuerySQLSat')]
  Param
  (
    [Parameter(
    ValueFromPipeLine=$true,
    Mandatory=$true,
    ParameterSetName='QuerySQLSat')]
    [int]
    $EventNumber,

    [Parameter()]
    [ValidateScript({Test-Path $_ -IsValid})]
    [string]
    $Path,

    [Parameter(
    Mandatory=$true,
    ParameterSetName='TranslateName')]
    [string]
    $Name,

    [Parameter(
    Mandatory=$true,
    ParameterSetName='TranslateScreenName')]
    [string]
    $ScreenName,

    [switch]
    $UseTwitterAPI
  )

  Begin
  {
    $webClient = New-Object System.Net.WebClient

    # #########################################################################
    # Function for querying Twitter API
    # http://dev.twitter.com/doc/get/users/show
    Function Invoke-TwitterQuery
    {
      Param
      (
        [string]$screen_name
      )

      # Twitter has a query limit based on IP Address, so a CSV is
      # setup to cache results locally. It is written to the Temp Path,
      # but given a standard name so it can be retrieved each time the
      # function is called.
      $cachePath = [System.IO.Path]::GetTempPath() + 'Get-TwitterUserCache.csv'
      Write-Verbose "Twitter cache: $cachePath"

      # Base URL for the twitter API being used.
      $twitterURL = 'http://api.twitter.com/1/users/show.xml?'

      # Import the cache file if it exists.
      if (Test-Path $cachePath)
      {
        try
        {
          $twitterCache = @(Import-Csv $cachePath)
        }
        catch
        {
          Write-Warning "Unable to import Twitter Cache."
          $twitterCache = @()
        }
      }
      else
      {
        $twitterCache = @()
      }

      # Check the cache for the screen name being searched for.
      $result = $twitterCache | Where-Object {$_.ScreenName -eq $screen_name}

      # Query twitter if the screen name was not found in the cache.
      if ($result -eq $null)
      {
        Write-Verbose "Screen Name $screen_name was NOT found in cache"
        $query = "screen_name=$screen_name"

        try
        {
          Write-Verbose "Query String: $twitterUrl$query"
          [xml]$xml = $webClient.DownloadString("$twitterUrl$query")
          $result = New-Object PSObject -Property @{
            Name=$xml.user.name
            ScreenName=$xml.user.screen_name
            Location=$xml.user.location
            Description=$xml.user.description
            Url=$xml.user.url
            Id=$xml.user.id}

          $twitterCache += $result
        }
        catch
        {
          Write-Warning "There was a problem attempting to query Twitter."

          if ($Error[0].exception.message -like "*(400) Bad Request*")
          {
            Write-Warning "400 Bad Request response from Twitter."
            Write-Warning "This may indicate the maximum number of API queries has been reached."
          }
        }
      }
      else
      {
        Write-Verbose "Screen Name $screen_name was found in local cache"
      }

      # Export the updated cache to a new CSV
      try
      {
        $twitterCache | Export-Csv -Path $cachePath -NoTypeInformation
      }
      catch
      {
        Write-Warning "Unable to export new cache to $cachePath"
      }

      Write-Output $result
    }
  }

  Process
  {
    # Run code specific to the specified paramters.
    Switch ($PsCmdlet.ParameterSetname)
    {
      # #######################################################################
      # Switch block for querying the SQL Saturday website.
      'QuerySQLSat'
      {
        $userCollection = @()
        $url = "http://www.sqlsaturday.com/$EventNumber/networking.aspx"
        $pattern = '<a href="http://www.twitter.com/'

        # Download the text for the Networking page, and split by
        # newline characters.
        try
        {
          Write-Verbose "Query string: $url"
          $result = $webClient.DownloadString($url).split("`n")
        }
        catch
        {
          Write-Warning "There was an error accessing the SQL Saturday site"
        }

        # Get an array of strings that contain the twitter URL pattern.
        [string[]]$matches = $result | Select-String -Pattern $pattern

        # Look at each string, extract the Name and ScreenName and
        # create a custom object with those properties.

        for ($i = 0; $i -lt $matches.Count; $i++)
        {
          Write-Progress -Activity "Query in Progress" `
                         -Status "$i of $($matches.Count)" `
                         -PercentComplete ($i / $matches.Count * 100)

          try
          {
            $start = ($matches[$i] -split $pattern)[0]
            $end = ($matches[$i] -split $pattern)[1]

            $name = $start.substring($start.lastindexof('>')+1)
            $screenName = $end.substring(0,$end.indexof('"'))
          }
          catch
          {
            Write-Warning "There was a problem parsing the HTML"
          }

          # Some of the twitter screen names are not correct on the
          # networking webpage, so we try to clean it up.
          try
          {
            $screenName = $screenName.substring($screenName.lastindexof('/')+1)
          }
          catch {}

          # If UseTwitterAPI parameter was specified, query twitter for
          # each screen name found on SQL Saturday page to get additional
          # information.
          if ($UseTwitterAPI)
          {
            $userInfo = Invoke-TwitterQuery $ScreenName
          }
          else
          {
            $userInfo = New-Object PSObject -Property @{
              Name=$name
              ScreenName=$screenName
              Location=''
              Description=''
              Url=''
              Id=''}
          }

          # Collect our information into an array so it can be
          # exported to a CSV in the End block.
          $userCollection += $userInfo
        }
      }

      # #######################################################################
      # Switch block for resolving a Name from the CSV file to the
      # corresponding twitter screen name. The twitter API being used
      # does not allow searching by Name, so we are limited to querying
      # the CSV specified by the Path parameter.
      'TranslateName'
      {
        # If the CSV was specified and exists, import and search it.
        if ( ($Path) -and (Test-Path $Path) )
        {
          try
          {
            $csv = Import-Csv $Path
          }
          catch
          {
            Write-Warning "Unable to import CSV $Path"
          }

          Write-Output $csv | Where-Object {$_.Name -like "*$Name*"}
        }
        else
        {
          Write-Warning "Path was not specified or file could not be found."
        }
      }

      # #######################################################################
      # Switch block for resolving a twitter screen name to a Name.
      # The twitter API being used allows us to query by screen name, which
      # gives us the option to resolve screen names that are not listed
      # on the SQL Saturday networking page.
      'TranslateScreenName'
      {
        if ($UseTwitterAPI)
        {
          Write-Output (Invoke-TwitterQuery $ScreenName)
        }
        else
        {
          # If the UserTwitterAPI parameter was not specified, just
          # query the CSV specified in the Path parameter.
          if ($Path)
          {
            try
            {
              $csv = Import-Csv $Path
            }
            catch
            {
              Write-Warning "Unable to import CSV $Path"
            }

            Write-Output $csv | Where-Object {$_.ScreenName -like "*$ScreenName*"}
          }
          else
          {
            Write-Warning "Neither Path or UseTwitterAPI were not specified. No results will be returned."
          }
        }
      }
    }
  }

  End
  {
    # Run code specific to the parameter set.
    Switch ($PsCmdlet.ParameterSetname)
    {
      'QuerySQLSat'
      {
        # Export results to a CSV if Path parameter was specified.
        if ($Path)
        {
          try
          {
            $userCollection | Export-Csv -Path $Path -ErrorAction STOP -NoTypeInformation
          }
          catch
          {
            "Error writing to $Path"
          }
        }

        # Write Screen Output.
        Write-Output $userCollection
      }
    }
  }

  <#

  .Synopsis
  Retrieves twitter users from the SQL Saturday website or from the twitter API.

  .Description
  The Get-TwitterUser function accesses the networking page for the
  specified SQL Saturday event and returns a list of all twitter users with
  names, and can export that information to a CSV file for later reference.

  The function can also access the Twitter Users/Show API, allowing twitter
  to be queried for additional information on SQL Saturday attendees, or for
  retrieving additional information about any Twitter screen name.

  .parameter EventNumber
  Gets usernames for the specified Event Number.
  This parameter is mandatory if Name or ScreenName are not provided.

  .parameter Path
  Path to a CSV file used to export information to, or import data from.

  When used with EventNumber, the twitter information is exported to the
  specified CSV file.

  When used with Name or ScreenName, the CSV file is loaded and searched for
  the name or screen name.

  .parameter Name
  Searches the CSV file specified in Path to resolve a User Name to a twitter
  username (screen name).

  .parameter ScreenName
  Searches the CSV file specified in Path to resolve a twitter username
  (screen name) to a User Name.

  When used with the UseTwitterAPI parameter, the CSV file is not queried in
  favor of directly querying twitter for the information associated with the
  screen name.

  .parameter UseTwitterAPI
  Uses the twitter Users/Show API when possible to resolve screen names or
  retrieve additional information.

  Due to API limits on the number of number of queries per IP Address, any
  results returned are cached in a CSV file created in the temp directory. The
  name and location of this file is displayed with the Verbose parameter.

  If the information is not found in the cache, twitter is queried and the
  cache is updated with the new information. The file can be manually deleted
  to reset the cache.

  When used with EventNumber, twitter names that cannot be resolved with the
  API will not be exported to the CSV.

  .Example
  Get-TwitterUser -EventNumber 70 -Path twitter.csv

  Description
  -----------
  This command gets twitter information for SQL Saturday event #70 and
  exports that information to the twitter.csv file.

  .Example
  Get-TwitterUser -EventNumber 70 -Path twitter.csv -UseTwitterAPI

  Description
  -----------
  This command gets twitter screen names from SQL Saturday event #70, queries
  twitter for additional information about those screen names, and exports
  that information to the twitter.csv file.

  .Example
  Get-TwitterUser -Name "Ed Wilson" -Path twitter.csv

  Description
  -----------
  This command queries the twitter.csv file for entries where the Name
  property matches "Ed Wilson" and displays that information, which
  includes the twitter screen name.

  .Example
  Get-TwitterUser -screenName scriptingwife -Path twitter.csv

  Description
  -----------
  This command queries the twitter.csv file for entries where the ScreenName
  property matches "scriptingwife" and displays that information, which
  includes the actual name.

  .Example
  PS C:\> Get-TwitterUser -ScreenName scriptingguys -UseTwitterAPI -Verbose
  VERBOSE: Twitter cache:
  C:\Users\Jason\AppData\Local\Temp\Get-TwitterUserCache.csv
  VERBOSE: Screen Name scriptingguys was found in local cache


  ScreenName  : ScriptingGuys
  Name        : MSFT Scripting Guys
  Url         : http://www.scriptingguys.com
  Id          : 21238450
  Description : Ed Wilson is the Microsoft Scripting Guy. He is an expert on scri
                pting technology such as PowerShell, VBScript and WMI. He is the
                author of over a dozen books.
  Location    : Redmond, Washington, United St

  Description
  -----------
  This command queries twitter for the screen name "scriptingguys" and
  displays information about that twitter user with verbose output.

  #>
}
