﻿<#
    .SYNOPSIS
    Script for getting data from HP MSA to Zabbix monitoring system.

    .DESCRIPTION
    The script may generate LLD data for HP Smart Array Controllers, Logical Drives and Physical Drives.
    Also it can takes some components health status. It's using HP Array Configuration Utility to
    connect to controller, so you must install it first:
    https://support.hpe.com/hpsc/swd/public/detail?swItemId=MTX_33fe6fcf4fcb4beab8fee4d2dc

    Works only with PowerShell 3.0 and above.
    
    .PARAMETER action
    What we want to do - make LLD or get component health status (takes: lld, health)

    .PARAMETER part
    Smart array component - controller, logical drive or physical drive (takes: ctrl, ld, pd)

    .PARAMETER identity
    Part of target, depends of context:
    For controllers: main controller status, it's battery or cache status (takes: main, batt, cache);
    For logical drives: id of logical drive (takes: 1, 2, 3, 4 etc);
    For physical drives: id of physical drive (takes: 1E:1:1..2E:1:12 etc)

    .PARAMETER ctrlid
    Controller identity. Usual it's controller slot, but may be set to serial number.

    .PARAMETER version
    Print verion number and exit

    .EXAMPLE
    Zbx-HPSmartArray.ps1 -action lld -part ctrl
    {"data":[{"{#CTRL.MODEL}":"Smart Array P800","{#CTRL.SN}":"P98690G9SVA0BE"}]}

    .EXAMPLE
    Zbx-HPSmartArray.ps1 health ld 1
    OK

    .EXAMPLE
    Zbx-HPSmartArray.ps1 health pd 2E:1:12
    Rebuilding

    .NOTES
    Author: Khatsayuk Alexander
    Github: https://github.com/asand3r/
#>

Param (
    [switch]$version = $False,
    [ValidateSet("lld","health")][Parameter(Position=0, Mandatory=$False)][string]$action,
    [ValidateSet("ctrl","ld","pd", "ctrl_json")][Parameter(Position=1, Mandatory=$False)][string]$part,
    [string][Parameter(Position=2, Mandatory=$False)]$ctrlid,
    [string][Parameter(Position=3, Mandatory=$False)]$partid
)

# Script version
$VERSION_NUM="0.5"
if ($version) {
    Write-Host $VERSION_NUM
    break
}

# HP Array Configuration Utility location
$ssacli = "$env:ProgramFiles\Smart Storage Administrator\ssacli\bin\ssacli.exe"
if (! (Test-Path $ssacli)) {
    $ssacli = "$env:ProgramFiles\Compaq\Hpacucli\Bin\hpacucli.exe"
}

# Retrieve one Smart Array Controller info from given string
function Get-CtrlInfo($ctrl) {
        $model = $ctrl -replace "\sin.*$"
        if ($ctrl -match '\(sn:\s.+$') {
            $sn = $Matches[0] -creplace '[sn:()\s]'
        } else {
            $sn = "UNKNOWN"
        }
        $slot = $ctrl -replace "^.+Slot\s" -replace "\s.+$"
        return $model, $sn, $slot
}

function Make-LLD() {
    param(
        [string]$part
    )

    # Detect all HP Smart Array Controllers
    [array]$all_ctrls = & "$ssacli" "ctrl all show".Split() | Where-Object {$_ -match "\w"}

    # Global list to store formed LLD object
    [array]$lld_obj_list = @()
    
    foreach ($ctrl in $all_ctrls) {
        $ctrl_model, $ctrl_sn, $ctrl_slot = Get-CtrlInfo($ctrl)
        switch ($part) {
            "ctrl" {
                    [array]$lld_obj_list += [psobject]@{"{#CTRL.MODEL}" = $ctrl_model; "{#CTRL.SN}" = $ctrl_sn; "{#CTRL.SLOT}" = $ctrl_slot}
            }
            "ld" {
                    $all_ld = & "$ssacli" "ctrl slot=$($ctrl_slot) ld all show status".Split() | Where-Object {$_ -match "logicaldrive"}
                    
                    foreach ($ld in $all_ld) {
                        if ($ld -match "logicaldrive (?<Num>\d{1,}) \((?<Capacity>[\d.]{1,} [KGT]B?), (?<RAID>RAID [\d\+]+)\)") {
                            [array]$lld_obj_list += [psobject]@{"{#LD.NUM}" = $Matches.Num;
                                                                "{#LD.CAPACITY}" = $Matches.Capacity;
                                                                "{#LD.RAID}" = $Matches.RAID;
                                                                "{#CTRL.SLOT}" = $ctrl_slot;
                                                                "{#CTRL.SN}" = $ctrl_sn;
                                                                "{#CTRL.MODEL}" = $ctrl_model
                                                                }
                        }
                    }
            }
            "pd" {
                    $all_pd = & "$ssacli" "ctrl slot=$($ctrl_slot) pd all show status".Split() | Where-Object {$_ -match "physicaldrive"}
                    
                    foreach ($pd in $all_pd) {
                        if ($pd -match "physicaldrive (?<Num>\d{1,}\w(:?\d){1,2}) \(.+ (?<Capacity>\d{1,} [KGT]B?)\)") {
                            [array]$lld_obj_list += [psobject]@{"{#PD.NUM}" = $Matches.Num;
                                                                "{#PD.CAPACITY}" = $Matches.Capacity;
                                                                "{#CTRL.SLOT}" = $ctrl_slot;
                                                                "{#CTRL.SN}" = $ctrl_sn;
                                                                "{#CTRL.MODEL}" = $ctrl_model
                                                                }
                        }
                    }
            }
        }
    }
    return ConvertTo-Json @{"data" = $lld_obj_list} -Compress
}

function Get-Health() {
    param(
        [string]$part,
        [string]$ctrl_id,
        [string]$part_id
    )

    # Determine which controller id is provided
    if ($ctrl_id -match "^\d{1,}\w?$") {
        $ctrl_id_type = "slot"
    } else {
        $ctrl_id_type = "sn"
    }

    # Hash table for master item to convert to JSON
    $master_item = @{}

    switch -Regex ($part) {
        "^ctrl$" {
            if ($ctrl_id -ne "full") {
                $ctrl_status = & "$ssacli" "ctrl $($ctrl_id_type)=$($ctrl_id) show status".Split() | Where-Object {$_ -match "status"}
                if ($ctrl_status.Length -eq 3) {
                    switch ($part_id) {
                        "main" {return $ctrl_status[0] -replace "^.+:\s"}
                        "cache" {return $ctrl_status[1] -replace "^.+:\s"}
                        "batt" {return $ctrl_status[2] -replace "^.+:\s"}
                    
                        "full" {
                            $ctrl_data = [psobject]@{"main" = $ctrl_status[0] -replace "^.+:\s";
                                                     "cache" = $ctrl_status[1] -replace "^.+:\s";
                                                     "battery" = $ctrl_status[2] -replace "^.+:\s"
                                                    }
                            $master_item.Add($ctrl_id.ToString(), $ctrl_data)
                            return ConvertTo-Json -InputObject $master_item -Compress
                        }
                    }
                } else {
                    return ($ctrl_status -replace ".+:\s")
                }
            } else {
                $all_ctrls = & "$ssacli" "ctrl all show".Split() | Where-Object {$_ -match "\w"}
                $all_ctrls | ForEach-Object {
                    if ($_ -match ".+ in Slot (?<Slot>\d{1,})") {
                        $ctrl_slot = $Matches.Slot
                        $data = & "$ssacli" "ctrl slot=$($ctrl_slot) show".Split() | Where-Object {$_ -match "\w"}
                        $json_obj = [psobject]@{
                            "main-status" = [string]($data -match "Controller Status" -replace "^.+:\s");
                            "battery-status" = [string]($data -match "Battery.+? Status" -replace "^.+:\s");
                            "cache-status" = [string]($data -match "Cache Status" -replace "^.+:\s");
                            "ctrl-temperature" = [string]($data -match "Controller Temperature" -replace "^.+:\s");
                            "cache-temperature" = [string]($data -match "Cache.+? Temperature" -replace "^.+:\s");
                            "driver-version" = [string]($data -match "Driver Version" -replace "^.+:\s");
                            "firmware-version" = [string]($data -match "Firmware Version" -replace "^.+:\s")
                        }
                    }
                    $master_item.Add($ctrl_slot.ToString(), $json_obj)
                }
                return ConvertTo-Json -InputObject $master_item
            }
        }
        "^(ld|pd)$" {
            if ($ctrl_id -ne "full") {
                if ($part_id -ne "full") {
                    $status = & "$ssacli" "ctrl $($ctrl_id_type)=$($ctrl_id) $($part) $($part_id) show status".Split() | Where-Object {$_ -match '(log|phys)icaldrive'}
                    return ($status -replace '.+:\s')
                } else {
                    $all_statuses = & "$ssacli" "ctrl $($ctrl_id_type)=$($ctrl_id) $($part) all show status".Split() | Where-Object {$_ -match '(log|phys)icaldrive'}
                    foreach ($status in $all_statuses) {
                        if ($status -match "(log|phys)icaldrive (?<Num>[\w\d:]{1,}) .+\): (?<Status>.+)") {
                            $master_item.add($Matches.Num, $Matches.Status)
                        }
                    }
                    return ConvertTo-Json -InputObject $master_item -Compress
                }
            } else {
                $all_ctrls = & "$ssacli" "ctrl all show".Split() | Where-Object {$_ -match "\w"}
                $all_ctrls | ForEach-Object {
                    if ($_ -match ".+ in Slot (?<Slot>\d{1,})") {
                        $ctrl_slot = $Matches.Slot
                        $data = & "$ssacli" "ctrl slot=$($ctrl_slot) $($part) all show status".Split() | Where-Object {$_ -match "\w"}

                        $data | ForEach-Object {
                            if ($_ -match "(log|phys)icaldrive (?<Num>[\w\d:]{1,}) .+\): (?<Status>.+)") {
                                $json_obj += [psobject]@{
                                    [string]$Matches.Num = $Matches.Status
                                }
                            }
                        }
                    }
                    $master_item.Add($ctrl_slot.ToString(), $json_obj)
                }
                return ConvertTo-Json -InputObject $master_item
            }
        }
    }
}

switch ($action) {
    "lld" {
        Write-Host $(Make-LLD -part $part)
    }
    "health" {
        Write-Host $(Get-Health -part $part -ctrl_id $ctrlid -part_id $partid)
    }
}