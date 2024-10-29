#Create self-signed certificate, Encrypt file by Certificate Public Key, Decrypt file by Certificate Private Key, Export Public key for others
#--------------------------------------------------------------Parameters.
Param(
    [Parameter(Mandatory=$true)][ValidateSet("Encrypt","Decrypt","CreateCert","ExportPublicKey","ExportPrivateAndPublicKey")][string]$Action,
	[Parameter(Mandatory=$true)][string]$CertSubjectName,
    [Parameter(Mandatory=$false)][string]$InputFilePath,
	[Parameter(Mandatory=$false)][string]$OutputFilePath,
    [Parameter(Mandatory=$false)][string]$PrivateKeyPassword
    )

    [string]$myTempInputFilePath
    [string]$myCertSubjectName

    $myTempInputFilePath=$null
    $myCertSubjectName="cn="+$CertSubjectName

    switch ($Action.ToUpper()) {
        "ENCRYPT" {  
            if (($InputFilePath) -and (Test-Path -Path $InputFilePath)) {
                $myTempInputFilePath=$InputFilePath+".temp"
                certutil -encode $InputFilePath $myTempInputFilePath
                Get-Content $myTempInputFilePath | Protect-CmsMessage -To $myCertSubjectName -OutFile $OutputFilePath
                Remove-Item -Path $myTempInputFilePath -Force
            } else {
                Write-Host "InputFilePath does not exist." -ForegroundColor Red
            }
        }
        "DECRYPT" {
            if (($InputFilePath) -and (Test-Path -Path $InputFilePath)) {
                $myTempInputFilePath=$InputFilePath+".temp"
                Unprotect-CmsMessage -Path $InputFilePath | Out-File -FilePath $myTempInputFilePath
                certutil -decode $myTempInputFilePath $OutputFilePath
                Remove-Item -Path $myTempInputFilePath -Force
            } else {
                Write-Host "InputFilePath does not exist." -ForegroundColor Red
            }
        }
        "CREATECERT" {
            [X509Certificate] $myCert
            $myCert=Get-Childitem -Path Cert:\CurrentUser\My -DocumentEncryptionCert | Where-Object -Property Subject -eq $myCertSubjectName
            if(!($myCert)) {
                New-SelfSignedCertificate -DnsName $CertSubjectName -CertStoreLocation "Cert:\CurrentUser\My" -KeyUsage KeyEncipherment,DataEncipherment,KeyAgreement,DigitalSignature -KeyAlgorithm "RSA" -KeyLength 2048 -Type DocumentEncryptionCert -NotAfter (Get-Date).AddYears(5)
            } else {
                Write-Host "Certificat is already exist." -ForegroundColor Red
            }
        }
        "EXPORTPUBLICKEY" {
            if (($OutputFilePath)) {
                [X509Certificate] $myCert
                $myCert=Get-Childitem -Path Cert:\CurrentUser\My -DocumentEncryptionCert | Where-Object -Property Subject -eq $myCertSubjectName
                Export-Certificate -Cert $myCert -FilePath $OutputFilePath
            } else {
                Write-Host "OutputFilePath does not exist." -ForegroundColor Red
            }
        }
        "EXPORTPRIVATEANDPUBLICKEY" {   #Export as pfx file
            if (($OutputFilePath)) {
                [X509Certificate] $myCert
                $myCert=Get-Childitem -Path Cert:\CurrentUser\My -DocumentEncryptionCert | Where-Object -Property Subject -eq $myCertSubjectName
                Export-PfxCertificate -Cert $myCert -FilePath $OutputFilePath -Password (ConvertTo-SecureString -AsPlainText $PrivateKeyPassword -Force)
            } else {
                Write-Host "OutputFilePath does not exist." -ForegroundColor Red
            }
        }
    }