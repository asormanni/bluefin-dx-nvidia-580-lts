# Custom Bluefin DX image with Nvidia 580 LTS support (from negativo17 repo)
# Heavily inspired by https://github.com/serandel/bluefin-dx-slimbook (a big thank you)
# Andrea Sormanni <andrea.sormanni@gmail.com>

ARG BASE_IMAGE=ghcr.io/ublue-os/bluefin-dx

FROM ${BASE_IMAGE}:stable

RUN <<-EOF
	set -eux

	KVER=$(rpm -qa kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')
	echo "Building for kernel: ${KVER}"

	# Install REAL kernel-devel (replacing the stub entry in the RPM DB).
	# Active Fedora repos only carry the current kernel-devel; fall back to
	# Koji, which archives every build permanently.
	rpm -e --nodeps kernel-devel-${KVER} 2>/dev/null || true
	if ! dnf install -y kernel-devel-${KVER}; then
		KVER_VER="${KVER%%-*}"
		KVER_REST="${KVER#*-}"
		KVER_ARCH="${KVER_REST##*.}"
		KVER_REL="${KVER_REST%.*}"
		dnf install -y "https://kojipkgs.fedoraproject.org/packages/kernel/${KVER_VER}/${KVER_REL}/${KVER_ARCH}/kernel-devel-${KVER}.rpm"
	fi
	ls -la /usr/src/kernels/

	### NVIDIA 580 LTS repository (negativo17)

	cd /etc/yum.repos.d
	wget https://negativo17.org/repos/fedora-nvidia-580.repo
	dnf config-manager setopt fedora-nvidia-580.priority=90

	### NVIDIA 580 LTS packages
	dnf install --disablerepo="fedora-multimedia" -y --setopt=tsflags=noscripts \
		nvidia-driver akmod-nvidia nvidia-settings nvidia-driver-libs.i686
	
	# Prepare a working directory and writable /tmp for the akmods user
	chmod 1777 /tmp
	echo
	mkdir -p /var/lib/akmods
	chown akmods:akmods /var/lib/akmods

	# Build each kernel module RPM as the akmods user
	ARCH=$(uname -m)
	for MODULE in nvidia-kmod ; do
		SRPM=$(ls /usr/src/akmods/${MODULE}-*.src.rpm)
		echo "Building ${MODULE} akmod RPM for kernel ${KVER}..."
		su -s /bin/bash akmods -c "cd /var/lib/akmods && HOME=/var/lib/akmods akmodsbuild --target ${ARCH} --kernels ${KVER} ${SRPM}"
	done

	# Install the built kmod RPMs as root
	dnf install -y \
		/var/lib/akmods/kmod-nvidia-${KVER}-*.rpm 

	# Verify modules landed where the kernel expects them
	ls -la /usr/lib/modules/${KVER}/extra/ || echo "Checking module location..."

	# Drop kernel-devel to save space; modules are already compiled
	dnf remove -y kernel-devel
	dnf clean all
EOF

# Customize os-release for bootloader branding 
RUN <<-EOF
	set -eux
	NVIDIA_DIGEST=580-LTS
	CURRENT_VERSION=$(grep '^VERSION=' /usr/lib/os-release | cut -d'"' -f2)
	NVIDIA_SHORT=$(echo "${NVIDIA_DIGEST}" | cut -c1-3)
	NEW_VERSION="${CURRENT_VERSION} + nvidia ${NVIDIA_SHORT}"
	sed -i "s/^NAME=.*/NAME=\"Bluefin DX nvidia 580-LTS\"/" /usr/lib/os-release
	sed -i "s/^VERSION=.*/VERSION=\"${NEW_VERSION}\"/" /usr/lib/os-release
	sed -i "s/^PRETTY_NAME=.*/PRETTY_NAME=\"Bluefin DX nvidia 580 LTS (${NEW_VERSION})\"/" /usr/lib/os-release
	sed -i "s/^VARIANT_ID=.*/VARIANT_ID=bluefin-dx-nvidia-580-lts/" /usr/lib/os-release
	sed -i "s|^HOME_URL=.*|HOME_URL=\"https://github.com/serandel/bluefin-dx-580-lts\"|" /usr/lib/os-release
EOF

# Standard ostree container commit
RUN ostree container commit
