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

# SIG # Begin signature block
# MIIbxQYJKoZIhvcNAQcCoIIbtjCCG7ICAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBehLkQiYApv55e
# HrMhGndIkXg+KW0MF6iIgmQrtYnktKCCFhswggMUMIIB/KADAgECAhAT2c9S4U98
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
# BCCuqd77eVu7iwCsxVunfl6h9SO3FJvaujx3mBCUD5gV3DANBgkqhkiG9w0BAQEF
# AASCAQDCDK809J5pR0Q1Jkm52yp27WXyXYX5ligxsRvL3Jm0AQJI9NpMXNuPQgxq
# +XFfz7Kis2c89VWN2hUYTUGI5gabyv9vnWbbGIUzJ77IUbKZ+CzAkba9YmTrye4a
# gBwxKSI8chZfFgnfRZDIF9cgQJCtyqCne2vD28BFGoo8VKVXHEoKdhAPdOm0BW6r
# Rxu4DeqfienL/z33OfQkWsKASnLm/ijdT8gncHlISGGeai9eTQDfhUyMPzz1etwe
# 58A3Wtu9LtYyZMKxTkBJqDJoEMcRu4ld0A4RbbppZNeeLfE3Z82T+PM3/GO0jEa7
# jod2koPDbNHI0w6ztNUVuEHR2GD0oYIDIDCCAxwGCSqGSIb3DQEJBjGCAw0wggMJ
# AgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTsw
# OQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0IFJTQTQwOTYgU0hBMjU2IFRpbWVT
# dGFtcGluZyBDQQIQC65mvFq6f5WHxvnpBOMzBDANBglghkgBZQMEAgEFAKBpMBgG
# CSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTI0MTAzMDEz
# MTIxMFowLwYJKoZIhvcNAQkEMSIEIPIoIfB41UfN2slhcd01W04bPvVt82gj9/r4
# sL5qgfcGMA0GCSqGSIb3DQEBAQUABIICAH+SdjifzkNx+PXz6MwrvboWDrEhcz2s
# 9oWdq6xME3nUJuEX4nN02oajq0dOCU7SpKBZu8bE3fko8FFPbwLkN+1NaAlHlIjt
# uSo2D0e3ypXFr7OZs3rItb++1+zN/1LEHoD8O6Jji6oBY2vZEil4N252WGmFxSzh
# 29i7qBVlCHar8PbRGpdAl7qbW4apKbkeXOFjMXVmy+EXDoYM3xhEd7xqIDIPKIit
# /AySaIHhlwEZFVaCe4lI7uJbLewHDv6KhrR8i6LAdOleJYXoQQ/CZWlRF3N9yzX8
# 3rYoIPy+BFWzTIq3UXbyY95SmfwpCjoIPJ8Webi4LqaHcIvIwSxKeA3zxzjsfNtL
# EBS4i80SevCch9yc4AECchCNqN3jkML7lhWjOOKAd2DstW8oNiaml37Atl5JY+1W
# Nh4UsR6MvKR/2vhpNYi+KB5W2O2xfIu/Jl7gpPZlD1PSO160b+3IvDz+RXZRN1ZH
# LXU44OovRznkrtv6pPzJo38zZRSiwSwcUBdNcXfjZG7glVDa/PH8a6/oFLcfrnOh
# ZLDCj5niMCyZXKsA1VZyr1fS7tOiWjW9UHQNF6+G2zeqkmlSHRRm7yQFoUcsE4h9
# SRwj5bZ48CD24BWx6HTegmUO0mV3mVxnwlXzLMjtJmBSEDArvixZD42eKDd8J9ip
# Q3XWHQlk92BU
# SIG # End signature block
