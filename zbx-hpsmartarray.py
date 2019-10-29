#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
Script for getting data from HP Smart Array Controller to Zabbix monitoring 
system.

The script may generate LLD data for HP Smart Array Controllers, Logical 
Drives and Physical Drives. Also it can takes some components health status.
It's using HP Array Configuration Utility to connect to controller, so you
must install it first.

Works with Python 2 and Python 3


Configuration

Attention: The HP utility must be run as root, so add "sudo -u root" to
your UserParameter configuration and add the zabbix-user to sudoers.

UserParameter=hp.smartarray[*],sudo -u root /usr/local/share/zabbix/zbx-hpsmartarray.py -a $1 -p $2 -c $3 -i $4

/etc/sudoers.d/zabbix
  Defaults:zabbix !syslog, !pam_session
  zabbix ALL=(ALL) NOPASSWD: /usr/local/share/zabbix/zbx-hpsmartarray.py


Usage examples

Example 1: Contoller discovery
$ ./zbx-hpsmartarray.py -a lld -p ctrl
{"data": [{"{#CTRL.MODEL}": "Smart Array P440", "{#CTRL.SN}": "PDNMF0********",
"{#CTRL.SLOT}": "1"}, {"{#CTRL.MODEL}": "Smart Array P440ar", "{#CTRL.SN}": 
"PDNLH0********", "{#CTRL.SLOT}": "0"}]}

Example 2: Health of logical drive
$ ./zbx-hpsmartarray.py -a health -p ld -c 0 -i 1
OK

Example 3: Health of physical drive 
$ ./zbx-hpsmartarray.py -a lld -p pd -c 
OK

"""

import sys
import getopt
import subprocess
import re
import json
import os

__author__ = "Thomas Hooge"
__email__ = "thomas@hoogi.de"
__version__ = "0.1"


def get_ctrlinfo(ctrl):
    try:
        model = re.search("(.*) in Slot.*", ctrl, flags=re.IGNORECASE).group(1)
    except:
        model = "UNKNOWN"
    try:
        sn = re.search(".*\(sn: (\w+)\)", ctrl, flags=re.IGNORECASE).group(1)
    except:
        sn = "UNKNOWN"
    try:
        slot = re.search(".*slot (\d+).*", ctrl, flags=re.IGNORECASE).group(1)
    except:
        slot = None
    return model, sn, slot


def get_ldinfo(ld):
    try:
        num = re.search("logicaldrive (\d+) ", ld).group(1)
    except:
        return None, None, None
    try:
        capacity = re.search("\(([\d.]+ [KGT]B?),", ld).group(1)
    except:
        capacity = "UNKNOWN"
    try:
        raid = re.search("(RAID [\d+]+)\)", ld).group(1)
    except:
        raid = "UNKNOWN"
    return num, capacity, raid


def get_pdinfo(pd):
    try:
        num = re.search("(\d+\w(:?\d+){1,2})", pd).group(1)
    except:
        return None, None
    try:
        capacity = re.search("(\d+ [KGT]B?)\)", pd).group(1)
    except:
        capacity = "UNKNOWN"
    return num, capacity


def make_lld(ssacli, part):
    cmd = [ssacli]

    # Global list to store formed LLD object
    lld_obj_list = []

    output = subprocess.check_output(cmd + ['ctrl', 'all', 'show']).decode("utf-8")
    for ctrl in (s for s in output.splitlines() if s):
        ctrl_model, ctrl_sn, ctrl_slot = get_ctrlinfo(ctrl)
        if part == 'ctrl':
            lld_obj_list.append(
                {'{#CTRL.MODEL}': ctrl_model, 
                 '{#CTRL.SN}': ctrl_sn,
                 '{#CTRL.SLOT}': ctrl_slot})
        elif part == 'ld':
            output = subprocess.check_output(cmd + ['ctrl', 'slot='+ctrl_slot, 'ld', 'all', 'show', 'status']).decode("utf-8")
            for ld in (s for s in output.splitlines() if s):
                ld_num, ld_capacity, ld_raid = get_ldinfo(ld)
                if ld_num:
                    lld_obj_list.append(
                        {'{#LD.NUM}': ld_num,
                         '{#LD_CAPACITY}': ld_capacity,
                         '{#LD_RAID}': ld_raid,
                         '{#CTRL.SLOT}': ctrl_slot,
                         '{#CTRL_SN}': ctrl_sn})
        elif part == 'pd':
            output = subprocess.check_output(cmd + ['ctrl', 'slot='+ctrl_slot, 'pd', 'all', 'show', 'status']).decode("utf-8")
            for pd in (s for s in output.splitlines() if s):
                pd_num, pd_capacity = get_pdinfo(pd)
                if pd_num:
                    lld_obj_list.append(
                        {'{#PD.NUM}': pd_num,
                         '{#PD_CAPACITY}': pd_capacity,
                         '{#CTRL.SLOT}': ctrl_slot,
                         '{#CTRL_SN}': ctrl_sn})

    return json.dumps({'data': lld_obj_list})


def get_health(ssacli, ctrlid, part, partid):
    cmd = [ssacli]

    if ctrlid is None:
        return "UNKNOWN"

    ctrlid = str(ctrlid)
    if re.match("^\d+\w?$", ctrlid):
        ctrlid_type = 'slot'
    else:
        ctrlid_type = 'sn'

    if part == 'ctrl':
        output = subprocess.check_output(cmd + ['ctrl', '='.join((ctrlid_type, ctrlid)),
                                                'show', 'status']).decode("utf-8")
        for line in output.splitlines():
            if partid == 'main':
                m = re.match("\s*controller status:\s(\w+)", line, flags=re.IGNORECASE)
                if m:
                    return m.group(1)
            elif partid == 'cache':
                m = re.match("\s*cache status:\s(\w+)", line, flags=re.IGNORECASE)
                if m:
                    return m.group(1)
            elif partid == 'batt':
                m = re.match("\s*battery.*status:\s(\w+)", line, flags=re.IGNORECASE)
                if m:
                    return m.group(1)

    elif part == 'ld':
        try:
            output = subprocess.check_output(cmd + ['ctrl', '='.join((ctrlid_type, ctrlid)),
                                                    'ld', partid, 'show', 'status']).decode("utf-8")
        except:
            return "UNKNOWN"
        for line in output.splitlines():
            m = re.match("\s*logicaldrive.*:\s(\w+)", line, flags=re.IGNORECASE)
            if m:
                return m.group(1)
        return "UNKNOWN"

    elif part == 'pd':
        try:
            output = subprocess.check_output(cmd + ['ctrl', '='.join((ctrlid_type, ctrlid)),
                                                    'pd', partid, 'show', 'status']).decode("utf-8")
        except:
            return "UNKNOWN"
        for line in output.splitlines():
            m = re.match("\s*physicaldrive.*:\s(\w+)", line, flags=re.IGNORECASE)
            if m:
                return m.group(1)
        return "UNKNOWN"

    return "UNKNOWN"


def usage():
    print("HP RAID Controller for Zabbix")
    print("-h --help this help page")
    print("-a --action required")
    print("-p --part required")
    print("-i --identity part identification")
    print("-c --ctrlid controller id oder serial number")


def get_ssacli():
    for fpath in ('/usr/sbin/ssacli', '/usr/sbin/hpssacli', '/usr/sbin/hpacucli'):
        if os.path.isfile(fpath) and os.access(fpath, os.X_OK):
            return fpath
    return None


def main(action, ctrlid, part, partid):
    ssacli = get_ssacli()

    if not ssacli:
        return 1
    if action == 'lld':
        print(make_lld(ssacli, part))
        return 0
    elif action == 'health':
        print(get_health(ssacli, ctrlid, part, partid))
        return 0
    else:
        print("ERROR: Wrong action argument: use 'lld' or 'health'")
        return 1


if __name__ == "__main__":
    try:
        opts, args = getopt.gnu_getopt(sys.argv[1:], "ha:p:i:c:",
                                       ["action=", "part=", "identity=", "ctrlid=", "help"])
    except getopt.GetoptError as err: 
        print(str(err))
        sys.exit(2)

    action = 'lld'
    part = ''
    partid = 1
    ctrlid = 0

    for opt, arg in opts:
        if opt in ("-h", "--help"):
            usage()
            sys.exit(1)
        elif opt in ("-a", "--action"):
            action = arg
        elif opt in ("-p", "--part"):
            part = arg
        elif opt in ("-i", "--identity"):
            partid = arg
        elif opt in ("-c", "--ctrlid"):
            ctrlid = arg

    sys.exit(main(action, ctrlid, part, partid))
