/* Minimal DRM dumb-buffer fill for DPU card2 / DSI-1. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <drm/drm.h>
#include <drm/drm_mode.h>

static int drm_ioctl(int fd, unsigned long req, void *arg)
{
	int ret;

	do {
		ret = ioctl(fd, req, arg);
	} while (ret == -1 && (errno == EINTR || errno == EAGAIN));
	return ret;
}

int main(int argc, char **argv)
{
	const char *path = argc > 1 ? argv[1] : "/dev/dri/card2";
	int fd, i, conn_id = -1, crtc_id = -1, enc_id = -1;
	struct drm_mode_card_res res;
	uint32_t conn_ids[32], crtc_ids[16], enc_ids[16];
	struct drm_mode_get_connector conn;
	uint32_t props[64], prop_values[64], encs[8];
	struct drm_mode_modeinfo modes[16];
	struct drm_mode_create_dumb dumb;
	struct drm_mode_map_dumb map;
	struct drm_mode_fb_cmd fb;
	struct drm_mode_crtc crtc;
	uint32_t *pix;
	uint32_t color = 0x00ff00ff; /* magenta XRGB8888 */
	int w = 0, h = 0;

	fd = open(path, O_RDWR | O_CLOEXEC);
	if (fd < 0) {
		perror("open");
		return 1;
	}

	memset(&res, 0, sizeof(res));
	if (drm_ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res)) {
		perror("GETRESOURCES1");
		return 1;
	}
	res.connector_id_ptr = (__u64)(uintptr_t)conn_ids;
	res.crtc_id_ptr = (__u64)(uintptr_t)crtc_ids;
	res.encoder_id_ptr = (__u64)(uintptr_t)enc_ids;
	if (res.count_connectors > 32 || res.count_crtcs > 16 ||
	    res.count_encoders > 16) {
		fprintf(stderr, "too many resources\n");
		return 1;
	}
	if (drm_ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res)) {
		perror("GETRESOURCES2");
		return 1;
	}

	for (i = 0; i < (int)res.count_connectors && i < 32; i++) {
		memset(&conn, 0, sizeof(conn));
		conn.connector_id = conn_ids[i];
		conn.count_props = 64;
		conn.props_ptr = (__u64)(uintptr_t)props;
		conn.prop_values_ptr = (__u64)(uintptr_t)prop_values;
		conn.count_encoders = 8;
		conn.encoders_ptr = (__u64)(uintptr_t)encs;
		conn.count_modes = 16;
		conn.modes_ptr = (__u64)(uintptr_t)modes;
		if (drm_ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &conn))
			continue;
		if (conn.connection == 1 && conn.count_modes > 0) {
			conn_id = (int)conn_ids[i];
			enc_id = conn.encoder_id ? (int)conn.encoder_id :
				 (conn.count_encoders ? (int)encs[0] : 0);
			w = modes[0].hdisplay;
			h = modes[0].vdisplay;
			break;
		}
	}
	if (conn_id < 0) {
		fprintf(stderr, "no connected connector\n");
		return 2;
	}

	if (enc_id) {
		struct drm_mode_get_encoder enc;

		memset(&enc, 0, sizeof(enc));
		enc.encoder_id = enc_id;
		if (drm_ioctl(fd, DRM_IOCTL_MODE_GETENCODER, &enc) == 0)
			crtc_id = (int)enc.crtc_id;
	}
	if (crtc_id <= 0 && res.count_crtcs)
		crtc_id = (int)crtc_ids[0];

	memset(&dumb, 0, sizeof(dumb));
	dumb.width = w;
	dumb.height = h;
	dumb.bpp = 32;
	if (drm_ioctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &dumb)) {
		perror("CREATE_DUMB");
		return 3;
	}

	memset(&map, 0, sizeof(map));
	map.handle = dumb.handle;
	if (drm_ioctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &map)) {
		perror("MAP_DUMB");
		return 4;
	}
	pix = mmap(NULL, dumb.size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, map.offset);
	if (pix == MAP_FAILED) {
		perror("mmap");
		return 5;
	}
	for (i = 0; i < (int)(dumb.size / 4); i++)
		pix[i] = color;
	munmap(pix, dumb.size);

	memset(&fb, 0, sizeof(fb));
	fb.width = w;
	fb.height = h;
	fb.pitch = dumb.pitch;
	fb.bpp = 32;
	fb.depth = 24;
	fb.handle = dumb.handle;
	if (drm_ioctl(fd, DRM_IOCTL_MODE_ADDFB, &fb)) {
		perror("ADDFB");
		return 6;
	}

	memset(&crtc, 0, sizeof(crtc));
	crtc.crtc_id = crtc_id;
	if (drm_ioctl(fd, DRM_IOCTL_MODE_GETCRTC, &crtc))
		perror("GETCRTC");
	crtc.set_connectors_ptr = (__u64)(uintptr_t)&conn_id;
	crtc.count_connectors = 1;
	crtc.fb_id = fb.fb_id;
	crtc.x = 0;
	crtc.y = 0;
	crtc.mode = modes[0];
	crtc.mode_valid = 1;
	if (drm_ioctl(fd, DRM_IOCTL_MODE_SETCRTC, &crtc)) {
		perror("SETCRTC");
		return 7;
	}

	fprintf(stderr, "dsi-fill: %s connector=%d crtc=%d %dx%d fb=%u magenta\n",
		path, conn_id, crtc_id, w, h, fb.fb_id);
	pause();
	return 0;
}
