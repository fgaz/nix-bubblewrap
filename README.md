# nix-bubblewrap

**[Nix](https://nixos.org) - [bubblewrap](https://github.com/containers/bubblewrap) integration**

## Why

In a typical Linux system, bubblewrap is run like this:

    bwrap --ro-bind /usr /usr --proc /proc --dev /dev --unshare-pid bash

With Nix, one would have to replace `/usr` with `/nix/store`...
but
[all kinds](https://search.nixos.org/options?channel=unstable&sort=relevance&type=packages&query=password)
[of stuff](https://search.nixos.org/options?channel=unstable&sort=relevance&type=packages&query=secret)
you may not want an attacker to see can end up in the store.
Binding individual store paths can also be a pain since the whole closure is
needed.
This script automates that process.
Additional flags to add permissions in a nixos-specific way
(eg. keeping `/run/opengl-driver` and `/etc/ssl` into account)
are provided.

## Installation

Both a traditional default.nix and a flake are provided. Install with:

    $ nix-env -f . -i

or:

    nix install

## Usage

    nix-bwrap [OPTIONS] COMMAND ...

Run `nix-bwrap -help` to list the available options.

Examples:

    $ nix-shell -p hello --run "nix-bwrap hello"
    Hello, world!
    $ nix-shell -p tree --run "nix-bwrap tree -L 3 /"
    /
    `-- nix
        `-- store
            |-- 0ldsqvqp3y1bn6852ymksfa2kfkr3dkb-tree-1.8.0
            |-- 563528481rvhc5kxwipjmg6rqrl95mdx-glibc-2.33-56
            |-- qbdsd82q5fyr0v31cvfxda0n0h7jh03g-libunistring-0.9.10
            `-- scz4zbxirykss3hh5iahgl39wk9wpaps-libidn2-2.3.2

    6 directories, 0 files

### Wrapping

In `lib.nix` (`lib` output in the flake) there are wrapper functions to create
wrapped versions of existing packages.
For example:

    with import ./lib.nix {};
    wrapPackage {
      package = (import <nixpkgs> {}).firefox;
      options = [
        "-x11"
        "-gpu"
        "-net"
        "-pulse"
      ];
    }

## Troubeshooting

### Missing `-gpu`

The following messages may indicate the application requires the `-gpu` flag:

* `Can't find icudtl.dat`

### Missing `-x11`

The following messages may indicate the application requires the `-x11` flag:

* `Missing X server or $DISPLAY`

## Contributing

You can send patches to my
[public-inbox mailing list](https://lists.sr.ht/~fgaz/public-inbox)
or to any of the contacts listed at [fgaz.me/about](https://fgaz.me/about).
Or you can send a pull request to the
[GitHub mirror](https://github.com/fgaz/nix-bubblewrap).

Issues are tracked at https://todo.sr.ht/~fgaz/nix-bubblewrap

## Alternatives

Using `writeReferencesToFile` or `closureInfo` from nixpkgs, the same can be
made to work entirely within nix, without needing an external program such as
this one.
Why does this tool exist then?
Because when only using `writeReferencesToFile` at build time, wrappers of
programs that need access to resources such as `/etc/ssl` would need to have
access to the same expressions as the NixOS system, and that can become
troublesome for user environments and shells.
With `nix-bwrap` there are no such problems, at a small runtime cost.
