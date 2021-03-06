cmake_minimum_required (VERSION 2.8.7)
project(ALaDyn2)
enable_language(Fortran)
enable_language(CXX)
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CMAKE_SOURCE_DIR}/cmake/Modules/")

# uncomment the following definition to enable GDB attach to debug while running
# add_definitions(-DENABLE_GDB_ATTACH)

# you can force FFTW if necessary, avoiding MKL (which is preferred on Intel systems)
set(FORCE_FFTW OFF CACHE BOOL "Forcing FFTW libraries")

if (FORCE_FFTW)
  message(STATUS "Forcing FFTW, avoid MKL even if found")
else()
  message(STATUS "MKL is preferred to FFTW, if found")
endif()

# set this variable to true to force static linking (if supported by the compiler)
set(FORCE_STATIC_LINK FALSE CACHE BOOL "Forcing static linking to libraries")

# make sure that the default is a RELEASE
set(default_build_type "Release")
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  message(STATUS "Setting build type to '${default_build_type}' as none was specified.")
  set(CMAKE_BUILD_TYPE "${default_build_type}" CACHE
      STRING "Choose the type of build." FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Release" "MinSizeRel" "RelWithDebInfo")
endif()


get_filename_component (Fortran_COMPILER_NAME ${CMAKE_Fortran_COMPILER} NAME)
if (Fortran_COMPILER_NAME MATCHES "gfortran*")
  string(APPEND CMAKE_CXX_COMPILE_FLAGS " -Wall")
  string(APPEND CMAKE_Fortran_FLAGS_RELEASE " -fdefault-real-8")
  string(APPEND CMAKE_Fortran_FLAGS_DEBUG   " -fdefault-real-8 -Wall -Wextra")
  if (MARCONI_KNL)
    string(APPEND CMAKE_CXX_COMPILE_FLAGS " -mavx512f -mavx512cd -mavx512er -mavx512pf")
    string(APPEND CMAKE_Fortran_FLAGS_RELEASE " -funroll-all-loops  -mavx512f -mavx512cd -mavx512er -mavx512pf -O3")
    string(APPEND CMAKE_Fortran_FLAGS_DEBUG   " -fbacktrace -fbounds-check -mavx512f -mavx512cd -mavx512er -mavx512pf -Og -g")
  else()
    string(APPEND CMAKE_Fortran_FLAGS_RELEASE " -funroll-all-loops -O3")
    string(APPEND CMAKE_Fortran_FLAGS_DEBUG   " -fbacktrace -fbounds-check -Og -g")
  endif()
elseif (Fortran_COMPILER_NAME MATCHES "ifort*" OR Fortran_COMPILER_NAME MATCHES "ftn*")
  set(USING_INTEL_COMPILER TRUE)
  string(APPEND CMAKE_CXX_COMPILE_FLAGS " -diag-enable warn")
  string(APPEND CMAKE_Fortran_FLAGS_RELEASE " -real-size 64")
  string(APPEND CMAKE_Fortran_FLAGS_DEBUG   " -real-size 64 -diag-enable warn")
  if (MARCONI_KNL)
    string(APPEND CMAKE_CXX_COMPILE_FLAGS " -xMIC-AVX512")
    string(APPEND CMAKE_Fortran_FLAGS_RELEASE " -xMIC-AVX512 -O3")
    string(APPEND CMAKE_Fortran_FLAGS_DEBUG   " -xMIC-AVX512 -check all -fpe0 -warn -traceback -debug extended -O0 -g")
    string(APPEND CMAKE_Fortran_LINK_FLAGS " -lstdc++")
    if (NOT FORCE_FFTW)
      string(APPEND CMAKE_Fortran_LINK_FLAGS " -mkl")
    endif()
  else()
    string(APPEND CMAKE_CXX_COMPILE_FLAGS " -axcore-avx-i,SSE4.2")
    string(APPEND CMAKE_Fortran_FLAGS_RELEASE " -axcore-avx-i,SSE4.2 -O3")
    string(APPEND CMAKE_Fortran_FLAGS_DEBUG   " -check all -fpe0 -warn -traceback -debug extended -O0 -g")
    string(APPEND CMAKE_Fortran_LINK_FLAGS " -lstdc++")
    if (NOT FORCE_FFTW)
      string(APPEND CMAKE_Fortran_LINK_FLAGS " -mkl")
    endif()
  endif()
else ()
  if (MARCONI_KNL)
    error ("Unsupported compiler for KNL")
  else()
    message ("CMAKE_Fortran_COMPILER found but unsupported")
    message ("Let's try using it...")
  endif ()
endif ()

if(FORCE_STATIC_LINK)
  string(APPEND CMAKE_Fortran_LINK_FLAGS " -static")
endif()

find_package(OpenMP)
if(OPENMP_FOUND)
	set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${OpenMP_C_FLAGS}")
	set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${OpenMP_CXX_FLAGS}")
	set(CMAKE_Fortran_FLAGS_RELEASE "${CMAKE_Fortran_FLAGS_RELEASE} ${OpenMP_Fortran_FLAGS}")
	set(CMAKE_Fortran_FLAGS_DEBUG "${CMAKE_Fortran_FLAGS_DEBUG} ${OpenMP_Fortran_FLAGS}")
	set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_CXX_FLAGS} ${OpenMP_EXE_LINKER_FLAGS}")
endif()

find_package(Boost COMPONENTS system filesystem REQUIRED)
find_package(MPI REQUIRED)
if (USING_INTEL_COMPILER AND NOT FORCE_FFTW)
  find_package(MKL REQUIRED)
  set(MKL_FFTW_INCLUDE_DIR "${MKL_INCLUDE_DIR}/fftw/")
else()
  find_package(FFTW REQUIRED)
endif()

string(APPEND CMAKE_CXX_COMPILE_FLAGS " ${MPI_COMPILE_FLAGS}")
string(APPEND CMAKE_CXX_LINK_FLAGS " ${MPI_LINK_FLAGS}")
string(APPEND CMAKE_Fortran_COMPILE_FLAGS " ${MPI_COMPILE_FLAGS} ${MPI_Fortran_COMPILE_FLAGS}")
string(APPEND CMAKE_Fortran_LINK_FLAGS " ${MPI_LINK_FLAGS} ${MPI_Fortran_LINK_FLAGS}")

include_directories(${OTHER_INCLUDE_DIR} ${MPI_INCLUDE_PATH} ${MPI_Fortran_INCLUDE_PATH} ${FFTW_INCLUDE_DIR} ${MKL_INCLUDE_DIR} ${MKL_FFTW_INCLUDE_DIR} ${Boost_INCLUDE_DIR})
link_directories(${OTHER_LINK_DIR})

add_executable (ALaDyn
  src/ALaDyn.F90
  src/precision_def.F90
  src/mpi_var.f90
  src/phys_param.f90
  src/grid_and_particles.f90
  src/code_util.f90
  src/system_utilities.f90
  src/util.f90
  src/fft_lib.F90
  src/struct_def.f90
  src/grid_param.f90
  src/control_bunch_input.f90
  src/ionz_data.f90
  src/ionize.f90
  src/pstruct_data.F90
  src/fstruct_data.f90
  src/psolv.f90
  src/all_param.f90
  src/particles.F90
  src/parallel.F90
  src/pic_rutil.f90
  src/der_lib.f90
  src/grid_fields.F90
  src/pdf_moments.f90
  src/pic_in.f90
  src/pic_out.f90
  src/pic_out_util.f90
  src/pic_dump.f90
  src/pic_evolve_in_time.f90
  src/read_input.f90
)

add_library(cpp_folder_tree STATIC src/cpp_folder_tree.cpp)
add_library(find_last_addr STATIC src/find_last_addr.cpp)
add_library(enable_gdb_attach STATIC src/enable_gdb_attach.cpp)

target_link_libraries(ALaDyn
  cpp_folder_tree
  find_last_addr
  enable_gdb_attach
  ${MPI_Fortran_LIBRARIES}
  ${MPI_LIBRARIES}
  ${Boost_LIBRARIES}
)


if (NOT USING_INTEL_COMPILER OR FORCE_FFTW)
  target_link_libraries(ALaDyn ${FFTW_LIBRARY})
endif()

set_target_properties(ALaDyn PROPERTIES LINKER_LANGUAGE Fortran)

install (TARGETS ALaDyn DESTINATION ${CMAKE_SOURCE_DIR}/bin/)
