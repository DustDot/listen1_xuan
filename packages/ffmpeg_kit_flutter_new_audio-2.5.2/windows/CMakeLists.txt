cmake_minimum_required(VERSION 3.14)

# Must match the pubspec package name so the generated public header lands at
# include/ffmpeg_kit_flutter_new_audio/ where generated_plugin_registrant.cc expects it.
set(PROJECT_NAME "ffmpeg_kit_flutter_new_audio")
project(${PROJECT_NAME} LANGUAGES CXX)

# Must match the Flutter plugin target name derived from the pubspec package
# name (ffmpeg_kit_flutter_new_audio): generated_plugins.cmake links ${plugin}_plugin
# and bundles ${plugin}_bundled_libraries.
set(PLUGIN_NAME "ffmpeg_kit_flutter_new_audio_plugin")

add_library(${PLUGIN_NAME} SHARED
  "ffmpeg_kit_flutter_plugin.cpp"
  "ffmpeg_kit_flutter_plugin_c_api.cpp"
)

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_STANDARD 17
  CXX_VISIBILITY_PRESET hidden)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

set(PUBLIC_HEADER_DIR "${CMAKE_CURRENT_BINARY_DIR}/include/${PROJECT_NAME}")
file(MAKE_DIRECTORY "${PUBLIC_HEADER_DIR}")
file(WRITE "${PUBLIC_HEADER_DIR}/f_fmpeg_kit_flutter_plugin.h" [=[
#ifndef FLUTTER_PLUGIN_FFMPEG_KIT_FLUTTER_PLUGIN_C_API_H_
#define FLUTTER_PLUGIN_FFMPEG_KIT_FLUTTER_PLUGIN_C_API_H_

#include <flutter_plugin_registrar.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

FLUTTER_PLUGIN_EXPORT void FFmpegKitFlutterPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#if defined(__cplusplus)
}
#endif

#endif  // FLUTTER_PLUGIN_FFMPEG_KIT_FLUTTER_PLUGIN_C_API_H_
]=])

target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_BINARY_DIR}")
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_BINARY_DIR}/include")

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

if(CMAKE_SYSTEM_PROCESSOR STREQUAL "AMD64" OR CMAKE_SYSTEM_PROCESSOR STREQUAL "x86_64")
  set(FFMPEGKIT_ARCH "x86_64")
elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "X86" OR CMAKE_SYSTEM_PROCESSOR STREQUAL "i686")
  set(FFMPEGKIT_ARCH "i686")
elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "ARM64" OR CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
  set(FFMPEGKIT_ARCH "aarch64")
else()
  set(FFMPEGKIT_ARCH "x86_64")
endif()

# Unpack into the app's build tree, NOT the plugin source directory. When the
# plugin is resolved from the pub cache, Flutter points
# windows/flutter/ephemeral/.plugin_symlinks/<plugin> at the cached package, so
# ${CMAKE_CURRENT_SOURCE_DIR} lives inside the pub cache. Extracting there makes
# `cmake -E tar` fail outright, because libarchive refuses to write through a
# symlink (#165):
#
#   Cannot extract through symlink ...\.plugin_symlinks\<plugin>
#
# It also wrote the unpacked DLLs into a directory shared by every project on
# the machine, which `flutter clean` never removes.
#
# CMAKE_CURRENT_BINARY_DIR is per-project and per-configuration, so it is
# cleaned normally and is never reached through a symlink.
set(FFMPEGKIT_PREBUILT_DIR "${CMAKE_CURRENT_BINARY_DIR}/ffmpeg-kit")
message(STATUS "FFmpegKit prebuilt dir: ${FFMPEGKIT_PREBUILT_DIR} (arch: ${FFMPEGKIT_ARCH})")

# FFmpegKit package variant to consume.
#
# This branch ships the "audio" variant, so the default is "audio": the
# audio-codec set (no GPL) — lame, libilbc, libvorbis, opencore-amr, opus, shine,
# soxr, speex, twolame. The variant name is an emergent property of that library
# set (see windows/src/Packages.cpp).
#   * The CANONICAL audio build (reports "audio") is produced by
#     ffmpeg-kit/build-windows-audio.sh — consume a self-built bundle by setting
#     FFMPEGKIT_LOCAL_DIR.
# audio contains no GPL components and stays under the default LGPL 3.0 license.
set(FFMPEGKIT_PACKAGE "audio" CACHE STRING "FFmpegKit variant: audio, video, min, https, full, ...")
set(FFMPEGKIT_VERSION "8.1.2" CACHE STRING "FFmpegKit release version")
set(FFMPEGKIT_LOCAL_DIR "" CACHE PATH "Path to a locally-built bundle (dir containing bin/ [+ include/]) to override the bundled archive")

# Allow pointing at a local bundle via the environment too, so it can be set
# without forwarding -D through `flutter run/build` (which inherits the env):
#   set FFMPEGKIT_LOCAL_DIR=C:/.../ffmpeg-kit/prebuilt/bundle-windows-x86_64/ffmpeg-kit
if(NOT FFMPEGKIT_LOCAL_DIR AND DEFINED ENV{FFMPEGKIT_LOCAL_DIR})
  set(FFMPEGKIT_LOCAL_DIR "$ENV{FFMPEGKIT_LOCAL_DIR}")
endif()

# The audio archive is checked into this local Flutter package. Windows builds
# must never need GitHub release assets during CMake configuration.
set(FFMPEGKIT_ZIP_NAME "ffmpeg-kit-windows-${FFMPEGKIT_ARCH}-${FFMPEGKIT_PACKAGE}-${FFMPEGKIT_VERSION}.zip")
set(FFMPEGKIT_BUNDLED_ZIP "${CMAKE_CURRENT_SOURCE_DIR}/prebuilt/${FFMPEGKIT_ZIP_NAME}")
set(FFMPEGKIT_BUNDLED_SHA256 "dcd9eabb067a3ef34ae8e7c1d01bf06592714978496e3b03c9015d2dc21ea94d")

# Marker recording which bundle is currently installed, so changing
# FFMPEGKIT_PACKAGE / FFMPEGKIT_LOCAL_DIR triggers a clean extraction.
set(FFMPEGKIT_MARKER "${FFMPEGKIT_PREBUILT_DIR}/bin/.ffmpegkit_variant")
if(FFMPEGKIT_LOCAL_DIR)
  set(FFMPEGKIT_WANT "local:${FFMPEGKIT_LOCAL_DIR}")
else()
  set(FFMPEGKIT_WANT "bundled:${FFMPEGKIT_BUNDLED_SHA256}")
endif()
set(FFMPEGKIT_HAVE "")
if(EXISTS "${FFMPEGKIT_MARKER}")
  file(READ "${FFMPEGKIT_MARKER}" FFMPEGKIT_HAVE)
  string(STRIP "${FFMPEGKIT_HAVE}" FFMPEGKIT_HAVE)
endif()

if(NOT "${FFMPEGKIT_HAVE}" STREQUAL "${FFMPEGKIT_WANT}")
  file(REMOVE_RECURSE "${FFMPEGKIT_PREBUILT_DIR}/bin")
  file(MAKE_DIRECTORY "${FFMPEGKIT_PREBUILT_DIR}")
  if(FFMPEGKIT_LOCAL_DIR)
    if(NOT EXISTS "${FFMPEGKIT_LOCAL_DIR}/bin/libffmpegkit.dll")
      message(FATAL_ERROR "FFMPEGKIT_LOCAL_DIR=${FFMPEGKIT_LOCAL_DIR} has no bin/libffmpegkit.dll")
    endif()
    message(STATUS "FFmpegKit: installing local bundle from ${FFMPEGKIT_LOCAL_DIR}")
    file(COPY "${FFMPEGKIT_LOCAL_DIR}/bin" DESTINATION "${FFMPEGKIT_PREBUILT_DIR}")
    if(EXISTS "${FFMPEGKIT_LOCAL_DIR}/include")
      file(REMOVE_RECURSE "${FFMPEGKIT_PREBUILT_DIR}/include")
      file(COPY "${FFMPEGKIT_LOCAL_DIR}/include" DESTINATION "${FFMPEGKIT_PREBUILT_DIR}")
    endif()
  else()
    if(NOT EXISTS "${FFMPEGKIT_BUNDLED_ZIP}")
      message(FATAL_ERROR
        "Bundled FFmpegKit archive is missing: ${FFMPEGKIT_BUNDLED_ZIP}. "
        "Restore packages/ffmpeg_kit_flutter_new_audio-2.5.2/windows/prebuilt; "
        "this build intentionally does not download native libraries.")
    endif()
    file(SHA256 "${FFMPEGKIT_BUNDLED_ZIP}" FFMPEGKIT_BUNDLED_ACTUAL_SHA256)
    if(NOT "${FFMPEGKIT_BUNDLED_ACTUAL_SHA256}" STREQUAL "${FFMPEGKIT_BUNDLED_SHA256}")
      message(FATAL_ERROR
        "Bundled FFmpegKit archive checksum mismatch. Expected "
        "${FFMPEGKIT_BUNDLED_SHA256}, got ${FFMPEGKIT_BUNDLED_ACTUAL_SHA256}")
    endif()
    message(STATUS "FFmpegKit: extracting bundled ${FFMPEGKIT_PACKAGE} archive")
    execute_process(
      COMMAND ${CMAKE_COMMAND} -E tar xf "${FFMPEGKIT_BUNDLED_ZIP}"
      WORKING_DIRECTORY "${FFMPEGKIT_PREBUILT_DIR}"
      RESULT_VARIABLE FFMPEGKIT_UNZIP_RESULT
    )
    if(NOT FFMPEGKIT_UNZIP_RESULT EQUAL 0)
      message(FATAL_ERROR "Failed to extract bundled FFmpegKit archive")
    endif()
  endif()
  file(WRITE "${FFMPEGKIT_MARKER}" "${FFMPEGKIT_WANT}\n")
  message(STATUS "FFmpegKit ${FFMPEGKIT_WANT} ready")
endif()

# Bundle every DLL shipped in the prebuilt bin/. The audio codecs link statically
# into the av* DLLs, so bin/ is just the av*/libffmpegkit DLLs plus the MinGW
# runtime; globbing is robust to FFmpeg soname bumps (avcodec-61 -> 62, etc.)
# without editing this list.
file(GLOB FFMPEGKIT_DLLS "${FFMPEGKIT_PREBUILT_DIR}/bin/*.dll")
if(NOT FFMPEGKIT_DLLS)
  message(FATAL_ERROR "FFmpegKit: no DLLs found in ${FFMPEGKIT_PREBUILT_DIR}/bin")
endif()

# MinGW-compiled DLLs ship with HIGH_ENTROPY_VA + DYNAMIC_BASE enabled and
# many share the same preferred ImageBase (0x180000000). When ASLR is on, or
# when overlapping DLLs force the loader to rebase, modules land far apart
# in 64-bit address space and MinGW's 32-bit pseudo-relocations overflow.
#
# Fix: clear ASLR flags and rebase every DLL into a compact, non-overlapping
# range starting at 0x10000000 so pseudo-relocs stay within +-2GB.
get_filename_component(MSVC_TOOLS_DIR "${CMAKE_CXX_COMPILER}" DIRECTORY)
find_program(EDITBIN_EXECUTABLE editbin HINTS "${MSVC_TOOLS_DIR}" REQUIRED)

add_custom_command(
    OUTPUT "${FFMPEGKIT_PREBUILT_DIR}/bin/.high_entropy_patched"
    COMMAND "${EDITBIN_EXECUTABLE}" /NOLOGO /HIGHENTROPYVA:NO /DYNAMICBASE:NO /REBASE:BASE=0x10000000 ${FFMPEGKIT_DLLS}
    COMMAND ${CMAKE_COMMAND} -E touch "${FFMPEGKIT_PREBUILT_DIR}/bin/.high_entropy_patched"
    DEPENDS ${FFMPEGKIT_DLLS}
    COMMENT "Patching MinGW FFmpegKit DLLs (ASLR off + rebase)"
)
add_custom_target(patch_ffmpegkit_dlls DEPENDS "${FFMPEGKIT_PREBUILT_DIR}/bin/.high_entropy_patched")
add_dependencies(${PLUGIN_NAME} patch_ffmpegkit_dlls)

set(ffmpeg_kit_flutter_new_audio_bundled_libraries
  ${FFMPEGKIT_DLLS}
  PARENT_SCOPE
)
