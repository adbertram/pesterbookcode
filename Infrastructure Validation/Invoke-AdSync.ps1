## Grab the employee names from a CSV file
$employees = Import-Csv -Path C:\employees.csv

foreach ($employee in $employees) {
    ## Check to see if the user account already exists
    $adUserParams = @{
        Filter = "givenName -eq '$($employee.FirstName)' -and surName -eq '$($employee.LastName)'"
    }
    if (-not (Get-ADUser @adUserParams)) {
        ## If not, create a new user account <FirstName><LastName>
        $newAdUserParams = @{
            Name = "$($employee.FirstName)$($employee.LastName)"
            GivenName = $employee.FirstName
            SurName = $employee.LastName
            Department = $employee.Department
            Title = $employee.Title
        }
        New-ADUser @newAdUserParams
    }
}