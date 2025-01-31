Function Save-EvergreenApp {
    <#
        .EXTERNALHELP Evergreen-help.xml
    #>
    [OutputType([System.Management.Automation.PSObject])]
    [CmdletBinding(SupportsShouldProcess = $True, HelpURI = "https://stealthpuppy.com/evergreen/save/", DefaultParameterSetName = "Path")]
    [Alias("sea")]
    param (
        [Parameter(
            Mandatory = $True,
            Position = 0,
            ValueFromPipeline,
            HelpMessage = "Pass an application object from Get-EvergreenApp.")]
        [ValidateNotNull()]
        [System.Management.Automation.PSObject] $InputObject,

        [Parameter(
            Mandatory = $False,
            Position = 1,
            ValueFromPipelineByPropertyName,
            HelpMessage = "Specify a top-level directory path where the application installers will be saved into.",
            ParameterSetName = "Path")]
        [System.IO.FileInfo] $Path,

        [Parameter(
            Mandatory = $False,
            Position = 1,
            ValueFromPipelineByPropertyName,
            HelpMessage = "Specify a single directory path where all application installers will be saved into.",
            ParameterSetName = "CustomPath")]
        [System.IO.FileInfo] $CustomPath,

        [Parameter(Mandatory = $False, Position = 2)]
        [System.String] $Proxy,

        [Parameter(Mandatory = $False, Position = 3)]
        [System.Management.Automation.PSCredential]
        $ProxyCredential = [System.Management.Automation.PSCredential]::Empty,

        [Parameter(Mandatory = $False)]
        [System.Management.Automation.SwitchParameter] $Force,

        [Parameter(Mandatory = $False)]
        [System.Management.Automation.SwitchParameter] $NoProgress
    )

    begin {
        # Disable the Invoke-WebRequest progress bar for faster downloads
        if ($PSBoundParameters.ContainsKey("Verbose") -and !($PSBoundParameters.ContainsKey("NoProgress"))) {
            $ProgressPreference = [System.Management.Automation.ActionPreference]::Continue
        }
        else {
            $ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
        }

        # Path variable from parameters set via -Path or -CustomPath
        switch ($PSCmdlet.ParameterSetName) {
            "Path" {
                if ([System.String]::IsNullOrEmpty($Path)) { throw "Cannot bind argument to parameter 'Path' because it is null." }
                $NewPath = $Path
            }
            "CustomPath" {
                if ([System.String]::IsNullOrEmpty($CustomPath)) { throw "Cannot bind argument to parameter 'CustomPath' because it is null." }
                $NewPath = $CustomPath
            }
        }

        #region Test $Path and attempt to create it if it doesn't exist
        if (Test-Path -Path $NewPath -PathType "Container") {
            Write-Verbose -Message "Path exists: $NewPath."
        }
        else {
            Write-Verbose -Message "Path does not exist: $NewPath."
            try {
                Write-Verbose -Message "Create: $NewPath."
                $params = @{
                    Path        = $NewPath
                    ItemType    = "Container"
                    ErrorAction = "SilentlyContinue"
                }
                New-Item @params | Out-Null
            }
            catch {
                throw "Failed to create $NewPath with: $($_.Exception.Message)"
            }
        }
        #endregion

        # Enable TLS 1.2
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }

    process {
        # Loop through each object and download to the target path
        foreach ($Object in $InputObject) {

            #region Validate the URI property and find the output filename
            if ([System.Boolean]($Object.URI)) {
                Write-Verbose -Message "URL: $($Object.URI)."
                if ([System.Boolean]($Object.FileName)) {
                    $OutFile = $Object.FileName
                }
                Elseif ([System.Boolean]($Object.URI)) {
                    $OutFile = Split-Path -Path $Object.URI -Leaf
                }
            }
            else {
                throw "Object does not have valid URI property."
            }
            #endregion

            # Handle the output path depending on whether -Path or -CustomPath are used
            switch ($PSCmdlet.ParameterSetName) {
                "Path" {
                    # Resolve $Path to build the initial value of $OutPath
                    $OutPath = Resolve-Path -Path $Path -ErrorAction "SilentlyContinue"
                    if ($Null -ne $OutPath) {

                        #region Validate the Version property
                        if ([System.Boolean]($Object.Version)) {

                            # Build $OutPath with the "Channel", "Release", "Language", "Architecture" properties
                            $OutPath = New-EvergreenPath -InputObject $Object -Path $OutPath
                        }
                        else {
                            throw "Object does not have valid Version property."
                        }
                        #endregion
                    }
                    else {
                        throw "Failed validating $OutPath."
                    }
                }
                "CustomPath" {
                    $OutPath = Resolve-Path -Path $CustomPath -ErrorAction "Stop"
                }
            }

            # Download the file
            if ($PSCmdlet.ShouldProcess($Object.URI, "Download")) {

                $DownloadFile = $(Join-Path -Path $OutPath -ChildPath $OutFile)
                if ($PSBoundParameters.ContainsKey("Force") -or !(Test-Path -Path $DownloadFile -PathType "Leaf" -ErrorAction "SilentlyContinue")) {

                    try {
                        #region Download the file
                        $params = @{
                            Uri             = $Object.URI
                            OutFile         = $DownloadFile
                            UseBasicParsing = $True
                            ErrorAction     = "Continue"
                        }
                        if ($PSBoundParameters.ContainsKey("Proxy")) {
                            $params.Proxy = $Proxy
                        }
                        if ($PSBoundParameters.ContainsKey("ProxyCredential")) {
                            $params.ProxyCredential = $ProxyCredential
                        }
                        Invoke-WebRequest @params
                        #endregion

                        #region Write the downloaded file path to the pipeline
                        if (Test-Path -Path $DownloadFile) {
                            Write-Verbose -Message "Successfully downloaded: $DownloadFile."
                            Write-Output -InputObject $(Get-ChildItem -Path $DownloadFile)
                        }
                        #endregion
                    }
                    catch [System.Exception] {
                        Write-Error -Message "Download failed: $($Object.URI)"
                        Write-Error -Message "Error: $($_.Exception.Message)"
                    }
                }
                else {
                    #region Write the downloaded file path to the pipeline
                    if (Test-Path -Path $DownloadFile) {
                        Write-Verbose -Message "File exists: $DownloadFile."
                        Write-Output -InputObject $(Get-ChildItem -Path $DownloadFile)
                    }
                    #endregion
                }
            }
        }
    }

    end {
        Write-Verbose -Message "Complete."
        if ($PSCmdlet.ShouldProcess("Remove variables")) {
            if (Test-Path -Path Variable:params) { Remove-Variable -Name "params" -ErrorAction "SilentlyContinue" }
            Remove-Variable -Name "OutPath", "OutFile" -ErrorAction "SilentlyContinue"
        }
    }
}
