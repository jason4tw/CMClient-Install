[CmdletBinding()]
param (
    [parameter(Mandatory=$false)]
    [Alias("ConfigurationFile","Config")]
    [String]$ConfigurationFilePath = ""
)
function Start-Logging {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
        [String]$Component,

        [parameter(Mandatory=$true)]
        [HashTable]$Properties
    )
    process {
        $locale = (Get-WinSystemLocale).LCID
        $msgFile = "$($Properties.Location)\$Component.strings.$locale.json"
        $msgFileLoadedSuccessfuly = $true
        
        try {
            $loadedStrings = Get-Content -Path $msgFile -ErrorAction Stop | ConvertFrom-Json
        }
        catch {
            $msgFile = "$($Properties.Location)\$Component.strings.json"
            
            try {
                $loadedStrings = Get-Content -Path $msgFile -ErrorAction Stop  | ConvertFrom-Json
            }
            catch {
                $msgFileLoadedSuccessfuly = $false
            }
        }

        if($msgFileLoadedSuccessfuly -eq $true) {
            $Properties.Strings = $loadedStrings
        }

        try {
            $Properties.LogPath = Get-ItemPropertyValue -Path $Properties.Strings.Defaults.REGISTRY_LOCATION -Name $Properties.Strings.Defaults.REGISTRY_LOGLOCATION_VALUE -ErrorAction Stop
            Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Properties.Strings.Messages.DIVIDER
            Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Properties.Strings.Messages.LOG_FILE_LOADED -MessageVars @{1=$Properties.Strings.Defaults.REGISTRY_LOGLOCATION_VALUE;2=$Properties.Strings.Defaults.REGISTRY_LOCATION}
        }
        catch {
            $Properties.LogPath = "$env:TEMP\$Component.log"
            Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Properties.Strings.Messages.DIVIDER
            Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Properties.Strings.Messages.LOG_FILE_NOT_LOADED
        }

        if($msgFileLoadedSuccessfuly) {
            Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Properties.Strings.Messages.STRINGS_FILE_LOADED -MessageVars @{1=$msgFile}
            Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Properties.Strings.Messages.BEGIN -MessageVars @{1 = $Properties.StartTime}
        }
        else {
            Write-LogMsg -MsgProperties $Properties -MsgType Error -Message $Properties.Strings.Errors.STRINGS_FILE_LOAD_ERROR
        }

        $msgFileLoadedSuccessfuly
    }
    end {
    }
}

function Stop-Logging {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
        [HashTable]$Properties
    )

    try {
        if(!(Get-Item -Path $Properties.Strings.Defaults.REGISTRY_LOCATION -ErrorAction SilentlyContinue)) {
            New-Item -Path $Properties.Strings.Defaults.REGISTRY_LOCATION -Force > $null 2>&1
        }
        
        Set-ItemProperty -Path $Properties.Strings.Defaults.REGISTRY_LOCATION -Name $Properties.Strings.Defaults.REGISTRY_LOGLOCATION_VALUE -Value $Properties.LogPath -Force -ErrorAction Stop
        Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Properties.Strings.Messages.LOG_FILE_STORED -MessageVars @{1=$Properties.LogPath;2=$Properties.Strings.Defaults.REGISTRY_LOGLOCATION_VALUE;3=$Properties.Strings.Defaults.REGISTRY_LOCATION}
    }
    catch {
        Write-LogMsg -MsgProperties $Properties -MsgType Error -Message $Properties.Strings.Errors.LOG_FILE_NOT_STORED
    }

    $endTime = Get-Date
    $elapsedTime = New-TimeSpan -Start $Properties.StartTime -End $endTime

    Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Properties.Strings.Messages.FINISH -MessageVars @{1=$endTime}
    Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Properties.Strings.Messages.ELAPSED_TIME -MessageVars @{1=($elapsedTime.ToString("hh\:mm\:ss"))}
    Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Properties.Strings.Messages.DIVIDER

    #TODO: check log file size, rename to .old
}

function Write-LogMsg {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true,ParameterSetName='Full')]
        [String]$Path,

        [parameter(Mandatory=$true,ParameterSetName='Full')]
        [String]$Component,

        [parameter(Mandatory=$true,ParameterSetName='Full')]
        [String]$Filename,

        [parameter(Mandatory=$true,ParameterSetName='Condensed')]
        [HashTable]$MsgProperties,

        [parameter(Mandatory=$true)]
        [String]$Message,

        [parameter(Mandatory=$false)]
        [HashTable]$MessageVars,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet("Info", "Warning", "Error")]
        [String]$MsgType
    )
    process {
        switch ($MsgType) {
            "Info" { [int]$MsgType = 1 }
            "Warning" { [int]$MsgType = 2 }
            "Error" { [int]$MsgType = 3 }
        }

        $logMessage = $Message

        if($MessageVars.Count -gt 0) {
            foreach($var in $MessageVars.GetEnumerator()) {
                $varPatern = '%{0}' -f $var.key
                $logMessage = $logMessage -replace $varPatern, $var.Value
            }
        }

        if ($PSBoundParameters.ContainsKey('MsgProperties')) {
            $Component = $MsgProperties.Name
            $Filename = $MsgProperties.Filename
            $Path = $MsgProperties.LogPath
        }

        $LogLine = "<![LOG[$logMessage]LOG]!>" +`
            "<time=`"$(Get-Date -Format "HH:mm:ss.ffffff")`" " +`
            "date=`"$(Get-Date -Format "M-d-yyyy")`" " +`
            "component=`"$Component`" " +`
            "context=`"$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " +`
            "type=`"$MsgType`" " +`
            "thread=`"$([Threading.Thread]::CurrentThread.ManagedThreadId)`" " +`
            "file=`"$($Filename):$($MyInvocation.ScriptLineNumber)`">"


        try {
            Add-Content -Path $Path -Value $LogLine
        }
        catch {
        }
    }
    end {
    }
}

function Test-InWinPE {
    $env:SystemDrive -eq 'X:'
}

function Test-IsAdmin {
    $erroractionpreference="Silently Continue"
    New-PSDrive -Name AdminEnv -PSProvider Registry -Root HKEY_USERS > $null 2>&1
    Get-Item AdminEnv:\S-1-5-19\Environment\ > $null 2>&1
    return $?
}

function Out-Configuration {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
        [HashTable]$Properties,

        [Parameter(Mandatory=$true)]
        [string]$ConfigurationType,

        [Parameter(Mandatory=$true)]
        [string]$ConfigurationTypeXMLElement
    )

    Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Properties.Strings.Messages.CONFIG_ITEMS_FOUND -MessageVars @{1=$ConfigurationType}

    foreach($item in $Properties.Config.DocumentElement.$ConfigurationTypeXMLElement) {
        Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Properties.Strings.Messages.CONFIG_ITEM_FOUND -MessageVars @{1=$item.Name;2=$item.'#text'}
    }
}

function Open-Config {
    [CmdletBinding()]
    param (
        [Parameter()]
        [String]$ConfigurationFile,
        
        [parameter(Mandatory=$true)]
        [HashTable]$Properties
    )

    if($ConfigurationFile -eq "") {
        $ConfigurationFile = "$($Properties.Location)\$($Properties.Name).config.xml"
    }

    if(Test-Path -Path $ConfigurationFile) {

        $ConfigurationFile = (Convert-Path -Path $ConfigurationFile)

        Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Properties.Strings.Messages.CONFIG_FILE_LOADING -MessageVars @{1=$ConfigurationFile}

        try {
            $Properties.Config.Load(($ConfigurationFile))

            Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Properties.Strings.Messages.CONFIG_FILE_LOADED
        }
        catch [System.Xml.XmlException] {
            Write-LogMsg -MsgProperties $Properties -MsgType Error -Message $Properties.Strings.Errors.CONFIG_FILE_LOAD_ERROR -MessageVars @{1=$_.Exception.Message}
            return $false
        }

        Out-Configuration -Properties $Properties -ConfigurationType $Properties.Strings.Defaults.XML_OPTION_ELEMENT_NAME -ConfigurationTypeXMLElement $Properties.Strings.Defaults.XML_OPTION_ELEMENT
        Out-Configuration -Properties $Properties -ConfigurationType $Properties.Strings.Defaults.XML_PROPERTY_ELEMENT_NAME -ConfigurationTypeXMLElement $Properties.Strings.Defaults.XML_PROPERTY_ELEMENT
        Out-Configuration -Properties $Properties -ConfigurationType $Properties.Strings.Defaults.XML_PARAMETER_ELEMENT_NAME -ConfigurationTypeXMLElement $Properties.Strings.Defaults.XML_PARAMETER_ELEMENT
        

        $true
    }
    else {
        Write-LogMsg -MsgProperties $Properties -MsgType Error -Message $Properties.Strings.Errors.CONFIG_FILE_NOT_FOUND -MessageVars @{1=$ConfigurationFile}

        $false
    }
}

$me = Get-Item -Path $PSCommandPath

$scriptProperties = @{StartTime = [DateTime](Get-Date);
                      Name = $me.Basename;
                      Filename = $me.Name;
                      Location = $me.DirectoryName;
                      LogPath = "";
                      Config = (New-Object xml);
                      Strings = [PSCustomObject]@{Messages=@{DIVIDER="----------------------------------------";
                                                                LOG_FILE_LOADED="Log file location loaded from the registry '%1' value at '%2'";
                                                                LOG_FILE_NOT_LOADED="Log file location was not loaded from the registry";
                                                                LOG_FILE_STORED="Stored location of log file (%1) in the registry value '%2' at '%3'";
                                                                BEGIN="Beginning Execution at %1";
                                                                FINISH="Finished Execution at %1";
                                                                ELAPSED_TIME="Total script execution time is %1"}; 
                                                    Errors=@{STRINGS_FILE_LOAD_ERROR="Can't load strings resource file.";
                                                                NOT_ADMIN="Current execution context/user is not elevated";
                                                                IN_WINPE="Running in WinPE"};
                                                    Defaults=@{REGISTRY_LOCATION="HKLM:\Software\ConfigMgrStartup";
                                                                REGISTRY_LOGLOCATION_VALUE="Log Location"}}}


 
$msgFileLoaded = Start-Logging -Component $scriptProperties.Name -Properties $scriptProperties

if(!(Test-IsAdmin)) {
    Write-LogMsg -MsgProperties $scriptProperties -MsgType Error -Message $scriptProperties.Strings.Errors.NOT_ADMIN
}
elseif(Test-InWinPE) {
    Write-LogMsg -MsgProperties $scriptProperties -MsgType Error -Message $scriptProperties.Errors.IN_WINPE
}
elseif($msgFileLoaded -eq $true) {

    if((Open-Config -ConfigurationFile $ConfigurationFilePath -Properties $scriptProperties) -eq $true) {

    }
}

Stop-Logging -Properties $scriptProperties

