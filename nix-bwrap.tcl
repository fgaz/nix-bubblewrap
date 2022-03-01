#! /usr/bin/env tclsh

# Or use this shebang to run the script directly:
#! /usr/bin/env nix-shell
#! nix-shell -i tclsh -p tcl tcllib coreutils which bubblewrap

# (c) Francesco Gazzetta 2022
# Licensed under the EUPL-1.2-or-later

package require Tcl 8.6
package require cmdline 1.5

set options {
  {bwrap-options.arg     "" "Additional options to pass to bwrap"          }
  {extra-store-paths.arg "" "Additional store paths to bind the closure of"}
  {x11                      "enable basic X11 access"                      }
  {gpu                      "enable GPU access"                            }
  {net                      "enable network access and ssl certificates"   }
  {pulse                    "enable pulseaudio"                            }
  {alsa                     "enable ALSA"                                  }
}
# TODO -print-command flag, so that nix-bwrap can be used to create wrapper packages
#        * Write a lib function too (will it work? is it recursive nix?)
# TODO move all other output to stderr

set usage "\[OPTIONS] COMMAND ...\noptions:"

try {
  array set params [::cmdline::getoptions argv $options $usage]
} trap {CMDLINE USAGE} {msg o} {
  puts $msg
  exit 1
}

if {$::argv == ""} {
  puts "error: no command supplied"
  puts [::cmdline::usage $options $usage]
  exit 1
}

proc requisites_binds {path} {
  set requisites [exec nix-store --query --requisites $path]
  return [concat {*}[lmap x $requisites {list --ro-bind $x $x}]]
}

try {
  exec nixos-version
  set is_nixos 1
} trap CHILDSTATUS {- -} {
  set is_nixos 0
}

# there used to be a realpath
# (or ::fileutil::fullnormalize, file normalize, file readlink) call here, but
# it makes single-executable tools (such as busybox or coreutils) useless
# MAYBE do it only for /run/current-system/sw/bin
set exe [exec which [lindex $::argv 0]]
set args [lreplace $::argv 0 0]

set bwrap_options [list --unshare-all --clearenv --setenv HOME $env(HOME)]

lappend bwrap_options {*}[requisites_binds $exe]

if {$params(x11) == 1} {
  set display [string trimleft $env(DISPLAY) ":"]
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
    puts "-gpu not supported on non-NixOS"
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
  set uid [exec id -u]
  lappend bwrap_options --ro-bind /run/user/$uid/pulse /run/user/$uid/pulse
}

if {$params(alsa) == 1} {
  # TODO stub group file like in https://github.com/containers/bubblewrap/blob/master/demos/bubblewrap-shell.sh
  lappend bwrap_options \
    --dev-bind /dev/snd /dev/snd \
    --ro-bind /etc/group /etc/group
}

lappend bwrap_options {*}[
  concat {*}[lmap path [split $params(extra-store-paths)] {requisites_binds $path}]
]
lappend bwrap_options --setenv PATH [
  join [lmap path $params(extra-store-paths) {string cat $path "/bin"}] ":"
]
# TODO dedupe the ro-binds
# MAYBE use a profile for PATH? it may help with dedup too. and with paths that already include /bin

# has to be done at the end to let the user override previous options
lappend bwrap_options {*}$params(bwrap-options)

try {
  exec bwrap {*}$bwrap_options $exe {*}$args <@stdin >@stdout 2>@stderr
} trap CHILDSTATUS {- options} {
  exit [lindex [dict get $options -errorcode] 2]
}
