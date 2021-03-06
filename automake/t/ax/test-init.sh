# -*- shell-script -*-
#
# Copyright (C) 1996-2012 Free Software Foundation, Inc.
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

########################################################
###  IMPORTANT NOTE: keep this file 'set -e' clean.  ###
########################################################

# Enable the errexit shell flag early.
set -e


## --------------------- ##
##  Early sanity checks. ##
## --------------------- ##

# Ensure $am_top_srcdir is set correctly.
test -f "$am_top_srcdir/defs-static.in" || {
   echo "$me: $am_top_srcdir/defs-static.in not found," \
        "check \$am_top_srcdir" >&2
   exit 99
}

# Ensure $am_top_builddir is set correctly.
test -f "$am_top_builddir/defs-static" || {
   echo "$me: $am_top_builddir/defs-static not found," \
        "check \$am_top_builddir" >&2
   exit 99
}


## ------------------ ##
##  Early variables.  ##
## ------------------ ##

# A single whitespace character.
sp=' '
# A tabulation character.
tab='	'
# A newline character.
nl='
'
# A literal escape character.  Used by test checking colored output.
esc=''

# As autoconf-generated configure scripts do, ensure that IFS
# is defined initially, so that saving and restoring $IFS works.
IFS=$sp$tab$nl


## ----------------------- ##
##  Early debugging info.  ##
## ----------------------- ##

echo "Running from installcheck: $am_running_installcheck"
echo "Using TAP: $am_using_tap"
echo "PATH = $PATH"


## ---------------------- ##
##  Environment cleanup.  ##
## ---------------------- ##

# Temporarily disable this, since some shells (e.g., older version
# of Bash) can return a non-zero exit status upon the when a non-set
# variable is unset.
set +e

# Unset some make-related variables that may cause $MAKE to act like
# a recursively invoked sub-make.  Any $MAKE invocation in a test is
# conceptually an independent invocation, not part of the main
# 'automake' build.
unset MFLAGS MAKEFLAGS AM_MAKEFLAGS MAKELEVEL
unset __MKLVL__ MAKE_JOBS_FIFO                     # For BSD make.
unset DMAKE_CHILD DMAKE_DEF_PRINTED DMAKE_MAX_JOBS # For Solaris dmake.
# Unset verbosity flag.
unset V
# Also unset variables that will let "make -e install" divert
# files into unwanted directories.
unset DESTDIR
unset prefix exec_prefix bindir datarootdir datadir docdir dvidir
unset htmldir includedir infodir libdir libexecdir localedir mandir
unset oldincludedir pdfdir psdir sbindir sharedstatedir sysconfdir
# Unset variables that might change the "make distcheck" behaviour.
unset DISTCHECK_CONFIGURE_FLAGS AM_DISTCHECK_CONFIGURE_FLAGS
# Used by install rules for info files.
unset AM_UPDATE_INFO_DIR
# The tests call "make -e" but we do not want $srcdir from the environment
# to override the definition from the Makefile.
unset srcdir
# Also unset variables that control our test driver.  While not
# conceptually independent, they cause some changed semantics we
# need to control (and test for) in some of the tests to ensure
# backward-compatible behavior.
unset TESTS_ENVIRONMENT AM_TESTS_ENVIRONMENT
unset DISABLE_HARD_ERRORS
unset AM_COLOR_TESTS
unset TESTS
unset XFAIL_TESTS
unset TEST_LOGS
unset TEST_SUITE_LOG
unset RECHECK_LOGS
unset VERBOSE
for pfx in TEST_ SH_ TAP_ ''; do
  unset ${pfx}LOG_COMPILER
  unset ${pfx}LOG_COMPILE # Not a typo!
  unset ${pfx}LOG_FLAGS
  unset AM_${pfx}LOG_FLAGS
  unset ${pfx}LOG_DRIVER
  unset ${pfx}LOG_DRIVER_FLAGS
  unset AM_${pfx}LOG_DRIVER_FLAGS
done
unset pfx

# Re-enable, it had been temporarily disabled above.
set -e

## ---------------------------- ##
##  Auxiliary shell functions.  ##
## ---------------------------- ##

# Tell whether we should keep the test directories around, even in
# case of success.  By default, we don't.
am_keeping_testdirs ()
{
  case $keep_testdirs in
     ""|n|no|NO) return 1;;
              *) return 0;;
  esac
}

# This is used in '_am_exit' and in the exit trap.  See comments in
# the latter for more information.
am__test_skipped=no

# We use a trap below for cleanup.  This requires us to go through
# hoops to get the right exit status transported through the signal.
# Turn off errexit here so that we don't trip the bug with OSF1/Tru64
# sh inside this function (FIXME: is this still relevant now that we
# require a POSIX shell?).
_am_exit ()
{
  set +e
  # See comments in the exit trap for the reason we do this.
  test 77 = $1 && am__test_skipped=yes
  # Spurious escaping to ensure we do not call our 'exit' alias.
  (\exit $1); \exit $1
}
alias exit=_am_exit

if test $am_using_tap = yes; then
  am_funcs_file=tap-functions.sh
else
  am_funcs_file=plain-functions.sh
fi

if test -f "$am_testauxdir/$am_funcs_file"; then
  . "$am_testauxdir/$am_funcs_file" || {
    echo "$me: error sourcing $am_testauxdir/$am_funcs_file" >&2
    exit 99
  }
else
  echo "$me: $am_testauxdir/$am_funcs_file not found" >&2
  exit 99
fi
unset am_funcs_file

# cross_compiling
# ---------------
# Tell whether we are cross-compiling.  This is especially useful to skip
# tests (or portions of them) that requires a native compiler.
cross_compiling ()
{
  # Quoting from the autoconf manual:
  #   ... [$host_alias and $build both] default to the result of running
  #   config.guess, unless you specify either --build or --host.  In
  #   this case, the default becomes the system type you specified.
  #   If you specify both, *and they're different*, configure enters
  #   cross compilation mode (so it doesn't run any tests that require
  #   execution).
  test x"$host_alias" != x && test x"$build_alias" != x"$host_alias"
}

# is_blocked_signal SIGNAL-NUMBER
# --------------------------------
# Return success if the given signal number is blocked in the shell,
# return a non-zero exit status and print a proper diagnostic otherwise.
is_blocked_signal ()
{
  # Use perl, since trying to do this portably in the shell can be
  # very tricky, if not downright impossible.  For reference, see:
  # <http://lists.gnu.org/archive/html/bug-autoconf/2011-09/msg00004.html>
  if $PERL -w -e '
    use strict;
    use warnings FATAL => "all";
    use POSIX;
    my %oldsigaction = ();
    sigaction('"$1"', 0, \%oldsigaction);
    exit ($oldsigaction{"HANDLER"} eq "IGNORE" ? 0 : 77);
  '; then
    return 0
  elif test $? -eq 77; then
    return 1
  else
    fatal_ "couldn't determine whether signal $1 is blocked"
  fi
}

# AUTOMAKE_run [-e STATUS] [-d DESCRIPTION] [--] [AUTOMAKE-ARGS...]
# -----------------------------------------------------------------
# Run automake with AUTOMAKE-ARGS, and fail if it doesn't exit with
# STATUS.  Should be polymorphic for TAP and "plain" tests.  The
# DESCRIPTION, when provided, is used for console reporting, only if
# the TAP protocol is in use in the current test script.
AUTOMAKE_run ()
{
  am__desc=
  am__exp_rc=0
  while test $# -gt 0; do
    case $1 in
      -d) am__desc=$2; shift;;
      -e) am__exp_rc=$2; shift;;
      --) shift; break;;
       # Don't fail on unknown option: assume they (and the rest of the
       # command line) are to be passed verbatim to automake (so stop our
       # own option parsing).
       *) break;;
    esac
    shift
  done
  am__got_rc=0
  $AUTOMAKE ${1+"$@"} >stdout 2>stderr || am__got_rc=$?
  cat stderr >&2
  cat stdout
  if test $am_using_tap != yes; then
    test $am__got_rc -eq $am__exp_rc || exit 1
    return
  fi
  if test -z "$am__desc"; then
    if test $am__got_rc -eq $am__exp_rc; then
      am__desc="automake exited $am__got_rc"
    else
      am__desc="automake exited $am__got_rc, expecting $am__exp_rc"
    fi
  fi
  command_ok_ "$am__desc" test $am__got_rc -eq $am__exp_rc
}

# AUTOMAKE_fails [-d DESCRIPTION] [OPTIONS...]
# --------------------------------------------
# Run automake with OPTIONS, and fail if doesn't exit with status 1.
# Should be polymorphic for TAP and "plain" tests.  The DESCRIPTION,
# when provided, is used for console reporting, only if the TAP
# protocol is in use in the current test script.
AUTOMAKE_fails ()
{
  AUTOMAKE_run -e 1 ${1+"$@"}
}

# extract_configure_help { --OPTION | VARIABLE-NAME } [FILES]
# -----------------------------------------------------------
# Use this to extract from the output of "./configure --help" (or similar)
# the description or help message associated to the given --OPTION or
# VARIABLE-NAME.
extract_configure_help ()
{
  am__opt_re='' am__var_re=''
  case $1 in
    --*'=')   am__opt_re="^  $1";;
    --*'[=]') am__opt_re='^  '$(printf '%s\n' "$1" | sed 's/...$//')'\[=';;
    --*)      am__opt_re="^  $1( .*|$)";;
      *)      am__var_re="^  $1( .*|$)";;
  esac
  shift
  if test x"$am__opt_re" != x; then
    LC_ALL=C awk '
      /'"$am__opt_re"'/        { print; do_print = 1; next; }
      /^$/                     { do_print = 0; next }
      /^  --/                  { do_print = 0; next }
      (do_print == 1)          { print }
    ' ${1+"$@"}
  else
    LC_ALL=C awk '
      /'"$am__var_re"'/        { print; do_print = 1; next; }
      /^$/                     { do_print = 0; next }
      /^  [A-Z][A-Z0-9_]* /    { do_print = 0; next }
      /^  [A-Z][A-Z0-9_]*$/    { do_print = 0; next }
      (do_print == 1)          { print }
    ' ${1+"$@"}
  fi
}

# grep_configure_help { --OPTION | VARIABLE-NAME } REGEXP
# -------------------------------------------------------
# Grep the section of "./configure --help" output associated with either
# --OPTION or VARIABLE-NAME for the given *extended* regular expression.
grep_configure_help ()
{
  ./configure --help > am--all-help \
    || { cat am--all-help; exit 1; }
  cat am--all-help
  extract_configure_help "$1" am--all-help > am--our-help \
    || { cat am--our-help; exit 1; }
  cat am--our-help
  $EGREP "$2" am--our-help || exit 1
}

# using_gmake
# -----------
# Return success if $MAKE is GNU make, return failure otherwise.
# Caches the result for speed reasons.
using_gmake ()
{
  case $am__using_gmake in
    yes)
      return 0;;
    no)
      return 1;;
    '')
      # Use --version AND -v, because SGI Make doesn't fail on --version.
      # Also grep for GNU because newer versions of FreeBSD make do
      # not complain about --version (they seem to silently ignore it).
      if $MAKE --version -v | grep GNU; then
        am__using_gmake=yes
        return 0
      else
        am__using_gmake=no
        return 1
      fi;;
    *)
      fatal_ "invalid value for \$am__using_gmake: '$am__using_gmake'";;
  esac
}
am__using_gmake="" # Avoid interferences from the environment.

# make_can_chain_suffix_rules
# ---------------------------
# Return 0 if $MAKE is a make implementation that can chain suffix rules
# automatically, return 1 otherwise.  Caches the result for speed reasons.
make_can_chain_suffix_rules ()
{
  if test -z "$am__can_chain_suffix_rules"; then
    if using_gmake; then
      am__can_chain_suffix_rules=yes
      return 0
    else
      mkdir am__chain.dir$$
      cd am__chain.dir$$
      unindent > Makefile << 'END'
        .SUFFIXES: .u .v .w
        .u.v: ; cp $< $@
        .v.w: ; cp $< $@
END
      echo make can chain suffix rules > foo.u
      if $MAKE foo.w && diff foo.u foo.w; then
        am__can_chain_suffix_rules=yes
      else
        am__can_chain_suffix_rules=no
      fi
      cd ..
      rm -rf am__chain.dir$$
    fi
  fi
  case $am__can_chain_suffix_rules in
    yes) return 0;;
     no) return 1;;
      *) fatal_ "make_can_chain_suffix_rules: internal error";;
  esac
}
am__can_chain_suffix_rules="" # Avoid interferences from the environment.

# useless_vpath_rebuild
# ---------------------
# Tell whether $MAKE suffers of the bug triggering automake bug#7884.
# For example, this happens with FreeBSD make, since in a VPATH build
# it tends to rebuilt files for which there is an explicit or even just
# a suffix rule, even if said files are already available in the VPATH
# directory.
useless_vpath_rebuild ()
{
  if test -z "$am__useless_vpath_rebuild"; then
    if using_gmake; then
      am__useless_vpath_rebuild=no
      return 1
    fi
    mkdir am__vpath.dir$$
    cd am__vpath.dir$$
    touch foo.a foo.b bar baz
    mkdir build
    cd build
    unindent > Makefile << 'END'
        .SUFFIXES: .a .b
        VPATH = ..
        all: foo.b baz
        .PHONY: all
        .a.b: ; cp $< $@
        baz: bar ; cp ../baz bar
END
    if $MAKE all && test ! -e foo.b && test ! -e bar; then
      am__useless_vpath_rebuild=no
    else
      am__useless_vpath_rebuild=yes
    fi
    cd ../..
    rm -rf am__vpath.dir$$
  fi
  case $am__useless_vpath_rebuild in
    yes) return 0;;
     no) return 1;;
     "") ;;
      *) fatal_ "no_useless_builddir_remake: internal error";;
  esac
}
am__useless_vpath_rebuild=""

yl_distcheck () { useless_vpath_rebuild || $MAKE distcheck ${1+"$@"}; }

# seq_ - print a sequence of numbers
# ----------------------------------
# This function simulates GNU seq(1) portably.  Valid usages:
#  - seq LAST
#  - seq FIRST LAST
#  - seq FIRST INCREMENT LAST
seq_ ()
{
  case $# in
    0) fatal_ "seq_: missing argument";;
    1) seq_first=1  seq_incr=1  seq_last=$1;;
    2) seq_first=$1 seq_incr=1  seq_last=$2;;
    3) seq_first=$1 seq_incr=$2 seq_last=$3;;
    *) fatal_ "seq_: too many arguments";;
  esac
  i=$seq_first
  while test $i -le $seq_last; do
    echo $i
    i=$(($i + $seq_incr))
  done
}

# rm_rf_ [FILES OR DIRECTORIES ...]
# ---------------------------------
# Recursively remove the given files or directory, also handling the case
# of non-writable subdirectories.
rm_rf_ ()
{
  test $# -gt 0 || return 0
  # Ignore failures in find, we are only interested in failures of the
  # final rm.
  find "$@" -type d ! -perm -700 -exec chmod u+rwx {} \; || :
  rm -rf "$@"
}

# count_test_results total=N pass=N fail=N xpass=N xfail=N skip=N error=N
# -----------------------------------------------------------------------
# Check that a testsuite run driven by the parallel-tests harness has
# had the specified numbers of test results (specified by kind).
# This function assumes that the output of "make check" or "make recheck"
# has been saved in the 'stdout' file in the current directory, and its
# log in the 'test-suite.log' file.
count_test_results ()
{
  # Use a subshell so that we won't pollute the script namespace.
  (
    # TODO: Do proper checks on the arguments?
    total=ERR pass=ERR fail=ERR xpass=ERR xfail=ERR skip=ERR error=ERR
    eval "$@"
    # For debugging.
    $EGREP -i '(total|x?pass|x?fail|skip|error)' stdout || :
    rc=0
    # Avoid spurious failures with shells with "overly sensible"
    # errexit shell flag, such as e.g., Solaris /bin/sh.
    set +e
    test $(grep -c '^PASS:'  stdout) -eq $pass  || rc=1
    test $(grep -c '^XFAIL:' stdout) -eq $xfail || rc=1
    test $(grep -c '^SKIP:'  stdout) -eq $skip  || rc=1
    test $(grep -c '^FAIL:'  stdout) -eq $fail  || rc=1
    test $(grep -c '^XPASS:' stdout) -eq $xpass || rc=1
    test $(grep -c '^ERROR:' stdout) -eq $error || rc=1
    grep "^# TOTAL:  *$total$" stdout || rc=1
    grep "^# PASS:  *$pass$"   stdout || rc=1
    grep "^# XFAIL:  *$xfail$" stdout || rc=1
    grep "^# SKIP:  *$skip$"   stdout || rc=1
    grep "^# FAIL:  *$fail$"   stdout || rc=1
    grep "^# XPASS:  *$xpass$" stdout || rc=1
    grep "^# ERROR:  *$error$" stdout || rc=1
    test $rc -eq 0
  )
}

commented_sed_unindent_prog='
  /^$/b                    # Nothing to do for empty lines.
  x                        # Get x<indent> into pattern space.
  /^$/{                    # No prior x<indent>, go prepare it.
    g                      # Copy this 1st non-blank line into pattern space.
    s/^\(['"$tab"' ]*\).*/x\1/   # Prepare x<indent> in pattern space.
  }                        # Now: x<indent> in pattern and <line> in hold.
  G                        # Build x<indent>\n<line> in pattern space, and
  h                        # duplicate it into hold space.
  s/\n.*$//                # Restore x<indent> in pattern space, and
  x                        # exchange with the above duplicate in hold space.
  s/^x\(.*\)\n\1//         # Remove leading <indent> from <line>.
  s/^x.*\n//               # Restore <line> when there is no leading <indent>.
'

# unindent [input files...]
# -------------------------
# Remove the "proper" amount of leading whitespace from the given files,
# and output the result on stdout.  That amount is determined by looking
# at the leading whitespace of the first non-blank line in the input
# files.  If no input file is specified, standard input is implied.
unindent ()
{
  if test x"$sed_unindent_prog" = x; then
    sed_unindent_prog=$(printf '%s\n' "$commented_sed_unindent_prog" \
                          | sed -e "s/  *# .*//")
  fi
  sed "$sed_unindent_prog" ${1+"$@"}
}
sed_unindent_prog="" # Avoid interferences from the environment.

# get_shell_script SCRIPT-NAME
# -----------------------------
# Fetch an Automake-provided shell script from the 'lib/' directory into
# the current directory, and, if the '$am_test_prefer_config_shell'
# variable is set to "yes", modify its shebang line to use $SHELL instead
# of /bin/sh.
get_shell_script ()
{
  test ! -f "$1" || rm -f "$1" || return 99
  if test x"$am_test_prefer_config_shell" = x"yes"; then
    sed "1s|#!.*|#! $SHELL|" "$am_scriptdir/$1" > "$1" \
     && chmod a+x "$1" \
     || return 99
  else
    cp -f "$am_scriptdir/$1" . || return 99
  fi
  sed 10q "$1" # For debugging.
}

# require_xsi SHELL
# -----------------
# Skip the test if the given shell fails to support common XSI constructs.
require_xsi ()
{
  test $# -eq 1 || fatal_ "require_xsi needs exactly one argument"
  echo "$me: trying some XSI constructs with $1"
  $1 -c "$xsi_shell_code" || skip_all_ "$1 lacks XSI features"
}
# Shell code supposed to work only with XSI shells.  Keep this in sync
# with libtool.m4:_LT_CHECK_SHELL_FEATURES.
xsi_shell_code='
  _lt_dummy="a/b/c"
  test "${_lt_dummy##*/},${_lt_dummy%/*},${_lt_dummy#??}"${_lt_dummy%"$_lt_dummy"}, \
      = c,a/b,b/c, \
    && eval '\''test $(( 1 + 1 )) -eq 2 \
    && test "${#_lt_dummy}" -eq 5'\'

# fetch_tap_driver
# ----------------
# Fetch the Automake-provided TAP driver from the 'lib/' directory into
# the current directory, and edit its shebang line so that it will be
# run with the perl interpreter determined at configure time.
fetch_tap_driver ()
{
  # TODO: we should devise a way to make the shell TAP driver tested also
  # TODO: with /bin/sh, for better coverage.
  case $am_tap_implementation in
    # Extra quoting required to avoid maintainer-check spurious failures.
   'perl')
      $PERL -MTAP::Parser -e 1 \
        || skip_all_ "cannot import TAP::Parser perl module"
      sed "1s|#!.*|#! $PERL -w|" "$am_scriptdir"/tap-driver.pl >tap-driver
      ;;
    shell)
      AM_TAP_AWK=$AWK; export AM_TAP_AWK
      sed "1s|#!.*|#! $SHELL|" "$am_scriptdir"/tap-driver.sh >tap-driver
      ;;
    *)
      fatal_ "invalid \$am_tap_implementation '$am_tap_implementation'" ;;
  esac \
    && chmod a+x tap-driver \
    || framework_failure_ "couldn't fetch $am_tap_implementation TAP driver"
  sed 10q tap-driver # For debugging.
}
# The shell/awk implementation of the TAP driver is still mostly dummy, so
# use the perl implementation by default for the moment.
am_tap_implementation=${am_tap_implementation-shell}

# Usage: require_compiler_ {cc|c++|fortran|fortran77}
require_compiler_ ()
{
  case $# in
    0) fatal_ "require_compiler_: missing argument";;
    1) ;;
    *) fatal_ "require_compiler_: too many arguments";;
  esac
  case $1 in
    cc)
      am__comp_lang="C"
      am__comp_var=CC
      am__comp_flag_vars='CFLAGS CPPFLAGS'
      ;;
    c++)
      am__comp_lang="C++"
      am__comp_var=CXX
      am__comp_flag_vars='CXXFLAGS CPPFLAGS'
      ;;
    fortran)
      am__comp_lang="Fortran"
      am__comp_var=FC
      am__comp_flag_vars='FCFLAGS'
      ;;
    fortran77)
      am__comp_lang="Fortran 77"
      am__comp_var=F77
      am__comp_flag_vars='FFLAGS'
      ;;
  esac
  shift
  eval "am__comp_prog=\${$am__comp_var}" \
    || fatal_ "expanding \${$am__comp_var} in require_compiler_"
  case $am__comp_prog in
    "")
      fatal_ "botched configuration: \$$am__comp_var is empty";;
    false)
      skip_all_ "no $am__comp_lang compiler available";;
    autodetect|autodetected)
      # Let the ./configure commands in the test script try to determine
      # these automatically.
      unset $am__comp_var $am__comp_flag_vars;;
    *)
      # Pre-set these for the ./configure commands in the test script.
      export $am__comp_var $am__comp_flag_vars;;
  esac
  # Delete private variables.
  unset am__comp_lang am__comp_prog am__comp_var am__comp_flag_vars
}

## ----------------------------------------------------------- ##
##  Checks for required tools, and additional setups (if any)  ##
##  required by them.                                          ##
## ----------------------------------------------------------- ##

# Performance tests must be enabled explicitly.
case $argv0 in
  */perf/*)
    case $AM_TESTSUITE_PERF in
      [yY]|[yY]es|1) ;;
      *) skip_ "performance tests not explicitly enabled" ;;
    esac
    ;;
esac

# Look for (and maybe set up) required tools and/or system features; skip
# the current test if they are not found.
for tool in : $required
do
  # Check that each required tool is present.
  case $tool in
    :) ;;
    cc|c++|fortran|fortran77)
      require_compiler_ $tool;;
    xsi-lib-shell)
      if test x"$am_test_prefer_config_shell" = x"yes"; then
        require_xsi "$SHELL"
      else
        require_xsi "/bin/sh"
      fi
      ;;
    bzip2)
      # Do not use --version, older versions bzip2 still tries to compress
      # stdin.
      echo "$me: running bzip2 --help"
      bzip2 --help \
        || skip_all_ "required program 'bzip2' not available"
      ;;
    cl)
      CC=cl
      # Don't export CFLAGS, as that could have been initialized to only
      # work with the C compiler detected at configure time.  If the user
      # wants CFLAGS to also influence 'cl', he can still export CFLAGS
      # in the environment "by hand" before calling the testsuite.
      export CC CPPFLAGS
      echo "$me: running $CC -?"
      $CC -? || skip_all_ "Microsoft C compiler '$CC' not available"
      ;;
    etags)
      # Exuberant Ctags will create a TAGS file even
      # when asked for --help or --version.  (Emacs's etags
      # does not have such problem.)  Use -o /dev/null
      # to make sure we do not pollute the build directory.
      echo "$me: running etags --version -o /dev/null"
      etags --version -o /dev/null \
        || skip_all_ "required program 'etags' not available"
      ;;
    GNUmake)
      for make_ in "$MAKE" gmake gnumake :; do
        MAKE=$make_ am__using_gmake=''
        test "$MAKE" =  : && break
        echo "$me: determine whether $MAKE is GNU make"
        using_gmake && break
        : For shells with busted 'set -e'.
      done
      test "$MAKE" = : && skip_all_ "this test requires GNU make"
      export MAKE
      unset make_
      ;;
    gcj)
      GCJ=$GNU_GCJ GCJFLAGS=$GNU_GCJFLAGS; export GCJ GCJFLAGS
      test "$GCJ" = false && skip_all_ "GNU Java compiler unavailable"
      : For shells with busted 'set -e'.
      ;;
    gcc)
      CC=$GNU_CC CFLAGS=$GNU_CFLAGS; export CC CFLAGS CPPFLAGS
      test "$CC" = false && skip_all_ "GNU C compiler unavailable"
      : For shells with busted 'set -e'.
      ;;
    g++)
      CXX=$GNU_CXX CXXFLAGS=$GNU_CXXFLAGS; export CXX CXXFLAGS CPPFLAGS
      test "$CXX" = false && skip_all_ "GNU C++ compiler unavailable"
      : For shells with busted 'set -e'.
      ;;
    gfortran)
      FC=$GNU_FC FCFLAGS=$GNU_FCFLAGS; export FC FCFLAGS
      test "$FC" = false && skip_all_ "GNU Fortran compiler unavailable"
      case " $required " in
        *\ g77\ *) ;;
        *) F77=$FC FFLAGS=$FCFLAGS; export F77 FFLAGS;;
      esac
      ;;
    g77)
      F77=$GNU_F77 FFLAGS=$GNU_FFLAGS; export F77 FFLAGS
      test "$F77" = false && skip_all_ "GNU Fortran 77 compiler unavailable"
      case " $required " in
        *\ gfortran\ *) ;;
        *) FC=$F77 FCFLAGS=$FFLAGS; export FC FCFLAGS;;
      esac
      ;;
    grep-nonprint)
      # Check that grep can parse nonprinting characters correctly.
      # BSD 'grep' works from a pipe, but not a seekable file.
      # GNU or BSD 'grep -a' works on files, but is not portable.
      case $(echo "$esc" | grep .)$(echo "$esc" | grep "$esc") in
        "$esc$esc") ;;
        *) skip_ "grep can't handle nonprinting characters correctly";;
      esac
      ;;
    javac)
      # The Java compiler from JDK 1.5 (and presumably earlier versions)
      # cannot handle the '-version' option by itself: it bails out
      # telling that source files are missing.  Adding also the '-help'
      # option seems to solve the problem.
      echo "$me: running javac -version -help"
      javac -version -help || skip_all_ "Sun Java compiler not available"
      ;;
    java)
      # See the comments above about 'javac' for why we use also '-help'.
      echo "$me: running java -version -help"
      java -version -help || skip_all_ "Sun Java interpreter not found"
      ;;
    lib)
      AR=lib
      export AR
      # Attempting to create an empty archive will actually not
      # create the archive, but lib will output its version.
      echo "$me: running $AR -out:defstest.lib"
      $AR -out:defstest.lib \
        || skip_all_ "Microsoft 'lib' utility not available"
      ;;
    makedepend)
      echo "$me: running makedepend -f-"
      makedepend -f- \
        || skip_all_ "required program 'makedepend' not available"
      ;;
    makeinfo-html)
      # Make sure we have makeinfo, and it understands '--html'.
      echo "$me: running makeinfo --html --version"
      makeinfo --html --version \
        || skip_all_ "cannot find a makeinfo program that groks" \
                     "the '--html' option"
      ;;
    mingw)
      uname_s=$(uname -s || echo UNKNOWN)
      echo "$me: system name: $uname_s"
      case $uname_s in
        MINGW*) ;;
        *) skip_all_ "this test requires MSYS in MinGW mode" ;;
      esac
      unset uname_s
      ;;
    non-root)
      # Skip this test case if the user is root.
      # We try to append to a read-only file to detect this.
      priv_check_temp=priv-check.$$
      touch $priv_check_temp && chmod a-w $priv_check_temp \
        || framework_failure_ "creating unwritable file $priv_check_temp"
      # Not a useless use of subshell: lesser shells might bail
      # out if a builtin fails.
      overwrite_status=0
      (echo foo >> $priv_check_temp) || overwrite_status=$?
      rm -f $priv_check_temp
      if test $overwrite_status -eq 0; then
        skip_all_ "cannot drop file write permissions"
      fi
      unset priv_check_temp overwrite_status
      ;;
    # Extra quoting required to avoid maintainer-check spurious failures.
    'perl-threads')
      if test "$WANT_NO_THREADS" = "yes"; then
        skip_all_ "Devel::Cover cannot cope with threads"
      fi
      ;;
    native)
      # Don't use "&&" here, to avoid a bug of 'set -e' present in
      # some (even relatively recent) versions of the BSD shell.
      # We add the dummy "else" branch for extra safety.
      ! cross_compiling || skip_all_ "doesn't work in cross-compile mode"
      ;;
    python)
      # Python doesn't support --version, it has -V
      echo "$me: running python -V"
      python -V || skip_all_ "python interpreter not available"
      ;;
    ro-dir)
      # Skip this test case if read-only directories aren't supported
      # (e.g., under DOS.)
      ro_dir_temp=ro_dir.$$
      mkdir $ro_dir_temp && chmod a-w $ro_dir_temp \
        || framework_failure_ "creating unwritable directory $ro_dir_temp"
      # Not a useless use of subshell: lesser shells might bail
      # out if a builtin fails.
      create_status=0
      (: > $ro_dir_temp/probe) || create_status=$?
      rm -rf $ro_dir_temp
      if test $create_status -eq 0; then
        skip_all_ "cannot drop directory write permissions"
      fi
      unset ro_dir_temp create_status
      ;;
    runtest)
      # DejaGnu's runtest program. We rely on being able to specify
      # the program on the runtest command-line. This requires
      # DejaGnu 1.4.3 or later.
      echo "$me: running runtest SOMEPROGRAM=someprogram --version"
      runtest SOMEPROGRAM=someprogram --version \
        || skip_all_ "DejaGnu is not available"
      ;;
    tex)
      # No all versions of Tex support '--version', so we use
      # a configure check.
      if test -z "$TEX"; then
        skip_all_ "TeX is required, but it wasn't found by configure"
      fi
      ;;
    texi2dvi-o)
      # Texi2dvi supports '-o' since Texinfo 4.1.
      echo "$me: running texi2dvi -o /dev/null --version"
      texi2dvi -o /dev/null --version \
        || skip_all_ "required program 'texi2dvi' not available"
      ;;
    lex)
      test x"$LEX" = x"false" && skip_all_ "lex not found or disabled"
      export LEX
      ;;
    yacc)
      test x"$YACC" = x"false" && skip_all_ "yacc not found or disabled"
      export YACC
      ;;
    flex)
      LEX=flex; export LEX
      echo "$me: running flex --version"
      flex --version || skip_all_ "required program 'flex' not available"
      ;;
    bison)
      YACC='bison -y'; export YACC
      echo "$me: running bison --version"
      bison --version || skip_all_ "required program 'bison' not available"
      ;;
    *)
      # Generic case: the tool must support --version.
      echo "$me: running $tool --version"
      # It is not likely but possible that $tool is a special builtin,
      # in which case the shell is allowed to exit after an error.  So
      # we need the subshell here.  Also, some tools, like Sun cscope,
      # can be interactive without redirection.
      ($tool --version) </dev/null \
        || skip_all_ "required program '$tool' not available"
      ;;
  esac
done

# We might need extra macros, e.g., from Libtool or Gettext.
case " $required " in *\ libtool*) . ./t/libtool-macros.dir/get.sh;; esac
case " $required " in *\ gettext*) . ./t/gettext-macros.dir/get.sh;; esac


## ---------------------------------------------------------------- ##
##  Create and set up of the temporary directory used by the test.  ##
##  Set up of the exit trap for cleanup of said directory.          ##
## ---------------------------------------------------------------- ##

# This might be used in testcases checking distribution-related features.
# Test scripts are free to override this if they need to.
distdir=$me-1.0

# Set up the exit trap.
trap 'exit_status=$?
  set +e
  cd "$am_top_builddir"
  if test $am_using_tap = yes; then
    if test "$planned_" = later && test $exit_status -eq 0; then
      plan_ "now"
    fi
    test $exit_status -eq 0 && test $tap_pass_count_ -eq $tap_count_ \
      || keep_testdirs=yes
  else
    # This is to ensure that a test script does give a SKIP outcome just
    # because a command in it happens to exit with status 77.  This
    # behaviour, while from time to time useful to developers, is not
    # meant to be enabled by default, as it could cause spurious failures
    # in the wild.  Thus it will be enabled only when the variable
    # "am_explicit_skips" is set to a "true" value.
    case $am_explicit_skips in
      [yY]|[yY]es|1)
        if test $exit_status -eq 77 && test $am__test_skipped != yes; then
          echo "$me: implicit skip turned into failure"
          exit_status=78
        fi;;
    esac
    test $exit_status -eq 0 || keep_testdirs=yes
  fi
  am_keeping_testdirs || rm_rf_ $am_test_subdir
  set +x
  echo "$me: exit $exit_status"
  # Spurious escaping to ensure we do not call our "exit" alias.
  \exit $exit_status
' 0
trap "fatal_ 'caught signal SIGHUP'" 1
trap "fatal_ 'caught signal SIGINT'" 2
trap "fatal_ 'caught signal SIGTERM'" 15
# Various shells seems to just ignore SIGQUIT under some circumstances,
# even if the signal is not blocked; however, if the signal it trapped,
# the trap gets correctly executed.  So we also trap SIGQUIT.
# Here is a list of some shells that have been verified to exhibit the
# problematic behavior with SIGQUIT:
#  - zsh 4.3.12 on Debian GNU/Linux
#  - /bin/ksh and /usr/xpg4/bin/sh on Solaris 10
#  - Bash 3.2.51 on Solaris 10 and bash 4.1.5 on Debian GNU/Linux
#  - AT&T ksh on Debian Gnu/Linux (deb package ksh, version 93u-1)
# OTOH, at least these shells that do *not* exhibit that behaviour:
#  - modern version of the Almquist Shell (at least 0.5.5.1), on
#    both Solaris and GNU/Linux
#  - public domain Korn Shell, version 5.2.14, on Debian GNU/Linux
trap "fatal_ 'caught signal SIGQUIT'" 3
# Ignore further SIGPIPE in the trap code.  This is required to avoid
# a very weird issue with some shells, at least when the execution of
# the automake testsuite is driven by the 'prove' utility: if prove
# (or the make process that has spawned it) gets interrupted with
# Ctrl-C, the shell might go in a loop, continually getting a SIGPIPE,
# sometimes finally dumping core, other times hanging indefinitely.
# See also Test::Harness bug [rt.cpan.org #70855], archived at
# <https://rt.cpan.org/Ticket/Display.html?id=70855>
trap "trap '' 13; fatal_ 'caught signal SIGPIPE'" 13

# Create and populate the temporary directory, if and as required.
if test x"$am_create_testdir" = x"no"; then
  am_test_subdir=
else
  # The subdirectory where the current test script will run and write its
  # temporary/data files.  This will be created shortly, and will be removed
  # by the cleanup trap below if the test passes.  If the test doesn't pass,
  # this directory will be kept, to facilitate debugging.
  am_test_subdir=${argv0#$am_rel_srcdir/}
  case $am_test_subdir in
    */*) am_test_subdir=${am_test_subdir%/*}/$me.dir;;
      *) am_test_subdir=$me.dir;;
  esac
  test ! -e $am_test_subdir || rm_rf_ $am_test_subdir \
    || framework_failure_ "removing old test subdirectory"
  $MKDIR_P $am_test_subdir \
    || framework_failure_ "creating test subdirectory"
  cd $am_test_subdir \
    || framework_failure_ "cannot chdir into test subdirectory"
  if test x"$am_create_testdir" != x"empty"; then
    cp "$am_scriptdir"/install-sh "$am_scriptdir"/missing \
       "$am_scriptdir"/depcomp . \
      || framework_failure_ "fetching common files from $am_scriptdir"
    # Build appropriate environment in test directory.  E.g., create
    # configure.ac, touch all necessary files, etc.  Don't use AC_OUTPUT,
    # but AC_CONFIG_FILES so that appending still produces a valid
    # configure.ac.  But then, tests running config.status really need
    # to append AC_OUTPUT.
    {
      echo "AC_INIT([$me], [1.0])"
      if test x"$am_serial_tests" = x"yes"; then
        echo "AM_INIT_AUTOMAKE"
      else
        echo "AM_INIT_AUTOMAKE([parallel-tests])"
      fi
      echo "AC_CONFIG_FILES([Makefile])"
    } >configure.ac || framework_failure_ "creating configure.ac skeleton"
  fi
fi


## ---------------- ##
##  Ready to go...  ##
## ---------------- ##

set -x
pwd
