#! /bin/sh
# Copyright (C) 2012 Free Software Foundation, Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# Basic tests on the Objective C++ support that don't actually
# require an Objective-C++ compiler.
# See also sister test 'objc-basic.sh'.

. ./defs || exit 1

cat > Makefile.am <<'END'
bin_PROGRAMS = hello
hello_SOURCES = hello.mm
END

$ACLOCAL
AUTOMAKE_fails
grep "'OBJCXX'.* undefined" stderr
grep "add .*'AC_PROG_OBJCXX'" stderr

rm -rf autom4te*.cache

cat >> configure.ac <<'END'
dnl Support for Object C++ was introduced only in Autoconf 2.65.
AC_PREREQ([2.65])
AC_PROG_OBJCXX
END

if $ACLOCAL; then
  : We have a modern enough autoconf, go ahead.
elif test $? -eq 63; then
  skip_ "Object C++ support requires Autoconf 2.65 or later"
else
  exit 1 # Some other aclocal failure.
fi

$AUTOMAKE
$EGREP '^\.SUFFIXES:.* \.mm( |$)' Makefile.in

:
