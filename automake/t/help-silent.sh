#! /bin/sh
# Copyright (C) 2010-2012 Free Software Foundation, Inc.
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

# Make sure that our macro 'AM_SILENT_RULES' adds proper text to
# the configure help screen.

. ./defs || exit 1

cat > configure.ac <<END
AC_INIT([$me], [1.0])
AM_SILENT_RULES
END

$ACLOCAL

mv -f configure.ac configure.tmpl

for args in '' '([])' '([yes])' '([no])'; do
  sed "s/AM_SILENT_RULES.*/&$args/" configure.tmpl >configure.ac
  cat configure.ac
  $AUTOCONF --force
  grep_configure_help --enable-silent-rules \
                      ' less verbose build.*\(undo.*"make V=1".*\)'
  grep_configure_help --disable-silent-rules \
                      ' verbose build.*\(undo.*"make V=0".*\)'
done

:
