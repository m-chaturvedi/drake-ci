# Select appropriate compiler version
set(DASHBOARD_GNU_COMPILER_SUFFIX "")
set(DASHBOARD_CLANG_COMPILER_SUFFIX "")
if(DASHBOARD_UNIX_DISTRIBUTION STREQUAL "Ubuntu")
  if(DASHBOARD_UNIX_DISTRIBUTION_VERSION VERSION_LESS 16.04)
    set(DASHBOARD_GNU_COMPILER_SUFFIX "-4.9")
    set(DASHBOARD_CLANG_COMPILER_SUFFIX "-3.9")
  else()
    set(DASHBOARD_GNU_COMPILER_SUFFIX "-5")
    set(DASHBOARD_CLANG_COMPILER_SUFFIX "-3.9")
  endif()
endif()

# Select appropriate compiler(s)
set(ENV{F77} "gfortran${DASHBOARD_GNU_COMPILER_SUFFIX}")
set(ENV{FC} "gfortran${DASHBOARD_GNU_COMPILER_SUFFIX}")

if(COMPILER STREQUAL "clang")
  set(ENV{CC} "clang${DASHBOARD_CLANG_COMPILER_SUFFIX}")
  set(ENV{CXX} "clang++${DASHBOARD_CLANG_COMPILER_SUFFIX}")
elseif(COMPILER STREQUAL "gcc")
  set(ENV{CC} "gcc${DASHBOARD_GNU_COMPILER_SUFFIX}")
  set(ENV{CXX} "g++${DASHBOARD_GNU_COMPILER_SUFFIX}")
else()
  fatal("unknown compiler '${COMPILER}'")
endif()

