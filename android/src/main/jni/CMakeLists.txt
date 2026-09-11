cmake_minimum_required(VERSION 3.13)
set(CMAKE_VERBOSE_MAKEFILE on)

add_compile_options(
  -fexceptions
  -frtti
  -O2
  -Wno-unused-parameter
)

# This file is at android/src/main/jni/; resolve the sibling build directory
# where the react-native gradle plugin writes codegen outputs.
get_filename_component(LIBRARY_ANDROID_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)
set(CODEGEN_JNI "${LIBRARY_ANDROID_DIR}/build/generated/source/codegen/jni")

file(GLOB react_codegen_SRCS CONFIGURE_DEPENDS
  "${CODEGEN_JNI}/*.cpp"
  "${CODEGEN_JNI}/react/renderer/components/rnpdf/*.cpp"
)

# Build as SHARED (not OBJECT) so autolinking can call target_link_libraries
# on this target from the parent CMake project scope without errors.
add_library(react_codegen_rnpdf SHARED ${react_codegen_SRCS})

target_include_directories(react_codegen_rnpdf
  PUBLIC
    "${CODEGEN_JNI}"
    "${CODEGEN_JNI}/react/renderer/components/rnpdf"
)

find_package(ReactAndroid REQUIRED CONFIG)
find_package(fbjni REQUIRED CONFIG)

target_link_libraries(react_codegen_rnpdf
  fbjni::fbjni
  ReactAndroid::jsi
  ReactAndroid::reactnative
)
