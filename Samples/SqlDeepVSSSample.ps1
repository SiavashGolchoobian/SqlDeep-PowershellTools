Import-Module .\SqlDeepVSS.psm1
$myShadowCopy=New-ShadowCopy -ComputerName localhost -Drive D: -Confirm:$false
Mount-ShadowCopy -Id ($myShadowCopy.Id) -Path D:\ShadowCopyContent
Unmount-ShadowCopy -Path D:\ShadowCopyContent
Remove-ShadowCopy -ComputerName localhost -Id ($myShadowCopy.Id)