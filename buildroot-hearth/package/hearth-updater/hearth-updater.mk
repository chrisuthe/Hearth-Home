################################################################################
#
# hearth-updater
#
################################################################################

HEARTH_UPDATER_VERSION = 1.0.0
HEARTH_UPDATER_SITE_METHOD = local
HEARTH_UPDATER_SITE = $(BR2_EXTERNAL_HEARTH_PATH)/package/hearth-updater
HEARTH_UPDATER_LICENSE = MIT

define HEARTH_UPDATER_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/hearth-updater.sh \
		$(TARGET_DIR)/usr/bin/hearth-updater
endef

$(eval $(generic-package))
