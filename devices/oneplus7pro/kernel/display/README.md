# Native display investigation

Status: **native2 #179 boots native DSI and accelerated Hyprland/Quickshell
automatically at 60 Hz**. Touch, keyboard, eight CPUs and USB SSH pass.
`guacamole-native-panel.dts` creates reciprocal DSI/panel endpoints;
`guacamole-panel-graph.dts` and `panel_graph.c` preserve the historical native1
live repair, which native2 does not need. Image/evidence checkpoint:
`out/checkpoints/20260917-native2-verified/`. See the investigation record for
physical feedback and validation limits; 90 Hz is not implemented.

`native1-from-touch1.patch` contains the complete adaptation against the
verified `.work/linux-sm8150-codex-cpu` tree, including the reference changes.
Apply it to a fresh copy of that tree; do not also apply the reference patch.
The prepared `.work/linux-sm8150-codex-native` already has these changes.
`guacamole-native-panel.dts` overlays the frozen touch1 embedded DTB.
Build with `bash scripts/build_native_display.sh` and verify with
`python3 scripts/verify_native_display.py`. The old CPU/touch builders still
target their original tree.

`hotdog-dsc-reference.patch` extracts the panel driver, DSI host packetization,
and DSC configuration header changes from Robin Snyders' patch:

- Repository: https://github.com/Sr-0w/hotdog-linux-bringup
- Local reference commit: `47087509c4289c2580c54f5433e55366b2e00445`
- Source: `aports/device/testing/linux-oneplus-hotdog-mainline616/0012-drm-msm-enable-native-hotdog-dsc-panel.patch`
- Original patch commit: `c5b312b51527f4773df2801e7f565c315bda3d03`

The extracted patch retains source copyright/license notices. It deliberately
does not contain the hotdog device tree or its Kconfig change: guacamole needs
its own wiring review and build integration. Treat this as a reference port,
not a finished upstream driver.

## Initial reference-only reproduction (historical)

The verified working tree was copied (including its local CPU/GPU/USB fixes)
to `.work/linux-sm8150-codex-native`. The working tree remains unchanged.
Starting with a new copy of `.work/linux-sm8150-codex-cpu`:

```sh
patch --batch -d .work/linux-sm8150-codex-native -p1 \
  < devices/oneplus7pro/kernel/display/hotdog-dsc-reference.patch
make -C .work/linux-sm8150-codex-native ARCH=arm64 LLVM=1 -j8 \
  drivers/gpu/drm/panel/panel-samsung-oneplus-dsc.o \
  drivers/gpu/drm/msm/dsi/dsi_host.o
```

Both objects compiled successfully. The driver is not selected by Kconfig or
linked into a new kernel. Do not run the existing CPU/touch image builders
assuming they use this isolated directory; those builders still use the
verified CPU tree.

See [the investigation record](../../../../docs/native-display-work-20260917.md)
for hardware evidence, open questions, and the next test design.
