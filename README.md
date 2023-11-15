# zbx-hpsmartarray
PowerShell script for monitoring HP SmartArray RAID controllers (Zabbix)

This version is completely compatibile with RAIDs storage with "dot" capacity like 1.2 Tb etc.

Zabbix Share page: https://share.zabbix.com/storage-devices/hp/hp-smart-array-controller  
Also you can contact me with Telegram: @asand3r

![alt_text](https://pp.userapi.com/c846321/v846321430/8e848/q_agCgTD6mU.jpg)

zbx-hpsmartarray provides possibility to make Low Level Discovery of HP Smart Array components, such as controllers, logical and physical drives. Also you can request health status of each discovered component.
The script wrote with PowerShell and works from version 3.0. To communicate with Smart Array it's using HP Array Configuration Utility or HP Smart Storage Administrator toolkit which you must install yourself.  

**Latest stable version:** 0.4.8

__Please, read [Requirements and Installation](https://github.com/asand3r/zbx-hpsmartarray/wiki/Requirements-and-Installation) section in Wiki before use. Need to edit zabbix_agentd.conf file.__  

## Notice
Please, attend! Version 0.4 works only with PowerShell v3.0 and above becouse contains ConvertTo-JSON cmdlet. For now, v0.3.x and v0.4 are same in syntax and functionality, so if you have only PowerShell v2.0, you must use v0.3.x without care.

## Dependencies
 - HP Array Configuration Utility or HP Smart Storage Administrator

## Feautres  
**Low Level Discovery:**
 - [x] physical disks 
 - [x] virtual disks
 - [x] controllers

**Component status:**
 - [x] physical disks 
 - [x] virtual disks
 - [x] controllers (main status, cache status and battery status)

## Supported arguments  
**-action**  
What we want to do - make LLD or get component health status (takes: lld, health)  
**-part**  
Smart array component - controller, logical drive or physical drive (takes: ctrl, ld, pd)  
**-partid**  
Part of target, depends of context:  
 - controllers: main controller status, it's battery or cache status (takes: main, batt, cache);  
 - logical drives: id of logical drive (takes: 1, 2, 3, 4 etc);  
 - physical drives: id of physical drive (takes: 1E:1:1..2E:1:12 etc)  

**-ctrlid**  
Controller id. By default it's slot number where controller installed (before v0.3 it was s/n).  
**-version**  
Print script version and exit.  

## Usage
You can find more examples on Wiki page, but I placed some cases here too.  
- LLD of enclosures, controllers, virtual disks and physical disks:
```powershell
PS C:\> .\zbx-hpsmartarray.ps1 -action lld -part ctrl

{"data":[{"{#VDISKNAME}":"vDisk01"},{"{#VDISKNAME}":"vDisk02"},"{#CTRL.SLOT}":"0"}]}
```
- Request health status of one component. E.g. disk '2E:1:12':
```powershell
PS C:\> .\zbx-hpsmartarray.ps1 -action health -ctrlid 0 -part pd -identity 2E:1:12

Rebuilding
```
Or just using positional parameters:
```powershell
PS C:\> .\zbx-hpsmartarray.ps1 healthd 0 pd 2E:1:12

Rebuilding
```

## Zabbix templates
In addition I've attached preconfigured Zabbix Template here, so you can use it in your environment. It's using Low Level Discovery functionality.   
Have fun and rate it on [share.zabbix.com](https://share.zabbix.com/storage-devices/hp/hp-smart-array-controller) if you like it. =)

**Tested with**:  
HP SmartArray P800, Smart Array P420i, Smart Array P440ar, Smart Array B110i

