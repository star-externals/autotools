#!/bin/sh
# Copyright (C) 2009-2012 Free Software Foundation, Inc.
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
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Check user extensibility of silent-rules mode.

. ./defs || exit 1

cat >>configure.ac <<'EOF'
AM_SILENT_RULES
AC_CONFIG_FILES([sub/Makefile])
AC_OUTPUT
EOF

# We delegate all the work to the subdir makefile.  This is done
# to ensure any command-line setting of $(V) gets correctly passed
# down to recursive make invocations.
echo SUBDIRS = sub > Makefile.am

mkdir sub
cat > sub/Makefile.am <<'EOF'
my_verbose = $(my_verbose_$(V))
my_verbose_ = $(my_verbose_$(AM_DEFAULT_VERBOSITY))
my_verbose_0 = @echo " XGEN    $@";

all-local: foo gen-headers

list = 0 1 2
.PHONY: gen-headers
gen-headers:
	@headers=`for i in $(list); do echo sub/$$i.h; done`; \
	if $(AM_V_P); then set -x; else \
	  echo " GEN     [headers]"; \
	fi; \
	rm -f $$headers || exit 1; \
## Only fake header generation.
	: generate-header --flags $$headers

foo: foo.in
	$(my_verbose)cp $(srcdir)/foo.in $@
EXTRA_DIST = foo.in
CLEANFILES = foo
EOF

: > sub/foo.in

$ACLOCAL
$AUTOMAKE --add-missing
$AUTOCONF

do_check ()
{
  case ${1-} in
    --silent) silent=:;;
    --verbose) silent=false;;
    *) fatal_ "do_check(): incorrect usage";;
  esac
  shift
  $MAKE clean
  $MAKE ${1+"$@"} >output 2>&1 || { cat output; exit 1; }
  sed 's/^/  /' output
  if $silent; then
    $FGREP 'cp ' output && exit 1
    $FGREP 'generate-header' output && exit 1
    $FGREP 'rm -f' output && exit 1
    grep '[012]\.h' output && exit 1
    grep '^ XGEN    foo$' output
    grep '^ GEN     \[headers\]$' output
  else
    $FGREP 'GEN ' output && exit 1
    $FGREP 'cp ./foo.in foo' output
    $FGREP "rm -f sub/0.h sub/1.h sub/2.h" output
    $FGREP "generate-header --flags sub/0.h sub/1.h sub/2.h" output
  fi
}

./configure --enable-silent-rules
do_check --silent
do_check --verbose V=1

$MAKE distclean

./configure --disable-silent-rules
do_check --verbose
do_check --silent V=0

$MAKE distclean

:
