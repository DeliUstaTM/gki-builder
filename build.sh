#!/usr/bin/env bash
set -e

# Check chat_id and token
if [[ -z $chat_id ]]; then
    echo "error: please fill your CHAT_ID secret!"
    exit 1
fi

if [[ -z $token ]]; then
    echo "error: please fill TOKEN secret!"
    exit 1
fi

mkdir -p android-kernel && cd android-kernel

## Variables

# Static variable, DO NOT change
WORK_DIR=$(pwd)
BUILDER_DIR="$WORK_DIR/.."
RANDOM_HASH=$(head -c 20 /dev/urandom | sha1sum | head -c 7)

# Common
GKI_VERSION="android12-5.10"
GKI_BUILD_USER="ambatubash69"
GKI_BUILD_HOST="gacorprjkt"
GKI_BUILD_TZ="Asia/Makassar"
CUSTOM_MANIFEST_REPO="https://github.com/DelitUstaTV/gki_manifest"
CUSTOM_MANIFEST_BRANCH="$GKI_VERSION"
ANYKERNEL_REPO="https://github.com/DeliUstaTV/Anykernel3"
ANYKERNEL_BRANCH="gki"
ZIP_NAME="v1llx-KVER-OPTIONE-$RANDOM_HASH.zip"
#AOSP_CLANG_VERSION="r547379"
KERNEL_IMAGE="$WORK_DIR/out/${GKI_VERSION}/dist/Image"

# Import telegram functions
. "$BUILDER_DIR/telegram_functions.sh"

# if ksu = yes
if [[ ${USE_KSU} == "yes" ]]; then
    ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/OPTIONE/KSU/g')
elif [[ ${USE_KSU_NEXT} == "yes" ]]; then
    # if ksu-next = yes
    ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/OPTIONE/KSU_NEXT/g')
else
    # if ksu = no
    ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/OPTIONE-//g')
fi

## Install needed packages
sudo apt update -y
sudo apt install -y rsync bash git perl rsync tar

## Install Google's repo
curl -so repo https://storage.googleapis.com/git-repo-downloads/repo
sudo mv repo /usr/bin
sudo chmod +x /usr/bin/repo

## Clone AnyKernel
git clone --depth=1 "$ANYKERNEL_REPO" -b "$ANYKERNEL_BRANCH" "$WORK_DIR/anykernel"

# Repo sync
repo init --depth 1 "$CUSTOM_MANIFEST_REPO" -b "$CUSTOM_MANIFEST_BRANCH"
repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync -j$(nproc --all)

## Extract kernel version
cd "$WORK_DIR/common"
KERNEL_VERSION=$(make kernelversion)
cd "$WORK_DIR"

# Apply some patch to _setup_env.sh
sed -i \
    -e "s|^export TZ=.*|export TZ=$GKI_BUILD_TZ|" \
    -e "s|^export KBUILD_BUILD_USER=.*|export KBUILD_BUILD_USER=$GKI_BUILD_USER|" \
    -e "s|^export KBUILD_BUILD_HOST=.*|export KBUILD_BUILD_HOST=$GKI_BUILD_HOST|" \
    -e 's|^export KBUILD_BUILD_TIMESTAMP=.*|export KBUILD_BUILD_TIMESTAMP=$(date)|' \
    build/_setup_env.sh

# Set aosp clang version
#sed -i "s/DUMMY1/$AOSP_CLANG_VERSION/g" $WORK_DIR/common/build.config.common

## Set kernel version in ZIP_NAME
ZIP_NAME=$(echo "$ZIP_NAME" | sed "s/KVER/$KERNEL_VERSION/g")

## Download Clang
wget https://apt.llvm.org/llvm.sh
chmod +x llvm.sh
sudo ./llvm.sh 20 all 

sudo apt install -y clang

## KSU or KSU-Next setup
if [[ ${USE_KSU_NEXT} == "yes" ]]; then

    if [[ $USE_KSU_SUSFS == "yes" ]]; then
        KSU_NEXT_BRANCH=next-susfs-$(echo "$GKI_VERSION" | sed 's/ndroid//g')
    elif [[ $USE_KSU_SUSFS != "yes" ]]; then
        KSU_NEXT_BRANCH=next
    fi
    
    wget -qO setup.sh https://raw.githubusercontent.com/rifsxd/KernelSU-Next/refs/heads/next/kernel/setup.sh
    chmod +x setup.sh
    bash ./setup.sh "$KSU_NEXT_BRANCH"
    cd "$WORK_DIR/KernelSU-Next"
    REPO_LINK=$(git config --get remote.origin.url)
    KSU_NEXT_VERSION=$(git ls-remote --tags $REPO_LINK | grep -o 'refs/tags/.*' | grep -v '\^{}' | sed 's#refs/tags/##' | sort -V | tail -n 1)
    cd "$WORK_DIR"
elif [[ ${USE_KSU} == "yes" ]]; then
    curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/refs/heads/main/kernel/setup.sh" | bash -
    cd "$WORK_DIR/KernelSU"
    KSU_VERSION=$(git describe --abbrev=0 --tags)
    cd "$WORK_DIR"
elif [[ ${USE_KSU_NEXT} == "yes" ]] && [[ ${USE_KSU} == "yes" ]]; then
    echo
    echo "Bruh"
    exit 1
fi

## Apply kernel patches
git config --global user.email "kontol@example.com"
git config --global user.name "Your Name"

## SUSFS4KSU
if [[ ${USE_KSU} == "yes" ]] || [[ $USE_KSU_NEXT == "yes" ]] && [[ ${USE_KSU_SUSFS} == "yes" ]]; then
    git clone --depth=1 "https://gitlab.com/simonpunk/susfs4ksu" -b "gki-${GKI_VERSION}"
    SUSFS_PATCHES="$WORK_DIR/susfs4ksu/kernel_patches"

    cd "$WORK_DIR/common"
    if [[ $USE_KSU == "yes" ]]; then
        ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/KSU/KSUxSUSFS/g')
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
    elif [[ $USE_KSU_NEXT == "yes" ]]; then
        ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/KSU_NEXT/KSU_NEXTxSUSFS/g')
        cp "$SUSFS_PATCHES/50_add_susfs_in_gki-${GKI_VERSION}.patch" .
        cp "$SUSFS_PATCHES/fs/susfs.c" ./fs/
        cp "$SUSFS_PATCHES/include/linux/susfs.h" ./include/linux/
        cp "$SUSFS_PATCHES/fs/sus_su.c" ./fs/
        cp "$SUSFS_PATCHES/include/linux/sus_su.h" ./include/linux/
        patch -p1 <50_add_susfs_in_gki-${GKI_VERSION}.patch || exit 1
    fi

    SUSFS_VERSION=$(grep -E '^#define SUSFS_VERSION' ./include/linux/susfs.h | cut -d' ' -f3 | sed 's/"//g')
elif [[ ${USE_KSU_SUSFS} == "yes" ]] && [[ $USE_KSU != "yes" ]] && [[ $USE_KSU_NEXT != "yes" ]]; then
    echo "[[ERROR]] You can't use SUSFS without KSU or KSU-Next enabled!"
    exit 1
fi

cd "$WORK_DIR"

text=$(
    cat <<EOF
*~~~ GKI Build Started ~~~*
*GKI Version*: \`${GKI_VERSION}\`
*Kernel Version*: \`${KERNEL_VERSION}\`
*Build Status*: \`${STATUS}\`
*Date*: \`$(TZ=$GKI_BUILD_TZ date)\`
*KSU*: \`$([[ $USE_KSU == "yes" ]] && echo "true" || echo "false")\`
*KSU Version*: \`$([[ $USE_KSU == "yes" ]] && echo "$KSU_VERSION" || echo "null")\`
*KSU-Next*: \`$([[ $USE_KSU_NEXT == "yes" ]] && echo "true" || echo "false")\`
*KSU-Next Version*: \`$([[ $USE_KSU_NEXT == "yes" ]] && echo "$KSU_NEXT_VERSION" || echo "null")\`
*SUSFS*: \`$([[ ${USE_KSU_SUSFS} == "yes" ]] && echo "true" || echo "false")\`
*SUSFS Version*: \`$([[ ${USE_KSU_SUSFS} == "yes" ]] && echo "$SUSFS_VERSION" || echo "null")\`
*Compiler*: \`${COMPILER_STRING}\`
EOF
)

send_msg "$text"

# Build GKI
set +e
BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh -j$(($(nproc --all) - 1)) 2>&1 | tee "$WORK_DIR/build_log.txt"
set -e

# Upload to telegram
if ! [[ -f $KERNEL_IMAGE ]]; then
    send_msg "❌ GKI Build failed!"
    upload_file "$WORK_DIR/build_log.txt"
    exit 1
else
    send_msg "✅ GKI Build succeeded"

    ## Zipping
    cd "$WORK_DIR/anykernel"
    sed -i "s/DUMMY1/$KERNEL_VERSION/g" anykernel.sh

    if [[ $USE_KSU != "yes" ]] && [[ $USE_KSU_NEXT != "yes" ]]; then
        sed -i "s/KSUDUMMY2 //g" anykernel.sh
    elif [[ $USE_KSU != "yes" ]] && [[ $USE_KSU_NEXT == "yes" ]]; then
        sed -i "s/KSU/KSU-Next/g" anykernel.sh
    fi

    if [[ $USE_KSU_SUSFS != "yes" ]]; then
        sed -i "s/DUMMY2//g" anykernel.sh
    elif [[ $USE_KSU_SUSFS == "yes" ]]; then
        sed -i "s/DUMMY2/xSUSFS/g" anykernel.sh
    fi

    cp "$KERNEL_IMAGE" .
    zip -r9 "$ZIP_NAME" * -x LICENSE
    mv "$ZIP_NAME" "$WORK_DIR"
    cd "$WORK_DIR"
    upload_file "$WORK_DIR/$ZIP_NAME"
    upload_file "$WORK_DIR/build_log.txt"
    exit 0
fi
