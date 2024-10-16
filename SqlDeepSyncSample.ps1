Using module .\SqlDeepSync.psm1

[string]$mySourceConnectionString=$null
[string]$myTargetConnectionString=$null
[string]$mySourceDacpacFilePath=$null
[string]$myTargetDacpacFilePath=$null
[string]$myDeltaFilePath=$null

$mySourceConnectionString='Data Source=172.18.3.49,2019;Initial Catalog=SqlDeep;user=sa;password=Armin1355$;TrustServerCertificate=True;Encrypt=True'
$mySourceDacpacFilePath='E:\log\SourceSqlDeep.dacpac'
$myTargetConnectionString='Data Source=172.18.3.49,2022;Initial Catalog=SqlDeep;user=sa;password=Armin1355$;TrustServerCertificate=True;Encrypt=True'
$myTargetDacpacFilePath='E:\log\TargetSqlDeep.dacpac'
$myDeltaFilePath='E:\log\Delta.sql'

#Sample #1: Export Sourcedb and Targetdb dacpac files, compare them and generate change script file
    Write-Host "Phase 1: Export Source Database dacpac"
    Export-DatabaseDacPac -ConnectionString $mySourceConnectionString -DacpacFilePath $mySourceDacpacFilePath

    Write-Host "Phase 2: Export Target Database dacpac"
    Export-DatabaseDacPac -ConnectionString $myTargetConnectionString -DacpacFilePath $myTargetDacpacFilePath

    Write-Host "Phase 3: Generate Delta script"
    Get-DacPacDeltaScript -RefrenceDacpacFilePath $mySourceDacpacFilePath -TargetDacpacFilePath $myTargetDacpacFilePath -DeltaScriptFilePath $myDeltaFilePath -DatabaseName 'SqlDeep'

    Write-Host "Phase 4: Publish Source Database dacpac to Target Database"
    Publish-DacPacDeltaScript -ConnectionString $myConnectionString -DeltaScriptFilePath $myDeltaFilePath

#Sample #2: Export Sourcedb dacpac file, compare it withtarget database and publish changes to target
    Write-Host "Phase 0: Update environment variable to contain SqlPackage path"
    $mySqlPackageFilePath=Find-SqlPackageLocation
    $mySqlPackageFolderPath=(Get-Item -Path $mySqlPackageFilePath).DirectoryName
    $mySqlPackageFolderPath=Clear-FolderPath -FolderPath $mySqlPackageFolderPath
    if (-not ($env:Path).Contains($mySqlPackageFolderPath)) {$env:path = $env:path + ';'+$mySqlPackageFolderPath+';'}
    
    Write-Host "Phase 1: Export Source Database dacpac"
    Export-DatabaseDacPac -ConnectionString $mySourceConnectionString -DacpacFilePath $mySourceDacpacFilePath
    
    Write-Host "Phase 2: Publish Source dacpac to Target Database"
    Publish-DatabaseDacPac -ConnectionString $myTargetConnectionString -DacpacFilePath $mySourceDacpacFilePath