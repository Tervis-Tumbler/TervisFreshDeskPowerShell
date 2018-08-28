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