// Spike 04: which VkFormat and DRM format modifier does the headset's Turnip take for the decoder's Q10C (UBWC TP10)?
//
// 1. Lists what the Vulkan driver offers: device, driver, YCbCr and format extensions, and for every 2-plane 4:2:0 and
//    10-bit format the features and the DRM format modifiers (with memory plane counts), plus whether a dmabuf import
//    of each (format, modifier) is possible. --scan-formats also walks the extension ranges for formats nobody listed
//    (a vendor format such as a VK_FORMAT_*_QCOM).
// 2. --selftest: the conversion pipeline below on a host-memory test pattern (no decoder): a check that the probe itself
//    is right, on any Vulkan driver (lavapipe on the PC, Turnip on the headset).
// 3. --decode FILE: decodes the first frame of a raw HEVC (Annex-B) file with /dev/video-dec0 into Q10C (or --capture
//    Q08C, P010, NV12), exports it with VIDIOC_EXPBUF, imports it with every candidate (format, modifier, plane layout),
//    reads it through a sampler with a YCbCr conversion (RGB_IDENTITY: the raw codes) into a buffer, and writes each
//    result as yuv420p10le (.yuv, the visible area) and a BT.709 preview (.ppm), with a verdict from the picture's own
//    statistics, and PSNR against --ref (FFmpeg's decode of the same frame) when given.
//
// Plain C, no libraries beyond libc and libdl: the Vulkan loader is dlopen()ed. Build: see the Makefile.

#define _GNU_SOURCE
#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <linux/dma-buf.h>
#include <linux/videodev2.h>
#include <math.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include "convert.spv.h"

#ifndef V4L2_PIX_FMT_QC10C
#define V4L2_PIX_FMT_QC10C v4l2_fourcc('Q', '1', '0', 'C')
#endif
#ifndef V4L2_PIX_FMT_QC08C
#define V4L2_PIX_FMT_QC08C v4l2_fourcc('Q', '0', '8', 'C')
#endif
#ifndef V4L2_PIX_FMT_P010
#define V4L2_PIX_FMT_P010 v4l2_fourcc('P', '0', '1', '0')
#endif

#define MOD_LINEAR 0ull
#define MOD_QCOM(n) ((uint64_t)0x05 << 56 | (uint64_t)(n))
#define MOD_INVALID 0x00ffffffffffffffull

/* ------------------------------------------------------------------------------------------ */
/* Vulkan entry points */

#define GLOBAL_FUNCS(X)                     \
	X(vkCreateInstance)                     \
	X(vkEnumerateInstanceExtensionProperties)
#define INSTANCE_FUNCS(X)                         \
	X(vkDestroyInstance)                          \
	X(vkEnumeratePhysicalDevices)                 \
	X(vkGetPhysicalDeviceProperties)              \
	X(vkGetPhysicalDeviceProperties2)             \
	X(vkGetPhysicalDeviceFeatures2)               \
	X(vkGetPhysicalDeviceFormatProperties)        \
	X(vkGetPhysicalDeviceFormatProperties2)       \
	X(vkGetPhysicalDeviceImageFormatProperties2)  \
	X(vkEnumerateDeviceExtensionProperties)       \
	X(vkGetPhysicalDeviceQueueFamilyProperties)   \
	X(vkGetPhysicalDeviceMemoryProperties)        \
	X(vkCreateDevice)                             \
	X(vkGetDeviceProcAddr)
#define DEVICE_FUNCS(X)                     \
	X(vkDestroyDevice)                      \
	X(vkGetDeviceQueue)                     \
	X(vkDeviceWaitIdle)                     \
	X(vkCreateImage)                        \
	X(vkDestroyImage)                       \
	X(vkGetImageMemoryRequirements2)        \
	X(vkGetImageSubresourceLayout)          \
	X(vkAllocateMemory)                     \
	X(vkFreeMemory)                         \
	X(vkBindImageMemory)                    \
	X(vkMapMemory)                          \
	X(vkUnmapMemory)                        \
	X(vkCreateSamplerYcbcrConversion)       \
	X(vkDestroySamplerYcbcrConversion)      \
	X(vkCreateSampler)                      \
	X(vkDestroySampler)                     \
	X(vkCreateImageView)                    \
	X(vkDestroyImageView)                   \
	X(vkCreateDescriptorSetLayout)          \
	X(vkDestroyDescriptorSetLayout)         \
	X(vkCreatePipelineLayout)               \
	X(vkDestroyPipelineLayout)              \
	X(vkCreateShaderModule)                 \
	X(vkDestroyShaderModule)                \
	X(vkCreateComputePipelines)             \
	X(vkDestroyPipeline)                    \
	X(vkCreateDescriptorPool)               \
	X(vkDestroyDescriptorPool)              \
	X(vkAllocateDescriptorSets)             \
	X(vkUpdateDescriptorSets)               \
	X(vkCreateBuffer)                       \
	X(vkDestroyBuffer)                      \
	X(vkGetBufferMemoryRequirements)        \
	X(vkBindBufferMemory)                   \
	X(vkCreateCommandPool)                  \
	X(vkDestroyCommandPool)                 \
	X(vkAllocateCommandBuffers)             \
	X(vkResetCommandPool)                   \
	X(vkBeginCommandBuffer)                 \
	X(vkEndCommandBuffer)                   \
	X(vkCmdPipelineBarrier)                 \
	X(vkCmdBindPipeline)                    \
	X(vkCmdBindDescriptorSets)              \
	X(vkCmdPushConstants)                   \
	X(vkCmdDispatch)                        \
	X(vkCreateFence)                        \
	X(vkDestroyFence)                       \
	X(vkWaitForFences)                      \
	X(vkResetFences)                        \
	X(vkQueueSubmit)

#define DECLARE(name) static PFN_##name name;
static PFN_vkGetInstanceProcAddr vkGetInstanceProcAddr;
GLOBAL_FUNCS(DECLARE)
INSTANCE_FUNCS(DECLARE)
DEVICE_FUNCS(DECLARE)
static PFN_vkGetMemoryFdPropertiesKHR vkGetMemoryFdPropertiesKHR;
static PFN_vkGetImageDrmFormatModifierPropertiesEXT vkGetImageDrmFormatModifierPropertiesEXT;

static VkInstance g_instance;
static VkPhysicalDevice g_pd;
static VkDevice g_dev;
static VkQueue g_queue;
static uint32_t g_queue_family;
static VkCommandPool g_cmd_pool;
static VkCommandBuffer g_cmd;
static VkFence g_fence;
static VkPhysicalDeviceMemoryProperties g_mem_props;
static bool g_has_modifiers, g_has_dmabuf, g_has_foreign, g_has_props_list2, g_ycbcr_feature;

/* ------------------------------------------------------------------------------------------ */
/* Options */

static struct {
	bool scan_formats;
	bool selftest;
	const char *decode_path;
	const char *device;
	uint32_t capture;
	unsigned frame;
	const char *out_dir;
	const char *ref_path;
	const char *only;
	int extra_format;
	uint64_t extra_modifier;
	bool have_extra_modifier;
	bool dump_raw;
	bool bt2020;
	bool ycbcr_model;
	bool all_modifiers;
} o = {
	.device = "/dev/video-dec0",
	.capture = V4L2_PIX_FMT_QC10C,
	.out_dir = "q10c-out",
	.extra_format = -1,
};

static double now_s(void) {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

static const char *fourcc_str(uint32_t f) {
	static char s[4][8];
	static int i;
	char *r = s[i++ & 3];
	for (int k = 0; k < 4; k++) {
		const char c = (char)((f >> (8 * k)) & 0xff);
		r[k] = (c >= 32 && c < 127) ? c : '?';
	}
	r[4] = 0;
	return r;
}

/* ------------------------------------------------------------------------------------------ */
/* Names */

struct format_desc {
	VkFormat format;
	const char *name;
	int bits; // Bits per sample of the codes the sampler returns (0: not a YCbCr candidate).
	bool candidate; // A 2-plane 4:2:0 format worth trying for a decoder buffer.
};

#define F(f, bits, cand) { VK_FORMAT_##f, #f, bits, cand }
static const struct format_desc g_formats[] = {
	F(G8_B8R8_2PLANE_420_UNORM, 8, true),
	F(G10X6_B10X6R10X6_2PLANE_420_UNORM_3PACK16, 10, true),
	F(G12X4_B12X4R12X4_2PLANE_420_UNORM_3PACK16, 12, true),
	F(G16_B16R16_2PLANE_420_UNORM, 16, true),
	F(G8_B8_R8_3PLANE_420_UNORM, 8, false),
	F(G10X6_B10X6_R10X6_3PLANE_420_UNORM_3PACK16, 10, false),
	F(G16_B16_R16_3PLANE_420_UNORM, 16, false),
	F(G8_B8R8_2PLANE_422_UNORM, 8, false),
	F(G10X6_B10X6R10X6_2PLANE_422_UNORM_3PACK16, 10, false),
	F(G8_B8R8_2PLANE_444_UNORM, 8, false),
	F(G10X6_B10X6R10X6_2PLANE_444_UNORM_3PACK16, 10, false),
	F(G8B8G8R8_422_UNORM, 8, false),
	F(B8G8R8G8_422_UNORM, 8, false),
	F(R10X6_UNORM_PACK16, 0, false),
	F(R10X6G10X6_UNORM_2PACK16, 0, false),
	F(R10X6G10X6B10X6A10X6_UNORM_4PACK16, 0, false),
	F(R12X4_UNORM_PACK16, 0, false),
	F(R16_UNORM, 0, false),
	F(R16G16_UNORM, 0, false),
	F(R8_UNORM, 0, false),
	F(R8G8_UNORM, 0, false),
	F(A2B10G10R10_UNORM_PACK32, 0, false),
	F(A2R10G10B10_UNORM_PACK32, 0, false),
	F(R8G8B8A8_UNORM, 0, false),
	F(R32_UINT, 0, false),
};
#undef F

static const char *format_name(VkFormat f) {
	for (size_t i = 0; i < sizeof(g_formats) / sizeof(g_formats[0]); i++) {
		if (g_formats[i].format == f) {
			return g_formats[i].name;
		}
	}
	return "?";
}

static int format_bits(VkFormat f) {
	for (size_t i = 0; i < sizeof(g_formats) / sizeof(g_formats[0]); i++) {
		if (g_formats[i].format == f) {
			return g_formats[i].bits;
		}
	}
	return 10; // An unknown (vendor) format: assume the 10-bit codes Q10C holds.
}

static const char *modifier_name(uint64_t m) {
	if (m == MOD_LINEAR) {
		return "LINEAR";
	}
	if ((m >> 56) == 0x05) {
		switch (m & 0x00ffffffffffffffull) {
			case 1: return "QCOM_COMPRESSED (UBWC)";
			case 2: return "QCOM 2 (upstream TILED2; Android downstream DX)";
			case 3: return "QCOM 3 (upstream TILED3; Android downstream COMPRESSED|DX: P010 UBWC)";
			case 4: return "QCOM 4 (Android downstream TIGHT)";
			case 5: return "QCOM 5 (Android downstream COMPRESSED|TIGHT)";
			case 6: return "QCOM 6 (Android downstream DX|TIGHT: TP10 linear)";
			case 7: return "QCOM 7 (Android downstream COMPRESSED|DX|TIGHT: TP10 UBWC)";
			default: return "QCOM (unknown)";
		}
	}
	if (m == MOD_INVALID) {
		return "INVALID";
	}
	return "other vendor";
}

static void print_features(const char *label, VkFormatFeatureFlags2 f) {
	static const struct {
		VkFormatFeatureFlags2 bit;
		const char *name;
	} names[] = {
		{ VK_FORMAT_FEATURE_2_SAMPLED_IMAGE_BIT, "SAMPLED" },
		{ VK_FORMAT_FEATURE_2_SAMPLED_IMAGE_FILTER_LINEAR_BIT, "FILTER_LINEAR" },
		{ VK_FORMAT_FEATURE_2_STORAGE_IMAGE_BIT, "STORAGE" },
		{ VK_FORMAT_FEATURE_2_COLOR_ATTACHMENT_BIT, "COLOR_ATTACHMENT" },
		{ VK_FORMAT_FEATURE_2_TRANSFER_SRC_BIT, "TRANSFER_SRC" },
		{ VK_FORMAT_FEATURE_2_TRANSFER_DST_BIT, "TRANSFER_DST" },
		{ VK_FORMAT_FEATURE_2_MIDPOINT_CHROMA_SAMPLES_BIT, "MIDPOINT_CHROMA" },
		{ VK_FORMAT_FEATURE_2_COSITED_CHROMA_SAMPLES_BIT, "COSITED_CHROMA" },
		{ VK_FORMAT_FEATURE_2_SAMPLED_IMAGE_YCBCR_CONVERSION_LINEAR_FILTER_BIT, "YCBCR_LINEAR_FILTER" },
		{ VK_FORMAT_FEATURE_2_SAMPLED_IMAGE_YCBCR_CONVERSION_SEPARATE_RECONSTRUCTION_FILTER_BIT, "YCBCR_SEPARATE_RECONSTRUCTION" },
		{ VK_FORMAT_FEATURE_2_SAMPLED_IMAGE_YCBCR_CONVERSION_CHROMA_RECONSTRUCTION_EXPLICIT_BIT, "YCBCR_EXPLICIT" },
		{ VK_FORMAT_FEATURE_2_SAMPLED_IMAGE_YCBCR_CONVERSION_CHROMA_RECONSTRUCTION_EXPLICIT_FORCEABLE_BIT, "YCBCR_EXPLICIT_FORCEABLE" },
		{ VK_FORMAT_FEATURE_2_DISJOINT_BIT, "DISJOINT" },
		{ VK_FORMAT_FEATURE_2_HOST_IMAGE_TRANSFER_BIT_EXT, "HOST_TRANSFER" },
	};
	printf("%s0x%" PRIx64, label, (uint64_t)f);
	if (f) {
		printf(" (");
		bool first = true;
		for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
			if (f & names[i].bit) {
				printf("%s%s", first ? "" : " ", names[i].name);
				first = false;
			}
		}
		printf(")");
	}
	printf("\n");
}

/* ------------------------------------------------------------------------------------------ */
/* Instance and device */

static bool has_ext(const VkExtensionProperties *e, uint32_t n, const char *name) {
	for (uint32_t i = 0; i < n; i++) {
		if (!strcmp(e[i].extensionName, name)) {
			return true;
		}
	}
	return false;
}

static int vk_init(void) {
	void *lib = dlopen("libvulkan.so.1", RTLD_NOW | RTLD_LOCAL);
	if (!lib) {
		lib = dlopen("libvulkan.so", RTLD_NOW | RTLD_LOCAL);
	}
	if (!lib) {
		printf("ERROR: can't load the Vulkan loader: %s\n", dlerror());
		return -1;
	}
	vkGetInstanceProcAddr = (PFN_vkGetInstanceProcAddr)dlsym(lib, "vkGetInstanceProcAddr");
#define LOAD_GLOBAL(name) name = (PFN_##name)vkGetInstanceProcAddr(NULL, #name);
	GLOBAL_FUNCS(LOAD_GLOBAL)
	PFN_vkEnumerateInstanceVersion enum_version = (PFN_vkEnumerateInstanceVersion)vkGetInstanceProcAddr(NULL, "vkEnumerateInstanceVersion");
	uint32_t instance_version = VK_API_VERSION_1_0;
	if (enum_version) {
		enum_version(&instance_version);
	}
	printf("loader: instance version %u.%u.%u\n", VK_API_VERSION_MAJOR(instance_version), VK_API_VERSION_MINOR(instance_version), VK_API_VERSION_PATCH(instance_version));
	if (instance_version < VK_API_VERSION_1_2) {
		printf("ERROR: needs Vulkan 1.2\n");
		return -1;
	}

	VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .pApplicationName = "q10c-probe", .apiVersion = VK_API_VERSION_1_3 };
	VkInstanceCreateInfo ici = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &app };
	VkResult r = vkCreateInstance(&ici, NULL, &g_instance);
	if (r != VK_SUCCESS) {
		printf("ERROR: vkCreateInstance: %d\n", r);
		return -1;
	}
#define LOAD_INSTANCE(name) name = (PFN_##name)vkGetInstanceProcAddr(g_instance, #name);
	INSTANCE_FUNCS(LOAD_INSTANCE)

	uint32_t count = 0;
	vkEnumeratePhysicalDevices(g_instance, &count, NULL);
	if (count == 0) {
		printf("ERROR: no Vulkan device\n");
		return -1;
	}
	VkPhysicalDevice pds[8];
	count = count > 8 ? 8 : count;
	vkEnumeratePhysicalDevices(g_instance, &count, pds);
	g_pd = pds[0];
	for (uint32_t i = 0; i < count; i++) {
		VkPhysicalDeviceDriverProperties driver = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES };
		VkPhysicalDeviceProperties2 p2 = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, .pNext = &driver };
		vkGetPhysicalDeviceProperties2(pds[i], &p2);
		printf("device %u: %s, API %u.%u.%u, driver %s (%s), vendor 0x%04x device 0x%08x%s\n", i, p2.properties.deviceName,
				VK_API_VERSION_MAJOR(p2.properties.apiVersion), VK_API_VERSION_MINOR(p2.properties.apiVersion), VK_API_VERSION_PATCH(p2.properties.apiVersion),
				driver.driverName, driver.driverInfo, p2.properties.vendorID, p2.properties.deviceID, i == 0 ? " <- used" : "");
	}

	uint32_t ext_count = 0;
	vkEnumerateDeviceExtensionProperties(g_pd, NULL, &ext_count, NULL);
	VkExtensionProperties *exts = calloc(ext_count, sizeof(*exts));
	vkEnumerateDeviceExtensionProperties(g_pd, NULL, &ext_count, exts);
	printf("device extensions (%u):", ext_count);
	for (uint32_t i = 0; i < ext_count; i++) {
		printf("%s%s", (i % 4) ? " " : "\n  ", exts[i].extensionName);
	}
	printf("\n");
	static const char *watch[] = {
		VK_EXT_IMAGE_DRM_FORMAT_MODIFIER_EXTENSION_NAME,
		VK_EXT_EXTERNAL_MEMORY_DMA_BUF_EXTENSION_NAME,
		VK_KHR_EXTERNAL_MEMORY_FD_EXTENSION_NAME,
		VK_EXT_QUEUE_FAMILY_FOREIGN_EXTENSION_NAME,
		VK_KHR_SAMPLER_YCBCR_CONVERSION_EXTENSION_NAME,
		VK_EXT_YCBCR_2PLANE_444_FORMATS_EXTENSION_NAME,
		VK_EXT_YCBCR_IMAGE_ARRAYS_EXTENSION_NAME,
		VK_KHR_FORMAT_FEATURE_FLAGS_2_EXTENSION_NAME,
		VK_KHR_IMAGE_FORMAT_LIST_EXTENSION_NAME,
		VK_EXT_IMAGE_COMPRESSION_CONTROL_EXTENSION_NAME,
		"VK_QCOM_ycbcr_degamma",
		"VK_QCOM_image_processing",
		"VK_VALVE_video_encode_rgb_conversion",
		"VK_KHR_video_queue",
		"VK_KHR_video_decode_queue",
		"VK_KHR_video_maintenance1",
		"VK_ANDROID_external_memory_android_hardware_buffer",
		"VK_EXT_ycbcr_image_arrays",
	};
	for (size_t i = 0; i < sizeof(watch) / sizeof(watch[0]); i++) {
		printf("  %-48s %s\n", watch[i], has_ext(exts, ext_count, watch[i]) ? "yes" : "no");
	}
	for (uint32_t i = 0; i < ext_count; i++) {
		const char *n = exts[i].extensionName;
		if (strstr(n, "QCOM") || strstr(n, "VALVE") || strstr(n, "MESA") || strstr(n, "ycbcr") || strstr(n, "format")) {
			printf("  of interest: %s (spec %u)\n", n, exts[i].specVersion);
		}
	}

	g_has_modifiers = has_ext(exts, ext_count, VK_EXT_IMAGE_DRM_FORMAT_MODIFIER_EXTENSION_NAME);
	g_has_dmabuf = has_ext(exts, ext_count, VK_EXT_EXTERNAL_MEMORY_DMA_BUF_EXTENSION_NAME) && has_ext(exts, ext_count, VK_KHR_EXTERNAL_MEMORY_FD_EXTENSION_NAME);
	g_has_foreign = has_ext(exts, ext_count, VK_EXT_QUEUE_FAMILY_FOREIGN_EXTENSION_NAME);
	g_has_props_list2 = has_ext(exts, ext_count, VK_KHR_FORMAT_FEATURE_FLAGS_2_EXTENSION_NAME);

	VkPhysicalDeviceSamplerYcbcrConversionFeatures ycbcr = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SAMPLER_YCBCR_CONVERSION_FEATURES };
	VkPhysicalDeviceFeatures2 f2 = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, .pNext = &ycbcr };
	vkGetPhysicalDeviceFeatures2(g_pd, &f2);
	g_ycbcr_feature = ycbcr.samplerYcbcrConversion;
	printf("samplerYcbcrConversion: %s\n", g_ycbcr_feature ? "yes" : "no");

	uint32_t qf_count = 0;
	vkGetPhysicalDeviceQueueFamilyProperties(g_pd, &qf_count, NULL);
	VkQueueFamilyProperties qfs[16];
	qf_count = qf_count > 16 ? 16 : qf_count;
	vkGetPhysicalDeviceQueueFamilyProperties(g_pd, &qf_count, qfs);
	g_queue_family = UINT32_MAX;
	for (uint32_t i = 0; i < qf_count; i++) {
		if (qfs[i].queueFlags & VK_QUEUE_COMPUTE_BIT) {
			g_queue_family = i;
			break;
		}
	}
	if (g_queue_family == UINT32_MAX) {
		printf("ERROR: no compute queue\n");
		return -1;
	}

	const char *enable[8];
	uint32_t n_enable = 0;
	if (g_has_modifiers) {
		enable[n_enable++] = VK_EXT_IMAGE_DRM_FORMAT_MODIFIER_EXTENSION_NAME;
	}
	if (g_has_dmabuf) {
		enable[n_enable++] = VK_EXT_EXTERNAL_MEMORY_DMA_BUF_EXTENSION_NAME;
		enable[n_enable++] = VK_KHR_EXTERNAL_MEMORY_FD_EXTENSION_NAME;
	}
	if (g_has_foreign) {
		enable[n_enable++] = VK_EXT_QUEUE_FAMILY_FOREIGN_EXTENSION_NAME;
	}
	if (has_ext(exts, ext_count, VK_KHR_IMAGE_FORMAT_LIST_EXTENSION_NAME)) {
		enable[n_enable++] = VK_KHR_IMAGE_FORMAT_LIST_EXTENSION_NAME;
	}
	free(exts);

	float prio = 1.0f;
	VkDeviceQueueCreateInfo qci = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueFamilyIndex = g_queue_family, .queueCount = 1, .pQueuePriorities = &prio };
	VkPhysicalDeviceSamplerYcbcrConversionFeatures ycbcr_on = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SAMPLER_YCBCR_CONVERSION_FEATURES, .samplerYcbcrConversion = g_ycbcr_feature };
	VkDeviceCreateInfo dci = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .pNext = &ycbcr_on, .queueCreateInfoCount = 1, .pQueueCreateInfos = &qci, .enabledExtensionCount = n_enable, .ppEnabledExtensionNames = enable };
	r = vkCreateDevice(g_pd, &dci, NULL, &g_dev);
	if (r != VK_SUCCESS) {
		printf("ERROR: vkCreateDevice: %d\n", r);
		return -1;
	}
#define LOAD_DEVICE(name) name = (PFN_##name)vkGetDeviceProcAddr(g_dev, #name);
	DEVICE_FUNCS(LOAD_DEVICE)
	vkGetMemoryFdPropertiesKHR = (PFN_vkGetMemoryFdPropertiesKHR)vkGetDeviceProcAddr(g_dev, "vkGetMemoryFdPropertiesKHR");
	vkGetImageDrmFormatModifierPropertiesEXT = (PFN_vkGetImageDrmFormatModifierPropertiesEXT)vkGetDeviceProcAddr(g_dev, "vkGetImageDrmFormatModifierPropertiesEXT");
	vkGetDeviceQueue(g_dev, g_queue_family, 0, &g_queue);
	vkGetPhysicalDeviceMemoryProperties(g_pd, &g_mem_props);

	VkCommandPoolCreateInfo cpci = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .queueFamilyIndex = g_queue_family };
	vkCreateCommandPool(g_dev, &cpci, NULL, &g_cmd_pool);
	VkCommandBufferAllocateInfo cbai = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = g_cmd_pool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1 };
	vkAllocateCommandBuffers(g_dev, &cbai, &g_cmd);
	VkFenceCreateInfo fci = { .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO };
	vkCreateFence(g_dev, &fci, NULL, &g_fence);
	return 0;
}

/* ------------------------------------------------------------------------------------------ */
/* Format listing */

#define MAX_MODS 32
struct mod_entry {
	uint64_t modifier;
	uint32_t planes;
	VkFormatFeatureFlags2 features;
};

static uint32_t get_modifiers(VkFormat f, struct mod_entry *out) {
	if (!g_has_modifiers) {
		return 0;
	}
	if (g_has_props_list2) {
		VkDrmFormatModifierProperties2EXT props[MAX_MODS];
		VkDrmFormatModifierPropertiesList2EXT list = { .sType = VK_STRUCTURE_TYPE_DRM_FORMAT_MODIFIER_PROPERTIES_LIST_2_EXT };
		VkFormatProperties2 fp = { .sType = VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_2, .pNext = &list };
		vkGetPhysicalDeviceFormatProperties2(g_pd, f, &fp);
		if (list.drmFormatModifierCount > MAX_MODS) {
			list.drmFormatModifierCount = MAX_MODS;
		}
		list.pDrmFormatModifierProperties = props;
		vkGetPhysicalDeviceFormatProperties2(g_pd, f, &fp);
		for (uint32_t i = 0; i < list.drmFormatModifierCount; i++) {
			out[i] = (struct mod_entry){ props[i].drmFormatModifier, props[i].drmFormatModifierPlaneCount, props[i].drmFormatModifierTilingFeatures };
		}
		return list.drmFormatModifierCount;
	}
	VkDrmFormatModifierPropertiesEXT props[MAX_MODS];
	VkDrmFormatModifierPropertiesListEXT list = { .sType = VK_STRUCTURE_TYPE_DRM_FORMAT_MODIFIER_PROPERTIES_LIST_EXT };
	VkFormatProperties2 fp = { .sType = VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_2, .pNext = &list };
	vkGetPhysicalDeviceFormatProperties2(g_pd, f, &fp);
	if (list.drmFormatModifierCount > MAX_MODS) {
		list.drmFormatModifierCount = MAX_MODS;
	}
	list.pDrmFormatModifierProperties = props;
	vkGetPhysicalDeviceFormatProperties2(g_pd, f, &fp);
	for (uint32_t i = 0; i < list.drmFormatModifierCount; i++) {
		out[i] = (struct mod_entry){ props[i].drmFormatModifier, props[i].drmFormatModifierPlaneCount, props[i].drmFormatModifierTilingFeatures };
	}
	return list.drmFormatModifierCount;
}

// Can a sampled, dmabuf-importable image of this format and modifier be made? Prints the answer.
static VkResult query_import(VkFormat f, uint64_t modifier, uint32_t width, uint32_t height, bool print) {
	VkPhysicalDeviceImageDrmFormatModifierInfoEXT mod_info = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_DRM_FORMAT_MODIFIER_INFO_EXT, .drmFormatModifier = modifier, .sharingMode = VK_SHARING_MODE_EXCLUSIVE };
	VkPhysicalDeviceExternalImageFormatInfo ext_info = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTERNAL_IMAGE_FORMAT_INFO, .pNext = &mod_info, .handleType = VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT };
	VkPhysicalDeviceImageFormatInfo2 info = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_FORMAT_INFO_2, .pNext = g_has_dmabuf ? (void *)&ext_info : (void *)&mod_info, .format = f, .type = VK_IMAGE_TYPE_2D, .tiling = VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT, .usage = VK_IMAGE_USAGE_SAMPLED_BIT };
	VkSamplerYcbcrConversionImageFormatProperties ycbcr_props = { .sType = VK_STRUCTURE_TYPE_SAMPLER_YCBCR_CONVERSION_IMAGE_FORMAT_PROPERTIES };
	VkExternalImageFormatProperties ext_props = { .sType = VK_STRUCTURE_TYPE_EXTERNAL_IMAGE_FORMAT_PROPERTIES, .pNext = &ycbcr_props };
	VkImageFormatProperties2 props = { .sType = VK_STRUCTURE_TYPE_IMAGE_FORMAT_PROPERTIES_2, .pNext = &ext_props };
	const VkResult r = vkGetPhysicalDeviceImageFormatProperties2(g_pd, &info, &props);
	if (print) {
		if (r == VK_SUCCESS) {
			const VkExtent3D e = props.imageFormatProperties.maxExtent;
			const bool importable = ext_props.externalMemoryProperties.externalMemoryFeatures & VK_EXTERNAL_MEMORY_FEATURE_IMPORTABLE_BIT;
			const bool dedicated = ext_props.externalMemoryProperties.externalMemoryFeatures & VK_EXTERNAL_MEMORY_FEATURE_DEDICATED_ONLY_BIT;
			printf("      dmabuf import query: OK, max %ux%u, importable %s%s, combinedImageSamplerDescriptorCount %u%s\n", e.width, e.height, importable ? "yes" : "NO",
					dedicated ? " (dedicated only)" : "", ycbcr_props.combinedImageSamplerDescriptorCount, (width > e.width || height > e.height) ? "; TOO SMALL for the frame" : "");
		} else {
			printf("      dmabuf import query: VkResult %d (not supported)\n", r);
		}
	}
	return r;
}

static void list_format(VkFormat f, const char *name) {
	VkFormatProperties3 p3 = { .sType = VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_3 };
	VkFormatProperties2 p2 = { .sType = VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_2, .pNext = g_has_props_list2 ? &p3 : NULL };
	vkGetPhysicalDeviceFormatProperties2(g_pd, f, &p2);
	if (!g_has_props_list2) {
		p3.linearTilingFeatures = p2.formatProperties.linearTilingFeatures;
		p3.optimalTilingFeatures = p2.formatProperties.optimalTilingFeatures;
	}
	printf("format %d %s\n", (int)f, name);
	print_features("  linear:  ", p3.linearTilingFeatures);
	print_features("  optimal: ", p3.optimalTilingFeatures);
	struct mod_entry mods[MAX_MODS];
	const uint32_t n = get_modifiers(f, mods);
	if (!g_has_modifiers) {
		printf("  (no VK_EXT_image_drm_format_modifier)\n");
		return;
	}
	if (n == 0) {
		printf("  modifiers: none\n");
	}
	for (uint32_t i = 0; i < n; i++) {
		printf("  modifier 0x%016" PRIx64 " %s: %u memory plane(s)\n", mods[i].modifier, modifier_name(mods[i].modifier), mods[i].planes);
		print_features("      features: ", mods[i].features);
		query_import(f, mods[i].modifier, 3840, 1600, true);
	}
	// QCOM modifiers the driver didn't list: does the image query take them anyway?
	for (uint64_t k = 1; k <= 7; k++) {
		bool listed = false;
		for (uint32_t i = 0; i < n; i++) {
			listed = listed || mods[i].modifier == MOD_QCOM(k);
		}
		if (!listed && query_import(f, MOD_QCOM(k), 3840, 1600, false) == VK_SUCCESS) {
			printf("  NOT LISTED but the image query accepts modifier 0x%016" PRIx64 " %s:\n", MOD_QCOM(k), modifier_name(MOD_QCOM(k)));
			query_import(f, MOD_QCOM(k), 3840, 1600, true);
		}
	}
}

static void list_formats(void) {
	printf("\n== Formats ==\n");
	for (size_t i = 0; i < sizeof(g_formats) / sizeof(g_formats[0]); i++) {
		list_format(g_formats[i].format, g_formats[i].name);
	}
	if (o.extra_format >= 0) {
		list_format((VkFormat)o.extra_format, "(--format)");
	}
}

// Formats in the extension ranges (1000000000 + (extension - 1) * 1000 + n) that have any feature: a vendor format
// nobody listed would show up here.
static void scan_formats(void) {
	printf("\n== Format scan (extension ranges) ==\n");
	unsigned found = 0;
	for (uint32_t ext = 1; ext <= 1000; ext++) {
		for (uint32_t n = 0; n < 64; n++) {
			const VkFormat f = (VkFormat)(1000000000u + (ext - 1) * 1000u + n);
			VkFormatProperties p = { 0 };
			vkGetPhysicalDeviceFormatProperties(g_pd, f, &p);
			if (p.linearTilingFeatures | p.optimalTilingFeatures | p.bufferFeatures) {
				const char *name = format_name(f);
				printf("  format %u (extension %u, +%u)%s%s: linear 0x%x optimal 0x%x buffer 0x%x\n", (unsigned)f, ext, n, name[0] != '?' ? " " : "", name[0] != '?' ? name : "",
						p.linearTilingFeatures, p.optimalTilingFeatures, p.bufferFeatures);
				found++;
			}
		}
	}
	printf("  %u formats with features in the extension ranges\n", found);
}

/* ------------------------------------------------------------------------------------------ */
/* Memory helpers */

static int find_memory_type(uint32_t bits, VkMemoryPropertyFlags want) {
	for (uint32_t i = 0; i < g_mem_props.memoryTypeCount; i++) {
		if ((bits & (1u << i)) && (g_mem_props.memoryTypes[i].propertyFlags & want) == want) {
			return (int)i;
		}
	}
	return -1;
}

struct host_buffer {
	VkBuffer buffer;
	VkDeviceMemory memory;
	void *map;
	VkDeviceSize size;
};

static int host_buffer_create(struct host_buffer *b, VkDeviceSize size) {
	memset(b, 0, sizeof(*b));
	VkBufferCreateInfo bci = { .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = size, .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, .sharingMode = VK_SHARING_MODE_EXCLUSIVE };
	if (vkCreateBuffer(g_dev, &bci, NULL, &b->buffer) != VK_SUCCESS) {
		return -1;
	}
	VkMemoryRequirements req;
	vkGetBufferMemoryRequirements(g_dev, b->buffer, &req);
	int type = find_memory_type(req.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
	if (type < 0) {
		return -1;
	}
	VkMemoryAllocateInfo mai = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = req.size, .memoryTypeIndex = (uint32_t)type };
	if (vkAllocateMemory(g_dev, &mai, NULL, &b->memory) != VK_SUCCESS) {
		return -1;
	}
	vkBindBufferMemory(g_dev, b->buffer, b->memory, 0);
	vkMapMemory(g_dev, b->memory, 0, VK_WHOLE_SIZE, 0, &b->map);
	b->size = size;
	return 0;
}

static void host_buffer_destroy(struct host_buffer *b) {
	if (b->memory) {
		vkUnmapMemory(g_dev, b->memory);
		vkFreeMemory(g_dev, b->memory, NULL);
	}
	if (b->buffer) {
		vkDestroyBuffer(g_dev, b->buffer, NULL);
	}
	memset(b, 0, sizeof(*b));
}

/* ------------------------------------------------------------------------------------------ */
/* The conversion: image -> YCbCr sampler -> integer codes */

// Reads the whole image (w x h, a 2-plane 4:2:0 format) through a sampler with a YCbCr conversion into codes[] (w*h luma,
// then w/2*h/2 Cb, then Cr). p_external: the image was imported (owned by the foreign queue family, GENERAL layout).
static int convert_image(VkImage image, VkFormat format, VkFormatFeatureFlags2 features, uint32_t w, uint32_t h, bool external, uint32_t sampler_descriptors, uint32_t *codes) {
	int ret = -1;
	VkSamplerYcbcrConversion conversion = VK_NULL_HANDLE;
	VkSampler sampler = VK_NULL_HANDLE;
	VkImageView view = VK_NULL_HANDLE;
	VkDescriptorSetLayout set_layout = VK_NULL_HANDLE;
	VkPipelineLayout pipeline_layout = VK_NULL_HANDLE;
	VkShaderModule module = VK_NULL_HANDLE;
	VkPipeline pipeline = VK_NULL_HANDLE;
	VkDescriptorPool pool = VK_NULL_HANDLE;
	struct host_buffer out = { 0 };
	VkResult r;

	const bool midpoint = features & VK_FORMAT_FEATURE_2_MIDPOINT_CHROMA_SAMPLES_BIT;
	const VkChromaLocation chroma = midpoint ? VK_CHROMA_LOCATION_MIDPOINT : VK_CHROMA_LOCATION_COSITED_EVEN;
	VkSamplerYcbcrConversionCreateInfo cci = {
		.sType = VK_STRUCTURE_TYPE_SAMPLER_YCBCR_CONVERSION_CREATE_INFO,
		.format = format,
		.ycbcrModel = o.ycbcr_model ? VK_SAMPLER_YCBCR_MODEL_CONVERSION_YCBCR_IDENTITY : VK_SAMPLER_YCBCR_MODEL_CONVERSION_RGB_IDENTITY,
		.ycbcrRange = VK_SAMPLER_YCBCR_RANGE_ITU_FULL,
		.components = { VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY },
		.xChromaOffset = chroma,
		.yChromaOffset = chroma,
		.chromaFilter = VK_FILTER_NEAREST,
		.forceExplicitReconstruction = VK_FALSE,
	};
	r = vkCreateSamplerYcbcrConversion(g_dev, &cci, NULL, &conversion);
	if (r != VK_SUCCESS) {
		printf("    vkCreateSamplerYcbcrConversion: %d\n", r);
		goto done;
	}
	VkSamplerYcbcrConversionInfo conv_info = { .sType = VK_STRUCTURE_TYPE_SAMPLER_YCBCR_CONVERSION_INFO, .conversion = conversion };
	VkSamplerCreateInfo sci = {
		.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
		.pNext = &conv_info,
		.magFilter = VK_FILTER_NEAREST,
		.minFilter = VK_FILTER_NEAREST,
		.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST,
		.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
		.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
		.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
		.borderColor = VK_BORDER_COLOR_FLOAT_OPAQUE_BLACK,
	};
	r = vkCreateSampler(g_dev, &sci, NULL, &sampler);
	if (r != VK_SUCCESS) {
		printf("    vkCreateSampler: %d\n", r);
		goto done;
	}
	VkImageViewCreateInfo vci = {
		.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
		.pNext = &conv_info,
		.image = image,
		.viewType = VK_IMAGE_VIEW_TYPE_2D,
		.format = format,
		.subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 },
	};
	r = vkCreateImageView(g_dev, &vci, NULL, &view);
	if (r != VK_SUCCESS) {
		printf("    vkCreateImageView: %d\n", r);
		goto done;
	}
	VkDescriptorSetLayoutBinding bindings[2] = {
		{ .binding = 0, .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = 1, .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT, .pImmutableSamplers = &sampler },
		{ .binding = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 1, .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT },
	};
	VkDescriptorSetLayoutCreateInfo dslci = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, .bindingCount = 2, .pBindings = bindings };
	vkCreateDescriptorSetLayout(g_dev, &dslci, NULL, &set_layout);
	VkPushConstantRange pcr = { VK_SHADER_STAGE_COMPUTE_BIT, 0, 16 };
	VkPipelineLayoutCreateInfo plci = { .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, .setLayoutCount = 1, .pSetLayouts = &set_layout, .pushConstantRangeCount = 1, .pPushConstantRanges = &pcr };
	vkCreatePipelineLayout(g_dev, &plci, NULL, &pipeline_layout);
	VkShaderModuleCreateInfo smci = { .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, .codeSize = sizeof(convert_spv), .pCode = convert_spv };
	vkCreateShaderModule(g_dev, &smci, NULL, &module);
	VkComputePipelineCreateInfo cpci = {
		.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
		.stage = { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = module, .pName = "main" },
		.layout = pipeline_layout,
	};
	r = vkCreateComputePipelines(g_dev, VK_NULL_HANDLE, 1, &cpci, NULL, &pipeline);
	if (r != VK_SUCCESS) {
		printf("    vkCreateComputePipelines: %d\n", r);
		goto done;
	}
	VkDescriptorPoolSize sizes[2] = { { VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, sampler_descriptors ? sampler_descriptors : 1 }, { VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1 } };
	VkDescriptorPoolCreateInfo dpci = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, .maxSets = 1, .poolSizeCount = 2, .pPoolSizes = sizes };
	vkCreateDescriptorPool(g_dev, &dpci, NULL, &pool);
	VkDescriptorSet set;
	VkDescriptorSetAllocateInfo dsai = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, .descriptorPool = pool, .descriptorSetCount = 1, .pSetLayouts = &set_layout };
	r = vkAllocateDescriptorSets(g_dev, &dsai, &set);
	if (r != VK_SUCCESS) {
		printf("    vkAllocateDescriptorSets: %d\n", r);
		goto done;
	}
	const VkDeviceSize codes_size = (VkDeviceSize)w * h * 3 / 2 * sizeof(uint32_t);
	if (host_buffer_create(&out, codes_size)) {
		printf("    can't make the output buffer\n");
		goto done;
	}
	memset(out.map, 0xff, codes_size);
	VkDescriptorImageInfo dii = { .imageView = view, .imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL };
	VkDescriptorBufferInfo dbi = { .buffer = out.buffer, .offset = 0, .range = VK_WHOLE_SIZE };
	VkWriteDescriptorSet writes[2] = {
		{ .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = set, .dstBinding = 0, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .pImageInfo = &dii },
		{ .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = set, .dstBinding = 1, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &dbi },
	};
	vkUpdateDescriptorSets(g_dev, 2, writes, 0, NULL);

	vkResetCommandPool(g_dev, g_cmd_pool, 0);
	VkCommandBufferBeginInfo cbbi = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO, .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT };
	vkBeginCommandBuffer(g_cmd, &cbbi);
	const uint32_t foreign = g_has_foreign ? VK_QUEUE_FAMILY_FOREIGN_EXT : VK_QUEUE_FAMILY_EXTERNAL;
	VkImageMemoryBarrier acquire = {
		.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
		.srcAccessMask = external ? 0 : VK_ACCESS_HOST_WRITE_BIT,
		.dstAccessMask = VK_ACCESS_SHADER_READ_BIT,
		.oldLayout = external ? VK_IMAGE_LAYOUT_GENERAL : VK_IMAGE_LAYOUT_PREINITIALIZED,
		.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
		.srcQueueFamilyIndex = external ? foreign : VK_QUEUE_FAMILY_IGNORED,
		.dstQueueFamilyIndex = external ? g_queue_family : VK_QUEUE_FAMILY_IGNORED,
		.image = image,
		.subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 },
	};
	vkCmdPipelineBarrier(g_cmd, external ? VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT : VK_PIPELINE_STAGE_HOST_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, NULL, 0, NULL, 1, &acquire);
	vkCmdBindPipeline(g_cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
	vkCmdBindDescriptorSets(g_cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline_layout, 0, 1, &set, 0, NULL);
	const int bits = format_bits(format);
	struct {
		uint32_t w, h;
		float scale, bias;
	} pc = { w, h, (float)((1u << bits) - 1u), 0.5f };
	if (bits > 8 && bits < 16) {
		pc.scale = 65535.0f / (float)(1u << (16 - bits));
		pc.bias = 0.0005f;
	}
	vkCmdPushConstants(g_cmd, pipeline_layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(pc), &pc);
	vkCmdDispatch(g_cmd, (w / 2 + 7) / 8, (h / 2 + 7) / 8, 1);
	VkBufferMemoryBarrier to_host = {
		.sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
		.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT,
		.dstAccessMask = VK_ACCESS_HOST_READ_BIT,
		.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
		.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
		.buffer = out.buffer,
		.size = VK_WHOLE_SIZE,
	};
	VkImageMemoryBarrier release = acquire;
	release.srcAccessMask = 0;
	release.dstAccessMask = 0;
	release.oldLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
	release.newLayout = VK_IMAGE_LAYOUT_GENERAL;
	release.srcQueueFamilyIndex = external ? g_queue_family : VK_QUEUE_FAMILY_IGNORED;
	release.dstQueueFamilyIndex = external ? foreign : VK_QUEUE_FAMILY_IGNORED;
	vkCmdPipelineBarrier(g_cmd, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_HOST_BIT | VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, NULL, 1, &to_host, 1, &release);
	vkEndCommandBuffer(g_cmd);
	VkSubmitInfo si = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &g_cmd };
	vkResetFences(g_dev, 1, &g_fence);
	const double t0 = now_s();
	r = vkQueueSubmit(g_queue, 1, &si, g_fence);
	if (r == VK_SUCCESS) {
		r = vkWaitForFences(g_dev, 1, &g_fence, VK_TRUE, 10ull * 1000 * 1000 * 1000);
	}
	if (r != VK_SUCCESS) {
		printf("    submit/wait: VkResult %d%s\n", r, r == VK_ERROR_DEVICE_LOST ? " (DEVICE LOST: a GPU fault; see dmesg)" : "");
		goto done;
	}
	printf("    conversion ran in %.1f ms (chroma %s, %s)\n", (now_s() - t0) * 1e3, midpoint ? "MIDPOINT" : "COSITED_EVEN", o.ycbcr_model ? "YCBCR_IDENTITY" : "RGB_IDENTITY");
	memcpy(codes, out.map, codes_size);
	ret = 0;
done:
	if (g_dev) {
		vkDeviceWaitIdle(g_dev);
	}
	host_buffer_destroy(&out);
	if (pool) vkDestroyDescriptorPool(g_dev, pool, NULL);
	if (pipeline) vkDestroyPipeline(g_dev, pipeline, NULL);
	if (module) vkDestroyShaderModule(g_dev, module, NULL);
	if (pipeline_layout) vkDestroyPipelineLayout(g_dev, pipeline_layout, NULL);
	if (set_layout) vkDestroyDescriptorSetLayout(g_dev, set_layout, NULL);
	if (view) vkDestroyImageView(g_dev, view, NULL);
	if (sampler) vkDestroySampler(g_dev, sampler, NULL);
	if (conversion) vkDestroySamplerYcbcrConversion(g_dev, conversion, NULL);
	return ret;
}

/* ------------------------------------------------------------------------------------------ */
/* Results */

struct picture {
	uint32_t w, h; // The image (decoded) size.
	uint32_t vx, vy, vw, vh; // The visible area.
	int bits;
	uint32_t *codes;
};

static uint32_t to10(uint32_t v, int bits) {
	return bits >= 10 ? v >> (bits - 10) : v << (10 - bits);
}

static uint32_t sample(const struct picture *p, int plane, uint32_t x, uint32_t y) {
	const uint32_t luma = p->w * p->h;
	const uint32_t cw = p->w / 2;
	const uint32_t chroma = cw * (p->h / 2);
	if (plane == 0) {
		return to10(p->codes[y * p->w + x], p->bits);
	}
	return to10(p->codes[luma + (plane == 2 ? chroma : 0) + y * cw + x], p->bits);
}

// Statistics of the visible area, on the 10-bit scale. A decoded picture is smooth: neighbouring luma samples differ by
// a few codes on average. Misread compressed data is noise: ~340 for uniform random codes.
static const char *judge(const struct picture *p, char *line, size_t line_size) {
	double mad[3] = { 0 };
	double sum[3] = { 0 };
	uint32_t mn[3] = { 1023, 1023, 1023 }, mx[3] = { 0 };
	uint64_t n[3] = { 0 }, in_range = 0, total_y = 0;
	for (int plane = 0; plane < 3; plane++) {
		const uint32_t x0 = plane ? p->vx / 2 : p->vx, y0 = plane ? p->vy / 2 : p->vy;
		const uint32_t w = plane ? p->vw / 2 : p->vw, h = plane ? p->vh / 2 : p->vh;
		uint64_t pairs = 0;
		for (uint32_t y = y0; y < y0 + h; y++) {
			uint32_t prev = 0;
			for (uint32_t x = x0; x < x0 + w; x++) {
				const uint32_t v = sample(p, plane, x, y);
				if (x > x0) {
					mad[plane] += fabs((double)v - (double)prev);
					pairs++;
				}
				prev = v;
				sum[plane] += v;
				mn[plane] = v < mn[plane] ? v : mn[plane];
				mx[plane] = v > mx[plane] ? v : mx[plane];
				n[plane]++;
				if (plane == 0) {
					total_y++;
					in_range += v >= 48 && v <= 956;
				}
			}
		}
		mad[plane] = pairs ? mad[plane] / (double)pairs : 0.0;
	}
	const double in_range_pct = total_y ? 100.0 * (double)in_range / (double)total_y : 0.0;
	snprintf(line, line_size, "Y mean %.1f min %u max %u neighbour-diff %.1f, in 48-956: %.1f%% | Cb mean %.1f diff %.1f | Cr mean %.1f diff %.1f",
			sum[0] / (double)(n[0] ? n[0] : 1), mn[0], mx[0], mad[0], in_range_pct, sum[1] / (double)(n[1] ? n[1] : 1), mad[1], sum[2] / (double)(n[2] ? n[2] : 1), mad[2]);
	if (mad[0] < 40.0 && mad[1] < 40.0 && mad[2] < 40.0 && in_range_pct > 90.0) {
		return "PLAUSIBLE PICTURE";
	}
	if (mad[0] > 120.0 || mad[1] > 120.0) {
		return "GARBAGE";
	}
	return "UNCLEAR (look at the .ppm)";
}

static void compare_ref(const struct picture *p, const uint16_t *ref) {
	static const char *names[3] = { "Y", "Cb", "Cr" };
	const uint32_t vw = p->vw, vh = p->vh;
	const uint16_t *planes[3] = { ref, ref + vw * vh, ref + vw * vh + (vw / 2) * (vh / 2) };
	printf("    against --ref:");
	for (int plane = 0; plane < 3; plane++) {
		const uint32_t w = plane ? vw / 2 : vw, h = plane ? vh / 2 : vh;
		const uint32_t x0 = plane ? p->vx / 2 : p->vx, y0 = plane ? p->vy / 2 : p->vy;
		double se = 0.0;
		uint64_t same = 0;
		for (uint32_t y = 0; y < h; y++) {
			for (uint32_t x = 0; x < w; x++) {
				const double d = (double)sample(p, plane, x0 + x, y0 + y) - (double)planes[plane][y * w + x];
				se += d * d;
				same += d == 0.0;
			}
		}
		const double mse = se / ((double)w * h);
		const double psnr = mse > 0.0 ? 10.0 * log10(1023.0 * 1023.0 / mse) : INFINITY;
		printf(" %s PSNR %.2f dB, identical %.2f%%;", names[plane], psnr, 100.0 * (double)same / ((double)w * h));
	}
	printf("\n");
}

static void write_outputs(const struct picture *p, const char *tag) {
	char path[512];
	mkdir(o.out_dir, 0755);
	snprintf(path, sizeof(path), "%s/%s.yuv", o.out_dir, tag);
	FILE *f = fopen(path, "wb");
	if (f) {
		for (int plane = 0; plane < 3; plane++) {
			const uint32_t w = plane ? p->vw / 2 : p->vw, h = plane ? p->vh / 2 : p->vh;
			const uint32_t x0 = plane ? p->vx / 2 : p->vx, y0 = plane ? p->vy / 2 : p->vy;
			uint16_t *row = malloc(w * 2);
			for (uint32_t y = 0; y < h; y++) {
				for (uint32_t x = 0; x < w; x++) {
					row[x] = (uint16_t)sample(p, plane, x0 + x, y0 + y);
				}
				fwrite(row, 2, w, f);
			}
			free(row);
		}
		fclose(f);
	}
	// A preview: limited range, BT.709 (or BT.2020 with --bt2020), gamma-encoded as it is (no transfer conversion).
	const double kr = o.bt2020 ? 0.2627 : 0.2126, kb = o.bt2020 ? 0.0593 : 0.0722, kg = 1.0 - kr - kb;
	snprintf(path, sizeof(path), "%s/%s.ppm", o.out_dir, tag);
	f = fopen(path, "wb");
	if (f) {
		fprintf(f, "P6\n%u %u\n255\n", p->vw, p->vh);
		uint8_t *row = malloc(p->vw * 3);
		for (uint32_t y = 0; y < p->vh; y++) {
			for (uint32_t x = 0; x < p->vw; x++) {
				const double Y = ((double)sample(p, 0, p->vx + x, p->vy + y) - 64.0) / 876.0;
				const double cb = ((double)sample(p, 1, (p->vx + x) / 2, (p->vy + y) / 2) - 512.0) / 896.0;
				const double cr = ((double)sample(p, 2, (p->vx + x) / 2, (p->vy + y) / 2) - 512.0) / 896.0;
				const double r = Y + 2.0 * (1.0 - kr) * cr;
				const double b = Y + 2.0 * (1.0 - kb) * cb;
				const double g = (Y - kr * r - kb * b) / kg;
				const double rgb[3] = { r, g, b };
				for (int c = 0; c < 3; c++) {
					const double v = rgb[c] < 0.0 ? 0.0 : (rgb[c] > 1.0 ? 1.0 : rgb[c]);
					row[x * 3 + c] = (uint8_t)(v * 255.0 + 0.5);
				}
			}
			fwrite(row, 3, p->vw, f);
		}
		free(row);
		fclose(f);
	}
	printf("    wrote %s/%s.yuv (yuv420p10le %ux%u) and .ppm\n", o.out_dir, tag, p->vw, p->vh);
}

/* ------------------------------------------------------------------------------------------ */
/* Self-test: a host-memory pattern through the same conversion */

static uint32_t pattern(int plane, uint32_t x, uint32_t y) {
	switch (plane) {
		case 0: return 64 + (x * 7 + y * 3) % 877;
		case 1: return 64 + (x * 5 + y * 11) % 897;
		default: return 64 + (x * 13 + y * 2) % 897;
	}
}

static int selftest_format(VkFormat format, int bits, uint32_t w, uint32_t h) {
	printf("selftest %s %ux%u (linear, host memory):\n", format_name(format), w, h);
	VkFormatProperties3 p3 = { .sType = VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_3 };
	VkFormatProperties2 p2 = { .sType = VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_2, .pNext = g_has_props_list2 ? &p3 : NULL };
	vkGetPhysicalDeviceFormatProperties2(g_pd, format, &p2);
	const VkFormatFeatureFlags2 features = g_has_props_list2 ? p3.linearTilingFeatures : p2.formatProperties.linearTilingFeatures;
	if (!(features & VK_FORMAT_FEATURE_2_SAMPLED_IMAGE_BIT)) {
		printf("  skipped: no linear sampling for this format\n");
		return 0;
	}
	VkImageCreateInfo ici = {
		.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
		.imageType = VK_IMAGE_TYPE_2D,
		.format = format,
		.extent = { w, h, 1 },
		.mipLevels = 1,
		.arrayLayers = 1,
		.samples = VK_SAMPLE_COUNT_1_BIT,
		.tiling = VK_IMAGE_TILING_LINEAR,
		.usage = VK_IMAGE_USAGE_SAMPLED_BIT,
		.initialLayout = VK_IMAGE_LAYOUT_PREINITIALIZED,
	};
	VkImage image;
	VkResult r = vkCreateImage(g_dev, &ici, NULL, &image);
	if (r != VK_SUCCESS) {
		printf("  vkCreateImage: %d\n", r);
		return -1;
	}
	VkImageMemoryRequirementsInfo2 rqi = { .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_REQUIREMENTS_INFO_2, .image = image };
	VkMemoryRequirements2 req = { .sType = VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2 };
	vkGetImageMemoryRequirements2(g_dev, &rqi, &req);
	const int type = find_memory_type(req.memoryRequirements.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
	VkDeviceMemory memory = VK_NULL_HANDLE;
	VkMemoryAllocateInfo mai = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = req.memoryRequirements.size, .memoryTypeIndex = (uint32_t)type };
	if (type < 0 || vkAllocateMemory(g_dev, &mai, NULL, &memory) != VK_SUCCESS) {
		printf("  no host-visible memory for the image\n");
		vkDestroyImage(g_dev, image, NULL);
		return -1;
	}
	vkBindImageMemory(g_dev, image, memory, 0);
	uint8_t *map;
	vkMapMemory(g_dev, memory, 0, VK_WHOLE_SIZE, 0, (void **)&map);
	VkSubresourceLayout layouts[2];
	for (int plane = 0; plane < 2; plane++) {
		VkImageSubresource sub = { VK_IMAGE_ASPECT_PLANE_0_BIT << plane, 0, 0 };
		vkGetImageSubresourceLayout(g_dev, image, &sub, &layouts[plane]);
	}
	const uint32_t bytes = bits > 8 ? 2 : 1;
	for (uint32_t y = 0; y < h; y++) {
		uint8_t *row = map + layouts[0].offset + y * layouts[0].rowPitch;
		for (uint32_t x = 0; x < w; x++) {
			const uint32_t v = pattern(0, x, y) >> (10 - (bits > 10 ? 10 : bits)) << (bits > 10 ? bits - 10 : 0);
			if (bytes == 2) {
				((uint16_t *)row)[x] = (uint16_t)(v << (16 - bits));
			} else {
				row[x] = (uint8_t)v;
			}
		}
	}
	for (uint32_t y = 0; y < h / 2; y++) {
		uint8_t *row = map + layouts[1].offset + y * layouts[1].rowPitch;
		for (uint32_t x = 0; x < w / 2; x++) {
			for (int c = 0; c < 2; c++) {
				const uint32_t v = pattern(1 + c, x, y) >> (10 - (bits > 10 ? 10 : bits)) << (bits > 10 ? bits - 10 : 0);
				if (bytes == 2) {
					((uint16_t *)row)[x * 2 + c] = (uint16_t)(v << (16 - bits));
				} else {
					row[x * 2 + c] = (uint8_t)v;
				}
			}
		}
	}
	vkUnmapMemory(g_dev, memory);

	struct picture pic = { .w = w, .h = h, .vx = 0, .vy = 0, .vw = w, .vh = h, .bits = bits };
	pic.codes = malloc((size_t)w * h * 3 / 2 * sizeof(uint32_t));
	int ret = convert_image(image, format, features, w, h, false, 1, pic.codes);
	if (ret == 0) {
		uint64_t wrong = 0, total = 0;
		for (int plane = 0; plane < 3; plane++) {
			const uint32_t pw = plane ? w / 2 : w, ph = plane ? h / 2 : h;
			for (uint32_t y = 0; y < ph; y++) {
				for (uint32_t x = 0; x < pw; x++) {
					const uint32_t want = to10(pattern(plane, x, y) >> (10 - (bits > 10 ? 10 : bits)) << (bits > 10 ? bits - 10 : 0), bits);
					const uint32_t got = sample(&pic, plane, x, y);
					if (got != want && wrong++ < 5) {
						printf("  plane %d (%u,%u): got %u, want %u\n", plane, x, y, got, want);
					}
					total++;
				}
			}
		}
		char line[512];
		const char *verdict = judge(&pic, line, sizeof(line));
		printf("  %s: %" PRIu64 " of %" PRIu64 " samples wrong (%s; %s)\n", wrong ? "FAIL" : "PASS", wrong, total, verdict, line);
		ret = wrong ? -1 : 0;
	}
	free(pic.codes);
	vkDestroyImage(g_dev, image, NULL);
	vkFreeMemory(g_dev, memory, NULL);
	return ret;
}

/* ------------------------------------------------------------------------------------------ */
/* Decoder: the first frame of a raw HEVC file */

struct au {
	size_t off, len;
};

struct stream {
	const uint8_t *data;
	size_t size;
	struct au *aus;
	size_t n_aus, cap;
	size_t max_au;
	unsigned width, height, bit_depth;
};

struct br {
	const uint8_t *p;
	size_t n, bit;
	bool err;
};

static uint32_t br_u(struct br *b, int n) {
	uint32_t v = 0;
	while (n-- > 0) {
		if (b->bit >= b->n * 8) {
			b->err = true;
			return 0;
		}
		v = (v << 1) | ((b->p[b->bit >> 3] >> (7 - (b->bit & 7))) & 1u);
		b->bit++;
	}
	return v;
}

static void br_skip(struct br *b, size_t n) {
	b->bit += n;
	if (b->bit > b->n * 8) {
		b->err = true;
	}
}

static uint32_t br_ue(struct br *b) {
	int lz = 0;
	while (!br_u(b, 1)) {
		if (b->err || ++lz > 31) {
			b->err = true;
			return 0;
		}
	}
	return lz ? ((1u << lz) - 1u + br_u(b, lz)) : 0;
}

static size_t unescape(const uint8_t *src, size_t n, uint8_t *dst, size_t cap) {
	size_t out = 0;
	int zeros = 0;
	for (size_t i = 0; i < n && out < cap; i++) {
		if (zeros >= 2 && src[i] == 3) {
			zeros = 0;
			continue;
		}
		dst[out++] = src[i];
		zeros = src[i] == 0 ? zeros + 1 : 0;
	}
	return out;
}

static void parse_hevc_sps(struct stream *st, const uint8_t *nal, size_t len) {
	uint8_t buf[512];
	if (len < 3 || st->width) {
		return;
	}
	struct br b = { buf, unescape(nal + 2, len - 2, buf, sizeof(buf)), 0, false };
	br_skip(&b, 4);
	const unsigned max_sub = br_u(&b, 3);
	br_skip(&b, 1);
	br_skip(&b, 88 + 8);
	bool sp[8] = { 0 }, sl[8] = { 0 };
	for (unsigned i = 0; i < max_sub; i++) {
		sp[i] = br_u(&b, 1);
		sl[i] = br_u(&b, 1);
	}
	if (max_sub > 0) {
		for (unsigned i = max_sub; i < 8; i++) {
			br_skip(&b, 2);
		}
	}
	for (unsigned i = 0; i < max_sub; i++) {
		if (sp[i]) {
			br_skip(&b, 88);
		}
		if (sl[i]) {
			br_skip(&b, 8);
		}
	}
	br_ue(&b);
	const unsigned chroma = br_ue(&b);
	if (chroma == 3) {
		br_skip(&b, 1);
	}
	const unsigned w = br_ue(&b), h = br_ue(&b);
	if (br_u(&b, 1)) {
		br_ue(&b);
		br_ue(&b);
		br_ue(&b);
		br_ue(&b);
	}
	const unsigned bd = br_ue(&b) + 8;
	if (!b.err && w && h && w <= 16384 && h <= 16384) {
		st->width = w;
		st->height = h;
		st->bit_depth = bd;
	}
}

static size_t next_sc(const uint8_t *p, size_t n, size_t i) {
	while (i + 3 <= n) {
		if (p[i + 2] > 1) {
			i += 3;
		} else if (p[i + 2] == 1 && p[i + 1] == 0 && p[i] == 0) {
			return i;
		} else {
			i++;
		}
	}
	return n;
}

static void push_au(struct stream *st, size_t off, size_t len) {
	if (!len) {
		return;
	}
	if (st->n_aus == st->cap) {
		st->cap = st->cap ? st->cap * 2 : 1024;
		st->aus = realloc(st->aus, st->cap * sizeof(*st->aus));
	}
	st->aus[st->n_aus++] = (struct au){ off, len };
	st->max_au = len > st->max_au ? len : st->max_au;
}

// Access units of a raw HEVC stream (the split of spike 01's v4l2dec.c), and the first SPS's size and bit depth.
static int load_hevc(struct stream *st, const char *path) {
	memset(st, 0, sizeof(*st));
	const int fd = open(path, O_RDONLY | O_CLOEXEC);
	struct stat sb;
	if (fd < 0 || fstat(fd, &sb) || sb.st_size <= 0) {
		printf("ERROR: can't read %s: %s\n", path, strerror(errno));
		return -1;
	}
	void *m = mmap(NULL, (size_t)sb.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
	close(fd);
	if (m == MAP_FAILED) {
		return -1;
	}
	st->data = m;
	st->size = (size_t)sb.st_size;
	const uint8_t *p = st->data;
	const size_t n = st->size;
	size_t sc = next_sc(p, n, 0), au_start = SIZE_MAX;
	bool seen_vcl = false;
	while (sc < n) {
		const size_t nal = sc + 3;
		const size_t start = (sc > 0 && p[sc - 1] == 0) ? sc - 1 : sc;
		const size_t next = next_sc(p, n, nal);
		const uint8_t *q = p + nal;
		const size_t len = next - nal;
		bool new_au = false, vcl = false;
		if (len >= 2) {
			const unsigned type = (q[0] >> 1) & 0x3f;
			const unsigned layer = ((q[0] & 1u) << 5) | (q[1] >> 3);
			vcl = type <= 31;
			if (type == 35 || (layer == 0 && ((type >= 32 && type <= 34) || type == 39 || (type >= 41 && type <= 44) || (type >= 48 && type <= 55)))) {
				new_au = true;
			} else if (layer == 0 && type <= 31 && len >= 3 && (q[2] & 0x80)) {
				new_au = true;
			}
			if (type == 33 && layer == 0) {
				parse_hevc_sps(st, q, len);
			}
		}
		if (au_start == SIZE_MAX) {
			au_start = start;
		} else if (seen_vcl && new_au) {
			push_au(st, au_start, start - au_start);
			au_start = start;
			seen_vcl = false;
		}
		seen_vcl = seen_vcl || vcl;
		sc = next;
	}
	if (au_start != SIZE_MAX && seen_vcl) {
		push_au(st, au_start, n - au_start);
	}
	printf("stream %s: %zu access units, largest %zu bytes, SPS %ux%u %u-bit\n", path, st->n_aus, st->max_au, st->width, st->height, st->bit_depth);
	return st->n_aus && st->width ? 0 : -1;
}

struct decoded {
	int vfd; // The decoder, kept open (and streaming) while the frame is in use.
	int fd; // EXPBUF of the frame's CAPTURE buffer.
	uint32_t fourcc, width, height, pitch, sizeimage;
	struct v4l2_rect visible;
	off_t dmabuf_size;
	int capture_fds[32];
	uint32_t n_capture;
};

#define OUT_TYPE V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE
#define CAP_TYPE V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE

static int xioctl(int fd, unsigned long req, void *arg, const char *name) {
	int r;
	do {
		r = ioctl(fd, req, arg);
	} while (r < 0 && errno == EINTR);
	if (r < 0 && name) {
		printf("  %s: %s\n", name, strerror(errno));
	}
	return r;
}

static int setup_capture(struct decoded *d) {
	struct v4l2_format f = { .type = CAP_TYPE };
	if (xioctl(d->vfd, VIDIOC_G_FMT, &f, "G_FMT CAPTURE")) {
		return -1;
	}
	printf("  SOURCE_CHANGE: CAPTURE %s %ux%u; offered:", fourcc_str(f.fmt.pix_mp.pixelformat), f.fmt.pix_mp.width, f.fmt.pix_mp.height);
	for (uint32_t i = 0;; i++) {
		struct v4l2_fmtdesc desc = { .index = i, .type = CAP_TYPE };
		if (ioctl(d->vfd, VIDIOC_ENUM_FMT, &desc) < 0) {
			break;
		}
		printf(" %s", fourcc_str(desc.pixelformat));
	}
	printf("\n");
	if (f.fmt.pix_mp.pixelformat != o.capture) {
		f.fmt.pix_mp.pixelformat = o.capture;
		xioctl(d->vfd, VIDIOC_S_FMT, &f, "S_FMT CAPTURE");
		f = (struct v4l2_format){ .type = CAP_TYPE };
		xioctl(d->vfd, VIDIOC_G_FMT, &f, "G_FMT CAPTURE");
	}
	const struct v4l2_pix_format_mplane *pf = &f.fmt.pix_mp;
	d->fourcc = pf->pixelformat;
	d->width = pf->width;
	d->height = pf->height;
	d->pitch = pf->plane_fmt[0].bytesperline;
	d->sizeimage = pf->plane_fmt[0].sizeimage;
	printf("  CAPTURE %s %ux%u, %u plane(s), bytesperline %u, sizeimage %u\n", fourcc_str(d->fourcc), d->width, d->height, pf->num_planes, d->pitch, d->sizeimage);
	if (d->fourcc != o.capture) {
		printf("ERROR: asked for CAPTURE %s, the driver chose %s\n", fourcc_str(o.capture), fourcc_str(d->fourcc));
		return -1;
	}
	struct v4l2_selection sel = { .type = V4L2_BUF_TYPE_VIDEO_CAPTURE, .target = V4L2_SEL_TGT_COMPOSE };
	if (ioctl(d->vfd, VIDIOC_G_SELECTION, &sel) == 0 && sel.r.width && sel.r.height) {
		d->visible = sel.r;
	} else {
		d->visible = (struct v4l2_rect){ 0, 0, d->width, d->height };
	}
	printf("  visible %ux%u+%d+%d\n", d->visible.width, d->visible.height, d->visible.left, d->visible.top);
	struct v4l2_control ctrl = { .id = V4L2_CID_MIN_BUFFERS_FOR_CAPTURE };
	const uint32_t min = ioctl(d->vfd, VIDIOC_G_CTRL, &ctrl) == 0 ? (uint32_t)ctrl.value : 4;
	struct v4l2_requestbuffers rb = { .count = min + 2, .type = CAP_TYPE, .memory = V4L2_MEMORY_MMAP };
	if (xioctl(d->vfd, VIDIOC_REQBUFS, &rb, "REQBUFS CAPTURE") || rb.count == 0) {
		return -1;
	}
	d->n_capture = rb.count > 32 ? 32 : rb.count;
	for (uint32_t i = 0; i < d->n_capture; i++) {
		struct v4l2_exportbuffer e = { .type = CAP_TYPE, .index = i, .plane = 0, .flags = O_RDWR | O_CLOEXEC };
		if (xioctl(d->vfd, VIDIOC_EXPBUF, &e, "EXPBUF")) {
			return -1;
		}
		d->capture_fds[i] = e.fd;
		struct v4l2_plane planes[VIDEO_MAX_PLANES] = { 0 };
		struct v4l2_buffer b = { .index = i, .type = CAP_TYPE, .memory = V4L2_MEMORY_MMAP, .m.planes = planes, .length = VIDEO_MAX_PLANES };
		if (xioctl(d->vfd, VIDIOC_QBUF, &b, "QBUF CAPTURE")) {
			return -1;
		}
	}
	int type = CAP_TYPE;
	if (xioctl(d->vfd, VIDIOC_STREAMON, &type, "STREAMON CAPTURE")) {
		return -1;
	}
	printf("  CAPTURE: %u buffers exported and queued\n", d->n_capture);
	return 0;
}

static int decode_frame(struct decoded *d) {
	memset(d, 0, sizeof(*d));
	d->vfd = d->fd = -1;
	struct stream st;
	if (load_hevc(&st, o.decode_path)) {
		printf("ERROR: no HEVC access units or SPS in %s (a raw Annex-B .h265/.hevc file is needed)\n", o.decode_path);
		return -1;
	}
	d->vfd = open(o.device, O_RDWR | O_NONBLOCK | O_CLOEXEC);
	if (d->vfd < 0) {
		printf("ERROR: open %s: %s\n", o.device, strerror(errno));
		return -1;
	}
	struct v4l2_capability cap = { 0 };
	xioctl(d->vfd, VIDIOC_QUERYCAP, &cap, "QUERYCAP");
	printf("decoder %s: driver '%s' card '%s'\n", o.device, (const char *)cap.driver, (const char *)cap.card);

	struct v4l2_format f = { .type = OUT_TYPE };
	f.fmt.pix_mp.pixelformat = V4L2_PIX_FMT_HEVC;
	f.fmt.pix_mp.width = st.width;
	f.fmt.pix_mp.height = st.height;
	f.fmt.pix_mp.num_planes = 1;
	size_t want = st.max_au + st.max_au / 8;
	want = want < (1u << 20) ? (1u << 20) : want;
	f.fmt.pix_mp.plane_fmt[0].sizeimage = (uint32_t)((want + 4095) & ~(size_t)4095);
	if (xioctl(d->vfd, VIDIOC_S_FMT, &f, "S_FMT OUTPUT")) {
		return -1;
	}
	enum { N_OUT = 8 };
	struct v4l2_requestbuffers rb = { .count = N_OUT, .type = OUT_TYPE, .memory = V4L2_MEMORY_MMAP };
	if (xioctl(d->vfd, VIDIOC_REQBUFS, &rb, "REQBUFS OUTPUT") || rb.count == 0) {
		return -1;
	}
	const uint32_t n_out = rb.count > N_OUT ? N_OUT : rb.count;
	void *maps[N_OUT];
	size_t lens[N_OUT];
	bool queued[N_OUT] = { 0 };
	for (uint32_t i = 0; i < n_out; i++) {
		struct v4l2_plane planes[VIDEO_MAX_PLANES] = { 0 };
		struct v4l2_buffer b = { .index = i, .type = OUT_TYPE, .memory = V4L2_MEMORY_MMAP, .m.planes = planes, .length = VIDEO_MAX_PLANES };
		if (xioctl(d->vfd, VIDIOC_QUERYBUF, &b, "QUERYBUF")) {
			return -1;
		}
		maps[i] = mmap(NULL, planes[0].length, PROT_READ | PROT_WRITE, MAP_SHARED, d->vfd, planes[0].m.mem_offset);
		lens[i] = planes[0].length;
		if (maps[i] == MAP_FAILED) {
			printf("ERROR: mmap OUTPUT: %s\n", strerror(errno));
			return -1;
		}
	}
	struct v4l2_event_subscription sub = { .type = V4L2_EVENT_SOURCE_CHANGE };
	xioctl(d->vfd, VIDIOC_SUBSCRIBE_EVENT, &sub, "SUBSCRIBE_EVENT");

	size_t next_au = 0;
	uint64_t seq = 0;
	bool streaming = false, capture_ready = false;
	unsigned frames = 0;
	const double deadline = now_s() + 15.0;
	while (now_s() < deadline) {
		// Feed: every free OUTPUT buffer gets the next access unit.
		for (uint32_t i = 0; i < n_out && next_au < st.n_aus; i++) {
			if (queued[i]) {
				continue;
			}
			const struct au *a = &st.aus[next_au];
			if (a->len > lens[i]) {
				next_au++;
				continue;
			}
			memcpy(maps[i], st.data + a->off, a->len);
			struct v4l2_plane planes[1] = { { .bytesused = (uint32_t)a->len, .length = (uint32_t)lens[i] } };
			struct v4l2_buffer b = { .index = i, .type = OUT_TYPE, .memory = V4L2_MEMORY_MMAP, .m.planes = planes, .length = 1 };
			b.timestamp.tv_sec = (time_t)(seq / 1000);
			b.timestamp.tv_usec = (suseconds_t)((seq % 1000) * 1000);
			if (xioctl(d->vfd, VIDIOC_QBUF, &b, "QBUF OUTPUT")) {
				return -1;
			}
			queued[i] = true;
			next_au++;
			seq++;
		}
		if (!streaming) {
			int type = OUT_TYPE;
			if (xioctl(d->vfd, VIDIOC_STREAMON, &type, "STREAMON OUTPUT")) {
				return -1;
			}
			streaming = true;
		}
		for (;;) {
			struct v4l2_plane planes[VIDEO_MAX_PLANES] = { 0 };
			struct v4l2_buffer b = { .type = OUT_TYPE, .memory = V4L2_MEMORY_MMAP, .m.planes = planes, .length = VIDEO_MAX_PLANES };
			if (ioctl(d->vfd, VIDIOC_DQBUF, &b) < 0) {
				break;
			}
			if (b.index < n_out) {
				queued[b.index] = false;
			}
		}
		struct v4l2_event ev;
		while (ioctl(d->vfd, VIDIOC_DQEVENT, &ev) == 0) {
			if (ev.type == V4L2_EVENT_SOURCE_CHANGE && !capture_ready) {
				if (setup_capture(d)) {
					return -1;
				}
				capture_ready = true;
			}
		}
		if (capture_ready) {
			struct v4l2_plane planes[VIDEO_MAX_PLANES] = { 0 };
			struct v4l2_buffer b = { .type = CAP_TYPE, .memory = V4L2_MEMORY_MMAP, .m.planes = planes, .length = VIDEO_MAX_PLANES };
			if (ioctl(d->vfd, VIDIOC_DQBUF, &b) == 0) {
				if (!(b.flags & V4L2_BUF_FLAG_ERROR) && planes[0].bytesused > 0) {
					if (frames++ == o.frame) {
						printf("  frame %u: CAPTURE buffer %u, bytesused %u, timestamp seq %" PRIu64 "\n", o.frame, b.index, planes[0].bytesused,
								(uint64_t)b.timestamp.tv_sec * 1000 + (uint64_t)b.timestamp.tv_usec / 1000);
						d->fd = d->capture_fds[b.index];
						d->dmabuf_size = lseek(d->fd, 0, SEEK_END);
						return 0; // The buffer stays dequeued; the session stays open until the end.
					}
				} else {
					printf("  CAPTURE buffer %u: flags 0x%x, bytesused %u (skipped)\n", b.index, b.flags, planes[0].bytesused);
				}
				xioctl(d->vfd, VIDIOC_QBUF, &b, "QBUF CAPTURE");
			}
		}
		usleep(2000);
	}
	printf("ERROR: no decoded frame within 15 s (%" PRIu64 " access units fed, CAPTURE %s)\n", seq, capture_ready ? "set up" : "never set up: no SOURCE_CHANGE");
	return -1;
}

static void decode_close(struct decoded *d) {
	if (d->vfd < 0) {
		return;
	}
	int type = CAP_TYPE;
	ioctl(d->vfd, VIDIOC_STREAMOFF, &type);
	type = OUT_TYPE;
	ioctl(d->vfd, VIDIOC_STREAMOFF, &type);
	for (uint32_t i = 0; i < d->n_capture; i++) {
		close(d->capture_fds[i]);
	}
	close(d->vfd);
	d->vfd = -1;
}

/* ------------------------------------------------------------------------------------------ */
/* Import attempts */

static uint64_t align_up(uint64_t v, uint64_t a) {
	return (v + a - 1) / a * a;
}

// Where the planes of the decoder's buffer are (iris's layouts; see the engine's V4L2Decoder::_setup_capture()).
struct buffer_layout {
	bool ubwc;
	uint64_t pitch;
	uint64_t y_meta, y_data, uv_meta, uv_data; // Offsets.
	uint64_t y_meta_pitch, uv_meta_pitch;
	uint64_t total;
};

static void compute_layout(const struct decoded *d, struct buffer_layout *l) {
	memset(l, 0, sizeof(*l));
	const uint64_t w = d->width, h = d->height;
	if (d->fourcc == V4L2_PIX_FMT_QC10C) {
		l->ubwc = true;
		l->pitch = align_up(w * 4 / 3, 256);
		l->y_meta_pitch = align_up((w + 47) / 48, 64);
		l->uv_meta_pitch = align_up(((w + 1) / 2 + 23) / 24, 64);
		const uint64_t y_meta = align_up(l->y_meta_pitch * align_up((h + 3) / 4, 16), 4096);
		const uint64_t y_size = align_up(l->pitch * align_up(h, 16), 4096);
		const uint64_t uv_meta = align_up(l->uv_meta_pitch * align_up(((h + 1) / 2 + 3) / 4, 16), 4096);
		const uint64_t uv_size = align_up(l->pitch * align_up((h + 1) / 2, 16), 4096);
		l->y_meta = 0;
		l->y_data = y_meta;
		l->uv_meta = y_meta + y_size;
		l->uv_data = y_meta + y_size + uv_meta;
		l->total = y_meta + y_size + uv_meta + uv_size;
	} else if (d->fourcc == V4L2_PIX_FMT_QC08C) {
		l->ubwc = true;
		l->pitch = align_up(w, 128);
		l->y_meta_pitch = align_up((w + 31) / 32, 64);
		l->uv_meta_pitch = align_up((w / 2 + 15) / 16, 64);
		const uint64_t y_meta = align_up(l->y_meta_pitch * align_up((h + 7) / 8, 16), 4096);
		const uint64_t y_size = align_up(l->pitch * align_up(h, 32), 4096);
		const uint64_t uv_meta = align_up(l->uv_meta_pitch * align_up((h / 2 + 7) / 8, 16), 4096);
		const uint64_t uv_size = align_up(l->pitch * align_up(h / 2, 32), 4096);
		l->y_meta = 0;
		l->y_data = y_meta;
		l->uv_meta = y_meta + y_size;
		l->uv_data = y_meta + y_size + uv_meta;
		l->total = y_meta + y_size + uv_meta + uv_size;
	} else {
		// NV12 / P010: luma, then chroma after the luma plane padded to 32 lines.
		l->pitch = d->pitch;
		l->y_data = 0;
		l->uv_data = (uint64_t)d->pitch * align_up(h, 32);
		if (l->uv_data + (uint64_t)d->pitch * (h / 2) > d->sizeimage) {
			l->uv_data = (uint64_t)d->pitch * h;
		}
		l->total = l->uv_data + (uint64_t)d->pitch * (h / 2);
	}
	printf("buffer layout (%s %ux%u): pitch %" PRIu64 ", Y metadata at 0x%" PRIx64 " (pitch %" PRIu64 "), Y at 0x%" PRIx64 ", UV metadata at 0x%" PRIx64 " (pitch %" PRIu64 "), UV at 0x%" PRIx64 "; total %" PRIu64 " (sizeimage %u%s)\n",
			fourcc_str(d->fourcc), d->width, d->height, l->pitch, l->y_meta, l->y_meta_pitch, l->y_data, l->uv_meta, l->uv_meta_pitch, l->uv_data, l->total, d->sizeimage,
			l->total == d->sizeimage ? "" : (l->ubwc ? ", MISMATCH" : ""));
}

enum layout_kind {
	LAYOUT_META, // 2 memory planes, each starting at its UBWC metadata (Turnip's QCOM_COMPRESSED convention).
	LAYOUT_DATA, // 2 memory planes, each starting at its pixels.
	LAYOUT_4PLANE, // Y pixels, UV pixels, Y metadata, UV metadata.
	LAYOUT_1PLANE, // One memory plane at 0.
	LAYOUT_LINEAR, // Linear NV12/P010: Y at 0, UV after the padded luma.
};
static const char *layout_names[] = { "meta", "data", "4plane", "1plane", "linear" };

static int make_plane_layouts(const struct buffer_layout *l, enum layout_kind kind, VkSubresourceLayout *out) {
	memset(out, 0, sizeof(VkSubresourceLayout) * 4);
	switch (kind) {
		case LAYOUT_META:
			out[0] = (VkSubresourceLayout){ .offset = l->y_meta, .rowPitch = l->pitch };
			out[1] = (VkSubresourceLayout){ .offset = l->uv_meta, .rowPitch = l->pitch };
			return 2;
		case LAYOUT_DATA:
			out[0] = (VkSubresourceLayout){ .offset = l->y_data, .rowPitch = l->pitch };
			out[1] = (VkSubresourceLayout){ .offset = l->uv_data, .rowPitch = l->pitch };
			return 2;
		case LAYOUT_4PLANE:
			out[0] = (VkSubresourceLayout){ .offset = l->y_data, .rowPitch = l->pitch };
			out[1] = (VkSubresourceLayout){ .offset = l->uv_data, .rowPitch = l->pitch };
			out[2] = (VkSubresourceLayout){ .offset = l->y_meta, .rowPitch = l->y_meta_pitch };
			out[3] = (VkSubresourceLayout){ .offset = l->uv_meta, .rowPitch = l->uv_meta_pitch };
			return 4;
		case LAYOUT_1PLANE:
			out[0] = (VkSubresourceLayout){ .offset = 0, .rowPitch = l->pitch };
			return 1;
		case LAYOUT_LINEAR:
			out[0] = (VkSubresourceLayout){ .offset = l->y_data, .rowPitch = l->pitch };
			out[1] = (VkSubresourceLayout){ .offset = l->uv_data, .rowPitch = l->pitch };
			return 2;
	}
	return 0;
}

static uint16_t *g_ref;
static size_t g_ref_size;
static unsigned g_attempts, g_plausible;

static void try_import(const struct decoded *d, const struct buffer_layout *l, VkFormat format, uint64_t modifier, uint32_t mod_planes, VkFormatFeatureFlags2 features, enum layout_kind kind) {
	char tag[160];
	snprintf(tag, sizeof(tag), "%s-%d-%016" PRIx64 "-%s", fourcc_str(d->fourcc), (int)format, modifier, layout_names[kind]);
	if (o.only && !strstr(tag, o.only)) {
		return;
	}
	g_attempts++;
	printf("\nattempt %s: format %d %s, modifier 0x%016" PRIx64 " %s, %u memory plane(s) reported, layout %s\n", tag, (int)format, format_name(format), modifier, modifier_name(modifier), mod_planes, layout_names[kind]);
	fflush(stdout);
	VkSubresourceLayout planes[4];
	const int n_planes = make_plane_layouts(l, kind, planes);
	for (int i = 0; i < n_planes; i++) {
		printf("    memory plane %d: offset 0x%" PRIx64 ", pitch %" PRIu64 "\n", i, (uint64_t)planes[i].offset, (uint64_t)planes[i].rowPitch);
	}
	VkImageDrmFormatModifierExplicitCreateInfoEXT explicit_info = {
		.sType = VK_STRUCTURE_TYPE_IMAGE_DRM_FORMAT_MODIFIER_EXPLICIT_CREATE_INFO_EXT,
		.drmFormatModifier = modifier,
		.drmFormatModifierPlaneCount = (uint32_t)n_planes,
		.pPlaneLayouts = planes,
	};
	VkExternalMemoryImageCreateInfo ext_info = { .sType = VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO, .pNext = &explicit_info, .handleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT };
	VkImageCreateInfo ici = {
		.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
		.pNext = &ext_info,
		.imageType = VK_IMAGE_TYPE_2D,
		.format = format,
		.extent = { d->width, d->height, 1 },
		.mipLevels = 1,
		.arrayLayers = 1,
		.samples = VK_SAMPLE_COUNT_1_BIT,
		.tiling = VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT,
		.usage = VK_IMAGE_USAGE_SAMPLED_BIT,
		.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
	};
	VkImage image = VK_NULL_HANDLE;
	VkResult r = vkCreateImage(g_dev, &ici, NULL, &image);
	if (r != VK_SUCCESS) {
		printf("    vkCreateImage: VkResult %d%s\n", r, r == VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT ? " (INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT: the driver disagrees with the offsets or pitches)" : "");
		return;
	}
	VkMemoryDedicatedRequirements dedicated = { .sType = VK_STRUCTURE_TYPE_MEMORY_DEDICATED_REQUIREMENTS };
	VkImageMemoryRequirementsInfo2 rqi = { .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_REQUIREMENTS_INFO_2, .image = image };
	VkMemoryRequirements2 req = { .sType = VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2, .pNext = &dedicated };
	vkGetImageMemoryRequirements2(g_dev, &rqi, &req);
	printf("    image created: needs %" PRIu64 " bytes (the dmabuf holds %" PRId64 ")%s\n", (uint64_t)req.memoryRequirements.size, (int64_t)d->dmabuf_size,
			dedicated.requiresDedicatedAllocation ? ", dedicated allocation required" : "");
	if (vkGetImageDrmFormatModifierPropertiesEXT) {
		for (int i = 0; i < n_planes; i++) {
			VkImageSubresource sub = { VK_IMAGE_ASPECT_MEMORY_PLANE_0_BIT_EXT << i, 0, 0 };
			VkSubresourceLayout got;
			vkGetImageSubresourceLayout(g_dev, image, &sub, &got);
			printf("    driver's memory plane %d: offset 0x%" PRIx64 ", pitch %" PRIu64 ", size %" PRIu64 "\n", i, (uint64_t)got.offset, (uint64_t)got.rowPitch, (uint64_t)got.size);
		}
	}
	if ((int64_t)req.memoryRequirements.size > (int64_t)d->dmabuf_size) {
		printf("    SKIPPED: the image needs more memory than the dmabuf has (a different layout than the decoder's)\n");
		vkDestroyImage(g_dev, image, NULL);
		return;
	}
	VkMemoryFdPropertiesKHR fd_props = { .sType = VK_STRUCTURE_TYPE_MEMORY_FD_PROPERTIES_KHR };
	r = vkGetMemoryFdPropertiesKHR(g_dev, VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT, d->fd, &fd_props);
	const uint32_t bits = req.memoryRequirements.memoryTypeBits & fd_props.memoryTypeBits;
	if (r != VK_SUCCESS || !bits) {
		printf("    vkGetMemoryFdPropertiesKHR: %d, memory types image 0x%x dmabuf 0x%x\n", r, req.memoryRequirements.memoryTypeBits, fd_props.memoryTypeBits);
		vkDestroyImage(g_dev, image, NULL);
		return;
	}
	const int import_fd = fcntl(d->fd, F_DUPFD_CLOEXEC, 0);
	VkMemoryDedicatedAllocateInfo ded = { .sType = VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO, .image = image };
	VkImportMemoryFdInfoKHR import = { .sType = VK_STRUCTURE_TYPE_IMPORT_MEMORY_FD_INFO_KHR, .pNext = &ded, .handleType = VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT, .fd = import_fd };
	VkMemoryAllocateInfo mai = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .pNext = &import, .allocationSize = req.memoryRequirements.size, .memoryTypeIndex = (uint32_t)__builtin_ctz(bits) };
	VkDeviceMemory memory = VK_NULL_HANDLE;
	r = vkAllocateMemory(g_dev, &mai, NULL, &memory);
	if (r != VK_SUCCESS) {
		printf("    import (vkAllocateMemory): VkResult %d\n", r);
		close(import_fd);
		vkDestroyImage(g_dev, image, NULL);
		return;
	}
	r = vkBindImageMemory(g_dev, image, memory, 0);
	if (r != VK_SUCCESS) {
		printf("    vkBindImageMemory: VkResult %d\n", r);
	} else {
		struct query_props {
			uint32_t descriptors;
		} q = { 1 };
		{
			VkPhysicalDeviceImageDrmFormatModifierInfoEXT mod_info = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_DRM_FORMAT_MODIFIER_INFO_EXT, .drmFormatModifier = modifier, .sharingMode = VK_SHARING_MODE_EXCLUSIVE };
			VkPhysicalDeviceImageFormatInfo2 info = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_FORMAT_INFO_2, .pNext = &mod_info, .format = format, .type = VK_IMAGE_TYPE_2D, .tiling = VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT, .usage = VK_IMAGE_USAGE_SAMPLED_BIT };
			VkSamplerYcbcrConversionImageFormatProperties yp = { .sType = VK_STRUCTURE_TYPE_SAMPLER_YCBCR_CONVERSION_IMAGE_FORMAT_PROPERTIES };
			VkImageFormatProperties2 props = { .sType = VK_STRUCTURE_TYPE_IMAGE_FORMAT_PROPERTIES_2, .pNext = &yp };
			if (vkGetPhysicalDeviceImageFormatProperties2(g_pd, &info, &props) == VK_SUCCESS && yp.combinedImageSamplerDescriptorCount) {
				q.descriptors = yp.combinedImageSamplerDescriptorCount;
			}
		}
		printf("    imported (one dedicated import of the dmabuf); converting\n");
		struct picture pic = { .w = d->width, .h = d->height, .vx = d->visible.left & ~1u, .vy = d->visible.top & ~1u, .vw = d->visible.width & ~1u, .vh = d->visible.height & ~1u, .bits = format_bits(format) };
		pic.codes = malloc((size_t)d->width * d->height * 3 / 2 * sizeof(uint32_t));
		if (convert_image(image, format, features, d->width, d->height, true, q.descriptors, pic.codes) == 0) {
			char line[512];
			const char *verdict = judge(&pic, line, sizeof(line));
			printf("    RESULT %s: %s\n    %s\n", tag, verdict, line);
			g_plausible += !strncmp(verdict, "PLAUSIBLE", 9);
			if (g_ref && g_ref_size == (size_t)pic.vw * pic.vh * 3) {
				compare_ref(&pic, g_ref);
			}
			write_outputs(&pic, tag);
		}
		free(pic.codes);
	}
	vkFreeMemory(g_dev, memory, NULL);
	vkDestroyImage(g_dev, image, NULL);
}

static void try_all(const struct decoded *d) {
	struct buffer_layout l;
	compute_layout(d, &l);
	VkFormat formats[8];
	uint32_t n_formats = 0;
	if (d->fourcc == V4L2_PIX_FMT_QC08C || d->fourcc == V4L2_PIX_FMT_NV12) {
		formats[n_formats++] = VK_FORMAT_G8_B8R8_2PLANE_420_UNORM;
	} else {
		formats[n_formats++] = VK_FORMAT_G10X6_B10X6R10X6_2PLANE_420_UNORM_3PACK16;
		formats[n_formats++] = VK_FORMAT_G16_B16R16_2PLANE_420_UNORM;
		formats[n_formats++] = VK_FORMAT_G12X4_B12X4R12X4_2PLANE_420_UNORM_3PACK16;
	}
	if (o.extra_format >= 0) {
		formats[n_formats++] = (VkFormat)o.extra_format;
	}
	for (uint32_t fi = 0; fi < n_formats; fi++) {
		const VkFormat format = formats[fi];
		struct mod_entry mods[MAX_MODS + 8];
		uint32_t n = get_modifiers(format, mods);
		const uint32_t listed = n;
		// The QCOM modifiers the driver doesn't list, if its image query takes them (and --modifier).
		for (uint64_t k = 1; k <= 7; k++) {
			bool have = false;
			for (uint32_t i = 0; i < n; i++) {
				have = have || mods[i].modifier == MOD_QCOM(k);
			}
			if (!have && (o.all_modifiers || query_import(format, MOD_QCOM(k), d->width, d->height, false) == VK_SUCCESS)) {
				mods[n++] = (struct mod_entry){ MOD_QCOM(k), 0, 0 };
			}
		}
		if (o.have_extra_modifier) {
			mods[n++] = (struct mod_entry){ o.extra_modifier, 0, 0 };
		}
		printf("\n== %s: %u modifier(s) listed, %u to try ==\n", format_name(format), listed, n);
		for (uint32_t i = 0; i < n; i++) {
			VkFormatFeatureFlags2 features = mods[i].features;
			if (!features) {
				VkFormatProperties3 p3 = { .sType = VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_3 };
				VkFormatProperties2 p2 = { .sType = VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_2, .pNext = &p3 };
				vkGetPhysicalDeviceFormatProperties2(g_pd, format, &p2);
				features = p3.optimalTilingFeatures;
			}
			const bool linear = mods[i].modifier == MOD_LINEAR;
			if (linear != !l.ubwc) {
				// A linear import of a UBWC buffer (or the other way round) can't be right; LINEAR is still tried for UBWC
				// buffers when asked (--all-modifiers), as a negative control.
				if (!(linear && o.all_modifiers)) {
					continue;
				}
			}
			if (linear) {
				try_import(d, &l, format, mods[i].modifier, mods[i].planes, features, l.ubwc ? LAYOUT_DATA : LAYOUT_LINEAR);
				continue;
			}
			const uint32_t planes = mods[i].planes;
			if (planes == 0 || planes == 2) {
				try_import(d, &l, format, mods[i].modifier, planes, features, LAYOUT_META);
				try_import(d, &l, format, mods[i].modifier, planes, features, LAYOUT_DATA);
			}
			if (planes == 0 || planes == 4) {
				try_import(d, &l, format, mods[i].modifier, planes, features, LAYOUT_4PLANE);
			}
			if (planes == 1) {
				try_import(d, &l, format, mods[i].modifier, planes, features, LAYOUT_1PLANE);
			}
		}
	}
}

static void dump_raw(const struct decoded *d) {
	void *m = mmap(NULL, (size_t)d->dmabuf_size, PROT_READ, MAP_SHARED, d->fd, 0);
	if (m == MAP_FAILED) {
		printf("can't map the dmabuf for --dump-raw: %s\n", strerror(errno));
		return;
	}
	struct dma_buf_sync sync = { .flags = DMA_BUF_SYNC_START | DMA_BUF_SYNC_READ };
	ioctl(d->fd, DMA_BUF_IOCTL_SYNC, &sync);
	char path[512];
	mkdir(o.out_dir, 0755);
	snprintf(path, sizeof(path), "%s/capture-%s-%ux%u-pitch%u.raw", o.out_dir, fourcc_str(d->fourcc), d->width, d->height, d->pitch);
	FILE *f = fopen(path, "wb");
	if (f) {
		fwrite(m, 1, (size_t)d->dmabuf_size, f);
		fclose(f);
		printf("wrote %s (%" PRId64 " bytes)\n", path, (int64_t)d->dmabuf_size);
	}
	sync.flags = DMA_BUF_SYNC_END | DMA_BUF_SYNC_READ;
	ioctl(d->fd, DMA_BUF_IOCTL_SYNC, &sync);
	munmap(m, (size_t)d->dmabuf_size);
}

/* ------------------------------------------------------------------------------------------ */

static void usage(void) {
	printf("usage: q10c-probe [options]\n"
		   "  (no option)            list the driver's formats, modifiers and import support\n"
		   "  --scan-formats         also look for unlisted (vendor) formats in the extension ranges\n"
		   "  --selftest             run the conversion on host-memory test patterns (no decoder)\n"
		   "  --decode FILE          decode the first frame of a raw HEVC file and try every import\n"
		   "  --capture FOURCC       Q10C (default), Q08C, P010 or NV12\n"
		   "  --frame N              use the Nth decoded frame (default 0)\n"
		   "  --device PATH          the decoder (default /dev/video-dec0)\n"
		   "  --out DIR              where .yuv/.ppm results go (default ./q10c-out)\n"
		   "  --ref FILE             yuv420p10le of the same frame (visible size) for PSNR\n"
		   "  --only TEXT            only attempts whose tag contains TEXT (e.g. 1000156011-0500000000000001-meta)\n"
		   "  --format N             also try VkFormat N\n"
		   "  --modifier HEX         also try this DRM format modifier\n"
		   "  --all-modifiers        try QCOM 1-7 even if the driver's query refuses them, and LINEAR as a control\n"
		   "  --dump-raw             write the CAPTURE buffer's bytes\n"
		   "  --bt2020               BT.2020 matrix for the .ppm previews\n"
		   "  --ycbcr-model          YCBCR_IDENTITY instead of RGB_IDENTITY (chroma then comes back signed and clips)\n");
}

int main(int argc, char **argv) {
	setvbuf(stdout, NULL, _IOLBF, 0);
	for (int i = 1; i < argc; i++) {
		const char *a = argv[i];
		const char *v = i + 1 < argc ? argv[i + 1] : NULL;
		if (!strcmp(a, "--scan-formats")) {
			o.scan_formats = true;
		} else if (!strcmp(a, "--selftest")) {
			o.selftest = true;
		} else if (!strcmp(a, "--decode") && v) {
			o.decode_path = v;
			i++;
		} else if (!strcmp(a, "--capture") && v && strlen(v) == 4) {
			o.capture = v4l2_fourcc(v[0], v[1], v[2], v[3]);
			i++;
		} else if (!strcmp(a, "--frame") && v) {
			o.frame = (unsigned)atoi(v);
			i++;
		} else if (!strcmp(a, "--device") && v) {
			o.device = v;
			i++;
		} else if (!strcmp(a, "--out") && v) {
			o.out_dir = v;
			i++;
		} else if (!strcmp(a, "--ref") && v) {
			o.ref_path = v;
			i++;
		} else if (!strcmp(a, "--only") && v) {
			o.only = v;
			i++;
		} else if (!strcmp(a, "--format") && v) {
			o.extra_format = atoi(v);
			i++;
		} else if (!strcmp(a, "--modifier") && v) {
			o.extra_modifier = strtoull(v, NULL, 16);
			o.have_extra_modifier = true;
			i++;
		} else if (!strcmp(a, "--all-modifiers")) {
			o.all_modifiers = true;
		} else if (!strcmp(a, "--dump-raw")) {
			o.dump_raw = true;
		} else if (!strcmp(a, "--bt2020")) {
			o.bt2020 = true;
		} else if (!strcmp(a, "--ycbcr-model")) {
			o.ycbcr_model = true;
		} else {
			usage();
			return a[2] == 'h' ? 0 : 2;
		}
	}
	printf("q10c-probe (spike 04)\n");
	if (vk_init()) {
		return 1;
	}
	list_formats();
	if (o.scan_formats) {
		scan_formats();
	}
	int ret = 0;
	if (o.selftest) {
		printf("\n== Self-test ==\n");
		if (!g_ycbcr_feature) {
			printf("no samplerYcbcrConversion: skipped\n");
		} else {
			ret |= selftest_format(VK_FORMAT_G10X6_B10X6R10X6_2PLANE_420_UNORM_3PACK16, 10, 256, 128) ? 1 : 0;
			ret |= selftest_format(VK_FORMAT_G8_B8R8_2PLANE_420_UNORM, 8, 256, 128) ? 1 : 0;
			ret |= selftest_format(VK_FORMAT_G16_B16R16_2PLANE_420_UNORM, 16, 256, 128) ? 1 : 0;
		}
	}
	if (o.decode_path) {
		printf("\n== Decode and import ==\n");
		if (!g_has_modifiers || !g_has_dmabuf || !vkGetMemoryFdPropertiesKHR || !g_ycbcr_feature) {
			printf("ERROR: the driver lacks dmabuf import, DRM format modifiers or samplerYcbcrConversion\n");
			ret = 1;
		} else {
			if (o.ref_path) {
				FILE *f = fopen(o.ref_path, "rb");
				if (f) {
					fseek(f, 0, SEEK_END);
					const long size = ftell(f);
					fseek(f, 0, SEEK_SET);
					g_ref = malloc((size_t)size);
					g_ref_size = (size_t)size;
					if (fread(g_ref, 1, (size_t)size, f) != (size_t)size) {
						free(g_ref);
						g_ref = NULL;
					}
					fclose(f);
					printf("reference %s: %ld bytes\n", o.ref_path, size);
				} else {
					printf("can't read --ref %s\n", o.ref_path);
				}
			}
			struct decoded d;
			if (decode_frame(&d) == 0) {
				printf("decoded frame %u: %s %ux%u, visible %ux%u+%d+%d, dmabuf %" PRId64 " bytes\n", o.frame, fourcc_str(d.fourcc), d.width, d.height, d.visible.width, d.visible.height, d.visible.left, d.visible.top, (int64_t)d.dmabuf_size);
				if (g_ref && (size_t)(d.visible.width & ~1u) * (d.visible.height & ~1u) * 3 > 0) {
					printf("(--ref must be yuv420p10le of %ux%u: %u bytes)\n", d.visible.width & ~1u, d.visible.height & ~1u, (d.visible.width & ~1u) * (d.visible.height & ~1u) * 3);
				}
				if (o.dump_raw) {
					dump_raw(&d);
				}
				try_all(&d);
				printf("\n== Summary: %u attempt(s), %u plausible picture(s) ==\n", g_attempts, g_plausible);
				vkDeviceWaitIdle(g_dev);
			} else {
				ret = 1;
			}
			decode_close(&d);
		}
	}
	vkDestroyFence(g_dev, g_fence, NULL);
	vkDestroyCommandPool(g_dev, g_cmd_pool, NULL);
	vkDestroyDevice(g_dev, NULL);
	vkDestroyInstance(g_instance, NULL);
	return ret;
}
