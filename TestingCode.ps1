ipmo -force freshdeskpowershell, TervisFreshDeskPowerShell, TervisWarrantyFormInternal, TervisWarrantyRequest
New-TervisWarrantyFormDashboard
Set-TervisFreshDeskEnvironment

1..10 | % {Get-FreshDeskTicketField | Out-Null}
Get-FreshdeskAPIAverageExecutionTime

get-runspace | where {$_.Debugger.InBreakpoint} | Debug-Runspace

Get-FreshDeskTicket | Measure-Object
New-FreshDeskTicket -description "description" -subject "subject" -email "dur@nooaol.com" -priority 1 -status 2
New-FreshDeskContact -name "Test Dur" -email dur@nooaol.com


try {
    New-FreshDeskContact -name "Test Dur" -email dur@nooaol.com
} catch {
    [PSCustomObject]@{
        StatusCode = $_.Exception.Response.StatusCode.value__
        Message = $_.Exception.Response
    }
}

$WarrantyRequest = New-WarrantyRequest -FirstName Bob -LastName Hope -Address1 "888 Blue Avenue" -City "North Star" -State FL -PostalCode 34286 -PhoneNumber 555-555-5555 -Email Not@NotValidEmail.com -ResidentialOrBusinessAddress Residence -WarrantyLines (
    New-WarrantyRequestLine -DesignName "Gators" -Size "10oz (5 1/2)" -Quantity 1 -ManufactureYear 2012 -ReturnReason Cracked
),(
    New-WarrantyRequestLine -DesignName "Dogs" -Size "12oz (4 1/4)" -Quantity 1 -ManufactureYear 2013 -ReturnReason "heat distortion"
)
$WarrantyRequest | New-WarrantyParentTicket
$WarrantyRequest | New-WarrantyParentFreshDeskTicketParameter


"06/13/2018 2:19:10 pm"
(get-date).tostring("MM-dd-yyyy")
(get-date).tostring("G")