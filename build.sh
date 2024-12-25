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
GKI_BUILD_USER="ambatubash69"
GKI_BUILD_TZ="Asia/Makassar"
GKI_BUILD_HOST="gacorprjkt"
CUSTOM_MANIFEST_REPO="https://github.com/DeliUstaTM/gki_manifest"
CUSTOM_MANIFEST_BRANCH="$GKI_VERSION"
ANYKERNEL_REPO="https://github.com/DeliUstaTM/Anykernel3"
ANYKERNEL_BRANCH="gki"
ZIP_NAME="villx-KVER-OPTIONE-$RANDOM_HASH.zip"
AOSP_CLANG_VERSION="r547379"
KERNEL_IMAGE="$WORK_DIR/out/${GKI_VERSION}/dist/Image"

# Import telegram functions
. "$BUILDER_DIR/telegram_functions.sh"

# if ksu = yes
if [ "${USE_KSU}" == "yes" ]; then
    ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/OPTIONE/KSU/g')
elif [ "${USE_KSU_NEXT_CI}" == "yes" ]; then
    ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/OPTIONE/KSU_NEXT_CI/g')
elif [ "${USE_KSU_NEXT}" == "yes" ]; then
    # if ksu-next = yes
    ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/OPTIONE/KSU_NEXT/g')
else
    # if ksu = no
    ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/OPTIONE-//g')
fi

## Install needed packages
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y automake flex lzop bison gperf build-essential zip curl zlib1g-dev g++-multilib libxml2-utils bzip2 libbz2-dev libbz2-1.0 libghc-bzlib-dev squashfs-tools pngcrush schedtool dpkg-dev liblz4-tool make optipng maven libssl-dev pwgen libswitch-perl policycoreutils minicom libxml-sax-base-perl libxml-simple-perl bc libc6-dev-i386 lib32ncurses5-dev libx11-dev lib32z-dev libgl1-mesa-dev xsltproc unzip device-tree-compiler python2 rename libelf-dev dwarves rsync

## Install Google's repo
curl -so repo https://storage.googleapis.com/git-repo-downloads/repo
sudo mv repo /usr/bin
sudo chmod +x /usr/bin/repo

## Clone AnyKernel
git clone --depth=1 "$ANYKERNEL_REPO" -b "$ANYKERNEL_BRANCH" "$WORK_DIR/anykernel"

# Repo sync
repo init --depth 1 "$CUSTOM_MANIFEST_REPO" -b "$CUSTOM_MANIFEST_BRANCH"
repo sync -j$(nproc --all) --force-sync

## Extract kernel version, git commit string
cd "$WORK_DIR/common"
KERNEL_VERSION=$(make kernelversion)
LAST_COMMIT_KERNEL=$(git log --format="%s" -n 1)
cd "$WORK_DIR"

# Apply some patch to _setup_env.sh
sed -i \
    -e "s|^export TZ=.*|export TZ=$GKI_BUILD_TZ|" \
    -e "s|^export KBUILD_BUILD_USER=.*|export KBUILD_BUILD_USER=$GKI_BUILD_USER|" \
    -e "s|^export KBUILD_BUILD_HOST=.*|export KBUILD_BUILD_HOST=$GKI_BUILD_HOST|" \
    -e "s|^export KBUILD_BUILD_TIMESTAMP=.*|export KBUILD_BUILD_TIMESTAMP=\$(date)|" \
    build/_setup_env.sh

# Set aosp clang version
sed -i "s/DUMMY1/$AOSP_CLANG_VERSION/g" $WORK_DIR/common/build.config.common

## Set kernel version in ZIP_NAME
ZIP_NAME=$(echo "$ZIP_NAME" | sed "s/KVER/$KERNEL_VERSION/g")

## Download Clang
rm -rf $WORK_DIR/prebuilts-master
mkdir -p $WORK_DIR/prebuilts-master/clang/host/linux-x86/clang-$AOSP_CLANG_VERSION
wget -qO $WORK_DIR/clang.tar.gz https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-$AOSP_CLANG_VERSION.tar.gz
tar -xf $WORK_DIR/clang.tar.gz -C $WORK_DIR/prebuilts-master/clang/host/linux-x86/clang-$AOSP_CLANG_VERSION
rm -f $WORK_DIR/clang.tar.gz

COMPILER_STRING=$("$WORK_DIR/prebuilts-master/clang/host/linux-x86/clang-${AOSP_CLANG_VERSION}/bin/clang" -v 2>&1 | head -n 1 | sed 's/(https..*//' | sed 's/ version//')

## KSU
if [ "${USE_KSU_NEXT}" == "yes" ]; then
        # Enable SUS🤨FS by default
        KSU_NEXT_BRANCH=next-susfs-$(echo "$GKI_VERSION" | sed 's/ndroid//g')
        curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/refs/heads/${KSU_NEXT_BRANCH}/kernel/setup.sh" | bash -
        cd "$WORK_DIR/KernelSU-Next"
        KSU_NEXT_VERSION=$(git describe --abbrev=0 --tags)
        cd "$WORK_DIR"
elif [ "${USE_KSU_NEXT_CI}" == "yes" ]; then
        curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/refs/heads/next/kernel/setup.sh" | bash - next-susfs-a12-5.10
        cd "$WORK_DIR/KernelSU-Next"
        KSU_NEXT_VERSION=$(git describe --abbrev=0 --tags)
        cd "$WORK_DIR"
elif [ "${USE_KSU}" == "yes" ]; then
    curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/refs/heads/main/kernel/setup.sh" | bash -
    cd "$WORK_DIR/KernelSU"
    KSU_VERSION=$(git describe --abbrev=0 --tags)
    cd "$WORK_DIR"
elif [ "${USE_KSU_NEXT}" == "yes" ] && [ "${USE_KSU}" == "yes" ]; then
    echo
    echo "KSU-Next: true"
    echo "KSU: true"
    echo "You are stupid!"
    exit 1
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
elif [ "${USE_KSU_SUSFS}" == "yes" ] && [ "$USE_KSU" != "yes" ]; then
    echo "[ERROR] You can't use SUSFS without KSU enabled!"
    exit 1
fi

cd "$WORK_DIR"

text=$(cat <<EOF
*~~~ GKI CI ~~~*
*GKI Version*: \`${GKI_VERSION}\`
*Kernel Version*: \`${KERNEL_VERSION}\`
*KSU*: \`$([ "$USE_KSU" == "yes" ] && echo "true" || echo "false")\`
*KSU Version*: \`$([ "$USE_KSU" == "yes" ] && echo "$KSU_VERSION" || echo "null")\`
*KSU-Next*: \`$([ "$USE_KSU_NEXT" == "yes" ] && echo "true" || echo "false")\`
*KSU-Next Version*: \`$([ "$USE_KSU_NEXT" == "yes" ] && echo "$KSU_NEXT_VERSION" || echo "null")\`
*KSU-Next-CI*: \`$([ "$USE_KSU_NEXT_CI" == "yes" ] && echo "true" || echo "false")\`
*KSU-Next Version*: \`$([ "$USE_KSU_NEXT" == "yes" ] && echo "$KSU_NEXT_VERSION" || echo "null")\`
*SUSFS*: \`$([ "${USE_KSU_SUSFS}" == "yes" ] && echo "true" || echo "false")\`
*SUSFS Version*: \`$([ "${USE_KSU_SUSFS}" == "yes" ] && echo "$SUSFS_VERSION" || echo "null")\`
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

# Build GKI
set +e
LTO="$LTO_TYPE" BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh -j$(( $(nproc --all) - 1 )) 2>&1 | tee "$WORK_DIR/build_log.txt"
set -e

# Upload to telegram
if ! [ -f "$KERNEL_IMAGE" ]; then
    send_msg "❌ GKI Build failed!"
    upload_file "$WORK_DIR/build_log.txt"
else
    send_msg "✅ GKI Build succeeded"
    
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
    upload_file "$WORK_DIR/$ZIP_NAME"
    
    if [ "$USE_KSU_SUSFS" == "yes" ]; then
        cd "$SUSFS_MODULE"
        zip -r9 "$SUSFS_MODULE_ZIP" * -x README.md
        mv "$SUSFS_MODULE_ZIP" "$WORK_DIR"
        cd "$WORK_DIR"
        upload_file "$WORK_DIR/$SUSFS_MODULE_ZIP"
    fi

    upload_file "$WORK_DIR/build_log.txt"
fi
