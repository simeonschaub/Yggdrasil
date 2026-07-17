using mlir_aie_jll
using Peano_jll

# ==========================================
# 1. The IRON-Style ObjectFIFO Input
# ==========================================
iron_mlir = """
module {
  aie.device(npu2) {
    %logical_core = aie.logical_tile<CoreTile>(?, ?)
    %logical_shim_noc = aie.logical_tile<ShimNOCTile>(?, ?)
    %logical_shim_noc_0 = aie.logical_tile<ShimNOCTile>(?, ?)
    aie.objectfifo @in(%logical_shim_noc, {%logical_core}, 2 : i32) : !aie.objectfifo<memref<1024xi32>>  
    aie.objectfifo @out(%logical_core, {%logical_shim_noc_0}, 2 : i32) : !aie.objectfifo<memref<1024xi32>>  
    %0 = aie.core(%logical_core) {
      %c0 = arith.constant 0 : index
      %c9223372036854775807 = arith.constant 9223372036854775807 : index
      %c1 = arith.constant 1 : index
      scf.for %arg0 = %c0 to %c9223372036854775807 step %c1 {
        %1 = aie.objectfifo.acquire @in(Consume, 1) : !aie.objectfifosubview<memref<1024xi32>>
        %2 = aie.objectfifo.subview.access %1[0] : !aie.objectfifosubview<memref<1024xi32>> -> memref<1024xi32>
        %3 = aie.objectfifo.acquire @out(Produce, 1) : !aie.objectfifosubview<memref<1024xi32>>
        %4 = aie.objectfifo.subview.access %3[0] : !aie.objectfifosubview<memref<1024xi32>> -> memref<1024xi32>
        %c0_1 = arith.constant 0 : index
        %c1024 = arith.constant 1024 : index
        %c1_2 = arith.constant 1 : index
        scf.for %arg1 = %c0_1 to %c1024 step %c1_2 {
          %5 = memref.load %2[%arg1] : memref<1024xi32>
          %c1_i32 = arith.constant 1 : i32
          %6 = arith.addi %5, %c1_i32 : i32
          memref.store %6, %4[%arg1] : memref<1024xi32>
        }
        aie.objectfifo.release @in(Consume, 1)
        aie.objectfifo.release @out(Produce, 1)
      }
      aie.end
    }
    aie.runtime_sequence(%arg0: memref<1024xi32>, %arg1: memref<1024xi32>) {
      %1 = aiex.dma_configure_task_for @in {
        // Buffer operand with type, then keyword operands: offset, len, and the
        // n-d sizes/strides as plain index lists (outermost dimension first).
        aie.dma_bd(%arg0 : memref<1024xi32> offset = 0 len = 1024 sizes = [1, 1, 1, 1024] strides = [0, 0, 0, 1]) {burst_length = 0 : i32}
        aie.end
      }
      aiex.dma_start_task(%1)

      %2 = aiex.dma_configure_task_for @out {
        aie.dma_bd(%arg1 : memref<1024xi32> offset = 0 len = 1024 sizes = [1, 1, 1, 1024] strides = [0, 0, 0, 1]) {burst_length = 0 : i32}
        aie.end
      } {issue_token = true}

      aiex.dma_start_task(%2)
      aiex.dma_await_task(%2)
      aiex.dma_free_task(%1)
    }
  }
}
"""

# Extract binaries
aie_opt       = mlir_aie_jll.aie_opt()
aie_translate = mlir_aie_jll.aie_translate()
peano_llc     = Peano_jll.llc()

# File paths
src_file      = "iron_input.mlir"
lowered_mlir  = "physical_mapped.mlir"
llvm_ir_file  = "npu_kernel.ll"
object_file   = "npu_kernel.o"

write(src_file, iron_mlir)

println("--- Starting IRON Compilation Pipeline via Julia ---")

# --------------------------------------------------------------------------
# Step 1: Map abstract topology & resolve objectFifos to registers/locks
# --------------------------------------------------------------------------
println("[Step 1] Resolving abstract objectFifos to hardware primitives...")

# Reproduces aiecc's core-compilation pipeline (tools/aiecc/aiecc.cpp) using only
# aie-opt, since the JLL ships aie-opt/aie-translate but not the aiecc driver. The
# module must end up in the `llvm` dialect: aie-translate's mlir-to-llvmir only
# translates llvm-dialect ops, so it is not enough to stop at aie-standard-lowering
# (which leaves the core in scf/arith/memref).
#
# Two phases, concatenated into one aie-opt invocation:
#   1. input-with-addresses: place tiles, lower objectFifos to buffers/locks/BDs,
#      and give the generated buffers their sym_name+address via
#      aie-assign-buffer-addresses (without it standard-lowering aborts with
#      "couldn't get name"); then scf -> cf inside the cores.
#   2. lower-to-llvm: localize locks, normalize address spaces, turn aie.core into
#      a func, then the standard MLIR conversions down to the llvm dialect.
# Feature passes aiecc also runs (cascade/broadcast/multicast, vector-transfer,
# bfp types, ...) are omitted: this scalar single-core design does not use them.
run(`$aie_opt
    --aie-place-tiles
    --aie-canonicalize-device
    --aie-assign-lock-ids
    --aie-objectFifo-stateful-transform=dynamic-objFifos=false
    --aie-assign-bd-ids
    --aie-assign-buffer-addresses
    --aie-scf-to-control-flow
    --aie-localize-locks
    --aie-normalize-address-spaces
    --aie-standard-lowering
    --aiex-standard-lowering
    --convert-aievec-to-llvm
    --canonicalize
    --cse
    --expand-strided-metadata
    --lower-affine
    --arith-expand
    --finalize-memref-to-llvm
    --convert-func-to-llvm=use-bare-ptr-memref-call-conv=true
    --convert-to-llvm
    --convert-vector-to-llvm
    --convert-ub-to-llvm
    --reconcile-unrealized-casts
    --canonicalize
    --cse
    $src_file -o $lowered_mlir`)
println("  ✓ Lowered to the llvm dialect.")

# --------------------------------------------------------------------------
# Step 2: Convert structural physical map to raw LLVM IR text assembly
# --------------------------------------------------------------------------
println("[Step 2] Translating structure into raw LLVM text assembly...")
# The translation is registered as `mlir-to-llvmir` (aie-translate.cpp), which
# wires in the AIE-specific intrinsic translations on top of the standard one.
run(`$aie_translate --mlir-to-llvmir $lowered_mlir -o $llvm_ir_file`)
println("  ✓ LLVM-IR written to disk.")

# --------------------------------------------------------------------------
# Step 3: Compile to NPU Machine Code via Peano Backend
# --------------------------------------------------------------------------
println("[Step 3] Cross-compiling LLVM IR to NPU ELF binary via Peano...")
# The device is npu2, i.e. AIE2p, so the lock intrinsics are llvm.aie2p.* and the
# backend must be selected with --march=aie2p (--march=aie is AIE1 and cannot
# select them). Matches aiecc's llc invocation (tools/aiecc/aiecc.cpp).
run(`$peano_llc --march=aie2p --function-sections -filetype=obj $llvm_ir_file -o $object_file`)

if isfile(object_file)
    println("\n🎉 SUCCESS!")
    println("Generated Hardware Object: ", abspath(object_file))
    println("Binary Size: ", filesize(object_file), " bytes")
end
