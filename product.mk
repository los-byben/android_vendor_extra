# GMS
ifeq ($(WITH_GMS),true)
$(call inherit-product, vendor/pixel/gms/products/gms.mk)
$(call inherit-product, vendor/pixel/clocks/products/clocks.mk)

PRODUCT_PACKAGES += \
    UpdaterOverlayExtraGMS
endif

# MiuiCamera
$(call inherit-product-if-exists, device/xiaomi/$(shell echo -n $(TARGET_PRODUCT) | sed -e 's/^[a-z]*_//g')-miuicamera/device.mk)

# Overlay
PRODUCT_PACKAGES += \
    UpdaterOverlayExtra
