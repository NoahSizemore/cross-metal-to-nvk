#!/usr/bin/env python3
"""
Probe a Vulkan ICD directly through the Khronos loader. No Vulkan SDK needed.

Usage:
    VK_DRIVER_FILES=/Library/GPUBundles/nvmtl/nvk_icd.json \
    python3 vk_icd_probe.py

Do NOT run under sudo: the loader ignores VK_DRIVER_FILES for elevated processes.
"""
import ctypes, os, struct, sys

LOADER = os.environ.get("VK_LOADER_LIB", "/Library/GPUBundles/nvmtl/libvulkan.1.dylib")

VK_SUCCESS = 0
DEVICE_TYPES = {0: "OTHER", 1: "INTEGRATED_GPU", 2: "DISCRETE_GPU",
                3: "VIRTUAL_GPU", 4: "CPU"}


def ver(v):
    return f"{v >> 22}.{(v >> 12) & 0x3FF}.{v & 0xFFF}"


class VkApplicationInfo(ctypes.Structure):
    _fields_ = [
        ("sType", ctypes.c_uint32),
        ("pNext", ctypes.c_void_p),
        ("pApplicationName", ctypes.c_char_p),
        ("applicationVersion", ctypes.c_uint32),
        ("pEngineName", ctypes.c_char_p),
        ("engineVersion", ctypes.c_uint32),
        ("apiVersion", ctypes.c_uint32),
    ]


class VkInstanceCreateInfo(ctypes.Structure):
    _fields_ = [
        ("sType", ctypes.c_uint32),
        ("pNext", ctypes.c_void_p),
        ("flags", ctypes.c_uint32),
        ("pApplicationInfo", ctypes.POINTER(VkApplicationInfo)),
        ("enabledLayerCount", ctypes.c_uint32),
        ("ppEnabledLayerNames", ctypes.c_void_p),
        ("enabledExtensionCount", ctypes.c_uint32),
        ("ppEnabledExtensionNames", ctypes.c_void_p),
    ]


def main():
    print(f"loader      : {LOADER}")
    print(f"VK_DRIVER_FILES: {os.environ.get('VK_DRIVER_FILES', '(unset)')}\n")

    if not os.path.exists(LOADER):
        sys.exit(f"FAIL: loader not found at {LOADER}")

    try:
        vk = ctypes.CDLL(LOADER)
    except OSError as e:
        sys.exit(f"FAIL: could not load the loader: {e}")

    vk.vkCreateInstance.restype = ctypes.c_int32
    vk.vkCreateInstance.argtypes = [ctypes.POINTER(VkInstanceCreateInfo),
                                    ctypes.c_void_p,
                                    ctypes.POINTER(ctypes.c_void_p)]
    vk.vkEnumeratePhysicalDevices.restype = ctypes.c_int32
    vk.vkEnumeratePhysicalDevices.argtypes = [ctypes.c_void_p,
                                              ctypes.POINTER(ctypes.c_uint32),
                                              ctypes.c_void_p]
    vk.vkGetPhysicalDeviceProperties.restype = None
    vk.vkGetPhysicalDeviceProperties.argtypes = [ctypes.c_void_p, ctypes.c_void_p]

    app = VkApplicationInfo(0, None, b"icdprobe", 1, b"none", 1, 1 << 22)  # API 1.0
    ci = VkInstanceCreateInfo(1, None, 0, ctypes.pointer(app), 0, None, 0, None)

    inst = ctypes.c_void_p()
    rc = vk.vkCreateInstance(ctypes.byref(ci), None, ctypes.byref(inst))
    if rc != VK_SUCCESS:
        sys.exit(f"FAIL: vkCreateInstance returned {rc}\n"
                 "  -9  = VK_ERROR_INCOMPATIBLE_DRIVER (loader found no usable ICD)\n"
                 "  Re-run with VK_LOADER_DEBUG=all to see ICD discovery.")
    print("vkCreateInstance: OK")

    n = ctypes.c_uint32(0)
    vk.vkEnumeratePhysicalDevices(inst, ctypes.byref(n), None)
    print(f"physical devices: {n.value}\n")
    if n.value == 0:
        sys.exit("FAIL: instance created but no physical devices. The ICD loaded "
                 "but reported no GPU.")

    devs = (ctypes.c_void_p * n.value)()
    vk.vkEnumeratePhysicalDevices(inst, ctypes.byref(n), devs)

    for i in range(n.value):
        buf = ctypes.create_string_buffer(4096)
        vk.vkGetPhysicalDeviceProperties(devs[i], buf)
        api, drv, vendor, devid, dtype = struct.unpack_from("<IIIII", buf, 0)
        name = buf.raw[20:20 + 256].split(b"\x00")[0].decode("utf-8", "replace")
        print(f"[device {i}] {name}")
        print(f"    type       : {DEVICE_TYPES.get(dtype, dtype)}")
        print(f"    apiVersion : {ver(api)}")
        print(f"    driverVer  : {drv} (0x{drv:08x})")
        print(f"    vendorID   : 0x{vendor:04x}"
              f"{'  <- NVIDIA' if vendor == 0x10DE else ''}")
        print(f"    deviceID   : 0x{devid:04x}")
    print("\nIf vendorID is 0x10de and the name is your RTX 4070, native NVK is live.")


if __name__ == "__main__":
    main()
