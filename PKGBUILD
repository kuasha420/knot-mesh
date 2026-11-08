# Maintainer: Arafat Zahan <kuasha420>
pkgname=knot-mesh
pkgver=1.0.0.rc6
pkgrel=1
pkgdesc="Distributed workspace mesh for Arch Linux / KDE Plasma 6 Wayland"
arch=('any')
url="https://github.com/kuasha420/knot-mesh"
license=('MIT')
depends=(
    'git'
    'python'
    'python-pyqt6'
    'layer-shell-qt'
    'openssh'
    'openssl'
    'iproute2'
    'deskflow'
    'libportal'
    'kde-cli-tools'
    'jq>=1.6'
)
optdepends=(
    'kscreen-doctor: Wayland display auto-discovery on KDE Plasma 6'
    'wlr-randr: Wayland display auto-discovery for wlroots compositors'
    'libnotify: Desktop notification support for KVM cursor locking'
    'kdeconnect: Full-mesh clipboard synchronization and Wayland Virtual Monitor signaling'
    'krdp: Wayland headless virtual display creation and RDP streaming (host)'
    'krdc: Wayland remote desktop client for Virtual Monitor rendering (client)'
    'freerdp: RDP protocol engine for KRDC'
    'ncurses: Terminal terminfo compiler and infocmp database tools'
    'kitty>=0.26: GPU-accelerated terminal multiplexer for Swarm Council Confluence cockpits'
    'kitty-terminfo: Terminal terminfo definitions for kitty remote control'
    'flatpak: Managing Wayland remote desktop portal permissions for Deskflow'
    'socat: Bidirectional socket proxying and sub-second port probing for SSH ProxyCommand'
    'openbsd-netcat: Fast zero-I/O port scanning and SSH proxy command transport'
    'rsync: Incremental delta-transfer synchronizer for swarm deployment and fleet updates'
    'pipewire: Low-latency multimedia and DMA-BUF screencasting substrate for KRdp'
    'wireplumber: Session management for PipeWire'
)
source=("knot-mesh-${pkgver}.tar.gz::https://github.com/kuasha420/knot-mesh/archive/refs/tags/v1.0.0-rc6.tar.gz")
sha256sums=('SKIP')

package() {
    if [ -d "${srcdir}/${pkgname}-${pkgver}" ]; then
        cd "${srcdir}/${pkgname}-${pkgver}"
    elif [ -d "${srcdir}/${pkgname}-1.0.0-rc6" ]; then
        cd "${srcdir}/${pkgname}-1.0.0-rc6"
    else
        cd "${srcdir}"
    fi

    local destdir="${pkgdir}/usr/lib/knot-mesh"
    mkdir -p "${destdir}" "${pkgdir}/usr/bin"

    # Copy mesh core, bin, templates, and runtime skills
    cp -r core bin templates runtime "${destdir}/"
    ln -sfn "runtime/skills" "${destdir}/skills"

    # Copy systemd units if present
    if [ -d "systemd" ]; then
        cp -r systemd "${destdir}/"
    fi

    # Symlink executables to /usr/bin
    ln -sf "/usr/lib/knot-mesh/bin/knot" "${pkgdir}/usr/bin/knot"
    ln -sf "/usr/lib/knot-mesh/bin/knot-installer" "${pkgdir}/usr/bin/knot-installer"
    ln -sf "/usr/lib/knot-mesh/bin/knot-agent" "${pkgdir}/usr/bin/knot-agent"
    ln -sf "/usr/lib/knot-mesh/bin/knot-hub" "${pkgdir}/usr/bin/knot-hub"
    ln -sf "/usr/lib/knot-mesh/bin/knot-autounlock" "${pkgdir}/usr/bin/knot-autounlock"
    ln -sf "/usr/lib/knot-mesh/bin/knot-stripd" "${pkgdir}/usr/bin/knot-stripd"
    ln -sf "/usr/lib/knot-mesh/bin/knot-vmon-keepalive" "${pkgdir}/usr/bin/knot-vmon-keepalive"

    # Install license if present
    if [ -f "LICENSE" ]; then
        install -Dm644 LICENSE "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
    fi
}
