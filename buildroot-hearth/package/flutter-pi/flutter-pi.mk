################################################################################
#
# flutter-pi
#
################################################################################

FLUTTER_PI_VERSION = v2.0.0
FLUTTER_PI_SITE = https://github.com/ardera/flutter-pi.git
FLUTTER_PI_SITE_METHOD = git
FLUTTER_PI_GIT_SUBMODULES = YES
FLUTTER_PI_LICENSE = MIT
FLUTTER_PI_LICENSE_FILES = LICENSE

FLUTTER_PI_DEPENDENCIES = \
	mesa3d \
	libdrm \
	libgbm \
	libinput \
	systemd \
	gstreamer1 \
	gst1-plugins-base

FLUTTER_PI_CONF_OPTS = \
	-DBUILD_GSTREAMER_VIDEO_PLAYER_PLUGIN=ON \
	-DBUILD_GSTREAMER_AUDIO_PLAYER_PLUGIN=ON \
	-DENABLE_VULKAN=OFF

$(eval $(cmake-package))
