Using module .\SqlDeepCommon.psm1
function Find-SqlPackageLocation {
    #Downloaded from https://www.powershellgallery.com/packages/PublishDacPac/
    <#
        .SYNOPSIS
        Lists all locations of SQLPackage.exe files on the machine
    
        .DESCRIPTION
        Simply finds and lists the location path to every version of SqlPackage.exe on the machine.
    
        For information on SqlPackage.exe see https://docs.microsoft.com/en-us/sql/tools/sqlpackage
    
        .EXAMPLE
        Find-SqlPackageLocations
    
        Simply lists all instances of SqlPackage.exe on the host machine
    
        .INPUTS
        None
    
        .OUTPUTS
        Output is written to standard output.
        
        .LINK
        https://github.com/DrJohnT/PublishDacPac
    
        .NOTES
        Written by (c) Dr. John Tunnicliffe, 2019-2021 https://github.com/DrJohnT/PublishDacPac
        This PowerShell script is released under the MIT license http://www.opensource.org/licenses/MIT
    #>
    [OutputType([string])]
    param()
    begin {
        [string]$myExeName = "SqlPackage.exe";
        [string]$mySqlPackageFilePath=$null;
        [string]$mySqlPackageFolderPath=$null;
    }
    process{
        [string]$myAnswer=$null
        [string]$myProductVersion=$null
        try {
            # Get SQL Server locations
            [System.Management.Automation.PathInfo[]]$myPathsToSearch = Resolve-Path -Path "${env:ProgramFiles}\Microsoft SQL Server\*\DAC\bin" -ErrorAction SilentlyContinue;
            $myPathsToSearch += Resolve-Path -Path "${env:ProgramFiles}\Microsoft SQL Server\*\Tools\Binn" -ErrorAction SilentlyContinue;
            $myPathsToSearch += Resolve-Path -Path "${env:ProgramFiles(x86)}\Microsoft SQL Server\*\Tools\Binn" -ErrorAction SilentlyContinue;
            $myPathsToSearch += Resolve-Path -Path "${env:ProgramFiles(x86)}\Microsoft SQL Server\*\DAC\bin" -ErrorAction SilentlyContinue;
            $myPathsToSearch += Resolve-Path -Path "${env:ProgramFiles(x86)}\Microsoft Visual Studio *\Common7\IDE\Extensions\Microsoft\SQLDB\DAC" -ErrorAction SilentlyContinue;
            $myPathsToSearch += Resolve-Path -Path "${env:ProgramFiles(x86)}\Microsoft Visual Studio\*\*\Common7\IDE\Extensions\Microsoft\SQLDB\DAC\" -ErrorAction SilentlyContinue;    

            # For those that install SQLPackage.exe in a completely different location, set environment variable CustomSqlPackageInstallLocation
            $myCustomInstallLocation = [Environment]::GetEnvironmentVariable('CustomSqlPackageInstallLocation');
            $myCustomInstallLocation = Clear-FolderPath -FolderPath $myCustomInstallLocation
            if ($myCustomInstallLocation -ne '') {
                if (Test-Path $myCustomInstallLocation) {
                    $myPathsToSearch += Resolve-Path -Path ($myCustomInstallLocation+'\') -ErrorAction SilentlyContinue;
                }        
            }

            foreach ($myPathToSearch in $myPathsToSearch) {
                [System.IO.FileSystemInfo[]]$mySqlPackageExes += Get-Childitem -Path $myPathToSearch -Recurse -Include $myExeName -ErrorAction SilentlyContinue;
            }

            # list all the locations found
            [string]$myCurrentVersion=''
            foreach ($mySqlPackageExe in $mySqlPackageExes) {
                $myProductVersion = $mySqlPackageExe.VersionInfo.ProductVersion.Substring(0,2);
                if ($myProductVersion -gt $myCurrentVersion){
                    $myCurrentVersion=$myProductVersion
                    $myAnswer=$mySqlPackageExe
                }
                Write-Host ($myProductVersion + ' ' + $mySqlPackageExe);
            }       
        }
        catch {
            Write-Error 'Find-SqlPackageLocations failed with error: ' + $_.ToString();
        }

        if ($myAnswer) {
            $mySqlPackageFilePath=$myAnswer
            $mySqlPackageFolderPath=(Get-Item -Path $mySqlPackageFilePath).DirectoryName
            $mySqlPackageFolderPath=Clear-FolderPath -FolderPath $mySqlPackageFolderPath
            if (-not ($env:Path).Contains($mySqlPackageFolderPath)) {$env:path = $env:path + ';'+$mySqlPackageFolderPath+';'}
        }
        return $myAnswer
    }
    end {
    }
}
function Export-DatabaseDacPac {
    [OutputType([bool])]
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Source database connection string")][ValidateNotNullOrEmpty()][string]$ConnectionString,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage=".dapac file path to export")][ValidateNotNullOrEmpty()][string]$DacpacFilePath
    )
    begin {}
    process {
        [bool]$myAnswer=$false;
        try
        {
            if (Test-Path -Path $DacpacFilePath) {Remove-Item -Path $DacpacFilePath -Force}
            $null=SqlPackage /Action:Extract /OverwriteFiles:true /SourceConnectionString:$ConnectionString /TargetFile:$DacpacFilePath /Properties:IgnorePermissions=False /Properties:ExtractAllTableData=True;
            if (Test-Path -Path $DacpacFilePath) {$myAnswer=$true}
            return $myAnswer
        }
        catch
        {       
            $myAnswer=$false;
            Write-Error($_.ToString());
            Throw;
        }
        return $myAnswer;
    }
    end {}
}
function Get-PrePublishReport {
    [OutputType([bool])]
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage=".dapac file path to import")][ValidateNotNullOrEmpty()][string]$DacpacFilePath,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Target database connection string")][ValidateNotNullOrEmpty()][string]$ConnectionString,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Report file path to export")][ValidateNotNullOrEmpty()][string]$ReportFilePath
    )
    begin {}
    process {
        [bool]$myAnswer=$false;
        try
        {
            if (Test-Path -Path $DacpacFilePath) {
                $null=SqlPackage /Action:DeployReport /OutputPath:$ReportFilePath /OverwriteFiles:true /TargetConnectionString:$ConnectionString /SourceFile:$DacpacFilePath /Properties:AllowIncompatiblePlatform=True /Properties:BackupDatabaseBeforeChanges=True /Properties:BlockOnPossibleDataLoss=False /Properties:DeployDatabaseInSingleUserMode=True /Properties:DisableAndReenableDdlTriggers=True /Properties:DropObjectsNotInSource=True /Properties:GenerateSmartDefaults=True /Properties:IgnoreExtendedProperties=True /Properties:IgnoreFilegroupPlacement=False /Properties:IgnoreFillFactor=False /Properties:IgnoreIndexPadding=False /Properties:IgnoreObjectPlacementOnPartitionScheme=False /Properties:IgnorePermissions=True /Properties:IgnoreRoleMembership=True /Properties:IgnoreSemicolonBetweenStatements=False /Properties:IncludeTransactionalScripts=True /Properties:VerifyDeployment=True;
                $myAnswer=$true
            }
            return $myAnswer
        }
        catch
        {       
            $myAnswer=$false;
            Write-Error($_.ToString());
            Throw;
        }
        return $myAnswer;
    }
    end {}
}
function Publish-DatabaseDacPac {
    [OutputType([bool])]
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage=".dapac file path to import")][ValidateNotNullOrEmpty()][string]$DacpacFilePath,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Target database connection string")][ValidateNotNullOrEmpty()][string]$ConnectionString
    )
    begin {}
    process {
        [bool]$myAnswer=$false;
        try
        {
            if (Test-Path -Path $DacpacFilePath) {
                $null=SqlPackage /Action:Publish /OverwriteFiles:true /TargetConnectionString:$ConnectionString /SourceFile:$DacpacFilePath /Properties:AllowIncompatiblePlatform=True /Properties:BackupDatabaseBeforeChanges=True /Properties:BlockOnPossibleDataLoss=False /Properties:DeployDatabaseInSingleUserMode=True /Properties:DisableAndReenableDdlTriggers=True /Properties:DropObjectsNotInSource=True /Properties:GenerateSmartDefaults=True /Properties:IgnoreExtendedProperties=True /Properties:IgnoreFilegroupPlacement=False /Properties:IgnoreFillFactor=False /Properties:IgnoreIndexPadding=False /Properties:IgnoreObjectPlacementOnPartitionScheme=False /Properties:IgnorePermissions=True /Properties:IgnoreRoleMembership=True /Properties:IgnoreSemicolonBetweenStatements=False /Properties:IncludeTransactionalScripts=True /Properties:VerifyDeployment=True;
                $myAnswer=$true
            }
            return $myAnswer
        }
        catch
        {       
            $myAnswer=$false;
            Write-Error($_.ToString());
            Throw;
        }
        return $myAnswer;
    }
    end {}
}
function Get-DacPacDeltaScript {
    [OutputType([bool])]
    [CmdletBinding(DefaultParameterSetName = 'dac_dac')]
    param (
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName = 'cstr_cstr',HelpMessage="Refrence database connection string")][ValidateNotNullOrEmpty()]
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName = 'cstr_dac',HelpMessage="Refrence database connection string")][ValidateNotNullOrEmpty()]
            [string]$RefrenceDatabaseConnectionString, 
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName = 'dac_cstr',HelpMessage="Refrence .dapac file path")][ValidateNotNullOrEmpty()]
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName = 'dac_dac',HelpMessage="Refrence .dapac file path")][ValidateNotNullOrEmpty()]
            [string]$RefrenceDacpacFilePath,
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName = 'cstr_cstr',HelpMessage="Target of update database connection string")][ValidateNotNullOrEmpty()]
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName = 'dac_cstr',HelpMessage="Target of update database connection string")][ValidateNotNullOrEmpty()]
            [string]$TargetDatabaseConnectionString,
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName = 'cstr_dac',HelpMessage="A .dapac file path use as target of update")][ValidateNotNullOrEmpty()]
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName = 'dac_dac',HelpMessage="A .dapac file path use as target of update")][ValidateNotNullOrEmpty()]
            [string]$TargetDacpacFilePath,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Delta script file path")][ValidateNotNullOrEmpty()][string]$DeltaScriptFilePath,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Target database name")][ValidateNotNullOrEmpty()][string]$DatabaseName
    )
    begin {}
    process {
        [bool]$myAnswer=$false;
        try
        {
            switch ($PSCmdlet.ParameterSetName) {
                'dac_dac' {
                    if ((Test-Path -Path $RefrenceDacpacFilePath) -and (Test-Path -Path $TargetDacpacFilePath)) {
                        if (Test-Path -Path $DeltaScriptFilePath) {Remove-Item -Path $DeltaScriptFilePath -Force}
                        $null=SqlPackage /Action:Script /OverwriteFiles:true /SourceFile:$RefrenceDacpacFilePath /TargetFile:$TargetDacpacFilePath /TargetDatabaseName:$DatabaseName /OutputPath:$DeltaScriptFilePath /Properties:DropObjectsNotInSource=True;
                        if (Test-Path -Path $DeltaScriptFilePath) {$myAnswer=$true}
                    }
                }
                'dac_cstr'{
                    if (Test-Path -Path $RefrenceDacpacFilePath) {
                        if (Test-Path -Path $DeltaScriptFilePath) {Remove-Item -Path $DeltaScriptFilePath -Force}
                        $null=SqlPackage /Action:Script /OverwriteFiles:true /SourceFile:$RefrenceDacpacFilePath /TargetConnectionString:$TargetDatabaseConnectionString /TargetDatabaseName:$DatabaseName /OutputPath:$DeltaScriptFilePath /Properties:DropObjectsNotInSource=True;
                        if (Test-Path -Path $DeltaScriptFilePath) {$myAnswer=$true}
                    }
                }
                'cstr_dac'{
                    if (Test-Path -Path $TargetDacpacFilePath) {
                        if (Test-Path -Path $DeltaScriptFilePath) {Remove-Item -Path $DeltaScriptFilePath -Force}
                        $null=SqlPackage /Action:Script /OverwriteFiles:true /SourceConnectionString:$RefrenceDatabaseConnectionString /TargetFile:$TargetDacpacFilePath /TargetDatabaseName:$DatabaseName /OutputPath:$DeltaScriptFilePath /Properties:DropObjectsNotInSource=True;
                        if (Test-Path -Path $DeltaScriptFilePath) {$myAnswer=$true}
                    }
                }
                'cstr_cstr'{
                        if (Test-Path -Path $DeltaScriptFilePath) {Remove-Item -Path $DeltaScriptFilePath -Force}
                        $null=SqlPackage /Action:Script /OverwriteFiles:true /SourceConnectionString:$RefrenceDatabaseConnectionString /TargetConnectionString:$TargetDatabaseConnectionString /TargetDatabaseName:$DatabaseName /OutputPath:$DeltaScriptFilePath /Properties:DropObjectsNotInSource=True;
                        if (Test-Path -Path $DeltaScriptFilePath) {$myAnswer=$true}
                }
            }
            return $myAnswer
        }
        catch
        {       
            $myAnswer=$false;
            Write-Error($_.ToString());
            Throw;
        }
        return $myAnswer;
    }
    end {}
}
function Publish-DacPacDeltaScript {
    [OutputType([bool])]
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Delta script file path")][ValidateNotNullOrEmpty()][string]$DeltaScriptFilePath,    
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Target of update database connection string")][ValidateNotNullOrEmpty()][string]$ConnectionString
    )
    begin {}
    process {
        [bool]$myAnswer=$false;
        try
        {
            if (Test-Path -Path $DeltaScriptFilePath) {
                Invoke-Sqlcmd -ConnectionString $ConnectionString -InputFile $DeltaScriptFilePath
                $myAnswer=$true
            }
            return $myAnswer
        }
        catch
        {       
            $myAnswer=$false;
            Write-Error($_.ToString());
            Throw;
        }
        return $myAnswer;
    }
    end {}
}
<#
Refrences:
    SqlPackage stanalone install package for all OS platforms:
        https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage-download?view=sql-server-ver16
    SqlPackage parameters:
        https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage-export?view=sql-server-ver16
        https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage-extract?view=sql-server-ver16
        https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage-pipelines?view=sql-server-ver16
    Helps:
        https://www.mssqltips.com/sqlservertip/4759/sql-server-database-schema-synchronization-via-sqlpackageexe-and-powershell/
        https://stackoverflow.com/questions/20673516/command-line-api-for-schema-compare-in-ssdt-sql-server-database-project
#>