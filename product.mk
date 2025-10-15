# Face Unlock
TARGET_FACE_UNLOCK_SUPPORTED ?= $(TARGET_SUPPORTS_64_BIT_APPS)

ifeq ($(TARGET_FACE_UNLOCK_SUPPORTED),true)
PRODUCT_PACKAGES += \
    ParanoidSense

PRODUCT_SYSTEM_EXT_PROPERTIES += \
    ro.face.sense_service=true

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.biometrics.face.xml:$(TARGET_COPY_OUT_SYSTEM)/etc/permissions/android.hardware.biometrics.face.xml
endif

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
