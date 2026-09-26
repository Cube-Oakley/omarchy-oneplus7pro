#!/usr/bin/env python3
"""Compile the actual diagnostic functions with a fake RPMh transport."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / '.work/linux-sm8150-dsi-phy-pm/drivers/pmdomain/qcom/rpmhpd.c'
TEST = ROOT / '.work/linux-sm8150-mmcx-sleep/drivers/pmdomain/qcom/rpmhpd.c'
HEADER = ROOT / 'kernel/power/rpmhpd-mmcx-sleep-test.h'


def function(path, name):
    text = path.read_text()
    start = text.index('static ', text.index(name) - 20)
    brace = text.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


prelude = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
typedef uint64_t u64;
#define max(a,b) ((a) > (b) ? (a) : (b))
#define READ_ONCE(a) (a)
#define WRITE_ONCE(a,b) ((a)=(b))
#define dev_info(...) ((void)0)
enum { RPMH_ACTIVE_ONLY_STATE, RPMH_WAKE_ONLY_STATE, RPMH_SLEEP_STATE };
struct rpmhpd {
 bool state_synced, enabled, active_only;
 unsigned int level_count, corner, enable_corner, active_corner, addr;
 void *dev;
 struct rpmhpd *peer;
};
static struct rpmhpd mmcx, mmcx_ao, other, other_ao;
static struct rpmhpd cx_w_mx_parent, cx_ao_w_mx_parent;
static int rpmhpd_lock, locked, send_error;
static int mutex_trylock(int *p) { return !locked; }
static void mutex_unlock(int *p) { }
struct call { unsigned int state, corner, sync; };
static struct call calls[3];
static int count;
static int rpmhpd_send_corner(struct rpmhpd *pd, int state, unsigned int corner, bool sync) {
 assert(count < 3);
 calls[count++] = (struct call){state, corner, sync};
 return send_error;
}
'''
header = HEADER.read_text().split('DEFINE_DEBUGFS_ATTRIBUTE')[0]
header = header.replace('#include <linux/debugfs.h>', '')
cx_header = (ROOT / 'kernel/power/rpmhpd-cx-sleep-test.h').read_text().split('DEFINE_DEBUGFS_ATTRIBUTE')[0].replace('#include <linux/debugfs.h>', '')
source = prelude + function(BASE, 'to_active_sleep(') + cx_header + header
source += function(BASE, 'rpmhpd_aggregate_corner(').replace('rpmhpd_aggregate_corner', 'original')
source += function(TEST, 'rpmhpd_aggregate_corner(')
source += r'''
static void reset(void) {
 mmcx = (struct rpmhpd){.level_count=7, .enable_corner=2,
    .addr=0x30000, .dev=(void *)1, .peer=&mmcx_ao};
 mmcx_ao = mmcx;
 mmcx_ao.active_only=true;
 mmcx_ao.peer=&mmcx;
 other=mmcx; other.peer=&other_ao;
 other_ao=mmcx_ao; other_ao.peer=&other;
 cx_w_mx_parent=mmcx; cx_w_mx_parent.peer=&cx_ao_w_mx_parent;
 cx_ao_w_mx_parent=mmcx_ao; cx_ao_w_mx_parent.peer=&cx_w_mx_parent;
 count=0; locked=0; send_error=0; mmcx_sleep_test_release=false; cx_sleep_test_release=false;
}
int main(void) {
 unsigned int cases=0;
 for (int kind=0; kind<6; kind++)
 for (int cx_release=0; cx_release<2; cx_release++)
 for (int synced=0; synced<2; synced++)
 for (int enabled=0; enabled<2; enabled++)
 for (int release=0; release<2; release++)
 for (unsigned int corner=0; corner<7; corner++)
 for (unsigned int pc=0; pc<7; pc++) {
   reset();
   struct rpmhpd *pd = kind==0 ? &mmcx : kind==1 ? &mmcx_ao :
                        kind==2 ? &other : kind==3 ? &other_ao : kind==4 ? &cx_w_mx_parent : &cx_ao_w_mx_parent;
   cx_sleep_test_release=cx_release;
   pd->state_synced=synced; pd->peer->enabled=enabled; pd->peer->corner=pc;
   assert(!original(pd,corner));
   struct call expected[3]; memcpy(expected,calls,sizeof(calls));
   count=0; pd->active_corner=0; pd->peer->active_corner=0;
   mmcx_sleep_test_release=release;
   assert(!rpmhpd_aggregate_corner(pd,corner)); assert(count==3);
   if (kind<2 && release && !synced) {
     unsigned int self=pd->active_only ? 0 : corner;
     unsigned int peer=enabled && !pd->peer->active_only ? max(pc,2) : 0;
     expected[2].corner=max(self,peer);
   }
   assert(!memcmp(calls,expected,sizeof(calls))); cases++;
 }
 for (int enabled=0; enabled<2; enabled++)
 for (unsigned int corner=0; corner<7; corner++) {
   reset(); mmcx.enabled=enabled; mmcx.corner=corner;
   assert(!mmcx_sleep_test_set(NULL,1)); assert(mmcx_sleep_test_release);
   assert(count==1 && calls[0].state==RPMH_SLEEP_STATE && !calls[0].sync);
   assert(calls[0].corner==(enabled ? max(corner,2) : 0));
   count=0;
   assert(!mmcx_sleep_test_set(NULL,0)); assert(!mmcx_sleep_test_release);
   assert(count==1 && calls[0].state==RPMH_SLEEP_STATE && calls[0].corner==6);
 }
 reset(); other.peer=NULL; mmcx_sleep_test_release=true;
 assert(!original(&other,0)); struct call mss_call=calls[0];
 count=0; other.active_corner=0;
 assert(!rpmhpd_aggregate_corner(&other,0));
 assert(count==1 && !memcmp(&calls[0],&mss_call,sizeof(mss_call)));
 reset(); assert(mmcx_sleep_test_set(NULL,2)==-EINVAL && count==0);
 reset(); locked=1; assert(mmcx_sleep_test_set(NULL,1)==-EBUSY && count==0);
 reset(); mmcx.state_synced=1;
 assert(mmcx_sleep_test_set(NULL,1)==-EBUSY && count==0);
 reset(); mmcx_ao.state_synced=1;
 assert(mmcx_sleep_test_set(NULL,1)==-EBUSY && count==0);
 reset(); send_error=-ENOMEM;
 assert(mmcx_sleep_test_set(NULL,1)==-ENOMEM && !mmcx_sleep_test_release);
 reset(); mmcx.dev=NULL;
 assert(mmcx_sleep_test_set(NULL,1)==-EBUSY && count==0);
 reset(); mmcx.level_count=0;
 assert(mmcx_sleep_test_set(NULL,1)==-EBUSY && count==0);
 reset(); mmcx.addr=0;
 assert(mmcx_sleep_test_set(NULL,1)==-EBUSY && count==0);
 reset(); assert(!mmcx_sleep_test_set(NULL,1)); count=0; send_error=-ENOMEM;
 assert(mmcx_sleep_test_set(NULL,0)==-ENOMEM && mmcx_sleep_test_release);
 reset();
 u64 value=99; assert(!mmcx_sleep_test_get(NULL,&value) && value==0);
 printf("PASS: %u aggregation cases; cache-only setters, guards and failed enable\n",cases);
}
'''
with tempfile.TemporaryDirectory(prefix='mmcx-kernel-test-') as tmp:
    c = Path(tmp) / 'test.c'
    binary = Path(tmp) / 'test'
    c.write_text(source)
    subprocess.run(['cc', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter', '-Wno-unused-function',
                    str(c), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
