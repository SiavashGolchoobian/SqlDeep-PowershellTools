<#
.SYNOPSIS
    A script module that provides some functionality.

.DESCRIPTION
    A detailed description of what the script module does.

.PARAMETER Input
    The input parameter for the Get-SomeData function.

.PARAMETER Output
    The output parameter for the Set-SomeData function.

.EXAMPLE
    Import-Module .\\MyModule.psm1

    Get-SomeData -Input C:\\input.txt | Set-SomeData -Output C:\\output.txt

    Imports the script module and runs the Get-SomeData and Set-SomeData functions with the specified input and output files.
#>
Enum LogType {
    INF
    WRN
    ERR
};
Enum ArchiveTimeScale {
    ByYear
    ByMonth
    ByDay
    ByHour
    ByTime
};
Class LogWriter {
    [string]$EventSource=$env:COMPUTERNAME
    [string]$Module="UNKNOWN"
    [bool]$LogToConsole
    [bool]$LogToFile
    [string]$LogFilePath
    [bool]$LogToTable
    [string]$LogInstanceConnectionString
    [string]$LogTableName="[dbo].[Events]"
    [int]$ErrCount=0
    [int]$WrnCount=0
    hidden[string]$LogFilePathPattern
    
    LogWriter(){
        $this.Init($null,"UNKNOWN",$true,$false,$null,$false,$null,$null)
    }
    LogWriter([string]$EventSource,[string]$Module){
        $this.Init($EventSource,$Module,$true,$false,$null,$false,$null,$null)
    }
    LogWriter([string]$EventSource,[string]$Module,[bool]$LogToConsole){
        $this.Init($EventSource,$Module,$LogToConsole,$false,$null,$false,$null,$null)
    }
    LogWriter([string]$EventSource,[string]$Module,[bool]$LogToFile,[string]$LogFilePath){
        $this.Init($EventSource,$Module,$true,$LogToFile,$LogFilePath,$false,$null,$null)
    }
    LogWriter([string]$EventSource,[string]$Module,[bool]$LogToTable,[string]$LogInstanceConnectionString,[string]$LogTableName){
        $this.Init($EventSource,$Module,$true,$false,$null,$LogToTable,$LogInstanceConnectionString,$LogTableName)
    }
    LogWriter([string]$EventSource,[string]$Module,[bool]$LogToConsole,[bool]$LogToFile,[string]$LogFilePath,[bool]$LogToTable,[string]$LogInstanceConnectionString,[string]$LogTableName){
        $this.Init($EventSource,$Module,$LogToConsole,$LogToFile,$LogFilePath,$LogToTable,$LogInstanceConnectionString,$LogTableName)
    }
    Reinitialize(){  #Reinitialize current instance with modified attributes
        $this.Init($this.EventSource,$this.Module,$this.LogToConsole,$this.LogToFile,$this.LogFilePath,$this.LogToTable,$this.LogInstanceConnectionString,$this.LogTableName)
    }
    hidden Init([string]$EventSource,[string]$Module,[bool]$LogToConsole,[bool]$LogToFile,[string]$LogFilePath,[bool]$LogToTable,[string]$LogInstanceConnectionString,[string]$LogTableName){
        $mySysToday = (Get-Date -Format "yyyyMMdd").ToString()
        $mySysTodayTime = (Get-Date -Format "yyyyMMdd_HHmm").ToString()
        $this.EventSource=$EventSource
        $this.Module=$Module
        $this.LogToConsole=$LogToConsole
        $this.LogToFile=$LogToFile
        $this.LogFilePathPattern=$LogFilePath
        $this.LogFilePath=($LogFilePath.Replace("{Date}",$mySysToday)).Replace("{DateTime}",$mySysTodayTime)
        $this.LogToTable=$LogToTable
        $this.LogInstanceConnectionString=$LogInstanceConnectionString
        $this.LogTableName=$LogTableName
        $this.ErrCount=0
        $this.WrnCount=0

        if ($null -eq $this.EventSource -or $this.EventSource.Trim.Length -eq 0) {$this.EventSource=$env:COMPUTERNAME}
        if ($null -eq $this.Module -or $this.Module.Trim.Length -eq 0) {$this.Module="UNKNOWN"}
        if ($null -eq $this.LogFilePath -or $this.LogFilePath.Trim.Length -eq 0) {$this.LogToFile=$false}
        if ($null -eq $this.LogInstanceConnectionString -or $this.LogInstanceConnectionString -eq 0) {$this.LogToTable=$false}
        if ($null -eq $this.LogTableName -or $this.LogTableName -eq 0) {$this.LogTableName="[dbo].[Events]"}
        if ($this.LogToTable) {$this.LogToTable=$this.CreateLogTable()}
    }

    #region Functions
    hidden [bool]CreateLogTable() {   #Create Events Table to Write Logs to a database table if not exists
        [bool]$myAnswer=[bool]$true
        [string]$myCommand="
        DECLARE @myTableName nvarchar(255)
        SET @myTableName=N'"+ $this.LogTableName +"'
        
        IF NOT EXISTS (
            SELECT 
                1
            FROM 
                sys.all_objects AS myTable
                INNER JOIN sys.schemas AS mySchema ON myTable.schema_id=mySchema.schema_id
            WHERE 
                mySchema.name + '.' + myTable.name = REPLACE(REPLACE(@myTableName,'[',''),']','')
        ) BEGIN
            CREATE TABLE" + $this.LogTableName + "(
                [Id] [bigint] IDENTITY(1,1) NOT NULL,
                [Module] [nvarchar](255) NOT NULL,
                [EventTimeStamp] [datetime] NOT NULL,
                [Serverity] [nvarchar](50) NULL,
                [Description] [nvarchar](max) NULL,
                [InsertTime] [datetime] NOT NULL DEFAULT (getdate()),
                [IsSMS] [bit] NOT NULL DEFAULT (0),
                [IsSent] [bit] NOT NULL DEFAULT (0),
                PRIMARY KEY CLUSTERED ([Id] ASC) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 85, Data_Compression=Page) ON [PRIMARY]
            ) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
        END
        "
        try{
            Invoke-Sqlcmd -ConnectionString ($this.LogInstanceConnectionString) -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Stop
        }Catch{
            Write-Error ($_.ToString()).ToString()
            $myAnswer=[bool]$false
        }
        return $myAnswer
    }
    hidden [string]GetFunctionName ([int]$StackNumber = 1) { #Create Log Table if not exists
        return [string]$(Get-PSCallStack)[$StackNumber].FunctionName
    }
    [void] Write([string]$Content) {
        $this.Write($Content,[LogType]::INF,$false,$false,$null)
    }
    [void] Write([string]$Content, [LogType]$Type) {
        $this.Write($Content,$Type,$false,$false,$null)
    }
    [void] Write([string]$Content, [LogType]$Type, [bool]$Terminate){
        $this.Write($Content,$Type,$Terminate,$false,$null)
    }
    [void] Write([string]$Content, [LogType]$Type, [bool]$Terminate, [bool]$IsSMS){
        $this.Write($Content,$Type,$Terminate,$IsSMS,$null)
    }
    [void] Write([string]$Content, [LogType]$Type, [bool]$Terminate, [bool]$IsSMS, [string]$EventTimeStamp){    #Fill Log file
        Write-Verbose "Write-Log started."
        [string]$myIsSMS="0"
        [string]$myEventTimeStamp=(Get-Date).ToString()
        [string]$myContent=""
        [string]$myColor="White"

        Switch ($Type) {
            INF {$myColor="White";$myIsSMS="0"}
            WRN {$myColor="Yellow";$myIsSMS="1";$this.WrnCount+=1}
            ERR {$myColor="Red";$myIsSMS="1";$this.ErrCount+=1}
            Default {$myColor="White"}
        }
        if ($IsSMS){$myIsSMS="1"} else {$myIsSMS="0"}
        try {
            $myEventTimeStamp=([datetime]$EventTimeStamp).ToString()
        }
        catch {
            $myEventTimeStamp=(Get-Date).ToString()
        }
        

        $myContent = $myEventTimeStamp + "`t" + $Type + "`t(" + ($this.GetFunctionName(3)) +")`t"+ $Content
        if ($Terminate) { $myContent+=$myContent + "`t" + ". Process terminated with " + $this.ErrCount.ToString() + " Error count and " + $this.WrnCount.ToString() + " Warning count."}

        #-----Write to stdout
        Write-Output $myContent
        #-----Write to console
        If ($this.LogToConsole) {
            Write-Host $myContent -ForegroundColor $myColor
        }
        #-----Write to file
        If ($this.LogToFile) {
            try {
                Add-Content -Path ($this.LogFilePath) -Value $myContent
            }
            catch {
                Write-Error ("Log to file " + $this.LogFilePath + " exception. LogToFile is disabled.")
                Write-Error ($_.ToString()).ToString()
                $this.LogToFile=$false
            }
        }
        #-----Write to database table
        if ($this.LogToTable) {
            try{
                $myCommand=
                    "
                    INSERT INTO "+ $this.LogTableName +" ([EventSource],[Module],[EventTimeStamp],[Serverity],[Description],[IsSMS])
                    VALUES(N'"+$this.EventSource+"',N'"+ $this.Module +"',CAST('"+$myEventTimeStamp+"' AS DATETIME),N'"+$Type+"',N'"+$Content.Replace("'",'"')+"',"+$myIsSMS+")
                    "
                Invoke-Sqlcmd -ConnectionString ($this.LogInstanceConnectionString) -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Ignore
            }
            catch {
                Write-Error ("Log to table " + $this.LogTableName + " exception. LogToTable is disabled.")
                Write-Error ($_.ToString()).ToString()
                $this.LogToTable=$false
            }
        }
        if ($Terminate){Exit}
        Write-Verbose "Write-Log finished."
    }
    [void] ArchiveLogFilesToZipFile([ArchiveTimeScale]$ArchiveFileTemplate,[int]$KeepLatestFilesCount=2,[int]$BatchCount=5,[bool]$RemoveSourceFiles=$true){
        Write-Verbose "ArchiveLogFilesToZipFile(4 param) started."
        [string]$myArchiveFolderPath=$null
        [string]$ArchiveFilePattern=$null

        if ($this.LogToFile) {
            $myArchiveFolderPath=(Split-Path -Parent ($this.LogFilePath)).Trim()
            $myArchiveFilePattern=$this.LogFilePathPattern.Replace("{Date}","").Replace("{DateTime}","")
            $this.ArchiveLogFilesToZipFile($myArchiveFolderPath,$myArchiveFilePattern,$ArchiveFilePattern,$ArchiveFileTemplate,$KeepLatestFilesCount,$BatchCount,$RemoveSourceFiles)
        }else{
            Write-Output ("Log to files is disabled.")
        }
        Write-Verbose "ArchiveLogFilesToZipFile(4 param) finished."
    }
    [void] ArchiveLogFilesToZipFile([string]$ArchiveFilePattern,[ArchiveTimeScale]$ArchiveFileTemplate,[int]$KeepLatestFilesCount=2,[int]$BatchCount=5,[bool]$RemoveSourceFiles=$true){
        Write-Verbose "ArchiveLogFilesToZipFile(5 param) started."
        [string]$myArchiveFolderPath=$null

        if ($this.LogToFile) {
            $myArchiveFolderPath=(Split-Path -Parent ($this.LogFilePath)).Trim()
            $this.ArchiveLogFilesToZipFile($myArchiveFolderPath,$ArchiveFilePattern,$ArchiveFileTemplate,$KeepLatestFilesCount,$BatchCount,$RemoveSourceFiles)
        }else{
            Write-Output ("Log to files is disabled.")
        }
        Write-Verbose "ArchiveLogFilesToZipFile(5 param) finished."
    }
    [void] ArchiveLogFilesToZipFile([string]$ArchiveFolderPath,[string]$ArchiveFilePattern,[ArchiveTimeScale]$ArchiveFileTemplate,[int]$KeepLatestFilesCount=2,[int]$BatchCount=5,[bool]$RemoveSourceFiles=$true){
        Write-Verbose "ArchiveLogFilesToZipFile(6 param) started."
        [string]$mySourceFolderPath=$null
        [string]$mySourceFilePattern=$null

        if ($this.LogToFile) {
            $mySourceFolderPath=(Split-Path -Parent ($this.LogFilePath))
            $mySourceFilePattern=(Split-Path -Path ($this.LogFilePathPattern) -Leaf)
            $this.ArchiveLogFilesToZipFile($mySourceFolderPath,$mySourceFilePattern,$ArchiveFolderPath,$ArchiveFilePattern,$ArchiveFileTemplate,$KeepLatestFilesCount,$BatchCount,$RemoveSourceFiles)
        }else{
            Write-Output ("Log to files is disabled.")
        }
        Write-Verbose "ArchiveLogFilesToZipFile(6 param) finished."
    }
    [void] ArchiveLogFilesToZipFile([string]$SourceFolderPath,[string]$SourceFilePattern,[string]$ArchiveFolderPath,[string]$ArchiveFilePattern,[ArchiveTimeScale]$ArchiveFileTemplate,[int]$KeepLatestFilesCount=2,[int]$BatchCount=5,[bool]$RemoveSourceFiles=$true){
        Write-Verbose "ArchiveLogFilesToZipFile started."
        [string]$mySourceFilePattern=$null
        [string]$myZipPathTemplate=$null
        [string]$myGroupByPattern=$null
        
        if ($BatchCount -lt 0){$BatchCount=5}
        if ($KeepLatestFilesCount -le 0){$KeepLatestFilesCount=2}
        $SourceFolderPath=$SourceFolderPath.Trim()
        $SourceFilePattern=$SourceFilePattern.Trim()
        $ArchiveFolderPath=$ArchiveFolderPath.Trim()
        $ArchiveFilePattern=$ArchiveFilePattern.Trim()
        if ($ArchiveFolderPath[-1] -ne "\") {$ArchiveFolderPath+="\"}
        if ($SourceFolderPath[-1] -ne "\") {$SourceFolderPath+="\"}
        $mySourceFilePattern="^"+($SourceFilePattern.Replace("{Database}",".*").Replace("{Date}","([0-9]{8})").Replace("{DateTime}","([0-9]{8})_([0-9]{4})"))+"$"
        $myZipPathTemplate = $ArchiveFolderPath + $ArchiveFilePattern + "{myGroup}.zip"

        Switch ($ArchiveFileTemplate) {
            ByYear {$myGroupByPattern="yyyy"}
            ByMonth {$myGroupByPattern="yyyyMM"}
            ByDay {$myGroupByPattern="yyyyMMdd"}
            ByHour {$myGroupByPattern="yyyyMMddHH"}
            ByTime {$myGroupByPattern="yyyyMMddHHmmss"}
            Default {$myGroupByPattern="yyyyMMdd"}
        }

        Write-Output ("SourceFolderPath is: "+$SourceFolderPath)
        Write-Output ("SourceFilePattern is: "+$mySourceFilePattern)
        Write-Output ("ArchiveFolderPath is: "+$ArchiveFolderPath)
        Write-Output ("ArchiveFilePattern is: "+$ArchiveFilePattern)
        Write-Output ("ZipPathTemplate is: "+$myZipPathTemplate)

        $mySelectedFiles = Get-ChildItem -Path $SourceFolderPath | Where-Object -Property Name -match $mySourceFilePattern | Sort-Object -Property LastWriteTime | Select-Object -SkipLast $KeepLatestFilesCount
        $myGroupedFiles = $mySelectedFiles | Group-Object -Property {$_.LastWriteTime.ToString($myGroupByPattern)}
        ForEach ($myGroup in $myGroupedFiles) {
            $myGroupCountOfFiles=[math]::Ceiling($myGroup.Count/$BatchCount)
            For ($myCounter=1; $myCounter -le $myGroupCountOfFiles; $myCounter+=1) {
                try{
                    $myCurrentZipPath = $myZipPathTemplate.Replace('{myGroup}',$myGroup.Name)
                    Write-Output ("Compressing files to " + $myCurrentZipPath + " (" + $myCounter.ToString() + " of " + $myGroupCountOfFiles.ToString() + ")...")
                    $myGroupChunk = $myGroup.Group | Select-Object -Skip (($myCounter-1)*$BatchCount) -First $BatchCount
                    $myGroupChunk | Compress-Archive -DestinationPath $myCurrentZipPath -CompressionLevel Optimal -Update
                    $myGroupChunk | ForEach-Object{Write-Output ($_.Name + " is compressed to " + $myCurrentZipPath + ".")}
                    Write-Output ("Batch Compression finished.")
                    if ($RemoveSourceFiles){
                        Write-Output ("Removing source files started.")
                        $myGroupChunk | Remove-Item 
                        Write-Output ("Source files removed.")
                    }
                }catch{
                    Write-Error ($_.ToString()).ToString()
                }
            }
        }

        Write-Verbose "ArchiveLogFilesToZipFile finished."
    }
    [void] DeleteArchiveFiles([ArchiveTimeScale]$ArchiveFileTemplate,[int]$KeepLatestFilesCount=2){
        Write-Verbose "DeleteArchiveFiles(2 param) started."
        [string]$myArchiveFolderPath=$null

        if ($this.LogToFile) {
            $myArchiveFolderPath=(Split-Path -Parent ($this.LogFilePath)).Trim()
            $this.DeleteArchiveFiles($myArchiveFolderPath,$ArchiveFileTemplate,$KeepLatestFilesCount)
        }else{
            Write-Output ("Log to files is disabled.")
        }
        Write-Verbose "DeleteArchiveFiles(2 param) finished."
    }
    [void] DeleteArchiveFiles([string]$ArchiveFolderPath,[ArchiveTimeScale]$ArchiveFileTemplate,[int]$KeepLatestFilesCount=2){
        Write-Verbose "DeleteArchiveFiles(3 param) started."
        [string]$myArchiveFilePattern=$null

        if ($this.LogToFile) {
            $myArchiveFilePattern=(Split-Path -Path ($this.LogFilePathPattern) -Leaf).Replace("{Date}","").Replace("{DateTime}","")
            $this.DeleteArchiveFiles($ArchiveFolderPath,$myArchiveFilePattern,$ArchiveFileTemplate,$KeepLatestFilesCount)
        }else{
            Write-Output ("Log to files is disabled.")
        }
        Write-Verbose "DeleteArchiveFiles(3 param) finished."

    }
    [void] DeleteArchiveFiles([string]$ArchiveFolderPath,[string]$ArchiveFilePattern,[ArchiveTimeScale]$ArchiveFileTemplate,[int]$KeepLatestFilesCount=2){
        Write-Verbose "DeleteArchiveFiles started."
        [string]$myZipPathTemplate=$null
        
        if ($KeepLatestFilesCount -lt 0){$KeepLatestFilesCount=2}
        $ArchiveFolderPath=$ArchiveFolderPath.Trim()
        $ArchiveFilePattern=$ArchiveFilePattern.Trim()
        if ($ArchiveFolderPath[-1] -ne "\") {$ArchiveFolderPath+="\"}
        $myZipPathTemplate=$ArchiveFilePattern + "{myGroup}.zip"
        
        Switch ($ArchiveFileTemplate) {
            ByYear {$myZipPathTemplate="^"+$myZipPathTemplate.Replace("{myGroup}","([0-9]{4})\")+"$"}
            ByMonth {$myZipPathTemplate="^"+$myZipPathTemplate.Replace("{myGroup}","([0-9]{6})\")+"$"}
            ByDay {$myZipPathTemplate="^"+$myZipPathTemplate.Replace("{myGroup}","([0-9]{8})\")+"$"}
            ByHour {$myZipPathTemplate="^"+$myZipPathTemplate.Replace("{myGroup}","([0-9]{10})\")+"$"}
            ByTime {$myZipPathTemplate="^"+$myZipPathTemplate.Replace("{myGroup}","([0-9]{14})\")+"$"}
            Default {$myZipPathTemplate="^"+$myZipPathTemplate.Replace("{myGroup}","([0-9]{4})\")+"$"}
        }

        Write-Output ("ArchiveFolderPath is: "+$ArchiveFolderPath)
        Write-Output ("ArchiveFilePattern is: "+$ArchiveFilePattern)
        Write-Output ("ZipPathTemplate is: "+$myZipPathTemplate)

        try{
            $mySelectedFiles = Get-ChildItem -Path $ArchiveFolderPath | Where-Object -Property Name -match $myZipPathTemplate | Sort-Object -Property LastWriteTime | Select-Object -SkipLast $KeepLatestFilesCount
            Write-Output ("Removing archive files started.")
            $mySelectedFiles | Remove-Item 
            $mySelectedFiles | ForEach-Object{Write-Output ($_.Name + " is removed.")}
            Write-Output ("Archive files removed.")
        }catch{
            Write-Error ($_.ToString()).ToString()
        }
        Write-Verbose "DeleteArchiveFiles finished."
    }
    #endregion
}

#region Functions
Function New-LogWriter {  #Create new LogWriter instance
    Param
        (
            [Parameter(Mandatory=$true)][string]$EventSource,
            [Parameter(Mandatory=$true)][string]$Module,
            [Parameter(Mandatory=$false)][Switch]$LogToConsole=$false,
            [Parameter(Mandatory=$false)][Switch]$LogToFile=$false,
            [Parameter(Mandatory=$false)][string]$LogFilePath,
            [Parameter(Mandatory=$false)][Switch]$LogToTable=$false,
            [Parameter(Mandatory=$false)][string]$LogInstanceConnectionString,
            [Parameter(Mandatory=$false)][string]$LogTableName="[dbo].[Events]"
         )

    Write-Verbose "Creating New-LogWriter"
    [string]$myEventSource=$EventSource
    [string]$myModule=$Module
    [bool]$myLogToConsole=$LogToConsole
    [bool]$myLogToFile=$LogToFile
    [string]$myLogFilePath=$LogFilePath
    [bool]$myLogToTable=$LogToTable
    [string]$myLogInstanceConnectionString=$LogInstanceConnectionString
    [string]$myLogTableName=$LogTableName

    [LogWriter]::New($myEventSource,$myModule,$myLogToConsole,$myLogToFile,$myLogFilePath,$myLogToTable,$myLogInstanceConnectionString,$myLogTableName)
    Write-Verbose "New-LogWriter Created"
}
#endregion

#region Export
Export-ModuleMember -Function New-LogWriter
#endregion

# SIG # Begin signature block
# MIIbxQYJKoZIhvcNAQcCoIIbtjCCG7ICAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAzeo3OA2mvy8aM
# OR39DeJwDE5wdtokP38ROyrOVkmWN6CCFhswggMUMIIB/KADAgECAhAT2c9S4U98
# jEh2eqrtOGKiMA0GCSqGSIb3DQEBBQUAMBYxFDASBgNVBAMMC3NxbGRlZXAuY29t
# MB4XDTI0MTAyMzEyMjAwMloXDTI2MTAyMzEyMzAwMlowFjEUMBIGA1UEAwwLc3Fs
# ZGVlcC5jb20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDivSzgGDqW
# woiD7OBa8twT0nzHGNakwZtEzvq3HcL8bCgfDdp/0kpzoS6IKpjt2pyr0xGcXnTL
# SvEtJ70XOgn179a1TlaRUly+ibuUfO15inrwPf1a6fqgvPMoXV6bMxpsbmx9vS6C
# UBYO14GUN10GtlQgpUYY1N0czabC7yXfo8EwkO1ZTGoXADinHBF0poKffnR0EX5B
# iL7/WGRfT3JgFZ8twYMoKOc4hJ+GZbudtAptvnWzAdiWM8UfwQwcH8SJQ7n5whPO
# PV8e+aICbmgf9j8NcVAKUKqBiGLmEhKKjGKaUow53cTsshtGCndv5dnMgE2ppkxh
# aWNn8qRqYdQFAgMBAAGjXjBcMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggr
# BgEFBQcDAzAWBgNVHREEDzANggtzcWxkZWVwLmNvbTAdBgNVHQ4EFgQUwoHZNhYd
# VvtzY5g9WlOViG86b8EwDQYJKoZIhvcNAQEFBQADggEBAAvLzZ9wWrupREYXkcex
# oLBwbxjIHueaxluMmJs4MSvfyLG7mzjvkskf2AxfaMnWr//W+0KLhxZ0+itc/B4F
# Ep4cLCZynBWa+iSCc8iCF0DczTjU1exG0mUff82e7c5mXs3oi6aOPRyy3XBjZqZd
# YE1HWl9GYhboC5kY65Z42ZsbNyPOM8nhJNzBKq9V6eyNE2JnxlrQ1v19lxXOm6WW
# Hgnh++tUf9k8DI1D7Da3bQqsj8O+ACHjhjMVzWKqAtnDxydaOOjRhKWIlHUQ7fLW
# GYFZW2JXnogqxFR2tzdpZxsNgD4vHFzt1CspiHzhIsMwfQFxIg44Ny/U96l2aVpR
# 6lUwggWNMIIEdaADAgECAhAOmxiO+dAt5+/bUOIIQBhaMA0GCSqGSIb3DQEBDAUA
# MGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsT
# EHd3dy5kaWdpY2VydC5jb20xJDAiBgNVBAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQg
# Um9vdCBDQTAeFw0yMjA4MDEwMDAwMDBaFw0zMTExMDkyMzU5NTlaMGIxCzAJBgNV
# BAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdp
# Y2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDCCAiIw
# DQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAL/mkHNo3rvkXUo8MCIwaTPswqcl
# LskhPfKK2FnC4SmnPVirdprNrnsbhA3EMB/zG6Q4FutWxpdtHauyefLKEdLkX9YF
# PFIPUh/GnhWlfr6fqVcWWVVyr2iTcMKyunWZanMylNEQRBAu34LzB4TmdDttceIt
# DBvuINXJIB1jKS3O7F5OyJP4IWGbNOsFxl7sWxq868nPzaw0QF+xembud8hIqGZX
# V59UWI4MK7dPpzDZVu7Ke13jrclPXuU15zHL2pNe3I6PgNq2kZhAkHnDeMe2scS1
# ahg4AxCN2NQ3pC4FfYj1gj4QkXCrVYJBMtfbBHMqbpEBfCFM1LyuGwN1XXhm2Tox
# RJozQL8I11pJpMLmqaBn3aQnvKFPObURWBf3JFxGj2T3wWmIdph2PVldQnaHiZdp
# ekjw4KISG2aadMreSx7nDmOu5tTvkpI6nj3cAORFJYm2mkQZK37AlLTSYW3rM9nF
# 30sEAMx9HJXDj/chsrIRt7t/8tWMcCxBYKqxYxhElRp2Yn72gLD76GSmM9GJB+G9
# t+ZDpBi4pncB4Q+UDCEdslQpJYls5Q5SUUd0viastkF13nqsX40/ybzTQRESW+UQ
# UOsxxcpyFiIJ33xMdT9j7CFfxCBRa2+xq4aLT8LWRV+dIPyhHsXAj6KxfgommfXk
# aS+YHS312amyHeUbAgMBAAGjggE6MIIBNjAPBgNVHRMBAf8EBTADAQH/MB0GA1Ud
# DgQWBBTs1+OC0nFdZEzfLmc/57qYrhwPTzAfBgNVHSMEGDAWgBRF66Kv9JLLgjEt
# UYunpyGd823IDzAOBgNVHQ8BAf8EBAMCAYYweQYIKwYBBQUHAQEEbTBrMCQGCCsG
# AQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0
# dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RD
# QS5jcnQwRQYDVR0fBD4wPDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29t
# L0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNybDARBgNVHSAECjAIMAYGBFUdIAAw
# DQYJKoZIhvcNAQEMBQADggEBAHCgv0NcVec4X6CjdBs9thbX979XB72arKGHLOyF
# XqkauyL4hxppVCLtpIh3bb0aFPQTSnovLbc47/T/gLn4offyct4kvFIDyE7QKt76
# LVbP+fT3rDB6mouyXtTP0UNEm0Mh65ZyoUi0mcudT6cGAxN3J0TU53/oWajwvy8L
# punyNDzs9wPHh6jSTEAZNUZqaVSwuKFWjuyk1T3osdz9HNj0d1pcVIxv76FQPfx2
# CWiEn2/K2yCNNWAcAgPLILCsWKAOQGPFmCLBsln1VWvPJ6tsds5vIy30fnFqI2si
# /xK4VC0nftg62fC2h5b9W9FcrBjDTZ9ztwGpn1eqXijiuZQwggauMIIElqADAgEC
# AhAHNje3JFR82Ees/ShmKl5bMA0GCSqGSIb3DQEBCwUAMGIxCzAJBgNVBAYTAlVT
# MRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5j
# b20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0yMjAzMjMw
# MDAwMDBaFw0zNzAzMjIyMzU5NTlaMGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5E
# aWdpQ2VydCwgSW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQgVHJ1c3RlZCBHNCBSU0E0
# MDk2IFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0EwggIiMA0GCSqGSIb3DQEBAQUAA4IC
# DwAwggIKAoICAQDGhjUGSbPBPXJJUVXHJQPE8pE3qZdRodbSg9GeTKJtoLDMg/la
# 9hGhRBVCX6SI82j6ffOciQt/nR+eDzMfUBMLJnOWbfhXqAJ9/UO0hNoR8XOxs+4r
# gISKIhjf69o9xBd/qxkrPkLcZ47qUT3w1lbU5ygt69OxtXXnHwZljZQp09nsad/Z
# kIdGAHvbREGJ3HxqV3rwN3mfXazL6IRktFLydkf3YYMZ3V+0VAshaG43IbtArF+y
# 3kp9zvU5EmfvDqVjbOSmxR3NNg1c1eYbqMFkdECnwHLFuk4fsbVYTXn+149zk6ws
# OeKlSNbwsDETqVcplicu9Yemj052FVUmcJgmf6AaRyBD40NjgHt1biclkJg6OBGz
# 9vae5jtb7IHeIhTZgirHkr+g3uM+onP65x9abJTyUpURK1h0QCirc0PO30qhHGs4
# xSnzyqqWc0Jon7ZGs506o9UD4L/wojzKQtwYSH8UNM/STKvvmz3+DrhkKvp1KCRB
# 7UK/BZxmSVJQ9FHzNklNiyDSLFc1eSuo80VgvCONWPfcYd6T/jnA+bIwpUzX6ZhK
# WD7TA4j+s4/TXkt2ElGTyYwMO1uKIqjBJgj5FBASA31fI7tk42PgpuE+9sJ0sj8e
# CXbsq11GdeJgo1gJASgADoRU7s7pXcheMBK9Rp6103a50g5rmQzSM7TNsQIDAQAB
# o4IBXTCCAVkwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQUuhbZbU2FL3Mp
# dpovdYxqII+eyG8wHwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYD
# VR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMHcGCCsGAQUFBwEBBGsw
# aTAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUF
# BzAChjVodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVk
# Um9vdEc0LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2Vy
# dC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAgBgNVHSAEGTAXMAgGBmeB
# DAEEAjALBglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQADggIBAH1ZjsCTtm+YqUQi
# AX5m1tghQuGwGC4QTRPPMFPOvxj7x1Bd4ksp+3CKDaopafxpwc8dB+k+YMjYC+Vc
# W9dth/qEICU0MWfNthKWb8RQTGIdDAiCqBa9qVbPFXONASIlzpVpP0d3+3J0FNf/
# q0+KLHqrhc1DX+1gtqpPkWaeLJ7giqzl/Yy8ZCaHbJK9nXzQcAp876i8dU+6Wvep
# ELJd6f8oVInw1YpxdmXazPByoyP6wCeCRK6ZJxurJB4mwbfeKuv2nrF5mYGjVoar
# CkXJ38SNoOeY+/umnXKvxMfBwWpx2cYTgAnEtp/Nh4cku0+jSbl3ZpHxcpzpSwJS
# pzd+k1OsOx0ISQ+UzTl63f8lY5knLD0/a6fxZsNBzU+2QJshIUDQtxMkzdwdeDrk
# nq3lNHGS1yZr5Dhzq6YBT70/O3itTK37xJV77QpfMzmHQXh6OOmc4d0j/R0o08f5
# 6PGYX/sr2H7yRp11LB4nLCbbbxV7HhmLNriT1ObyF5lZynDwN7+YAN8gFk8n+2Bn
# FqFmut1VwDophrCYoCvtlUG3OtUVmDG0YgkPCr2B2RP+v6TR81fZvAT6gt4y3wSJ
# 8ADNXcL50CN/AAvkdgIm2fBldkKmKYcJRyvmfxqkhQ/8mJb2VVQrH4D6wPIOK+XW
# +6kvRBVK5xMOHds3OBqhK/bt1nz8MIIGvDCCBKSgAwIBAgIQC65mvFq6f5WHxvnp
# BOMzBDANBgkqhkiG9w0BAQsFADBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGln
# aUNlcnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5
# NiBTSEEyNTYgVGltZVN0YW1waW5nIENBMB4XDTI0MDkyNjAwMDAwMFoXDTM1MTEy
# NTIzNTk1OVowQjELMAkGA1UEBhMCVVMxETAPBgNVBAoTCERpZ2lDZXJ0MSAwHgYD
# VQQDExdEaWdpQ2VydCBUaW1lc3RhbXAgMjAyNDCCAiIwDQYJKoZIhvcNAQEBBQAD
# ggIPADCCAgoCggIBAL5qc5/2lSGrljC6W23mWaO16P2RHxjEiDtqmeOlwf0KMCBD
# Er4IxHRGd7+L660x5XltSVhhK64zi9CeC9B6lUdXM0s71EOcRe8+CEJp+3R2O8oo
# 76EO7o5tLuslxdr9Qq82aKcpA9O//X6QE+AcaU/byaCagLD/GLoUb35SfWHh43rO
# H3bpLEx7pZ7avVnpUVmPvkxT8c2a2yC0WMp8hMu60tZR0ChaV76Nhnj37DEYTX9R
# eNZ8hIOYe4jl7/r419CvEYVIrH6sN00yx49boUuumF9i2T8UuKGn9966fR5X6kgX
# j3o5WHhHVO+NBikDO0mlUh902wS/Eeh8F/UFaRp1z5SnROHwSJ+QQRZ1fisD8UTV
# DSupWJNstVkiqLq+ISTdEjJKGjVfIcsgA4l9cbk8Smlzddh4EfvFrpVNnes4c16J
# idj5XiPVdsn5n10jxmGpxoMc6iPkoaDhi6JjHd5ibfdp5uzIXp4P0wXkgNs+CO/C
# acBqU0R4k+8h6gYldp4FCMgrXdKWfM4N0u25OEAuEa3JyidxW48jwBqIJqImd93N
# Rxvd1aepSeNeREXAu2xUDEW8aqzFQDYmr9ZONuc2MhTMizchNULpUEoA6Vva7b1X
# CB+1rxvbKmLqfY/M/SdV6mwWTyeVy5Z/JkvMFpnQy5wR14GJcv6dQ4aEKOX5AgMB
# AAGjggGLMIIBhzAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIwADAWBgNVHSUB
# Af8EDDAKBggrBgEFBQcDCDAgBgNVHSAEGTAXMAgGBmeBDAEEAjALBglghkgBhv1s
# BwEwHwYDVR0jBBgwFoAUuhbZbU2FL3MpdpovdYxqII+eyG8wHQYDVR0OBBYEFJ9X
# LAN3DigVkGalY17uT5IfdqBbMFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwz
# LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFJTQTQwOTZTSEEyNTZUaW1l
# U3RhbXBpbmdDQS5jcmwwgZAGCCsGAQUFBwEBBIGDMIGAMCQGCCsGAQUFBzABhhho
# dHRwOi8vb2NzcC5kaWdpY2VydC5jb20wWAYIKwYBBQUHMAKGTGh0dHA6Ly9jYWNl
# cnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFJTQTQwOTZTSEEyNTZU
# aW1lU3RhbXBpbmdDQS5jcnQwDQYJKoZIhvcNAQELBQADggIBAD2tHh92mVvjOIQS
# R9lDkfYR25tOCB3RKE/P09x7gUsmXqt40ouRl3lj+8QioVYq3igpwrPvBmZdrlWB
# b0HvqT00nFSXgmUrDKNSQqGTdpjHsPy+LaalTW0qVjvUBhcHzBMutB6HzeledbDC
# zFzUy34VarPnvIWrqVogK0qM8gJhh/+qDEAIdO/KkYesLyTVOoJ4eTq7gj9UFAL1
# UruJKlTnCVaM2UeUUW/8z3fvjxhN6hdT98Vr2FYlCS7Mbb4Hv5swO+aAXxWUm3Wp
# ByXtgVQxiBlTVYzqfLDbe9PpBKDBfk+rabTFDZXoUke7zPgtd7/fvWTlCs30VAGE
# sshJmLbJ6ZbQ/xll/HjO9JbNVekBv2Tgem+mLptR7yIrpaidRJXrI+UzB6vAlk/8
# a1u7cIqV0yef4uaZFORNekUgQHTqddmsPCEIYQP7xGxZBIhdmm4bhYsVA6G2WgNF
# YagLDBzpmk9104WQzYuVNsxyoVLObhx3RugaEGru+SojW4dHPoWrUhftNpFC5H7Q
# EY7MhKRyrBe7ucykW7eaCuWBsBb4HOKRFVDcrZgdwaSIqMDiCLg4D+TPVgKx2EgE
# deoHNHT9l3ZDBD+XgbF+23/zBjeCtxz+dL/9NWR6P2eZRi7zcEO1xwcdcqJsyz/J
# ceENc2Sg8h3KeFUCS7tpFk7CrDqkMYIFADCCBPwCAQEwKjAWMRQwEgYDVQQDDAtz
# cWxkZWVwLmNvbQIQE9nPUuFPfIxIdnqq7ThiojANBglghkgBZQMEAgEFAKCBhDAY
# BgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3
# AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3DQEJBDEi
# BCD8geXOSatfQEUAWDE8nUHUeS3SbiNZLjpnX+chTbnEcTANBgkqhkiG9w0BAQEF
# AASCAQC7nVcR0KLJVn8UfdFc4NcTRJoKBcjlkxYgFYG4BLvan0DmU3Yxt7rmcKNz
# l/9qAl1zMpqT/vQ2s0NHO/oSVPU9OfeUxkcuo8U15MH8vVNPchdnSmEVS26ePwBn
# FCuK9B8MHHBkuhYZm3GP4UkEX3mOdsynGDGDEZNPSzNAxTktxbDon4P+ckXlZdoc
# H0duIXRZP/hCd/iKdP6ThUrnX1VvuAe6AqSpyAMPZuq0lBSqPc/6g6oJovgFxV1u
# BBbjZmR9Mue9iHjuMTx3Hag3M7CjJao2nQsWFDkdFUp32btsg395QsBp7TKbS8by
# R+ob1/kfF2vqlNkf3uyyTNWHeyq+oYIDIDCCAxwGCSqGSIb3DQEJBjGCAw0wggMJ
# AgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTsw
# OQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0IFJTQTQwOTYgU0hBMjU2IFRpbWVT
# dGFtcGluZyBDQQIQC65mvFq6f5WHxvnpBOMzBDANBglghkgBZQMEAgEFAKBpMBgG
# CSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTI0MTEwMTIw
# MjQzOFowLwYJKoZIhvcNAQkEMSIEIKfjigBP6vuyruCCGHUuGfHJ5nXIJWDufr6U
# uJVmGNisMA0GCSqGSIb3DQEBAQUABIICALMgOxV6UrbfaB1hGxrQEFnV70sf67ES
# UH5BMJSJRqCgKKN/MAVs8PiCz1vN4eszijHyEznSSStqchIIpy4TFyuyfEdvszE0
# XFjprji93JQGKRRW/hS2kTv06HJNoUen+nLXeYRNyp6B/B9m0NloV4/r2zFkLS/j
# hTZfRaSirIxVBrrR5WPyTlilfo/XTgASmtFKWZNryLD0cbyrn1KWBWWlwi7A2m6X
# 9T4zASQAE8ShkfWfmJbR0BrohTrtvvJ+oJIOt/8kS94yQKCbvAjz6AuKfTVPUax9
# i4Df8azgDvr16pszLGvXHvcRHWuRp/VCZLMGY9o9nYpCs9xjo8ZgnTKJ7t8V9b2a
# 5nljA4rLEIX9dc8waeVyHhPeIoSzKymiotNWFogKDXiDNr4Y0HIC/o7FwR2iu+Il
# vzWTHn3RGRiA1Jptoz2OwLfFRkCdi3Yi3+eusGXFqe+yR2UQzJHFIXxQ/Uu57Pd8
# bSEem5OSJAIT/SX026/Nzqrq3d3JqA7GOhD1mgs1RJj+wwkE9SZnpqsb5L0Jyp3B
# 2B0A3PPLnUADf4reDfFhVYFGSJUDqfZNGJgM04vVTuagz2FvpShaVQk21R0akeK0
# rFueIPQiNuZ4wtAyRQMmEGV8yEMIv99sw16qATAXuXcydM9TLyS27aASrIkikEzu
# LUIDr4iY08Li
# SIG # End signature block
