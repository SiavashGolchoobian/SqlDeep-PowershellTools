Using module .\SqlDeepDatabaseShipping.psm1

Class BackupTest:DatabaseShipping {
    [string]$Text;

    BackupTest(){
        $this.Text='Hello World'
    }
    [string]Print(){
        return $this.Text;
    }
}

#Test inherited class
$myBackupTest=[BackupTest]::New()