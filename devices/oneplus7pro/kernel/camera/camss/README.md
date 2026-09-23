# CAMSS patches for SM8150

`scripts/build_camera_modules.sh` applies these, in file-name order, to a copy
of the native5 tree's `drivers/media/platform/qcom/camss` before building
`qcom-camss.ko`.

They come from the OnePlus 7T Pro (hotdog) r181 kernel checkpoint,
`.work/hotdog-reference/kernel-checkpoints/clearstaff-403b56c-r181/patches/`,
by Sr-0w. Six are byte-exact copies. 0067 and 0075 also changed
`arch/arm64/boot/dts/qcom/sm8150.dtsi`; only their camss file sections are kept
here (the interconnects they add to the DT live in our camera overlay instead).

| r181 | What it does |
|------|--------------|
| 0055 | Adds `qcom,sm8150-camss`: four CSIPHYs, two CSIDs (gen2), two VFEs (17x), templated on SDM845. |
| 0064 | Adds `CAMSS_8150` so the CSIPHY uses the v1.1 lane sequence (sc8280xp's) rather than SDM845's v1.0. |
| 0066 | Limits SM8150 DMA to a 31-bit mask so buffers stay inside the IFE's addressable IOVA range. |
| 0067 | Votes camera NoC bandwidth (`cam_ahb`, `cam_hf_0_mnoc`, `cam_sf_0_mnoc`) on SM8150 (camss hunk only). |
| 0075 | Also votes the internal CAMNOC HF0-uncompressed path, `cam_hf_0_camnoc` (camss hunk only). |
| 0076 | Makes both VFEs enable the `gcc_camera_axi` HF AXI bridge clock. |
| 0089 | Adds C-PHY support (3-trio lane tables from the vendor driver, CSID PHY-type select, DT parsing). |
| 0114 | Unwinds a failed stream start cleanly and avoids completing vb2 buffers twice on flush. |

The other two r181 camss patches are not taken: 0065 (VFE interrupt status
reporting for bring-up) and 0074 (CAMNOC QoS programming, kept in r181 only as
a diagnostic because its effect did not reproduce).
