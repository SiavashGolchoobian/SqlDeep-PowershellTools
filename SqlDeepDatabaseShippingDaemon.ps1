# region Include required files
#
$ScriptDirectory = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
try {
    Import-Module Sql
    #. ("$ScriptDirectory\SqlDeepLogWriter.ps1")
    #. ("$ScriptDirectory\SqlDeepDatabaseShipping.ps1")
}
catch {
    Write-Host "Error while loading supporting PowerShell Scripts" 
}
#endregion
