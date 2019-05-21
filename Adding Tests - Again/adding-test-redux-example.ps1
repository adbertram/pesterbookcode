function Set-RemoteRegistryValue {
    param(
        $ComputerName,
        $Path,
        $Name,
        $Value
    )
    $null = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        Set-ItemProperty -Path $using:Path -Name $using:Name -Value $using:Value
    }
}

function Test-WindowsFeature {
    param(
        $ComputerName,
        $Name
    )
    if ($feature = Get-WindowsFeature -ComputerName $ComputerName -Name $Name -ErrorAction Ignore) {
        if ($feature.Installed) {
            $true
        } else {
            $false
        }
    } else {
        $false
    }
}

function Enable-IISRemoteManagement
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateScript({
            if (-not (Test-Connection -ComputerName $_ -Quiet -Count 1)) {
                throw "The computer [$_] could not be reached."
            } else {
                $true
            }
        })]
        [ValidateLength(1,15)]
        [string]$ComputerName
    )

    # Verify the IIS Management Service Windows feature is installed.
    if (Test-WindowsFeature -ComputerName $ComputerName -Name 'Web-Mgmt-Service')
    {
        # Enable Remote Management via a registry key.
        Set-RemoteRegistryValue -ComputerName $ComputerName -Path 'HKLM:\SOFTWARE\Microsoft\WebManagement\Server' -Name EnableRemoteManagement -Value 1

        # Set the IIS Remote Management service to automatically start.
        Set-Service -ComputerName $ComputerName -Name WMSvc -StartupType Automatic

        # Start the IIS Remote Management service.
        Get-Service -ComputerName $ComputerName -Name 'WMSvc' | Start-Service
    }
    else
    {
        throw 'IIS Management Service Windows feature is not installed.'
    }

}

Describe 'Enable-IISRemoteManagement' {

    context 'Input' {
        it 'when the computer being passed is offline, it will throw an exception' {

            mock 'Test-Connection' {
                $false
            }
            { Enable-IISRemoteManagement -ComputerName 'IAMOFFLINE' } | should throw 'could not be reached'
        }
    }

    context 'Execution' {
        mock 'Test-Connection' {
            $true
        }

        mock 'Test-WindowsFeature' {
            $true
        }

        mock 'Set-RemoteRegistryValue'

        mock 'Set-Service'

        mock 'Start-Service'

        mock 'Get-Service' {
            New-MockObject -Type 'System.ServiceProcess.ServiceController'
        }

        it 'when the Web-Mgmt-Service feature is already installed, it attempts to change the EnableRemoteManagement reg value to 1' {

            $null = Enable-IISRemoteManagement -ComputerName 'SOMETHING'

            $assMParams = @{
                CommandName = 'Set-RemoteRegistryValue'
                Times = 1
                Scope = 'It'
                Exactly = $true
                ParameterFilter = { $ComputerName -eq 'SOMETHING' }
            }
            Assert-MockCalled @assMParams
        }

        it 'when the Web-Mgmt-Service feature is already installed, it attempts to change the WMSvc service startup type to Automatic' {

            $null = Enable-IISRemoteManagement -ComputerName 'SOMETHING'

            $assMParams = @{
                CommandName = 'Set-Service'
                Times = 1
                Scope = 'It'
                Exactly = $true
                ParameterFilter = { $ComputerName -eq 'SOMETHING' }
            }
            Assert-MockCalled @assMParams
        }

        it 'when the Web-Mgmt-Service feature is already installed, it attempts to start the WMSvc service' {

            $null = Enable-IISRemoteManagement -ComputerName 'SOMETHING'

            $assMParams = @{
                CommandName = 'Get-Service'
                Times = 1
                Scope = 'It'
                Exactly = $true
            }
            Assert-MockCalled @assMParams -ParameterFilter { $ComputerName -eq 'SOMETHING' }

            $assMParams.CommandName = 'Start-Service'
            Assert-MockCalled @assMParams
        }

    }

    context 'Output' {
        it 'when the computer already has the Web-Mgmt-Service feature installed, it will throw an exception' {

            mock 'Test-Connection' {
                $true
            }

            mock 'Test-WindowsFeature' {
                $false
            }

            { Enable-IISRemoteManagement -ComputerName 'IAMONLINE' } | should throw 'Windows feature is not installed'
        }
    }
}