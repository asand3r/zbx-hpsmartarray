<#
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
    [Parameter(Mandatory=$False)][switch]$version = $False,
    [ValidateSet("lld","health")][Parameter(Position=0, Mandatory=$False)][string]$action,
    [ValidateSet("ctrl","ld","pd")][Parameter(Position=1, Mandatory=$False)][string]$part,
    [Parameter(Position=2, Mandatory=$False)][string]$ctrlid,
    [Parameter(Position=3, Mandatory=$False)][string]$partid,
    [Parameter(Mandatory=$False)][switch]$Pretty
)

# Script version
$VERSION_NUM="0.4.8"
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
                        if ($ld -match "logicaldrive (?<Num>\d{1,}) \((?<Capacity>[\d.]{1,} [KGT]B?), (?<RAID>(RAID)?\s?[\d\+]+)\)") {
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
                        if ($pd -match "physicaldrive (?<Num>\d{1,}\w(:\d{1,2}){1,2}) \(.+ (?<Capacity>\d{1,}(?:\.\d+)? [KGT]B?)(, \w+)?\)") {
                            [array]$lld_obj_list += [pscustomobject]@{"{#PD.NUM}" = $Matches.Num;
                                                                        "{#PD.CAPACITY}" = $Matches.Capacity;
                                                                        "{#CTRL.SLOT}" = $ctrl_slot;
                                                                        "{#CTRL.SN}" = $ctrl_sn;
                                                                        "{#CTRL.MODEL}" = $ctrl_model}
                        }
                    }
            }
        }
    }
    if ($Pretty) {
        return ConvertTo-Json @{"data" = $lld_obj_list}
    } else {
        return ConvertTo-Json @{"data" = $lld_obj_list} -Compress
    }
}

function Get-Health() {
    param(
        [string]$part,
        [string]$ctrlid,
        [string]$partid
    )

    # Determine which controller id is provided
    if ($ctrlid -match "^\d{1,}\w?$") {
        $ctrid_type = "slot"
    } else {
        $ctrid_type = "sn"
    }

    switch ($part) {
        "ctrl" {
            $ctrl_status = & "$ssacli" "ctrl $($ctrid_type)=$($ctrlid) show status".Split() | Where-Object {$_ -match "status"}
            if ($ctrl_status.Length -gt 1) {
                switch ($partid) {
                    "main" {return ($ctrl_status[0] -replace ".+:\s")}
                    "cache" {return ($ctrl_status[1] -replace ".+:\s")}
                    "batt" {return ($ctrl_status[2] -replace ".+:\s")}
                } else {
                    return ($ctrl_status -replace ".+:\s")
                }
            }
        }
        "ld" {
            $ld_status = & "$ssacli" "ctrl $($ctrid_type)=$($ctrlid) ld $($partid) show status".Split() | Where-Object {$_ -match 'logicaldrive \d'}
            return ($ld_status -replace '.+:\s')
        }
        "pd" {
            $pd_status = & "$ssacli" "ctrl $($ctrid_type)=$($ctrlid) pd $($partid) show status".Split() | Where-Object {$_ -match 'physicaldrive \d'}
            return ($pd_status -replace '.+\:\s')
        }
    }
}

switch ($action) {
    "lld" {
        Write-Host $(Make-LLD -part $part)
    }
    "health" {
        Write-Host $(Get-Health -part $part -ctrlid $ctrlid -partid $partid)
    }
    default {Write-Host "ERROR: Wrong first argument: use 'lld' or 'health'"}
}
