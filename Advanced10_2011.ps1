# -----------------------------------------------------------------------------
# Script: Out-TempFile
# Author: Jason Hofferle
# Date: 04/16/2011
# Version: 1.0.0
# Comments: This advanced function creates a uniquely named tmp file in the
# current user's temporary directory. It accepts any type of object through the
# pipeline or InputObject parameter. It supports Unicode and ASCII encoding, and
# includes a parameter for opening the temporary file with notepad.
#
# -----------------------------------------------------------------------------

Function Out-TempFile
{
    [CmdletBinding(SupportsShouldProcess=$True,
                   ConfirmImpact="Low")]
    Param
    (
        [Parameter(
        Mandatory=$True,
        ValueFromPipeline=$True)]
        $InputObject,

        [Parameter()]
        [ValidateSet("ascii","unicode")]
        [string]
        $Encoding = "unicode",

        [Parameter()]
        [switch]
        $Notepad
    )

    Begin
    {
        # If -Debug was specified, change preference to Continue
        if ($PSBoundParameters.Debug) { $DebugPreference = "Continue" }

        # Generate Temporary File
        try
        {
            $TempFile = [System.IO.Path]::GetTempFileName()
            Write-Verbose "TempFile: $TempFile"

            # Setup hashtable with parameters that will be passed to Out-File
            $OutFileArgs = @{
                FilePath    = $TempFile
                InputObject = $Null
                Encoding    = $Encoding
                Append      = $True}
        }
        catch
        {
            Write-Warning "There was an error creating the temp file."
            Write-Debug ($_ | Out-String)
        }
    }

    Process
    {
        if ($PSBoundParameters.Debug) { $DebugPreference = "Continue" }

        # Make sure temp file was created before continuing
        if ($TempFile)
        {
            if ($PSCmdlet.ShouldProcess($InputObject))
            {
                # Change the hashtable to reflect the current object in the
                # process block.
                $OutFileArgs.InputObject = $InputObject
                Write-Verbose ($OutFileArgs | Out-String)

                try
                {
                    # Pass parameters to Out-File via splatting
                    Out-File @OutFileArgs
                }
                catch
                {
                    Write-Warning "There was an error writing to the temp file."
                    Write-Debug ($_ | Out-String)
                }
            }
        }
        else
        {
            Write-Warning "TempFile variable is empty. Unable to continue."
        }
    }

    End
    {
        if ($PSBoundParameters.Debug) { $DebugPreference = "Continue" }

        # Return path to the temporary file
        Write-Output $TempFile

        # View temp file with notepad if -Notepad parameter was specified
        if ( ($Notepad) -and (-NOT $PSBoundParameters.WhatIf) )
        {
            try
            {
                notepad.exe $TempFile
            }
            catch
            {
                Write-Warning "There was an error launching notepad.exe"
                Write-Debug ($_ | Out-String)
            }
        }
    }
  <#

  .Synopsis
  Sends output to a temporary file and returns the file name.

  .Description
  The Out-TempFile function sends output to a temporary file and returns the
  full path to the file. The temporary file is uniquely named and created in
  the current user's temporary directory.

  .parameter InputObject
  Specifies the objects to be written to the file.

  .parameter Encoding
  Specifies the character encoding used in the file. Valid values are "Unicode"
  and "ASCII". The default value is Unicode.

  .parameter Notepad
  Opens the temporary file in Notepad after all objects have been written.

  .Inputs
  System.Management.Automation.PSObject
  You can pipe any object to Out-TempFile.

  .Outputs
  System.String

  .Example
  Get-Process | Out-TempFile

  Description
  -----------
  This command sends a list of processes on the computer to a temporary file
  and returns the full path of the file.

  .Example
  $a = Get-Process
  C:\PS>Out-TempFile -InputObject $a -Encoding ASCII -Notepad

  Description
  -----------
  These commands send a list of processes to a temporary file. The text is
  encoded in ASCII format and the temporary file is displayed using notepad.

  The first command gets the list of processes and stores them in the $a
  variable. The second command uses the Out-TempFile function to send the list
  to a temporary file.

  #>
}
