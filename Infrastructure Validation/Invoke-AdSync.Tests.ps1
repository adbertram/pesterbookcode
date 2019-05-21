describe 'AD CSV Sync script' {

    $employeeCsvFileLocation = 'C:\TestArtifacts\Employees.csv'

    $dependencies = @(
        @{
            Label = "CSV file at $employeeCsvLocation exists"
            Test = { Test-Path -Path $employeeCsvLocation }
        }
        @{
            Label = "The $(whoami) user can read AD user objects"
            Test = { [bool](Get-AdUser -Identity 'S-1-5-21-4117810001-3432493942-696130396-500') }
        }
    )

    foreach ($dep in $dependencies) {
        if (-not (& $dep)) {
            throw "The check: $($dep.Label) failed. Halting all tests.'
        }
    }

    & C:\Scripts\Invoke-Adsync.ps1

    it 'when provided a valid CSV file, it creates a user account for each employee inside the CSV file' {

        ## This should be covered by a unit test assuming the CSV has all the right properties
        $employees = Import-Csv -Path $employeeCsvFileLocation

        foreach ($employee in $employees) {
            $adUserParams = @{
                Filter = "givenName -eq '$($employee.FirstName)' -and surName -eq '$($employee.LastName)'"
                Properties = 'Department','Title'
            }
            $user = Get-ADUser @adUserParams
            $user | should not benullorempty
            $user.Department | should be $employee.Department
            $user.Title | should be $employee.Title
        }
    }

}