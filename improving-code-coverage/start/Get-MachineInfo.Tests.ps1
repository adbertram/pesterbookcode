$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"

Describe "Get-MachineInfo" {

    It "should return object over CIM" {
        $params = @{'ComputerName'='localhost'
                    'Protocol'='Wsman'}
        $result = Get-MachineInfo @params
        $result.computername | Should Be 'localhost'
    }

    It "should not allow WMI as protocol" {
        {Get-MachineInfo -Protocol WMI} |
        Should Throw
    }

    It "should write error log" {
        $params = @{'ComputerName'='FAIL'
                    'LogFailuresToPath'='TESTDRIVE:\fails.txt'
                    'Protocol'='Wsman'}
        Get-MachineInfo @params
        Get-Content TESTDRIVE:\fails.txt |
        Should Be "FAIL"
    }

}
