# Copyright (c) 2025 Hartmut Kaiser
#
# SPDX-License-Identifier: BSL-1.0
# Distributed under the Boost Software License, Version 1.0. (See accompanying
# file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)

include(HPX_AddCompileFlag)
include(HPX_Message)
include(CheckCXXCompilerFlag)

if(NOT HPX_WITH_CXX_MODULES)
  return()
endif()

# Unfortunately, different compilers expect different file extensions for the
# C++ module definition files.
if(MSVC)
  set(HPX_MODULE_INTERFACE_EXTENSION ".ixx")
elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang" OR CMAKE_CXX_COMPILER_ID MATCHES
                                                "AppleClang"
)
  set(HPX_MODULE_INTERFACE_EXTENSION ".cppm")
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
  # GCC 14+ uses .cxx for module interface units
  set(HPX_MODULE_INTERFACE_EXTENSION ".cxx")
  # GCC 14 requires -fmodules-ts to enable C++20 named modules
  # even when -std=c++20 is set (this is a known GCC limitation)
  add_compile_options($<$<COMPILE_LANGUAGE:CXX>:-fmodules-ts>)
else()
  hpx_error(
    "C++ modules are not supported for the used compiler ('${CMAKE_CXX_COMPILER_ID}')"
  )
endif()

# hpx_configure_module_producer(<producer> [MODULE_OUT_DIR <dir>])
#
# * Ensures a stable module output dir for producer target
# * Adds compiler flags to write module cache there (Clang/GCC)
# * Creates an interface target '<producer>_if' for consumers to link to
function(hpx_configure_module_producer producer)
  if(NOT TARGET ${producer})
    hpx_error("hpx_configure_module_producer: target '${producer}' not found")
  endif()

  # parse optional args
  set(options)
  set(one_value_args MODULE_OUT_DIR)
  set(multi_value_args)
  cmake_parse_arguments(
    _args "${options}" "${one_value_args}" "${multi_value_args}" ${ARGN}
  )

  if(_args_MODULE_OUT_DIR)
    set(_moddir "${_args_MODULE_OUT_DIR}")
  else()
    set(_moddir "$<TARGET_FILE_DIR:${producer}>")
  endif()

  set(_iface "${producer}_if")
  if(NOT TARGET ${_iface})
    add_library(${_iface} INTERFACE)
    target_link_libraries(${_iface} INTERFACE ${producer})
  endif()

  # Set a property so consumers can query the BMI directory via
  # get_target_property.
  set_target_properties(
    ${_iface} PROPERTIES INTERFACE_EXPORT_MODULE_DIR "${_moddir}"
  )

  # Make sure consumers scan for the BMI
  set_target_properties(${_iface} PROPERTIES INTERFACE_CXX_SCAN_FOR_MODULES On)

  if(MSVC)
    # MSVC: CMake/MSVC handle IFCs automatically; create a target for
    # convenience, consumers can link to this to get ordering and include info
    return()
  endif()

  # Compiler-specific flags to instruct where to write module cache
  if(CMAKE_CXX_COMPILER_ID MATCHES "Clang" OR CMAKE_CXX_COMPILER_ID MATCHES
                                              "AppleClang"
  )
    # Clang common flags
    target_compile_options(${producer} PRIVATE "-fmodule-output=${_moddir}")
  elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    # GCC 14+: C++20 named modules require -fmodules-ts even when -std=c++20 is set.
    # Unlike Clang (-fmodule-output=) or MSVC (automatic IFC), GCC uses the
    # module mapper protocol. With CMake 3.29+ and Ninja, CMake's native
    # CXX_SCAN_FOR_MODULES handles the dependency graph and build ordering.
    # We only need to explicitly add -fmodules-ts; GCC will write .gcm files
    # to gcm.cache/ relative to the compiler's working directory automatically.
    check_cxx_compiler_flag("-fmodules-ts" HPX_GCC_SUPPORTS_FMODULES_TS)
    if(HPX_GCC_SUPPORTS_FMODULES_TS)
      target_compile_options(${producer} PRIVATE "-fmodules-ts")
      hpx_info(
        "GCC module support: '-fmodules-ts' enabled for producer '${producer}'. "
        "GCC will write .gcm files to gcm.cache/ relative to the build directory."
      )
    else()
      hpx_error(
        "hpx_configure_module_producer: GCC >= 14 is required for C++ module "
        "support. The detected compiler does not support '-fmodules-ts'. "
        "Please upgrade to GCC 14 or later."
      )
    endif()
  else()
    hpx_warn(
      "hpx_configure_module_producer: unknown compiler '${CMAKE_CXX_COMPILER_ID}'; "
      "exposing EXPORT_MODULE_DIR='${_moddir}' for manual handling"
    )
  endif()
endfunction()

# hpx_configure_module_consumer(<consumer> <producer>])
#
# * propagates module-related properties from producer interface target
# * sets necessary consumer compiler flags for clang and gcc
function(hpx_configure_module_consumer consumer producer)
  if(NOT TARGET ${consumer})
    hpx_error("hpx_configure_module_consumer: target '${consumer}' not found")
  endif()
  if(NOT TARGET ${producer})
    hpx_error("hpx_configure_module_consumer: target '${producer}' not found")
  endif()

  target_link_libraries(${consumer} PRIVATE ${producer})
  get_target_property(_scan ${producer} INTERFACE_CXX_SCAN_FOR_MODULES)
  if(_scan)
    set_target_properties(${consumer} PROPERTIES CXX_SCAN_FOR_MODULES ${_scan})
  endif()

  get_target_property(_module_dir ${producer} INTERFACE_EXPORT_MODULE_DIR)
  if(_module_dir)
    if(MSVC)
      return()
    elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang" OR CMAKE_CXX_COMPILER_ID
                                                    MATCHES "AppleClang"
    )
      target_compile_options(
        ${consumer} PRIVATE "-fprebuilt-module-path=${_module_dir}"
      )
      get_target_property(_type ${consumer} TYPE)
      if((_type STREQUAL "SHARED_LIBRARY") OR (_type STREQUAL "EXECUTABLE"))
        target_link_options(${consumer} PRIVATE "-fuse-ld=lld")
        target_link_options(${consumer} PRIVATE "-Wl,--error-limit=0")
      endif()
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
      # GCC 14+: Only -fmodules-ts is needed for consumers.
      # CMake's native module scanning handles build ordering and discovery.
      # -fprebuilt-module-path= is Clang-only and NOT supported by GCC.
      if(HPX_GCC_SUPPORTS_FMODULES_TS)
        target_compile_options(${consumer} PRIVATE "-fmodules-ts")
      else()
        hpx_error(
          "hpx_configure_module_consumer: GCC >= 14 is required for C++ module "
          "support. Please upgrade to GCC 14 or later."
        )
      endif()
    else()
      hpx_warn(
        "hpx_configure_module_consumer: unknown compiler '${CMAKE_CXX_COMPILER_ID}'"
      )
    endif()
  endif()
endfunction()
