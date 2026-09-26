#!/usr/bin/env python3
"""Exercise the actual runtime callbacks against a fake CCF transport."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / '.work/linux-sm8150-dsi-phy-pm/drivers/gpu/drm/msm/dsi/phy/dsi_phy.c').read_text()

def extract(name):
    start = source.index('static int __maybe_unused ' + name)
    brace = source.index('{', start)
    end = brace + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

program = r'''
#include <assert.h>
#include <errno.h>
#include <stdio.h>
#define __maybe_unused
struct clk { int prepared, enabled; };
struct msm_dsi_phy { struct clk *iface_clk; };
struct device { struct msm_dsi_phy *data; };
static int fail_prepare, fail_enable;
static struct msm_dsi_phy *dev_get_drvdata(struct device *d) { return d->data; }
static int clk_prepare_enable(struct clk *c) {
    if (fail_prepare) return -EIO;
    c->prepared++;
    if (fail_enable) { c->prepared--; return -ETIMEDOUT; }
    c->enabled++; return 0;
}
static void clk_disable_unprepare(struct clk *c) {
    assert(c->enabled > 0 && c->prepared > 0);
    c->enabled--; c->prepared--;
}
'''
program += extract('dsi_phy_runtime_suspend') + extract('dsi_phy_runtime_resume')
program += r'''
int main(void) {
    for (int other=0; other<5; other++) {
        struct clk clock={other,other};
        struct msm_dsi_phy phy={&clock};
        struct device dev={&phy};
        for (int cycle=0; cycle<100; cycle++) {
            assert(dsi_phy_runtime_resume(&dev)==0);
            assert(clock.prepared==other+1 && clock.enabled==other+1);
            assert(dsi_phy_runtime_suspend(&dev)==0);
            assert(clock.prepared==other && clock.enabled==other);
        }
        fail_prepare=1;
        assert(dsi_phy_runtime_resume(&dev)==-EIO);
        assert(clock.prepared==other && clock.enabled==other);
        fail_prepare=0; fail_enable=1;
        assert(dsi_phy_runtime_resume(&dev)==-ETIMEDOUT);
        assert(clock.prepared==other && clock.enabled==other);
        fail_enable=0;
        assert(!dsi_phy_runtime_resume(&dev));
        assert(!dsi_phy_runtime_suspend(&dev));
        assert(clock.prepared==other && clock.enabled==other);
    }
    puts("PASS: 500 callback cycles balance both references; prepare/enable errors propagate; other references preserved");
}
'''
with tempfile.TemporaryDirectory(prefix='dsi-pm-callback-test-') as temp:
    c=Path(temp)/'test.c'; binary=Path(temp)/'test'
    c.write_text(program)
    subprocess.run(['cc','-Wall','-Wextra','-Werror',str(c),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
