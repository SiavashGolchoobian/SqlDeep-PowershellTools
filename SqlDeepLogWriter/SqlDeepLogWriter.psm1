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
Using module .\SqlDeepLogWriterEnums.psm1
Class LogWriter {
    [string]$EventSource=$env:COMPUTERNAME
    [string]$Module="UNKNOWN"
    [bool]$LogToConsole
    [bool]$LogToFile
    [string]$LogFilePath
    [bool]$LogToTable
    [string]$LogInstanceConnectionString
    [string]$LogTableName="[dbo].[Events]"
    hidden [int]$ErrCount=0
    hidden [int]$WrnCount=0
    
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
    hidden Init([string]$EventSource,[string]$Module,[bool]$LogToConsole,[bool]$LogToFile,[string]$LogFilePath,[bool]$LogToTable,[string]$LogInstanceConnectionString,[string]$LogTableName){
        $mySysToday = (Get-Date -Format "yyyyMMdd").ToString()
        $mySysTodayTime = (Get-Date -Format "yyyyMMdd_HHmm").ToString()
        $this.EventSource=$EventSource
        $this.Module=$Module
        $this.LogToConsole=$LogToConsole
        $this.LogToFile=$LogToFile
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
        $this.Write($Content,[LogType]::INF,$false)
    }
    [void] Write([string]$Content, [LogType]$Type) {
        $this.Write($Content,$Type,$false)
    }
    [void] Write([string]$Content, [LogType]$Type, [bool]$Terminate){    #Fill Log file
        Write-Verbose "Write-Log started"
        [string]$myIsSMS="0"
        [string]$myEventTimeStamp=(Get-Date).ToString()
        [string]$myContent=""
        [string]$myColor="White"

        Switch ($Type) {
            [LogType]::INF {$myColor="White";$myIsSMS="0"}
            [LogType]::WRN {$myColor="Yellow";$myIsSMS="1";$mySysWrnCount+=1}
            [LogType]::ERR {$myColor="Red";$myIsSMS="1";$mySysErrCount+=1}
            Default {$myColor="White"}
        }

        $myContent = $myEventTimeStamp + "`t" + $Type + "`t(" + ($this.GetFunctionName(3)) +")`t"+ $Content
        if ($Terminate) { $myContent+=$myContent + "`t" + ". Prcess terminated with " + $this.ErrCount.ToString() + " Error count and " + $this.WrnCount.ToString() + " Warning count."}

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
        Write-Verbose "Write-Log finished"
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