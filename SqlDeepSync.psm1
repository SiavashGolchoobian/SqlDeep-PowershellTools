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
        return $myAnswer
    }
    end {}
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
            $null=SqlPackage /Action:Extract /OverwriteFiles:true /SourceConnectionString:$ConnectionString /TargetFile:$DacpacFilePath;
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
function Publish-DatabaseDacPac {
    [OutputType([bool])]
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Target database connection string")][ValidateNotNullOrEmpty()][string]$ConnectionString,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage=".dapac file path to import")][ValidateNotNullOrEmpty()][string]$DacpacFilePath
    )
    begin {}
    process {
        [bool]$myAnswer=$false;
        try
        {
            if (Test-Path -Path $DacpacFilePath) {
                $null=SqlPackage /Action:Publish /OverwriteFiles:true /TargetConnectionString:$ConnectionString /SourceFile:$DacpacFilePath /Properties:VerifyDeployment=False /Properties:DeployDatabaseInSingleUserMode=True /Properties:DisableAndReenableDdlTriggers=True /Properties:DropObjectsNotInSource=True /Properties:IgnoreExtendedProperties=True /Properties:BackupDatabaseBeforeChanges=True;
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
    param (
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Refrence database connection string")][ValidateNotNullOrEmpty()][string]$RefrenceDatabaseConnectionString,    
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Refrence .dapac file path")][ValidateNotNullOrEmpty()][string]$RefrenceDacpacFilePath,
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Target of update database connection string")][ValidateNotNullOrEmpty()][string]$TargetDatabaseConnectionString,
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="A .dapac file path use as target of update")][ValidateNotNullOrEmpty()][string]$TargetDacpacFilePath,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Delta script file path")][ValidateNotNullOrEmpty()][string]$DeltaScriptFilePath,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Target database name")][ValidateNotNullOrEmpty()][string]$DatabaseName
    )
    begin {}
    process {
        [bool]$myAnswer=$false;
        try
        {
            if ((Test-Path -Path $RefrenceDacpacFilePath) -and (Test-Path -Path $TargetDacpacFilePath)) {
                $null=SqlPackage /Action:Script /OverwriteFiles:true /SourceFile:$RefrenceDacpacFilePath /TargetFile:$TargetDacpacFilePath /TargetDatabaseName:$DatabaseName /OutputPath:$DeltaScriptFilePath /Properties:DropObjectsNotInSource=True;
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
function Publish-DacPacDeltaScript {
    [OutputType([bool])]
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Target of update database connection string")][ValidateNotNullOrEmpty()][string]$ConnectionString,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Delta script file path")][ValidateNotNullOrEmpty()][string]$DeltaScriptFilePath
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

[string]$mySqlPackageFilePath=$null
[string]$mySqlPackageFolderPath=$null
[string]$myConnectionString=$null
[string]$mySourceDacpacFilePath=$null
[string]$myTargetDacpacFilePath=$null
[string]$myDeltaFilePath=$null
[bool]$mySourceIsExported=$false
[bool]$myTargetIsExported=$false
[bool]$myDeltaIsExported=$false
[bool]$myPublishIsApplied=$false

#SqlPackage stanalone install package for all OS platforms:  https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage-download?view=sql-server-ver16
#https://www.mssqltips.com/sqlservertip/4759/sql-server-database-schema-synchronization-via-sqlpackageexe-and-powershell/
#https://stackoverflow.com/questions/20673516/command-line-api-for-schema-compare-in-ssdt-sql-server-database-project

#Add path for SQLPackage.exe to environment variables
$mySqlPackageFilePath=Find-SqlPackageLocation
$mySqlPackageFolderPath=(Get-Item -Path $mySqlPackageFilePath).DirectoryName
$mySqlPackageFolderPath=Clear-FolderPath -FolderPath $mySqlPackageFolderPath
if (-not ($env:Path).Contains($mySqlPackageFolderPath)) {$env:path = $env:path + ';'+$mySqlPackageFolderPath+';'}

Write-Host "Phase 1: Export Source Database dacpac"
$myConnectionString='Data Source=172.18.3.49,2019;Initial Catalog=SqlDeep;user=sa;password=Armin1355$;TrustServerCertificate=True;Encrypt=True'
$mySourceDacpacFilePath='E:\log\SourceSqlDeep.dacpac'
$mySourceIsExported=Export-DatabaseDacPac -ConnectionString $myConnectionString -DacpacFilePath $mySourceDacpacFilePath

Write-Host "Phase 2: Export Target Database dacpac"
$myConnectionString='Data Source=172.18.3.49,2022;Initial Catalog=SqlDeep;user=sa;password=Armin1355$;TrustServerCertificate=True;Encrypt=True'
$myTargetDacpacFilePath='E:\log\TargetSqlDeep.dacpac'
$myTargetIsExported=Export-DatabaseDacPac -ConnectionString $myConnectionString -DacpacFilePath $myTargetDacpacFilePath

Write-Host "Phase 3: Generate Delta script"
$myDeltaFilePath='E:\log\Delta.sql'
$myDeltaIsExported=Get-DacPacDeltaScript -RefrenceDacpacFilePath $mySourceDacpacFilePath -TargetDacpacFilePath $myTargetDacpacFilePath -DeltaScriptFilePath $myDeltaFilePath -DatabaseName 'SqlDeep'

Write-Host "Phase 4: Publish Source Database dacpac to Target Database"
$myConnectionString='Data Source=172.18.3.49,2022;Initial Catalog=SqlDeep;user=sa;password=Armin1355$;TrustServerCertificate=True;Encrypt=True'
$myPublishIsApplied=Publish-DatabaseDacPac -ConnectionString $myConnectionString -DacpacFilePath $mySourceDacpacFilePath
#$myPublishIsApplied=Publish-DacPacDeltaScript -ConnectionString $myConnectionString -DeltaScriptFilePath $myDeltaFilePath