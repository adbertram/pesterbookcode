function Get-MachineInfo {
<#
.SYNOPSIS
Retrieves specific information about one or more
computers, using WMI or CIM.
.DESCRIPTION
This command uses either WMI or CIM to retrieve
specific information about one or more computers.
You must run this command as a user who has permission
to remotely query CIM or WMI on the machines involved.
You can specify a starting protocol (CIM by default),
and specify that, in the event of a failure, the other
protocol be used on a per-machine basis.
.PARAMETER ComputerName
One or more computer names. When using WMI, this can
also be IP addresses. IP addresses may not work for CIM.
.PARAMETER LogFailuresToPath
A path and filename to write failed computer names to.
If omitted, no log will be written.
.PARAMETER Protocol
Valid values: Wsman (uses CIM) or Dcom (uses WMI). Will
be used for all machines. "Wsman" is the default.
.PARAMETER ProtocolFallback
Specify this to automatically try the other protocol if
a machine fails.
.EXAMPLE
Get-MachineInfo -ComputerName ONE,TWO,THREE
This example will query three machines.
.EXAMPLE
Get-ADUser -filter * | Select -Expand Name | Get-MachineInfo
This example will attempt to query all machines in AD.
#>
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline=$True,
                   Mandatory=$True)]
        [Alias('CN','MachineName','Name')]
        [string[]]$ComputerName,
        
        [string]$LogFailuresToPath,

        [ValidateSet('Wsman','Dcom')]
        [string]$Protocol = "Wsman",

        [switch]$ProtocolFallback
    )
 
 BEGIN {}

 PROCESS {
    foreach ($computer in $computername) {
 
        if ($protocol -eq 'Dcom') {
            $option = New-CimSessionOption -Protocol Dcom
        } else {
            $option = New-CimSessionOption -Protocol Wsman
        }
 
        Try {
            Write-Verbose "Connecting to $computer over $protocol"
            $params = @{'ComputerName'=$Computer
                        'SessionOption'=$option
                        'ErrorAction'='Stop'}
            $session = New-CimSession @params
  
            Write-Verbose "Querying from $computer"
            $os_params = @{'ClassName'='Win32_OperatingSystem'
                           'CimSession'=$session}
            $os = Get-CimInstance @os_params

            $cs_params = @{'ClassName'='Win32_ComputerSystem'
                           'CimSession'=$session}
            $cs = Get-CimInstance @cs_params

            $sysdrive = $os.SystemDrive
            $drive_params = @{'ClassName'='Win32_LogicalDisk'
                              'Filter'="DeviceId='$sysdrive'"
                              'CimSession'=$session}
            $drive = Get-CimInstance @drive_params

            $proc_params = @{'ClassName'='Win32_Processor'
                             'CimSession'=$session}
            $proc = Get-CimInstance @proc_params |
                    Select-Object -first 1

  
            Write-Verbose "Closing session to $computer"
            $session | Remove-CimSession
  
            Write-Verbose "Outputting for $computer"
            $obj = [pscustomobject]@{'ComputerName'=$computer
                       'OSVersion'=$os.version
                       'SPVersion'=$os.servicepackmajorversion
                       'OSBuild'=$os.buildnumber
                       'Manufacturer'=$cs.manufacturer
                       'Model'=$cs.model
                       'Procs'=$cs.numberofprocessors
                       'Cores'=$cs.numberoflogicalprocessors
                       'RAM'=($cs.totalphysicalmemory / 1GB)
                       'Arch'=$proc.addresswidth
                       'SysDriveFreeSpace'=$drive.freespace}
            Write-Output $obj
        } Catch {
            Write-Warning "FAILED $computer on $protocol"
            
            # Did we specify protocol fallback?
            # If so, try again. If we specified logging,
            # we won't log a problem here - we'll let
            # the logging occur if this fallback also
            # fails
            If ($ProtocolFallback) {
                If ($Protocol -eq 'Dcom') {
                    $newprotocol = 'Wsman'
                } else {
                    $newprotocol = 'Dcom'
                } #if protocol

                Write-Verbose "Trying again with $newprotocol"
                $params = @{'ComputerName'=$Computer
                            'Protocol'=$newprotocol
                            'ProtocolFallback'=$False}
                
                If ($PSBoundParameters.ContainsKey('LogFailuresToPath')){
                    $params += @{'LogFailuresToPath'=$LogFailuresToPath}
                } #if logging

                Get-MachineInfo @params
            } #if protocolfallback

            # if we didn't specify fallback, but we
            # did specify logging, then log the error,
            # because we won't be trying again
            If (-not $ProtocolFallback -and
                $PSBoundParameters.ContainsKey('LogFailuresToPath')){
                Write-Verbose "Logging to $LogFailuresToPath"
                $computer | Out-File $LogFailuresToPath -Append
            } # if write to log

        } #try/catch
 
    } #foreach
} #PROCESS

END {}

} #function

