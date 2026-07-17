//===- ironxrt.cpp ----------------------------------------------*- C++ -*-===//
//
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// A minimal C ABI over the XRT C++ runtime, just enough to load and launch an
// MLIR-AIE design on an AMD NPU from a non-C++ host (IRON.jl calls these via
// `ccall`). The NPU launch path -- register_xclbin + hw_context + kernel-by-name
// -- lives only in XRT's C++ API, so a thin shim is the clean way to reach it.
//
// The split mirrors MLIR-AIE's Python host runtime (python/utils/hostruntime):
//
//   * A device is opened once. Buffer objects are allocated from it and stay
//     resident on the NPU; host code maps them and syncs each direction. Data
//     buffers use group_id 0 with host-only flags -- the same magic default the
//     Python XRTTensor uses.
//   * A launch context loads and registers an xclbin, creates a hardware context
//     for it, and opens the kernel ("MLIR_AIE" by default). A run sets the fixed
//     NPU argument layout and binds the caller's already-resident buffers.
//
// Every entry point is `noexcept` at the boundary: exceptions are caught and
// turned into a null/non-zero return plus a thread-local message retrievable
// with ironxrt_last_error(). That keeps XRT's exceptions from unwinding into
// Julia, which has no way to catch them.
//
//===----------------------------------------------------------------------===//

// xrt_device.h transitively pulls in xrt::xclbin (from experimental/) and
// xrt::uuid, whose installed locations differ across XRT versions, so we do not
// include those directly.
#include "xrt/xrt_bo.h"
#include "xrt/xrt_device.h"
#include "xrt/xrt_hw_context.h"
#include "xrt/xrt_kernel.h"

#include <cstdint>
#include <string>

namespace {

// Per-thread last-error buffer. Set on every failure, read by callers to
// produce a Julia-side error message.
thread_local std::string g_last_error;

void set_error(const char *what) { g_last_error = what ? what : "unknown error"; }

// An open NPU device. Buffer objects are allocated from it and the launch
// context borrows it, so tensors and the kernel share one device handle.
struct Device {
  xrt::device device;
};

// A launch context: an xclbin registered on the device, a hardware context for
// it, and the opened kernel. Outlives individual runs.
struct Context {
  xrt::device device;
  xrt::xclbin xclbin;
  xrt::hw_context hwctx;
  xrt::kernel kernel;
};

// A single buffer object; host_only ones are host-visible after map().
struct Bo {
  xrt::bo bo;
};

} // namespace

extern "C" {

// Opaque handles handed back to the caller.
typedef void *ironxrt_device;
typedef void *ironxrt_ctx;
typedef void *ironxrt_bo;

/// Message describing the most recent failure on the calling thread. Valid
/// until the next ironxrt call on this thread. Never null.
const char *ironxrt_last_error(void) { return g_last_error.c_str(); }

/// Open NPU device `index`. Returns an opaque device, or null on failure.
ironxrt_device ironxrt_device_open(unsigned index) {
  try {
    return new Device{xrt::device(index)};
  } catch (const std::exception &e) {
    set_error(e.what());
    return nullptr;
  } catch (...) {
    set_error("ironxrt_device_open: unknown exception");
    return nullptr;
  }
}

/// Close a device opened with ironxrt_device_open. Safe on null.
void ironxrt_device_close(ironxrt_device handle) {
  delete static_cast<Device *>(handle);
}

/// Allocate a buffer object of `nbytes` on `dev` in bank `group_id`. `cacheable`
/// selects a cacheable BO (used for the instruction stream); otherwise a
/// host-only BO (used for data buffers, which map to host-visible memory).
/// Returns an opaque BO, or null on failure.
ironxrt_bo ironxrt_bo_alloc(ironxrt_device handle, size_t nbytes, int group_id,
                            int cacheable) {
  try {
    auto *dev = static_cast<Device *>(handle);
    auto flags = cacheable ? xrt::bo::flags::cacheable : xrt::bo::flags::host_only;
    return new Bo{xrt::bo(dev->device, nbytes, flags,
                          static_cast<xrt::memory_group>(group_id))};
  } catch (const std::exception &e) {
    set_error(e.what());
    return nullptr;
  } catch (...) {
    set_error("ironxrt_bo_alloc: unknown exception");
    return nullptr;
  }
}

/// Host pointer for a BO's memory, for reading/writing around a sync. Returns
/// null on failure.
void *ironxrt_bo_map(ironxrt_bo handle) {
  try {
    return static_cast<Bo *>(handle)->bo.map();
  } catch (const std::exception &e) {
    set_error(e.what());
    return nullptr;
  } catch (...) {
    set_error("ironxrt_bo_map: unknown exception");
    return nullptr;
  }
}

/// Flush the host-side contents of a BO to the device. Returns 0 on success.
int ironxrt_bo_sync_to_device(ironxrt_bo handle) {
  try {
    static_cast<Bo *>(handle)->bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
    return 0;
  } catch (const std::exception &e) {
    set_error(e.what());
    return 1;
  } catch (...) {
    set_error("ironxrt_bo_sync_to_device: unknown exception");
    return 1;
  }
}

/// Pull the device-side contents of a BO back to the host mapping. Returns 0 on
/// success.
int ironxrt_bo_sync_from_device(ironxrt_bo handle) {
  try {
    static_cast<Bo *>(handle)->bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE);
    return 0;
  } catch (const std::exception &e) {
    set_error(e.what());
    return 1;
  } catch (...) {
    set_error("ironxrt_bo_sync_from_device: unknown exception");
    return 1;
  }
}

/// Release a BO. Safe on null.
void ironxrt_bo_free(ironxrt_bo handle) { delete static_cast<Bo *>(handle); }

/// Load and register `xclbin_path` on `dev`, create a hardware context, and open
/// the kernel named `kernel_name` (aiecc emits "MLIR_AIE"). Returns an opaque
/// launch context, or null on failure.
ironxrt_ctx ironxrt_open(ironxrt_device handle, const char *xclbin_path,
                         const char *kernel_name) {
  try {
    auto *dev = static_cast<Device *>(handle);
    auto *ctx = new Context{};
    ctx->device = dev->device;
    ctx->xclbin = xrt::xclbin(std::string(xclbin_path));
    ctx->device.register_xclbin(ctx->xclbin);
    ctx->hwctx = xrt::hw_context(ctx->device, ctx->xclbin.get_uuid());
    ctx->kernel = xrt::kernel(ctx->hwctx, std::string(kernel_name));
    return ctx;
  } catch (const std::exception &e) {
    set_error(e.what());
    return nullptr;
  } catch (...) {
    set_error("ironxrt_open: unknown exception");
    return nullptr;
  }
}

/// Release a launch context opened with ironxrt_open. Safe on null.
void ironxrt_close(ironxrt_ctx handle) { delete static_cast<Context *>(handle); }

/// Memory-bank group id XRT expects for kernel argument `argno` (the instruction
/// buffer is argument 1). Returns -1 on failure.
int ironxrt_group_id(ironxrt_ctx handle, int argno) {
  try {
    return static_cast<Context *>(handle)->kernel.group_id(argno);
  } catch (const std::exception &e) {
    set_error(e.what());
    return -1;
  } catch (...) {
    set_error("ironxrt_group_id: unknown exception");
    return -1;
  }
}

/// Launch the design and wait for completion. Sets the fixed NPU argument
/// layout: arg0 = opcode (3), arg1 = instruction BO, arg2 = instruction word
/// count, arg3.. = the `nargs` data BOs in order. The data BOs are the caller's
/// resident buffers; no copying happens here. Returns 0 on success.
///
/// Scalars are passed as 64-bit; XRT copies only as many bytes as the kernel's
/// argument declares, so this is safe whether opcode/count are 32- or 64-bit.
int ironxrt_run(ironxrt_ctx handle, ironxrt_bo instr, unsigned ninstr,
                ironxrt_bo *args, unsigned nargs) {
  try {
    auto *ctx = static_cast<Context *>(handle);
    xrt::run run(ctx->kernel);
    uint64_t opcode = 3;
    uint64_t count = ninstr;
    run.set_arg(0, opcode);
    run.set_arg(1, static_cast<Bo *>(instr)->bo);
    run.set_arg(2, count);
    for (unsigned i = 0; i < nargs; ++i)
      run.set_arg(static_cast<int>(3 + i), static_cast<Bo *>(args[i])->bo);
    run.start();
    run.wait();
    return 0;
  } catch (const std::exception &e) {
    set_error(e.what());
    return 1;
  } catch (...) {
    set_error("ironxrt_run: unknown exception");
    return 1;
  }
}

} // extern "C"
