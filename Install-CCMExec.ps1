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

        [parameter(Mandatory=$true)]
        [System.Xml.XmlElement]$ParentElement,

        [Parameter(Mandatory=$true)]
        [string]$ConfigurationType
    )

    Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Properties.Strings.Messages.CONFIG_ITEMS_FOUND -MessageVars @{1=$ConfigurationType}

    foreach($item in $ParentElement.GetElementsByTagName($ConfigurationType)) {
        Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Properties.Strings.Messages.CONFIG_ITEM_FOUND -MessageVars @{1=$item.Name;2=$item.'#text'}
    }
}

function Test-Configuration {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
        [HashTable]$Properties
    )
    
    try {
        $standardXSDFoundinXML = $false
        $standardSchemaNS = "http://home.configmgrftw.com/$($Properties.Name)"
        $standardSchemaFile = "$($Properties.Name).config.xsd"
        $doc = [System.Xml.XmlDocument]$Properties.Config
        $schemaLocations = $doc.DocumentElement.schemaLocation -split '\s+' -match '\S'
        $schemaSet = New-Object System.Xml.Schema.XmlSchemaSet
        
        while ($schemaLocations) {
            $schemaNamespace, $schemaURI, $schemaLocations = $schemaLocations
            $schemaSet.Add($schemaNamespace, $schemaURI)

            if($schemaNamespace -eq $standardSchemaNS -and $schemaURI -eq $standardSchemaFile) {
                $standardXSDFoundinXML = $true
            }
        }

        if(-not $standardXSDFoundinXML) {
            $schemaSet.Add($standardSchemaNS, $standardSchemaFile)    
        }

        $schemaSet.Compile()
        $doc.Schemas.Add($schemaSet)

        $doc.Validate([System.Xml.Schema.ValidationEventHandler] {
            param ([object] $sender, [System.Xml.Schema.ValidationEventArgs] $e)
            throw $e.Exception
        })
    }
    catch {

        if($null -ne $_.Exception.InnerException) {
            if($null -ne $_.Exception.InnerException.InnerException) {
                $e = $_.Exception.InnerException.InnerException
            }
            else {
                $e = $_.Exception.InnerException
            }
        }
        else {
            $e = $_.Exception
        }

        Write-LogMsg -MsgProperties $Properties -MsgType Error -Message $Properties.Strings.Errors.CONFIG_FILE_VALIDATE_ERROR -MessageVars @{1=$e.Message}
        return $false
    }

    return $true
}

function Open-Config {
    [CmdletBinding()]
    param (
        [Parameter()]
        [String]$ConfigurationFile,
        
        [parameter(Mandatory=$true)]
        [HashTable]$Properties
    )

    if($ConfigurationFile -eq "" -Or $null -eq $ConfigurationFile) {
        $ConfigurationFile = "$($Properties.Location)\$($Properties.Name).config.xml"
    }

    if(Test-Path -Path $ConfigurationFile) {

        $ConfigurationFile = (Convert-Path -Path $ConfigurationFile)

        Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Properties.Strings.Messages.CONFIG_FILE_LOADING -MessageVars @{1=$ConfigurationFile}

        try {
            $Properties.Config.Load(($ConfigurationFile))
        }
        catch {
            Write-LogMsg -MsgProperties $Properties -MsgType Error -Message $Properties.Strings.Errors.CONFIG_FILE_LOAD_ERROR -MessageVars @{1=$_.Exception.Message}
            return $false
        }

        # if(-not (Test-Configuration -Properties $Properties)) {
        #     return $false
        # }

        $config = @{
            $Properties.Strings.Defaults.XML_ELEMENT_OPTION = $Properties.Config.DocumentElement.$($Properties.Strings.Defaults.XML_ELEMENT_SCRIPTOPTIONS)
            $Properties.Strings.Defaults.XML_ELEMENT_PROPERTY = $Properties.Config.DocumentElement.$($Properties.Strings.Defaults.XML_ELEMENT_INSTALLOPTIONS)
            $Properties.Strings.Defaults.XML_ELEMENT_PARAMETER = $Properties.Config.DocumentElement.$($Properties.Strings.Defaults.XML_ELEMENT_INSTALLOPTIONS)
        }

        foreach($item in $config.Keys) {
            Out-Configuration -Properties $Properties -ConfigurationType $item -ParentElement $config.$item
        }
        
        return $true
    }
    else {
        Write-LogMsg -MsgProperties $Properties -MsgType Error -Message $Properties.Strings.Errors.CONFIG_FILE_NOT_FOUND -MessageVars @{1=$ConfigurationFile}
        return $false
    }
}

function Get-PassFailString {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
        [HashTable]$Properties,

        [Parameter()]
        [Bool]$PassFail,

        [Parameter()]
        [String]$Condition
    )

    if(($PassFail -eq $true -and $Condition -eq $Properties.Strings.Defaults.XML_PREREQ_CONDITION_MUST_EXIST) -Or 
        ($PassFail -eq $false -and $Condition -eq $Properties.Strings.Defaults.XML_PREREQ_CONDITION_MUST_NOT_EXIST)){
        $Properties.Strings.Messages.PASSED
    }
    else{
        $Properties.Strings.Messages.FAILED
    }
}
function Test-Prereqs {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
        [HashTable]$Properties
    )

    $allPassed = $true
    Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Properties.Strings.Messages.START_CHECK_PREREQS

    foreach($item in $Properties.Config.DocumentElement.$($Properties.Strings.Defaults.XML_ELEMENT_PREREQ).ChildNodes) {
        
        $condition = $item.$($Properties.Strings.Defaults.XML_PREREQ_CONDITION_PROPERTY)
        $msgType = ''

        if($condition -eq $Properties.Strings.Defaults.XML_PREREQ_CONDITION_MUST_EXIST) {
            $condition = $Properties.Strings.Messages.PREREQ_EXISTS
        }
        elseif($condition -eq $Properties.Strings.Defaults.XML_PREREQ_CONDITION_MUST_NOT_EXIST) {
            $condition = $Properties.Strings.Messages.PREREQ_DOESNOTEXIST
        }
        else {
            break
        }
        
        $type = $item.LocalName

        try {
            if($type -eq $Properties.Strings.Defaults.XML_ELEMENT_REGKEY) {
                $msg = $Properties.Strings.Messages.PREREQ_REGKEY
                $msgVars = @{2=$item.'#text';3=$condition}
                $itemExists = Test-Path -Path $item.'#text' -PathType Container -ErrorAction Stop
            }
            elseif($type -eq $Properties.Strings.Defaults.XML_ELEMENT_SERVICE){
                $msg = $Properties.Strings.Messages.PREREQ_SERVICE
                $msgVars = @{2=$item.'#text';3=$condition}
                $itemExists = ((Get-Service -Name $item.'#text' -ErrorAction SilentlyContinue).Count -gt 0)
            }
            elseif($type -eq $Properties.Strings.Defaults.XML_ELEMENT_REGVALUE) {
                $msg = $Properties.Strings.Messages.PREREQ_REGVALUE
                $reg = $item.'#text' -split ':', -2
                $msgVars = @{2=$reg[0];3=$reg[1];4=$condition}
                $itemExists = ((Get-ItemProperty -Path $reg[0] -Name $reg[1] -ErrorAction SilentlyContinue).Count -gt 0)
            }
            else {
                break
            }

            $msgType = 'Info'
            $msgVars['1'] = Get-PassFailString -Properties $Properties -Condition $item.Condition -PassFail $itemExists
        }
        catch {
            $msgType = 'Error'
            $msgVars['1'] = $_
            $allPassed = $false
        }

        Write-LogMsg -MsgProperties $Properties -MsgType $msgType -Message $msg -MessageVars $msgVars

        if($msgVars['1'] -eq $Properties.Strings.Messages.FAILED) {
            $allPassed = $false
        }
    }

    if($allPassed) {
        Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Properties.Strings.Messages.PREREQ_ALLPASSED
        return $true
    }
    else {
        Write-LogMsg -MsgProperties $Properties -MsgType Error -Message $Properties.Strings.Errors.PREREQ_ONEFAILED
        return $false
    }
}

function Test-Services {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
        [HashTable]$Properties
    )

    Write-LogMsg -MsgProperties $Properties -MsgType Info -Message $Properties.Strings.Messages.START_CHECK_SERVICES

    foreach($item in $Properties.Config.DocumentElement.$($Properties.Strings.Defaults.XML_ELEMENT_CHECKS).$($Properties.Strings.Defaults.XML_ELEMENT_SERVICE)) {
        Write-Host $item.Name
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

        if(Test-Prereqs -Properties $scriptProperties) {
            Test-Services -Properties $scriptProperties
        }

    }
}

Stop-Logging -Properties $scriptProperties

