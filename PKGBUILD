# Maintainer: Arafat Zahan <kuasha420>
pkgname=knot-mesh
pkgver=1.0.0.rc2
pkgrel=1
pkgdesc="Distributed workspace mesh for Arch Linux / KDE Plasma 6 Wayland"
arch=('any')
url="https://github.com/kuasha420/knot-mesh"
license=('MIT')
depends=(
    'python'
    'python-pyqt6'
    'layer-shell-qt'
    'openssh'
    'openssl'
    'iproute2'
    'deskflow'
    'libportal'
    'kde-cli-tools'
)
optdepends=(
    'kscreen-doctor: Wayland display auto-discovery on KDE Plasma 6'
    'wlr-randr: Wayland display auto-discovery for wlroots compositors'
    'libnotify: Desktop notification support for KVM cursor locking'
)
source=("knot-mesh-${pkgver}.tar.gz::https://github.com/kuasha420/knot-mesh/archive/refs/tags/v1.0.0-rc2.tar.gz")
sha256sums=('SKIP')

package() {
    if [ -d "${srcdir}/${pkgname}-${pkgver}" ]; then
        cd "${srcdir}/${pkgname}-${pkgver}"
    elif [ -d "${srcdir}/${pkgname}-1.0.0-rc2" ]; then
        cd "${srcdir}/${pkgname}-1.0.0-rc2"
    else
        cd "${srcdir}"
    fi

    local destdir="${pkgdir}/usr/lib/knot-mesh"
    mkdir -p "${destdir}" "${pkgdir}/usr/bin"

    # Copy mesh core, bin, and templates
    cp -r core bin templates "${destdir}/"

    # Copy systemd units if present
    if [ -d "systemd" ]; then
        cp -r systemd "${destdir}/"
    fi

    # Copy web if present
    if [ -d "web" ]; then
        cp -r web "${destdir}/"
    fi

    # Symlink executables to /usr/bin
    ln -sf "/usr/lib/knot-mesh/bin/knot" "${pkgdir}/usr/bin/knot"
    ln -sf "/usr/lib/knot-mesh/bin/knot-installer" "${pkgdir}/usr/bin/knot-installer"
    ln -sf "/usr/lib/knot-mesh/bin/knot-agent" "${pkgdir}/usr/bin/knot-agent"
    ln -sf "/usr/lib/knot-mesh/bin/knot-stripd" "${pkgdir}/usr/bin/knot-stripd"

    # Install license if present
    if [ -f "LICENSE" ]; then
        install -Dm644 LICENSE "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
    fi
}
