# GMS
ifeq ($(WITH_GMS),true)
$(call inherit-product, vendor/pixel/gms/products/gms.mk)
$(call inherit-product, vendor/pixel/clocks/products/clocks.mk)

PRODUCT_PACKAGES += \
    UpdaterOverlayExtraGMS
endif

# Overlay
PRODUCT_PACKAGES += \
    UpdaterOverlayExtra
