#!/usr/bin/env bash
set -e

# Check chat_id and token
if [ -z "$chat_id" ]; then
    echo "error: please fill your CHAT_ID secret!"
    exit 1
fi

if [ -z "$token" ]; then
    echo "error: please fill TOKEN secret!"
    exit 1
fi

mkdir -p android-kernel && cd android-kernel

## Variables

# DO NOT change
WORK_DIR=$(pwd)
BUILDER_DIR="$WORK_DIR/.."
RANDOM_HASH=$(head -c 20 /dev/urandom | sha1sum | head -c 7)
LAST_COMMIT_BUILDER=$(git log --format="%s" -n 1)

# Common
GKI_VERSION="android12-5.10"
CUSTOM_MANIFEST_REPO="https://github.com/ambatubash69/gki_manifest"
CUSTOM_MANIFEST_BRANCH="$GKI_VERSION"
ANYKERNEL_REPO="https://github.com/ambatubash69/Anykernel3"
ANYKERNEL_BRANCH="gki"
ZIP_NAME="gki-KVER-OPTIONE-$RANDOM_HASH.zip"
AOSP_CLANG_VERSION="r536225"
KERNEL_IMAGE="$WORK_DIR/out/${GKI_VERSION}/dist/Image"

# Import telegram functions
. "$BUILDER_DIR/telegram_functions.sh"

# if ksu = yes
if [ "${USE_KSU}" == "yes" ]; then
    ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/OPTIONE/KSU/g')
else
    # if ksu = no
    ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/OPTIONE-//g')
fi

## Install needed packages
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y automake flex lzop bison gperf build-essential zip curl zlib1g-dev g++-multilib libxml2-utils bzip2 libbz2-dev libbz2-1.0 libghc-bzlib-dev squashfs-tools pngcrush schedtool dpkg-dev liblz4-tool make optipng maven libssl-dev pwgen libswitch-perl policycoreutils minicom libxml-sax-base-perl libxml-simple-perl bc libc6-dev-i386 lib32ncurses5-dev libx11-dev lib32z-dev libgl1-mesa-dev xsltproc unzip device-tree-compiler python2 rename libelf-dev dwarves rsync

## Install Google's repo
curl -o repo https://storage.googleapis.com/git-repo-downloads/repo
sudo mv repo /usr/bin
sudo chmod +x /usr/bin/repo

## Clone AnyKernel
git clone --depth=1 "$ANYKERNEL_REPO" -b "$ANYKERNEL_BRANCH" "$WORK_DIR/anykernel"

# Set swappiness
sudo sysctl vm.swappiness=100
sudo sysctl -p

# Repo sync
repo init --depth 1 "$CUSTOM_MANIFEST_REPO" -b "$CUSTOM_MANIFEST_BRANCH"
repo sync -j$(nproc --all) --force-sync

## Extract kernel version, git commit string
cd "$WORK_DIR/common"
KERNEL_VERSION=$(make kernelversion)
LAST_COMMIT_KERNEL=$(git log --format="%s" -n 1)
cd "$WORK_DIR"

# Set aosp clang version
sed -i "s/DUMMY1/$AOSP_CLANG_VERSION/g" $WORK_DIR/common/build.config.common

## Set kernel version in ZIP_NAME
ZIP_NAME=$(echo "$ZIP_NAME" | sed "s/KVER/$KERNEL_VERSION/g")

## Clone crdroid's clang
rm -rf "$WORK_DIR/prebuilts-master"
mkdir -p "$WORK_DIR/prebuilts-master/clang/host/linux-x86"
git clone --depth=1 "https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-${AOSP_CLANG_VERSION}" "$WORK_DIR/prebuilts-master/clang/host/linux-x86/clang-${AOSP_CLANG_VERSION}"
COMPILER_STRING=$("$WORK_DIR/prebuilts-master/clang/host/linux-x86/clang-${AOSP_CLANG_VERSION}/bin/clang" -v 2>&1 | head -n 1 | sed 's/(https..*//' | sed 's/ version//')

## KernelSU setup
if [ "${USE_KSU}" == "yes" ]; then
    curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -
    cd "$WORK_DIR/KernelSU"
    KSU_VERSION=$(git describe --abbrev=0 --tags)
    cd "$WORK_DIR"
fi

## Apply kernel patches
git config --global user.email "eraselk@proton.me"
git config --global user.name "eraselk"

## SUSFS4KSU
if [ "${USE_KSU}" == "yes" ] && [ "${USE_KSU_SUSFS}" == "yes" ]; then
    git clone --depth=1 "https://gitlab.com/simonpunk/susfs4ksu" -b "gki-${GKI_VERSION}"
    SUSFS_PATCHES="$WORK_DIR/susfs4ksu/kernel_patches"
    SUSFS_MODULE="$WORK_DIR/susfs4ksu/ksu_module_susfs"
    ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/KSU/KSUxSUSFS/g')
    cd "$WORK_DIR/susfs4ksu"
    LAST_COMMIT_SUSFS=$(git log --format="%s" -n 1)

    cd "$WORK_DIR/common"
    cp "$SUSFS_PATCHES/50_add_susfs_in_gki-${GKI_VERSION}.patch" .
    cp "$SUSFS_PATCHES/fs/susfs.c" ./fs/
    cp "$SUSFS_PATCHES/include/linux/susfs.h" ./include/linux/
    cp "$SUSFS_PATCHES/fs/sus_su.c" ./fs/
    cp "$SUSFS_PATCHES/include/linux/sus_su.h" ./include/linux/
    cd "$WORK_DIR/KernelSU"
    cp "$SUSFS_PATCHES/KernelSU/10_enable_susfs_for_ksu.patch" .
    patch -p1 <10_enable_susfs_for_ksu.patch || exit 1
    cd "$WORK_DIR/common"
    patch -p1 <50_add_susfs_in_gki-${GKI_VERSION}.patch || exit 1

    SUSFS_VERSION=$(grep -E '^#define SUSFS_VERSION' ./include/linux/susfs.h | cut -d' ' -f3 | sed 's/"//g')
    SUSFS_MODULE_ZIP="ksu_module_susfs_${SUSFS_VERSION}.zip"
elif [ "${USE_KSU_SUSFS}" == "yes" ]; then
    echo "[ERROR] You can't use SUSFS without KSU enabled!"
    exit 1
fi

cd "$WORK_DIR"

text=$(cat <<EOF
*~~~ GKI CI ~~~*
*GKI Version*: \`${GKI_VERSION}\`
*Kernel Version*: \`${KERNEL_VERSION}\`
*KSU*: \`$([ "$USE_KSU" == "yes" ] && echo "true" || echo "false")\`
$([ "$USE_KSU" == "yes" ] && echo "*KSU Version*: \`${KSU_VERSION}\`")
*SUSFS*: \`$([ "${USE_KSU_SUSFS}" == "yes" ] && echo "true" || echo "false")\`
$([ "${USE_KSU_SUSFS}" == "yes" ] && echo "*SUSFS Version*: \`${SUSFS_VERSION}\`")
*LTO Mode*: \`${LTO_TYPE}\`
*Host OS*: \`$(lsb_release -d -s)\`
*CPU Cores*: \`$(( $(nproc --all) - 1 ))\`
*Zip Output*: \`${ZIP_NAME}\`
*Compiler*: \`${COMPILER_STRING}\`
*Last Commit (Builder)*:
\`\`\`
${LAST_COMMIT_BUILDER}
\`\`\`
*Last Commit (Kernel)*:
\`\`\`
${LAST_COMMIT_KERNEL}
\`\`\`
$([ "${USE_KSU_SUSFS}" == "yes" ] && echo "*Last Commit (SUSFS)*:
\`\`\`
${LAST_COMMIT_SUSFS}
\`\`\`")
$([ "${NOTE}" ] && echo "*Release Note*:
\`\`\`
${NOTE}
\`\`\`")
EOF
)

send_msg "$text"

set +e

## Build GKI
LTO=$LTO_TYPE BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh -j$(( $(nproc --all) - 1 )) | tee "$WORK_DIR/build_log.txt"

set -e

if ! [ -f "$KERNEL_IMAGE" ]; then
    send_msg "Build failed!"
    upload_file "$WORK_DIR/build_log.txt" "Build Log"
else
    ## Zipping
    cd "$WORK_DIR/anykernel"
    sed -i "s/DUMMY1/$KERNEL_VERSION/g" anykernel.sh
    
    if [ -z "$USE_KSU" ]; then
        sed -i "s/KSUDUMMY2 //g" anykernel.sh
    fi
    
    if [ -z "$USE_KSU_SUSFS" ]; then
        sed -i "s/DUMMY2//g" anykernel.sh
    else
        sed -i "s/DUMMY2/xSUSFS/g" anykernel.sh
    fi
    
    cp "$KERNEL_IMAGE" .
    zip -r9 "$ZIP_NAME" * -x LICENSE
    mv "$ZIP_NAME" "$WORK_DIR"
    cd "$WORK_DIR"
    
    if [ "$USE_KSU_SUSFS" == "yes" ]; then
        cd "$SUSFS_MODULE"
        zip -r9 "$SUSFS_MODULE_ZIP" * -x README.md
        mv "$SUSFS_MODULE_ZIP" "$WORK_DIR"
        cd "$WORK_DIR"
    fi
    upload_file "$WORK_DIR/$ZIP_NAME" "GKI $KERNEL_VERSION$([ "$USE_KSU" == "yes" ] && echo " // KSU ${KSU_VERSION}")$([ "$USE_KSU_SUSFS" == "yes" ] && echo " // SUSFS $SUSFS_VERSION")"
    if [ "$USE_KSU_SUSFS" == "yes" ]; then
        upload_file "$WORK_DIR/$SUSFS_MODULE_ZIP" "SUSFS Module"
    fi
    upload_file "$WORK_DIR/build_log.txt" "Build Log"
fi
