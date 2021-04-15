function Set-TervisFreshDeskAPIKey {
    $APIKey = Get-PasswordstatePassword -ID 5470 | Select-Object -ExpandProperty Password
    Set-FreshDeskAPIKey -APIKey $APIKey
}

function Set-TervisFreshDeskEnvironment {
    Set-TervisFreshDeskAPIKey
    Set-FreshDeskDomain -Domain Tervis
}

function Remove-TervisFreshDeskEnvironment {
    Remove-FreshDeskCredential
    Remove-FreshDeskDomain
}

function Get-TervisFreshDeskTicketField {
    if (-not $Script:TicketFields) { 
        $Script:TicketFields = Get-FreshDeskTicketField
    }

    $Script:TicketFields
}

function Invoke-TervisUpdateQuantityToQuantityNumber {
    param (
        $PathToExport
    )
    Set-TervisFreshDeskEnvironment
    $Tickets = Import-Csv -Path $PathToExport | 
    Add-Member -MemberType ScriptProperty -Name QuantityNumberInt -Value {
        if ($this.QuantityNumber) {
            [int]$this.QuantityNumber
        }
    } -PassThru |
    Add-Member -MemberType ScriptProperty -Name QuantityInt -Value {
        if ($this.Quantity) {
            [int]$this.Quantity
        }
     } -PassThru |
    Add-Member -MemberType ScriptProperty -Name UnifiedQuantity -PassThru -Value {
        if ($This.QuantityNumberInt -and -not $This.QuantityInt) {
            $This.QuantityNumberInt
        } elseif (-not $This.QuantityNumberInt -and $This.QuantityInt) {
            $This.QuantityInt
        } elseif ($This.QuantityNumberInt -and $This.QuantityInt) {
            if ($This.QuantityNumberInt -ge $This.QuantityInt) {
                $This.QuantityNumberInt
            } else {
                $This.QuantityInt
            }
        } 
    } |
    Add-Member -MemberType ScriptProperty -Name QuantityNumberToUpdate -PassThru -Value {
        if ($This.QuantityNumberInt -ne $this.UnifiedQuantity) {
            $this.UnifiedQuantity
        }
    }

    $Tickets |
    Where-Object {
        ($_.QuantityNumber -and $_.Quantity) -and
        ($_.QuantityNumber -ne $_.Quantity)
    } | Format-Table


    if ($ticket.QuantityNumber -and $ticket.Quantity) {
        if ($ticket.QuantityNumber -ge $ticket.Quantity) {
            $ticket.QuantityNumber
        } else {
            $ticket.Quantity
        }
    } 

    $Tickets | 
    Where-Object {$_.QuantityNumberToUpdate} |
    Measure-Object

    $Tickets | Group-Object Quantity | Sort-Object -Descending -Property Count
    $Tickets | Group-Object QuantityNumber | Sort-Object -Descending -Property Count
    $Tickets | Where-Object {$_.QuantityNumberToUpdate} | Group-Object -Property QuantityNumberToUpdate | Sort-Object -Descending -Property Count


    $Tickets | 
    Where-Object {$_.QuantityNumberToUpdate} |
    Select-Object -First 10 -Skip 1000 -ExpandProperty "Ticket ID"

    $Tickets | 
    Where-Object {$_.QuantityNumberToUpdate} |
    ForEach-Object {
        Set-FreshDeskTicket -id $_."Ticket ID" -custom_fields @{cf_quantitynumber = $_.QuantityNumberToUpdate} | Out-Null
        Start-Sleep -Seconds 1.2
    }
}

function Invoke-TervisUpdateIssueTypeIfOnlyReasonForReturnPopulated {
    param (
        $PathToExport
    )
    Set-TervisFreshDeskEnvironment
    $ReturnReasonIssueTypeMapping = Get-ReturnReasonIssueTypeMapping
    $Tickets = Import-Csv -Path $PathToExport |
    Where-Object -FilterScript {
        $_.Type -eq "Warranty Child" -and
        -not $_."Issue Type" -and
        $_."Reason for Return"
    } |
    Add-Member -MemberType ScriptProperty -Name IssueTypeMapping -PassThru -Value {
        $ReturnReasonIssueTypeMapping[$this."Reason for Return"]
    }

    $Tickets | Select-Object -Property Type, "Issue Type", "Reason for Return", IssueTypeMapping | Format-Table
    $Tickets | Where-object {$_."Reason for Return" -in $ReturnReasonIssueTypeMapping.Keys} | Measure-Object
    $Tickets | Measure-Object
    
    $Results = $Tickets | 
    ForEach-Object {
        Set-FreshDeskTicket -id $_."Ticket ID" -custom_fields $_.IssueTypeMapping
    }
}

function Invoke-TervisUpdateChannelBasedOnSourceExtended {
    param (
        $PathToExport
    )
    Set-TervisFreshDeskEnvironment
    $Tickets = Import-Csv -Path $PathToExport |
    Where-Object -FilterScript {
        $_.Type -eq "Warranty Parent" -and
        -not $_."Channel" -and
        $_."Source Extended"
    }

    $Tickets |
    Where-Object -Property "Source Extended" -EQ "Web" | Measure-Object
    
    $Results = $Tickets |
    Where-Object -Property "Source Extended" -EQ "Web" |
    ForEach-Object {
        Set-FreshDeskTicket -id $_."Ticket ID" -custom_fields @{cf_channel = "Web"}
        Start-Sleep -Seconds 1.2
    }

    $Results2 = $Tickets |
    Where-Object -Property "Source Extended" -EQ "Warranty Return Form Internal" |
    ForEach-Object {
        Set-FreshDeskTicket -id $_."Ticket ID" -custom_fields @{cf_channel = "Production"}
    }
}

function Invoke-TervisFreshDeskUpdateChildTicketIDs {
    param (
        $CSVPath
    )
    $CSVData = Import-Csv -Path $CSVPath |
    Add-Member -MemberType AliasProperty -Name "TicketID" -Value "Ticket ID" -SecondValue Int -PassThru |
    Sort-Object -Property "TicketID"

    Set-TervisFreshDeskEnvironment
    
    $CSVData |
    Where-Object Channel -eq "Store" |
    Where-Object {-not $_.ChildTicketIDs} |
    Measure-Object

    # (23280 * 1.2) / 60 / 60

    $CSVData |
    Where-Object Channel -eq "Store" |
    Where-Object {-not $_.ChildTicketIDs} |
    Where-Object TicketID -gt 696098 |
    ForEach-Object {
        $Ticket = Get-FreshDeskTicket -ID $_.TicketID
        if ($Ticket.associated_tickets_list) {
            Set-FreshDeskTicket -id $_.TicketID -custom_fields @{
                cf_childticketids = $Ticket.associated_tickets_list -join ","
            }
            Start-Sleep -Seconds 1.2
        }
        Start-Sleep -Seconds 1.2
    }
}

function Invoke-TervisFreshDeskUpdateParentTicketID {
    param (
        $CSVPath,
        $LogDirectory,
        $APICallsPerHour = 2000
    )

    $APICallDelay = 3600/$APICallsPerHour
    $StartTime = Get-Date
    $LogFileName = "$(Get-Date $StartTime -Format yyyyMMdd_HHmmss)_FailedParentTickets.log"

    # Export from Freshdesk with Channel filtered to "Store" and Association Type
    # filtered to "Parent". Export the following fields:
    # - Ticket ID

    # In the future, should be automated with a scheduled, and just go by "Child"
    # with no ParentTicketID. Doing this by parent now since it's a one-shot for 
    # a subset of tickets.

    $ParentTicketIDs = Import-Csv -Path $CSVPath | 
        Select-Object -ExpandProperty "Ticket ID"

    Set-TervisFreshDeskEnvironment

    $TotalCount = $ParentTicketIDs.Count
    $CurrentParentCount = 0

    foreach ($ParentTicketID in $ParentTicketIDs) {
        $CurrentParentCount += 1
        $SecondsRemaining = Get-TervisFreshdeskTimeRemainingEstimate -StartTime $StartTime -Completed $CurrentParentCount -Total $TotalCount
        Write-Progress -Activity "Parent Ticket $ParentTicketID" -Status "$CurrentParentCount of $TotalCount" `
            -PercentComplete ($CurrentParentCount * 100 / $TotalCount) -CurrentOperation "" -SecondsRemaining $SecondsRemaining
        try {
            $ParentTicket = Get-FreshDeskTicket -ID $ParentTicketID
            foreach ($ChildTicketID in $ParentTicket.associated_tickets_list) {
                Write-Progress -Activity "Parent Ticket $ParentTicketID" -Status "$CurrentParentCount of $TotalCount" `
                    -PercentComplete ($CurrentParentCount * 100 / $TotalCount) -CurrentOperation "Updating Child Ticket $ChildTicketID" -SecondsRemaining $SecondsRemaining
                Start-Sleep -Seconds $APICallDelay
                $ChildTicket = Set-FreshDeskTicket -id $ChildTicketID -custom_fields @{
                    cf_parentticketid = $ParentTicketID
                }
                [PSCustomObject]@{
                    ParentTicketID = $ChildTicket.custom_fields.cf_parentticketid
                    ChildTicketID = $ChildTicket.id
                    Description = $ChildTicket.description_text
                }
            }
        }
        catch {
            $ParentTicketID | Out-File -FilePath "$LogDirectory\$LogFileName" -Append
        }
        Start-Sleep -Seconds $APICallDelay
    }
}

function Invoke-TervisFreshDeskUpdateParentTicketID_ByChildTicket {
    param (
        $CSVPath
    )

    $ChildTicketIDs = Import-Csv -Path $CSVPath | 
        Select-Object -ExpandProperty "Ticket ID"

    Set-TervisFreshDeskEnvironment

    $TotalCount = $ChildTicketIDs.Count
    $CurrentChildCount = 0

    foreach ($ChildTicketID in $ChildTicketIDs) {
        $CurrentChildCount += 1
        Write-Progress -Activity "Child Ticket $ChildTicketID" -Status "$CurrentChildCount of $TotalCount" `
            -PercentComplete ($CurrentChildCount * 100 / $TotalCount) -CurrentOperation ""
        try {
            $ChildTicket = Get-FreshDeskTicket -ID $ChildTicketID
            $ParentTicketID = "$($ChildTicket.associated_tickets_list[0])"
            Start-Sleep -Seconds 1.3
            $NewChildTicket = Set-FreshDeskTicket -id $ChildTicketID -custom_fields @{
                cf_parentticketid = $ParentTicketID
            }
            [PSCustomObject]@{
                ParentTicketID = $NewChildTicket.custom_fields.cf_parentticketid
                ChildTicketID = $NewChildTicket.id
                Description = $NewChildTicket.description_text
            }
        }
        catch {
            $ChildTicketID | Out-File -FilePath "$LogDirectory\FreshFailedTickets.log" -Append
        }
        Start-Sleep -Seconds 1.3
    }
}

function Install-TervisFreshdeskMFL {
    param (
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]$ComputerName,
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]
        [ValidateSet("Delta","Epsilon","Production")]$EnvironmentName
    )
    begin {
        $ScheduledTasksCredential = Get-TervisPasswordstatePassword -Guid "eed2bd81-fd47-4342-bd59-b396da75c7ed" -AsCredential
    }
    process {
        $PowerShellApplicationParameters = @{
            ComputerName = $ComputerName
            EnvironmentName = $EnvironmentName
            ModuleName = "TervisFreshDeskPowerShell"
            TervisModuleDependencies = `
                "OracleE-BusinessSuitePowerShell",
                "TervisOracleE-BusinessSuitePowerShell",
                "InvokeSQL",
                "WebServicesPowerShellProxyBuilder",
                "TervisMicrosoft.PowerShell.Utility",
                "TervisMicrosoft.PowerShell.Security",
                "PasswordstatePowershell",
                "TervisPasswordstatePowershell",
                "TervisPowershellJobs",
                "ShopifyPowerShell",
                "TervisShopify",
                "FreshDeskPowerShell",
                "TervisFreshDeskPowerShell"
            NugetDependencies = "Oracle.ManagedDataAccess.Core"
            ScheduledTaskName = "FreshDesk MFL Ticket Import - $EnvironmentName"
            RepetitionIntervalName = "EveryDayAt730am"
            CommandString = "Invoke-TervisFreshDeskMFLTransactionImport -Environment $EnvironmentName"
            ScheduledTasksCredential = $ScheduledTasksCredential
        }
        
        Install-PowerShellApplication @PowerShellApplicationParameters
    }
}

function Invoke-TervisFreshDeskMFLTransactionImport {
    param (
        [ValidateSet("Delta","Epsilon","Production")]$Environment
    )
    Set-TervisFreshDeskEnvironment
    Set-TervisEBSEnvironment -Name $Environment | Out-Null
    Get-TervisFreshDeskMFLTickets |
    New-TervisFreshDeskInventoryAdjustmentQuery |
    Invoke-TervisFreshDeskMFLTransactionQueries
}

function Get-TervisFreshDeskMFLTickets {
    Invoke-FreshDeskAPI -Resource tickets -Method GET -Query 'tag:StoreMFL' | Select-Object -ExpandProperty results
}

function Remove-TervisFreshDeskTicketMFLImportTag {
    param (
        [Parameter(Mandatory,ValueFromPipeline)]$Ticket
    )
    process {
        [array]$Tags = $Ticket.tags | Where-Object {$_ -ne "StoreMFL"}
        if (-not $Tags) { $Tags = @() }
        Set-FreshDeskTicket -id $Ticket.id -tags $Tags
    }
}

function New-TervisFreshDeskInventoryAdjustmentQuery {
    param (
        [Parameter(ValueFromPipeline)]$Ticket
    )
    begin {
        $Locations = Get-TervisShopifyLocationDefinition -All
        $ParentTicketCache = ""
    }
    process {
        $ReturnType = $Ticket.custom_fields.cf_returntype
        if ($ReturnType -ne "Like For Like" -and $ReturnType -ne "Exchange For Clear") { return }
        
        $ExchangeItems = $Ticket.custom_fields.cf_exchangeitems | ConvertFrom-Json
        
        $ParentTicketID = $Ticket.custom_fields.cf_parentticketid
        if ($ParentTicketID -ne $ParentTicketCache.id) {
            $ParentTicketCache = Get-FreshDeskTicket -ID $ParentTicketID
        }
        $Location = $Locations | Where-Object FreshDeskLocation -eq $ParentTicketCache.custom_fields.cf_subchannel
        
        $Query = "INSERT ALL`n"
        foreach ($Item in $ExchangeItems) {
            $Query += @"
            INTO xxtrvs.xxmtl_transactions_interface (
                SOURCE_CODE
                ,LAST_UPDATE_DATE
                ,CREATION_DATE
                ,ITEM_SEGMENT1
                ,TRANSACTION_QUANTITY
                ,TRANSACTION_UOM
                ,TRANSACTION_DATE
                ,SUBINVENTORY_CODE
                ,TRANSFER_LOCATOR_NAME
                ,PROCESS_FLAG
                ,CREATED_BY_NAME
                ,LAST_UPDATED_BY_NAME
                ,ORGANIZATION_CODE
                ,FRESHDESK_ID
            )
            VALUES (
                'INVENTORY_ADJUSTMENT_MFL'
                ,TRUNC(SYSDATE)
                ,TRUNC(SYSDATE)
                ,'$($Item.ItemNumber)'
                ,$($Item.Quantity * -1)
                ,'EA'
                ,TO_DATE('$($Ticket.created_at.Substring(0,10))', 'YYYY-MM-DD')
                ,'$($Location.Subinventory)'
                ,'$($Location.CustomerNumber)'
                ,'N'
                ,'FreshdeskMFL'
                ,'FreshdeskMFL'
                ,'STO'
                ,'$($Ticket.id)'
            )`n`n
"@          
        }
        $Query += "SELECT 1 FROM DUAL"
        return [PSCustomObject]@{
            Ticket = $Ticket
            Query = $Query
        }
    }
}

function Invoke-TervisFreshDeskMFLTransactionQueries {
    param (
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]$Ticket,
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]$Query
    )
    process {
        try {
            $ExistingRecord = Invoke-EBSSQL -SQLCommand `
                "SELECT freshdesk_id FROM xxtrvs.xxmtl_transactions_interface WHERE freshdesk_id = $($Ticket.id)"
            if (-not $ExistingRecord) {
                Invoke-EBSSQL -SQLCommand $Query
            }
            Remove-TervisFreshDeskTicketMFLImportTag -Ticket $Ticket
        } catch {
            Write-Warning "Could not process $TicketID`: `n$_`n$($_.InvocationInfo.PositionMessage)"
        }
    }
}

function Get-TervisFreshdeskTimeRemainingEstimate {
    param (
        $StartTime,
        $Completed,
        $Total
    )
    $SecondsPassed = New-TimeSpan -Start $StartTime -End (Get-Date) | Select-Object -ExpandProperty TotalSeconds
    $AverageSecondsPerTicket = $SecondsPassed / $Completed
    $SecondsRemaining = ( $Total - $Completed ) * $AverageSecondsPerTicket
    return $SecondsRemaining

}
