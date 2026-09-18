#!/usr/bin/env python3
"""Fault-inject a nested show during wvkbd's sizing roundtrip.

Usage: python tests/check_wvkbd_show.py path/to/patched/main.c
Compiles the actual show() function with protocol stubs; no compositor needed.
"""
import pathlib
import subprocess
import sys
import tempfile

source = pathlib.Path(sys.argv[1]).read_text()
start = source.index('void\nshow()\n{')
end = source.index('\nvoid\ntoggle_visibility()', start)
show = source[start:end]
fixture = r'''
#include <stdbool.h>
#include <stdint.h>
#include <assert.h>
#include <stdio.h>
static bool show_in_progress;
static int64_t im_hide_deadline;
static void *layer_surface;
static bool injected;
static unsigned created;
static struct { void *surf; } draw_surf;
static struct { bool exclusive; } keyboard;
static void *wfs_mgr, *viewporter, *wfs_draw_surf, *draw_surf_viewport;
static int height;
#define wl_compositor_create_surface(...) ((void *)1)
#define wl_surface_add_listener(...) ((void)0)
#define wp_fractional_scale_manager_v1_get_fractional_scale(...) ((void *)1)
#define wp_fractional_scale_v1_add_listener(...) ((void)0)
#define wp_viewporter_get_viewport(...) ((void *)1)
#define zwlr_layer_shell_v1_get_layer_surface(...) ((void *)(uintptr_t)++created)
#define zwlr_layer_surface_v1_set_size(...) ((void)0)
#define zwlr_layer_surface_v1_set_anchor(...) ((void)0)
#define zwlr_layer_surface_v1_set_exclusive_zone(...) ((void)0)
#define zwlr_layer_surface_v1_set_keyboard_interactivity(...) ((void)0)
#define zwlr_layer_surface_v1_add_listener(...) ((void)0)
#define wl_surface_commit(...) ((void)0)
void show(void);
void refresh_available_dimension(void) {
    if (!injected) { injected = true; show(); }
}
void redimension_keyboard(void) {}
'''
checks = r'''
int main(void) {
    show();
    assert(created == 1 && layer_surface);
    show();
    assert(created == 1);
    layer_surface = NULL;
    injected = false;
    show();
    assert(created == 2 && layer_surface);
    puts("PASS: nested show creates one surface; subsequent reopening still works");
}
'''
with tempfile.TemporaryDirectory(prefix='wvkbd-reentry-') as temp:
    root = pathlib.Path(temp)
    (root / 'check.c').write_text(fixture + show + checks)
    subprocess.run(['cc', '-std=c99', str(root / 'check.c'), '-o', str(root / 'check')], check=True)
    result = subprocess.run([str(root / 'check')], cwd=root)
    sys.exit(0 if result.returncode == 0 else 1)
