#! /usr/bin/env tclsh

# Or use this shebang to run the script directly:
#! /usr/bin/env nix-shell
#! nix-shell -i tclsh -p tcl tcllib coreutils which bubblewrap

# (c) Francesco Gazzetta 2022
# Licensed under the EUPL-1.2-or-later

package require Tcl 8.6
package require Tclx 8.6
package require cmdline 1.5
package require fileutil 1.16

set options {
  {bwrap-options.arg     "" "Additional options to pass to bwrap"          }
  {extra-store-paths.arg "" "Additional store paths to bind the closure of"}
  {x11                      "Enable basic X11 access"                      }
  {gpu                      "Enable GPU access"                            }
  {net                      "Enable network access and ssl certificates"   }
  {pulse                    "Enable pulseaudio"                            }
  {alsa                     "Enable ALSA"                                  }
}
# TODO -print-command flag, so that nix-bwrap can be used to create wrapper packages
#        * Write a lib function too (will it work? is it recursive nix?)

set usage "\[OPTIONS] COMMAND ...\noptions:"

try {
  array set params [::cmdline::getoptions argv $options $usage]
} trap {CMDLINE USAGE} {msg o} {
  puts $msg
  exit 2
}

if {$::argv == ""} {
  puts stderr "error: no command supplied"
  puts stderr [::cmdline::usage $options $usage]
  exit 1
}

proc requisites_binds {path} {
  set requisites [exec -ignorestderr nix-store --query --requisites $path]
  return [concat {*}[lmap x $requisites {list --ro-bind $x $x}]]
}

try {
  exec -ignorestderr nixos-version
  set is_nixos 1
} trap {POSIX ENOENT} {- -} {
  set is_nixos 0
}

set args [lassign $::argv argv0]
set exe [::fileutil::fullnormalize [auto_execok $argv0]]

set bwrap_options [list --unshare-all --clearenv --setenv HOME $env(HOME)]

lappend bwrap_options {*}[requisites_binds $exe]

if {$params(x11) == 1} {
  regexp {:([0-9]+)(\.[0-9]+)?} $env(DISPLAY) _ display
  lappend bwrap_options \
    --ro-bind "$env(HOME)/.Xauthority" "$env(HOME)/.Xauthority" \
    --ro-bind "/tmp/.X11-unix/X$display" "/tmp/.X11-unix/X$display" \
    --setenv DISPLAY ":$display"
}

if {$params(gpu) == 1} {
  if {$is_nixos} {
    lappend bwrap_options \
      --dev /dev \
      --dev-bind /dev/dri /dev/dri \
      --proc /proc \
      --ro-bind /sys/devices/pci0000:00 /sys/devices/pci0000:00 \
      --ro-bind /sys/dev/char /sys/dev/char \
      --ro-bind /run/opengl-driver /run/opengl-driver \
      {*}[requisites_binds /run/opengl-driver]
      # MAYBE add /run/opengl-driver32 too (if it exists. does it always exist?)
  } else {
    puts stderr "-gpu not supported on non-NixOS"
    exit 1
  }
}

if {$params(net) == 1} {
  lappend bwrap_options \
    --share-net \
    --ro-bind /etc/resolv.conf /etc/resolv.conf \
    --ro-bind /etc/ssl /etc/ssl
  if {$is_nixos} {
    lappend bwrap_options \
      --ro-bind /etc/static/ssl /etc/static/ssl \
      {*}[requisites_binds /etc/ssl/trust-source] \
      {*}[requisites_binds /etc/ssl/certs/ca-bundle.crt]
  }
}

if {$params(pulse) == 1} {
  if {[info exists env(XDG_RUNTIME_DIR)]} {
    set runtime_dir $env(XDG_RUNTIME_DIR)
  } else {
    set runtime_dir /run/user/[id effective userid]
  }
  lappend bwrap_options \
    --ro-bind $runtime_dir/pulse $runtime_dir/pulse \
    --setenv XDG_RUNTIME_DIR $runtime_dir
}

if {$params(alsa) == 1} {
  # TODO stub group file like in https://github.com/containers/bubblewrap/blob/master/demos/bubblewrap-shell.sh
  lappend bwrap_options \
    --dev-bind /dev/snd /dev/snd \
    --ro-bind /etc/group /etc/group
}

if {$params(extra-store-paths) != ""} {
  set tmp_profile_dir [::fileutil::maketempdir -prefix "nix-bubblewrap."]
  # MAYBE just put $exe in here... or even every other path too (ca-bundle...)
  #       The downside is that a profile is built every time
  #       ...but if it already exists only links are created
  exec -ignorestderr nix-env \
    --profile "$tmp_profile_dir/profile" \
    -i {*}$params(extra-store-paths)
  set profile_path \
    [file readlink $tmp_profile_dir/[file readlink "$tmp_profile_dir/profile"]]
  file delete -force $tmp_profile_dir
  lappend bwrap_options {*}[requisites_binds $profile_path]
  lappend bwrap_options --setenv PATH "$profile_path/bin"
}

# has to be done at the end to let the user override previous options
lappend bwrap_options {*}$params(bwrap-options)

try {
  exec -ignorestderr bwrap {*}$bwrap_options --argv0 $argv0 $exe {*}$args <@stdin >@stdout 2>@stderr
} trap CHILDSTATUS {- options} {
  exit [lindex [dict get $options -errorcode] 2]
}
