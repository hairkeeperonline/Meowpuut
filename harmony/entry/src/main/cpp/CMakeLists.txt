cmake_minimum_required(VERSION 3.5.0)
project(meowpuut_napi)

# 顶层 DevEco 工程通过 `-DMEOWPUUT_ROOT=<仓库根>` 传入，用于定位 Rust 静态库输出。
# 参考 Android 版：scripts/build-harmony.sh 先把库编到 .build/rust/harmony/<abi>/libmeowpuut_ffi.a。
# 词典由 ArkTS 侧用 resourceManager 读取，本库不需要 rawfile 原生依赖。
# 未显式传入时，从本文件位置自动推导仓库根（…/harmony/entry/src/main/cpp → 上 5 级）。

if(NOT DEFINED MEOWPUUT_ROOT)
  get_filename_component(_cpp ${CMAKE_CURRENT_SOURCE_DIR} ABSOLUTE)
  get_filename_component(MEOWPUUT_ROOT "${_cpp}/../../../../../" ABSOLUTE)
endif()

set(NATIVE_LIBRARY_OUTPUT ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libmeowpuut_napi.so CACHE STRING "" FORCE)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/${OHOS_ARCH})

# OHOS_ARCH 由 DevEco 定义：arm64-v8a、x86_64。
if("${OHOS_ARCH}" STREQUAL "arm64-v8a")
  set(MEOWPUUT_RUST_LIB "${MEOWPUUT_ROOT}/.build/rust/harmony/arm64-v8a/libmeowpuut_ffi.a")
elseif("${OHOS_ARCH}" STREQUAL "x86_64")
  set(MEOWPUUT_RUST_LIB "${MEOWPUUT_ROOT}/.build/rust/harmony/x86_64/libmeowpuut_ffi.a")
else()
  message(FATAL_ERROR "仅支持 arm64-v8a 与 x86_64：OHOS_ARCH=${OHOS_ARCH}")
endif()

# 头文件可能在 Engine/crates/meowpuut-ffi/include（submodule）或旧路径 crates/meowpuut-ffi/include。
set(_FFI_INCLUDE "")
if(EXISTS "${MEOWPUUT_ROOT}/Engine/crates/meowpuut-ffi/include/meowpuut.h")
  set(_FFI_INCLUDE "${MEOWPUUT_ROOT}/Engine/crates/meowpuut-ffi/include")
elseif(EXISTS "${MEOWPUUT_ROOT}/crates/meowpuut-ffi/include/meowpuut.h")
  set(_FFI_INCLUDE "${MEOWPUUT_ROOT}/crates/meowpuut-ffi/include")
endif()

# 如果 Rust 引擎尚未编译（缺少头文件），生成 stub .so 让 ArkTS 编译能通过。
if("${_FFI_INCLUDE}" STREQUAL "")
  message(WARNING "Rust 引擎未就绪（缺 ${MEOWPUUT_RUST_LIB} 或 meowpuut.h），生成 stub .so 供 ArkTS 编译检查")
  file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/stub_napi.cpp"
    "// Auto-generated stub: Rust engine not yet available.\n"
    "#include <napi/native_api.h>\n"
    "static napi_value Stub(napi_env env, napi_callback_info info) { return nullptr; }\n"
    "static napi_module _module = { .nm_version = 1, .nm_flags = 0, .nm_filename = __FILE__,\n"
    "  .nm_register_func = [](napi_env e, napi_value ex) -> napi_value {\n"
    "    napi_property_descriptor desc[] = { { \"stub\", nullptr, Stub, nullptr, nullptr, nullptr, napi_default, nullptr } };\n"
    "    napi_define_properties(e, ex, 1, desc); return ex;\n"
    "  }, .nm_modname = \"meowpuut_napi\", .nm_priv = nullptr, .reserved = {0} };\n"
    "extern \"C\" __attribute__((constructor)) void RegisterModule(void) { napi_module_register(&_module); }\n"
  )
  add_library(meowpuut_napi SHARED "${CMAKE_CURRENT_BINARY_DIR}/stub_napi.cpp")
  target_link_libraries(meowpuut_napi PRIVATE libace_napi.z.so)
else()
  add_library(meowpuut_ffi STATIC IMPORTED)
  set_target_properties(meowpuut_ffi PROPERTIES IMPORTED_LOCATION "${MEOWPUUT_RUST_LIB}")

  add_library(meowpuut_napi SHARED napi_init.cpp)
  target_include_directories(meowpuut_napi PRIVATE "${_FFI_INCLUDE}")
  target_compile_options(meowpuut_napi PRIVATE -Wall -Wextra -O2 -fPIC)
  target_link_libraries(meowpuut_napi PRIVATE meowpuut_ffi libace_napi.z.so)
endif()