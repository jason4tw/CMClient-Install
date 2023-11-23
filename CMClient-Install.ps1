
function Start-Logging {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
        [String]$Component,

        [parameter(Mandatory=$true)]
        [PSCustomObject]$Strings,

        [parameter(Mandatory=$true)]
        [HashTable]$Properties
    )
    process {
        $Locale = (Get-WinSystemLocale).LCID
        $MsgFile = "$($Properties.Location)\$Component.strings.$Locale.1.json"
        $MsgFileLoadedSuccessfuly = $true
        
        try {
            $LoadedStrings = Get-Content -Path $MsgFile -ErrorAction Stop | ConvertFrom-Json
        }
        catch {
            $MsgFile = "$($Properties.Location)\$Component.strings.json"
            
            try {
                $LoadedStrings = Get-Content -Path $MsgFile -ErrorAction Stop  | ConvertFrom-Json
            }
            catch {
                $MsgFileLoadedSuccessfuly = $false
            }
        }
        
        if($MsgFileLoadedSuccessfuly) {
            $Strings.Messages = $LoadedStrings.Messages
            $Strings.Errors = $LoadedStrings.Errors
        }

        try {
            $Properties.LogPath = Get-ItemPropertyValue -Path $Strings.Defaults.REGISTRY_LOCATION -Name $Strings.Defaults.REGISTRY_LOGLOCATION_VALUE -ErrorAction Stop
            Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Strings.Messages.DIVIDER
            Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Strings.Messages.LOG_FILE_LOADED -MessageVars @{1="`"$($Strings.Defaults.REGISTRY_LOGLOCATION_VALUE)`"";2="`"$($Strings.Defaults.REGISTRY_LOCATION)`""}
        }
        catch {
            $Properties.LogPath = "$env:TEMP\$Component.log"
            Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Strings.Messages.DIVIDER
        }

        if($MsgFileLoadedSuccessfuly) {
            Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Strings.Messages.BEGIN -MessageVars @{1 = $Properties.StartTime}
            Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Strings.Messages.LOADED_STRINGS_FILE -MessageVars @{1=$MsgFile}
        }
        else {
            Write-LogMsg -MsgProperties $Properties -MsgType Error -Message $Strings.Errors.CANT_LOAD_MESSAGES
        }

        $MsgFileLoadedSuccessfuly
    }
    end {
    }
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

        if($MessageVars.Count -gt 0) {
            foreach( $Var in $MessageVars.GetEnumerator() ) {
                $VarPatern = '%{0}' -f $Var.key
                $Message = $Message -replace $VarPatern, $Var.Value
            }
        }

        if ($PSBoundParameters.ContainsKey('MsgProperties')) {
            $Component = $MsgProperties.Name
            $Filename = $MsgProperties.Filename
            $Path = $MsgProperties.LogPath
        }

        $LogLine = "<![LOG[$Message]LOG]!>" +`
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

$MyStrings = [PSCustomObject]@{Messages=@{"DIVIDER"="----------------------------------------";LOG_FILE_LOADED="Log file location loaded from the registry %1 value at %2"}; 
                               Errors=@{CANT_LOAD_MESSAGES="Can't load strings resource file."};
                               Defaults=@{REGISTRY_LOCATION="HKLM:\Software\ConfigMgrStartup";REGISTRY_LOGLOCATION_VALUE="Log Location"}}

$Me = Get-Item -Path $PSCommandPath

$ScriptProperties = @{StartTime = $(Get-Date);
                      Name = $Me.Basename;
                      Filename = $Me.Name;
                      Location = $Me.DirectoryName;
                      LogPath = ""}
 
$MsgFileLoaded = Start-Logging -Component $ScriptName -Strings $MyStrings -Properties $ScriptProperties

if($MsgFileLoaded -eq $true) {

}
