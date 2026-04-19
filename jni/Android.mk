LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE    := oom_guardian
LOCAL_SRC_FILES := oom_guardian.c
LOCAL_CFLAGS    := -O2 -Wall -Wextra
LOCAL_LDFLAGS   := -static
include $(BUILD_EXECUTABLE)
