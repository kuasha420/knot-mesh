# Maintainer: Arafat Zahan <kuasha420>
pkgname=knot-mesh
pkgver=1.0.0.rc4
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
    'webkit2gtk-4.1: Knot Kommand Kafe Tauri v2 native desktop container'
    'gtk3: Native system tray and Wayland/X11 container support'
)
source=("knot-mesh-${pkgver}.tar.gz::https://github.com/kuasha420/knot-mesh/archive/refs/tags/v1.0.0-rc4.tar.gz")
sha256sums=('SKIP')

package() {
    if [ -d "${srcdir}/${pkgname}-${pkgver}" ]; then
        cd "${srcdir}/${pkgname}-${pkgver}"
    elif [ -d "${srcdir}/${pkgname}-1.0.0-rc4" ]; then
        cd "${srcdir}/${pkgname}-1.0.0-rc4"
    else
        cd "${srcdir}"
    fi

    local destdir="${pkgdir}/usr/lib/knot-mesh"
    mkdir -p "${destdir}" "${pkgdir}/usr/bin"

    # Copy mesh core, bin, templates, and skills
    cp -r core bin templates skills "${destdir}/"

    # Copy systemd units if present
    if [ -d "systemd" ]; then
        cp -r systemd "${destdir}/"
    fi

    # Copy web and src-tauri if present
    if [ -d "web" ]; then
        cp -r web "${destdir}/"
    fi
    if [ -d "src-tauri" ]; then
        cp -r src-tauri "${destdir}/"
        if [ -f "src-tauri/target/release/knot-kafe" ]; then
            install -Dm755 "src-tauri/target/release/knot-kafe" "${destdir}/bin/knot-kafe"
            ln -sf "/usr/lib/knot-mesh/bin/knot-kafe" "${pkgdir}/usr/bin/knot-kafe"
        fi
    fi

    # Symlink executables to /usr/bin
    ln -sf "/usr/lib/knot-mesh/bin/knot" "${pkgdir}/usr/bin/knot"
    ln -sf "/usr/lib/knot-mesh/bin/knot-installer" "${pkgdir}/usr/bin/knot-installer"
    ln -sf "/usr/lib/knot-mesh/bin/knot-agent" "${pkgdir}/usr/bin/knot-agent"
    ln -sf "/usr/lib/knot-mesh/bin/knot-hub" "${pkgdir}/usr/bin/knot-hub"
    ln -sf "/usr/lib/knot-mesh/bin/knot-autounlock" "${pkgdir}/usr/bin/knot-autounlock"
    ln -sf "/usr/lib/knot-mesh/bin/knot-stripd" "${pkgdir}/usr/bin/knot-stripd"

    # Install license if present
    if [ -f "LICENSE" ]; then
        install -Dm644 LICENSE "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
    fi
}
