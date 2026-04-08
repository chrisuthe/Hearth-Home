cmake_minimum_required(VERSION 3.13)
project(sendspin_flac LANGUAGES C)

# Try to find libFLAC via pkg-config first, then direct search.
set(FLAC_AVAILABLE FALSE)

find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
  pkg_check_modules(FLAC QUIET IMPORTED_TARGET flac)
  if(FLAC_FOUND)
    set(FLAC_AVAILABLE TRUE)
  endif()
endif()

if(NOT FLAC_AVAILABLE)
  # Try to find the header directly
  find_path(FLAC_INCLUDE_DIR FLAC/stream_decoder.h)
  find_library(FLAC_LIBRARY NAMES FLAC flac)
  if(FLAC_INCLUDE_DIR AND FLAC_LIBRARY)
    set(FLAC_AVAILABLE TRUE)
  endif()
endif()

if(NOT FLAC_AVAILABLE)
  message(WARNING "libFLAC not found — sendspin_flac will NOT be built. "
    "Install libflac-dev (Linux) or provide FLAC via vcpkg (Windows).")
  # Create an INTERFACE target so dependents don't break
  add_library(sendspin_flac INTERFACE)
  return()
endif()

add_library(sendspin_flac SHARED sendspin_flac.c)

if(FLAC_FOUND AND TARGET PkgConfig::FLAC)
  target_link_libraries(sendspin_flac PRIVATE PkgConfig::FLAC)
else()
  target_include_directories(sendspin_flac PRIVATE "${FLAC_INCLUDE_DIR}")
  target_link_libraries(sendspin_flac PRIVATE "${FLAC_LIBRARY}")
endif()

target_include_directories(sendspin_flac PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")

if(NOT WIN32)
  set_target_properties(sendspin_flac PROPERTIES
    C_VISIBILITY_PRESET hidden)
endif()
