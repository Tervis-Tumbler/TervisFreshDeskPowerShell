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
    } | FT


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

    $Tickets | Select-Object -Property Type, "Issue Type", "Reason for Return", IssueTypeMapping | FT
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
    % {
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
        $CSVPath
    )
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
        Write-Progress -Activity "Parent Ticket $ParentTicketID" -Status "$CurrentParentCount of $TotalCount" `
            -PercentComplete ($CurrentParentCount * 100 / $TotalCount) -CurrentOperation ""
        $ParentTicket = Get-FreshDeskTicket -ID $ParentTicketID
        foreach ($ChildTicketID in $ParentTicket.associated_tickets_list) {
            Write-Progress -Activity "Parent Ticket $ParentTicketID" -Status "$CurrentParentCount of $TotalCount" `
                -PercentComplete ($CurrentParentCount * 100 / $TotalCount) -CurrentOperation "Updating Child Ticket $ChildTicketID"
            Start-Sleep -Seconds 1.2
            $ChildTicket = Set-FreshDeskTicket -id $ChildTicketID -custom_fields @{
                cf_parentticketid = $ParentTicketID
            }
            [PSCustomObject]@{
                ParentTicketID = $ChildTicket.custom_fields.cf_parentticketid
                ChildTicketID = $ChildTicket.id
                Description = $ChildTicket.description_text
            }
        }
        Start-Sleep -Seconds 1.2
    }
}
