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
    param(
        [Parameter(Mandatory=$false,HelpMessage="Force function to return this path as SqlPackage.exe file path, if exists.")]$SqlPackageFilePath
    )
    begin {
        Write-Host ('Find-SqlPackageLocation started.')
        Write-Host ('Find-SqlPackageLocation called with ' + $SqlPackageFilePath)
        [string]$myAnswer=$null
        [string]$myExeName = "SqlPackage.exe";
        [string]$mySqlPackageFilePath=$null;
        [string]$mySqlPackageFolderPath=$null;
    }
    process{
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
            if ($myCustomInstallLocation -ne '' -and $null -ne $myCustomInstallLocation) {
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
                Write-Host ('Product Version is ' + $myCurrentVersion + ' and Currently loaded version is ' + $myProductVersion)
                if ($myProductVersion -gt $myCurrentVersion){
                    $myCurrentVersion=$myProductVersion
                    $myAnswer=$mySqlPackageExe
                    Write-Host ('Product Version changes to ' + $myCurrentVersion)
                }
                Write-Host ($myProductVersion + ' ' + $mySqlPackageExe);
            } 
        }
        catch {
            Write-Error ('Find-SqlPackageLocations failed with error: ' + $_.ToString());
        }

        if ($null -ne $SqlPackageFilePath -and ($SqlPackageFilePath.Length) -ge 10) {
            if (Test-Path -Path $SqlPackageFilePath -PathType Leaf) {
                $myAnswer=$SqlPackageFilePath
                Write-Host ('User defined SqlPackageFilePath that send by caller was used with path: ' + $myAnswer)
            }else{
                Write-Host ('User defined SqlPackageFilePath parameter path does not exists' + $SqlPackageFilePath)
            }
        }else{
            Write-Host ('User defined SqlPackageFilePath parameter is null or empty' + $SqlPackageFilePath + ', file length is ' + $SqlPackageFilePath.Length.ToString())
        }
        if ($myAnswer) {
            $mySqlPackageFilePath=$myAnswer
            $mySqlPackageFolderPath=(Get-Item -Path $mySqlPackageFilePath).DirectoryName
            $mySqlPackageFolderPath=Clear-FolderPath -FolderPath $mySqlPackageFolderPath
            if (-not ($env:Path).Contains($mySqlPackageFolderPath)) {$env:path = $env:path + ';'+$mySqlPackageFolderPath+';'}
        }
        Write-Host $myAnswer
        return $myAnswer
    }
    end {
        if ($null -eq $myAnswer) {
            Write-Host 'DacPac module does not found, please Downloaded and install it from official site https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage-download?view=sql-server-ver16 or install informal version from https://www.powershellgallery.com/packages/PublishDacPac/ or run this command in powershell console: Install-Module -Name PublishDacPac'
        }
        Write-Host ('Find-SqlPackageLocation finished.')
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
            $null=SqlPackage /Action:Extract /OverwriteFiles:true /SourceConnectionString:$ConnectionString /TargetFile:$DacpacFilePath /Properties:IgnorePermissions=False /Properties:ExtractAllTableData=False /Properties:TableData=[maintenance].[_CatalogOfFields] /Properties:TableData=[maintenance].[_CatalogOfTables] /Properties:TableData=[maintenance].[Lookup_VariableSource] /Properties:TableData=[maintenance].[Variables];
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

# SIG # Begin signature block
# MIIbxQYJKoZIhvcNAQcCoIIbtjCCG7ICAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAgjhqQKtmbU8Z2
# NS3JljyvS02fHoV4mhucSTnKnUyv/qCCFhswggMUMIIB/KADAgECAhAT2c9S4U98
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
# BCB2584O+K8SbZj+n2C7y0D9jbnatWIYQmk5ksqRyC/HZzANBgkqhkiG9w0BAQEF
# AASCAQC2g4sFb/GgmKz4ezDZo2CrV2qo+L3QLDj6BOyxhaRTNaj+ftIUPW0QRpJF
# tMWd77uI256XOVfls8w+J37lXJJwqryLBtb+a67sHDLLDWLCO+U3TvKGYybRIUSG
# nlxwjIVkvleqDcOYhOLQ/DE2AlhxdU/2zV2W+R6G+sPEZhgBBEMPD6NOxvWln8yI
# PRwNR6qI+QuqeW1ttNFtyxAxxVTVKdr2JN7Fu0Vwcw20XALXJagjCW9s1MbC0OOB
# cUFsC4tEJ1r873tCLh8XpN7QKOsKKWTZlq1I3OgvLWGbAFmjOigyODpnGh+ApoBh
# wDxGyqVHzGs6KWLqo+dvefQzu65GoYIDIDCCAxwGCSqGSIb3DQEJBjGCAw0wggMJ
# AgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTsw
# OQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0IFJTQTQwOTYgU0hBMjU2IFRpbWVT
# dGFtcGluZyBDQQIQC65mvFq6f5WHxvnpBOMzBDANBglghkgBZQMEAgEFAKBpMBgG
# CSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTI0MTExMjE2
# NTcxNVowLwYJKoZIhvcNAQkEMSIEII5baUXhzBt0RQhOB9wicXKZ5i+dQUPjyaLO
# vVmgXD4oMA0GCSqGSIb3DQEBAQUABIICAH5rNjvVP9FDUKXhaxprHu8NeROYvv76
# x5X+/aysZGeEpV7XFfCKfHEOLURt7iczjleoTqRCZ28bjKSB18LJjRVvbTEbJ9/S
# Pi0CzHPZdKY7jMnpjMgv+y4/XNpDYsfTGdYngu62fx1ky19W371siJ0t6Y5MDpuZ
# 69ciYOipAkaObmneS+AkhdsW6tFhRHf1p5+hGXBpBBmgjO8HRhFb5ZzdTwFCxjpd
# 8D7lS8TxUAzjaOnfZ3NoQZYxrbf1W3KKmUkGJKcZBeIl0JuF22On66A7HQtyO4Qf
# o10MD61WR0tN/zZv6OjFHvE0x3mLZt6Ye0UbCz7sJoxgn/kNeCtdsMLtLf2y83FH
# W77iI1SalhEZf2ff/ncHk0jFSuCN9ewuf4Y+Kif8/JexjoqGI6xuk3EggOiLSVUc
# M64I4DzM9El0N95mHUrxxWb44KamsBZaS5HZuCh2WJEpa6re4m8zTogCX5bT6SAj
# hog7kI+YXGVE7zxxlvmiRSR14Mzf2fuG26eag0O/dv5PCfmkMrmLDNlJilfXx35Y
# 4sYoe0TBDGJwjsO/b1MMiSIjJlZaFv+wr4bJLnZ57leCkNITTQ53dmVQIrmINnOk
# biWDSx+Gac29lQAeW3sNH+WJTUG+CWApL7N2d5pXPExk4qq+PHnfTzL9vhZZCK3b
# 7apHF+NB4849
# SIG # End signature block
