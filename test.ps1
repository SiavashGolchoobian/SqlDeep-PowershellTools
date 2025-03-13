Using module .\SqlDeepLogWriter.psm1
Using module .\SqlDeepAlwaysOnSync.psm1

$myLogWriter=New-LogWriter -EventSource ($env:computername) -Module 'AlwaysOnSync' -LogToConsole
$myAlwaysOnSync=[BackupShipping]::New('Data Source=ubuntu,2019;Initial Catalog=master;TrustServerCertificate=True;Encrypt=True;user id=sa;password=Armin1355$',$myLogWriter)
$myAlwaysOnSync.Sync()
# [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.Management.Smo') | Out-Null;
# [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.Management.Common') | Out-Null;

# [string]$myConnectionString='Data Source=172.18.3.49,2019;User Id=sa;Password=Armin1355$;initial catalog = master;Encrypt=True;TrustServerCertificate=True'
# #[Microsoft.SqlServer.Management.Smo.SqlSmoObject]$mySqlServer = New-Object ('Microsoft.SqlServer.Management.Smo.Server')
# [Microsoft.SqlServer.Management.Smo.SqlSmoObject]$mySqlServer = $null;
# $mySqlServer = New-Object ('Microsoft.SqlServer.Management.Smo.Server')
# $mySqlServer.ConnectionContext.ConnectionString=$myConnectionString
# $mySqlServer.JobServer.Jobs.Count


#-------------------------------
[string]$baseUri='https://www.nemoudar.com/blog/page/{pageNo}/'
[string]$baseFilePath='D:\Learning\Nemoudar\{pageNo}.xml'
$pages=1,2,3,4,5

$pages | %{
    $currentUri=$baseUri.Replace('{pageNo}',$_);
    $currentFilePath=$baseFilePath.Replace('{pageNo}',$_);
    Write-Host ('Saving ' + $currentUri + ' content to ' + $currentFilePath)
    Invoke-WebRequest -Uri $currentUri -OutFile $currentFilePath
}
#-------------------------------
[string]$baseUri='https://www.minoogroup.com/fa/product?page={pageNo}&order=hit'
[string]$baseFilePath='D:\Learning\Nemoudar\{pageNo}.xml'
[string]$catalogFilePath='D:\Learning\Nemoudar\catalog.txt'
[string]$pattern = '<div class="product__title">([\s\S]*?)s<\/div>'

Remove-Item -Path $catalogFilePath -Force
$pages=1

$pages | %{
    $currentUri=$baseUri.Replace('{pageNo}',$_);
    $currentFilePath=$baseFilePath.Replace('{pageNo}',$_);
    Write-Host ('Saving ' + $currentUri + ' content to ' + $currentFilePath)
    $webResponse=Invoke-WebRequest -Uri $currentUri
    $products = [regex]::Match($webResponse.Content, $pattern)[0].Groups[1].Value
    Write-Host $products
    #Out-File -FilePath $catalogFilePath -Append -InputObject ($_.ToString()+','+$currentFilePath)
}
#get-Content $catalogFilePath