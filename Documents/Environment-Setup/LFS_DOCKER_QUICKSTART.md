# Complete LFS Build - Automated Instructions

## Build a Complete Linux From Scratch System in 2 Commands

### Automated Quick Start (Total Time: 8-12 hours)

```bash
# 1. Setup environment (5 minutes)
cd Documents/Environment-Setup/phase9/build_system/docker/
./build_fixed_container.sh

# 2. Start container with host storage access
docker run -it --name lfs-build --privileged \
  -v /tmp:/tmp \
  -v /home:/home \
  -v /mnt:/host-mnt \
  secureos/bootstrap:fixed /bin/bash

# 3. Inside container - Run complete automated LFS build (8-12 hours)
# The script will now see host storage options
/usr/local/bin/complete_lfs_build.sh

# 4. Boot your new LFS system
/usr/local/bin/boot_lfs_system.sh
```

### Storage Selection with Host Access
The automated build includes interactive storage selection with host storage access:
- **Option 1**: `/tmp/lfs` (Host /tmp mounted)
- **Option 2**: `/home/lfs` (Host /home mounted)
- **Option 3**: `/host-mnt/lfs` (Host /mnt mounted as /host-mnt)
- **Minimum**: 15GB required for LFS build

### Required Docker Volume Mounts
```bash
-v /tmp:/tmp          # Host /tmp access
-v /home:/home        # Host /home access  
-v /mnt:/host-mnt     # Host /mnt access
```

### What the Automated Build Does
- ✅ **Environment validation** - Checks tools and disk space
- ✅ **LFS directory setup** - Creates proper FHS structure
- ✅ **Package download** - Downloads and verifies all LFS 12.0 packages
- ✅ **Cross-compilation toolchain** - Builds binutils, GCC, glibc, libstdc++
- ✅ **Temporary system** - Builds essential tools (M4, ncurses, bash, etc.)
- ✅ **Final system** - Complete chroot build with all packages
- ✅ **System configuration** - Network, locale, fstab setup
- ✅ **Bootloader installation** - GRUB configuration
- ✅ **System image creation** - Bootable tar.gz archive

### Build Progress Monitoring
```bash
# Monitor build progress (in another terminal)
docker exec -it lfs-build tail -f /tmp/lfs_build_*.log

# Check current build stage
docker exec -it lfs-build cat /tmp/lfs_current_stage.txt

# Check time estimates
docker exec -it lfs-build cat /tmp/lfs_time_estimate.txt
```

---

## Detailed Step-by-Step Instructions

### Step 1: Prepare Build Environment
```bash
# Build the LFS container
cd Documents/Environment-Setup/phase9/build_system/docker/
./build_fixed_container.sh

# Start LFS build container with host storage access
docker run -it --name lfs-build \
  -v /tmp:/tmp \
  -v /home:/home \
  -v /mnt:/host-mnt \
  --privileged \
  secureos/bootstrap:fixed /bin/bash
```

### Step 2: Setup LFS Environment
```bash
# Inside container - setup LFS environment
export LFS=/mnt/lfs
export LFS_TGT=x86_64-lfs-linux-gnu
export PATH=/usr/bin:/bin
export MAKEFLAGS=-j$(nproc)

# Create directory structure
mkdir -pv $LFS/{etc,var} $LFS/usr/{bin,lib,sbin} $LFS/sources $LFS/tools
for i in bin lib sbin; do ln -sfv usr/$i $LFS/$i; done
chmod -v a+wt $LFS/sources
```

### Step 3: Download LFS Packages
```bash
# Download all LFS packages
cd $LFS/sources
wget https://www.linuxfromscratch.org/lfs/downloads/12.0/wget-list-sysv
wget --input-file=wget-list-sysv --continue
```

### Step 4: Build Cross Toolchain (2-3 hours)
```bash
# Binutils Pass 1
tar -xf binutils-2.41.tar.xz
cd binutils-2.41
mkdir -v build && cd build
../configure --prefix=$LFS/tools --with-sysroot=$LFS --target=$LFS_TGT \
  --disable-nls --enable-gprofng=no --disable-werror --enable-default-hash-style=gnu
make && make install
cd $LFS/sources

# GCC Pass 1
tar -xf gcc-13.2.0.tar.xz
cd gcc-13.2.0
tar -xf ../mpfr-4.2.0.tar.xz && mv mpfr-4.2.0 mpfr
tar -xf ../gmp-6.3.0.tar.xz && mv gmp-6.3.0 gmp
tar -xf ../mpc-1.3.1.tar.gz && mv mpc-1.3.1 mpc
sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
mkdir -v build && cd build
../configure --target=$LFS_TGT --prefix=$LFS/tools --with-glibc-version=2.38 \
  --with-sysroot=$LFS --with-newlib --without-headers --enable-default-pie \
  --enable-default-ssp --disable-nls --disable-shared --disable-multilib \
  --disable-threads --disable-libatomic --disable-libgomp --disable-libquadmath \
  --disable-libssp --disable-libvtv --disable-libstdcxx --enable-languages=c,c++
make && make install
cd $LFS/sources

# Linux API Headers
tar -xf linux-6.4.12.tar.xz
cd linux-6.4.12
make mrproper
make headers
find usr/include -type f ! -name '*.h' -delete
cp -rv usr/include $LFS/usr
cd $LFS/sources

# Glibc
tar -xf glibc-2.38.tar.xz
cd glibc-2.38
case $(uname -m) in
    i?86)   ln -sfv ld-linux.so.2 $LFS/lib/ld-lsb.so.3 ;;
    x86_64) ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64 && ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64/ld-lsb-x86-64.so.3 ;;
esac
patch -Np1 -i ../glibc-2.38-fhs-1.patch
mkdir -v build && cd build
echo "rootsbindir=/usr/sbin" > configparms
../configure --prefix=/usr --host=$LFS_TGT --build=$(../scripts/config.guess) \
  --enable-kernel=4.14 --with-headers=$LFS/usr/include libc_cv_slibdir=/usr/lib
make && make DESTDIR=$LFS install
sed '/RTLDLIST=/s@/usr@@g' -i $LFS/usr/bin/ldd
cd $LFS/sources

# Libstdc++
cd gcc-13.2.0
rm -rf build && mkdir -v build && cd build
../libstdc++-v3/configure --host=$LFS_TGT --build=$(../config.guess) \
  --prefix=/usr --disable-multilib --disable-nls --disable-libstdcxx-pch \
  --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/13.2.0
make && make DESTDIR=$LFS install
rm -v $LFS/usr/lib/lib{stdc++{,exp,fs},supc++}.la
cd $LFS/sources
```

### Step 5: Build Temporary System (2-3 hours)
```bash
# Continue with remaining temporary tools...
# M4, Ncurses, Bash, Coreutils, Diffutils, File, Findutils, Gawk, Grep, Gzip, Make, Patch, Sed, Tar, Xz, Binutils Pass 2, GCC Pass 2
# Follow LFS book chapter 6 for complete list
```

### Step 6: Build Final System (4-6 hours)
```bash
# Enter chroot environment
sudo chroot "$LFS" /usr/bin/env -i HOME=/root TERM="$TERM" PS1='(lfs chroot) \u:\w\$ ' \
  PATH=/usr/bin:/usr/sbin /bin/bash --login

# Inside chroot - build all final packages
# Follow LFS book chapters 8-10 for complete system
```

## Key Build Commands

### Essential Environment Variables
```bash
export LFS=/mnt/lfs
export LFS_TGT=x86_64-lfs-linux-gnu
export PATH=/usr/bin:/bin
export MAKEFLAGS=-j$(nproc)
```

### Package Build Pattern
```bash
# For each package:
tar -xf package.tar.xz
cd package
# Configure, make, install
# Return to sources
cd $LFS/sources
```

### Chroot Entry
```bash
sudo chroot "$LFS" /usr/bin/env -i HOME=/root TERM="$TERM" \
  PS1='(lfs chroot) \u:\w\$ ' PATH=/usr/bin:/usr/sbin /bin/bash --login
```

## Monitor Build Progress

```bash
# Check disk usage
df -h $LFS

# Check current directory
pwd

# List built tools
ls -la $LFS/tools/bin/

# Test cross compiler
$LFS_TGT-gcc --version
```

## Build Stages and Time Estimates

1. **Environment Setup**: 5 minutes
2. **Package Download**: 10-15 minutes
3. **Cross Toolchain**: 2-3 hours
   - Binutils: 20 minutes
   - GCC pass 1: 45 minutes
   - Linux headers: 5 minutes
   - Glibc: 60 minutes
   - Libstdc++: 15 minutes
4. **Temporary System**: 2-3 hours
   - 25+ packages
5. **Final System**: 4-6 hours
   - 80+ packages including kernel
6. **System Configuration**: 30 minutes
7. **Bootloader Installation**: 15 minutes

**Total Time: 8-12 hours**

## Success Verification

```bash
# After build completes, verify system
ls -la $LFS/
# Should show: bin/ boot/ dev/ etc/ home/ lib/ media/ mnt/ opt/ proc/ root/ run/ sbin/ srv/ sys/ tmp/ usr/ var/

# Check kernel
ls -la $LFS/boot/
# Should show: vmlinuz-6.4.12-lfs-12.0

# Check bootloader
ls -la $LFS/boot/grub/
# Should show GRUB configuration

# Test chroot
sudo chroot $LFS /usr/bin/env -i \
  HOME=/root TERM="$TERM" \
  PS1='(lfs chroot) \u:\w\$ ' \
  PATH=/usr/bin:/usr/sbin \
  /bin/bash --login

# Inside chroot:
echo "LFS System Ready!"
exit
```

## Boot Your LFS System (Automated)

```bash
# Interactive boot menu
/usr/local/bin/boot_lfs_system.sh

# Or specific format:
/usr/local/bin/boot_lfs_system.sh --qemu    # Boot in QEMU VM
/usr/local/bin/boot_lfs_system.sh --iso     # Create bootable ISO
/usr/local/bin/boot_lfs_system.sh --vmdk    # Create VMware image
/usr/local/bin/boot_lfs_system.sh --raw     # Create raw disk image
```

### Boot Options Available
1. **QEMU Virtual Machine** (Recommended)
   - Boots directly with KVM acceleration
   - 2GB RAM, full GUI support
   - Network connectivity included

2. **Bootable ISO Image**
   - Creates `/tmp/secureos-lfs.iso`
   - Hybrid boot (UEFI/BIOS compatible)
   - Ready for USB/DVD burning

3. **VMware VMDK Image**
   - Creates `/tmp/secureos-lfs.vmdk`
   - VMware ESXi compatible
   - 8GB disk with bootloader

4. **Raw Disk Image**
   - Creates `/tmp/secureos-lfs-boot.img`
   - Direct disk deployment
   - GRUB bootloader included

## Troubleshooting

### Build Fails
```bash
# Check detailed logs
tail -100 /tmp/lfs_build_*.log

# Check current stage
cat /tmp/lfs_current_stage.txt

# Restart build from beginning
/usr/local/bin/complete_lfs_build.sh
```

### Out of Space
```bash
# Check space (need 20GB minimum)
df -h $LFS

# Clean build artifacts
/usr/local/bin/clean_lfs_build.sh
```

### Container Issues
```bash
# Restart container
docker restart lfs-build
docker exec -it lfs-build /bin/bash

# Or create new container
docker rm lfs-build
docker run -it --name lfs-build --privileged secureos/bootstrap:fixed /bin/bash
```

## Final Result

After successful build:
- Complete Linux system in `/mnt/lfs/`
- Bootable ISO: `/tmp/lfs-system.iso`
- VM image: `/tmp/lfs-system.qcow2`
- SecureOS components integrated
- Ready for production use

## Quick Commands Summary

```bash
# Complete automated build (working commands)
cd Documents/Environment-Setup/phase9/build_system/docker/
./build_fixed_container.sh
docker run -it --name lfs-build --privileged \
  -v /tmp:/tmp -v /home:/home -v /mnt:/host-mnt \
  secureos/bootstrap:fixed /bin/bash

# Inside container - run automated build
/usr/local/bin/complete_lfs_build.sh

# Boot the system (after build completes)
/usr/local/bin/boot_lfs_system.sh --raw
```

### Expected Results
- **Build Time**: 8-12 hours (fully automated)
- **System Image**: `/tmp/secureos-lfs-system.tar.gz` (complete system)
- **Boot Images**: ISO (~2GB), VMDK (~8GB), Raw disk images
- **Security**: Full SecureOS security components integrated
- **Compatibility**: UEFI/BIOS hybrid boot support

**Result**: Complete, bootable Linux From Scratch system with SecureOS security components - **FULLY AUTOMATED**.

---

## Manual Build Instructions (Advanced Users)

If you prefer manual control over the build process, the following sections provide step-by-step instructions for building LFS manually.