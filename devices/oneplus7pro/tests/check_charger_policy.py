#!/usr/bin/env python3
"""Execute the actual charger monitor/cleanup C against simulated I/O failures."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'kernel/power/qcom_smbx_mobile.h').read_text()


def function(name):
    import re
    match = re.search(r'static (?:int|void) ' + name + r'\(', source)
    assert match, name
    start = source.index('{', match.start())
    depth = 1
    end = start + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[match.start():end]


prefix = r'''
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <errno.h>
#define BIT(x) (1u << (x))
#define CHARGING_ENABLE_CMD 0x42
#define BATTERY_CHARGER_STATUS_7 0x0d
#define BATTERY_CHARGER_STATUS_2 0x07
#define POWER_PATH_STATUS(chip) 0x10b
#define FAST_CHARGE_CURRENT_CFG 0x61
#define FLOAT_VOLTAGE_CFG 0x70
#define USBIN_CURRENT_LIMIT_CFG 0x370
#define SMB5_CHARGER_ERROR_STATUS_BAT_OV_BIT 2
#define container_of(ptr, type, member) ((type *)((char *)(ptr) - offsetof(type, member)))
#define dev_err_ratelimited(...) ((void)0)
#define dev_err(...) ((void)0)
#define dev_info(...) ((void)0)
#define mutex_lock(...) ((void)0)
#define mutex_unlock(...) ((void)0)
#define msecs_to_jiffies(x) (x)
enum { POWER_SUPPLY_PROP_TEMP, POWER_SUPPLY_PROP_VOLTAGE_NOW, POWER_SUPPLY_PROP_CURRENT_NOW, POWER_SUPPLY_PROP_PRESENT };
union power_supply_propval { int intval; };
struct work_struct { int unused; };
struct delayed_work { struct work_struct work; };
struct smb_chip {
    unsigned base; void *regmap, *dev, *fuel_gauge, *chg_psy;
    bool fault_latched, charge_active, stopping;
    int charge_lock; struct delayed_work status_change_work;
};
static unsigned regs[0x4000];
static int values[4], gauge_error, read_error, write_error;
static int scheduled, canceled, notifications, writes;
static int power_supply_get_property(void *p, int prop, union power_supply_propval *v) {
    if (gauge_error) return -EIO;
    v->intval = values[prop]; return 0;
}
static int regmap_read(void *m, unsigned r, unsigned *v) {
    if (read_error) return -EIO;
    *v = regs[r]; return 0;
}
static int regmap_write(void *m, unsigned r, unsigned v) {
    writes++;
    if (write_error) return -EIO;
    regs[r] = v; return 0;
}
static void power_supply_changed(void *p) { notifications++; }
static void schedule_delayed_work(struct delayed_work *w, int delay) { scheduled++; }
static void cancel_delayed_work_sync(struct delayed_work *w) { canceled++; }
static struct smb_chip reset(void) {
    struct smb_chip chip = { .base = 0x1000 };
    for (unsigned i=0;i<sizeof(regs)/sizeof(*regs);i++) regs[i]=0;
    regs[0x110b]=0x95; regs[0x1061]=10; regs[0x1070]=60; regs[0x1370]=10;
    values[0]=260; values[1]=4050000; values[2]=0; values[3]=1;
    gauge_error=read_error=write_error=scheduled=canceled=notifications=writes=0;
    return chip;
}
'''
body = '\n'.join(function(name) for name in ['smb_mobile_write_verify', 'smb_mobile_disable', 'smb_mobile_sample', 'smb_mobile_work', 'smb_mobile_stop'])
tests = r'''
int main(void) {
    bool allow; struct smb_chip c = reset();
    assert(!smb_mobile_sample(&c,&allow) && allow);
    smb_mobile_work(&c.status_change_work.work);
    assert(regs[0x1042]==1 && c.charge_active && scheduled==1);
    int enabled_writes=writes;
    smb_mobile_work(&c.status_change_work.work);
    assert(writes==enabled_writes && c.charge_active);
    gauge_error=1; smb_mobile_work(&c.status_change_work.work);
    assert(regs[0x1042]==0 && !c.charge_active);
    c=reset(); regs[0x110b]=0; smb_mobile_work(&c.status_change_work.work);
    assert(regs[0x1042]==0 && !c.charge_active);
    for (int t=99;t<=400;t++) {
        c=reset(); values[0]=t;
        assert(!smb_mobile_sample(&c,&allow)); assert(allow == (t>=120 && t<380));
        c.charge_active=true;
        assert(!smb_mobile_sample(&c,&allow)); assert(allow == (t>=100 && t<400));
    }
    c=reset(); regs[0x100d]=8; assert(!smb_mobile_sample(&c,&allow) && !allow);
    c=reset(); regs[0x1007]=2; assert(smb_mobile_sample(&c,&allow)<0 && c.fault_latched);
    regs[0x1007]=0; assert(smb_mobile_sample(&c,&allow)<0 && !allow);
    c=reset(); regs[0x1061]=78; assert(smb_mobile_sample(&c,&allow)<0 && c.fault_latched);
    c=reset(); regs[0x1070]=96; assert(smb_mobile_sample(&c,&allow)<0 && c.fault_latched);
    c=reset(); regs[0x1370]=32; assert(smb_mobile_sample(&c,&allow)<0 && c.fault_latched);
    c=reset(); values[2]=651000; assert(smb_mobile_sample(&c,&allow)<0 && c.fault_latched);
    c=reset(); values[1]=4250000; assert(smb_mobile_sample(&c,&allow)<0 && c.fault_latched);
    c=reset(); values[3]=0; assert(smb_mobile_sample(&c,&allow)<0 && !allow);
    c=reset(); read_error=1; assert(smb_mobile_sample(&c,&allow)<0 && !allow);
    c=reset(); write_error=1; smb_mobile_work(&c.status_change_work.work);
    assert(c.fault_latched && !c.charge_active);
    c=reset(); smb_mobile_work(&c.status_change_work.work); regs[0x1042]=0;
    smb_mobile_work(&c.status_change_work.work);
    assert(c.fault_latched && !c.charge_active && regs[0x1042]==0);
    c=reset(); smb_mobile_work(&c.status_change_work.work); smb_mobile_stop(&c);
    assert(c.stopping && canceled==1 && regs[0x1042]==0 && !c.charge_active);
    int previous=writes; smb_mobile_work(&c.status_change_work.work); assert(writes==previous);
    puts("PASS: actual charger C policy — thermal hysteresis, input loss, gauge/I/O failures, overvoltage/current, wrong register encodings, latched faults, stop/cancel");
}
'''
with tempfile.TemporaryDirectory(prefix='charger-policy-') as directory:
    cfile = Path(directory) / 'policy.c'
    binary = Path(directory) / 'policy'
    cfile.write_text(prefix + body + tests)
    subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Wno-unused-parameter', '-Werror', str(cfile), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
