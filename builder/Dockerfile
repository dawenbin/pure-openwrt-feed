# 编译宿主镜像：只装宿主工具，不含 OpenWrt SDK（SDK 由 scripts/build.sh 下载校验后挂进来）。
#
# 为什么不用官方 openwrt/sdk 镜像：
#   它基于 Debian 11，自带 pahole 1.20，不认识 6.12 内核 DWARF 里的
#   DW_TAG_unspecified_type，也不支持 --btf_encode_detached / --btf_features。
#
# 为什么是 Debian 12 而不是 13：
#   OpenWrt 的主机检查要求 python3-distutils，Debian 13 已移除（PEP 632）。
#
# 为什么 pahole 从源码编：
#   与 6.12 内核 scripts/Makefile.btf 的 --btf_features 写法对齐需要 >= 1.26，
#   钉在 1.32 的提交上，行为确定，升级只改两个 ARG。
#
# 基础镜像钉 digest：tag 会漂移，digest 不会。

FROM debian:12-slim@sha256:99c0b25c46d0214d5a2091092e7908907dcaecd6a962cde0ac700acee222b6f3

ARG PAHOLE_VERSION=1.32
ARG PAHOLE_COMMIT=fa725d687ce3a712ef296b46bc63ea57ef466014

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential make cmake \
        git ca-certificates curl wget rsync unzip bzip2 xz-utils zstd \
        gawk gettext bison flex bc file patch diffstat time \
        libncurses-dev libssl-dev zlib1g-dev \
        libelf-dev libdw-dev \
        python3 python3-distutils python3-setuptools \
        perl cpio \
    && rm -rf /var/lib/apt/lists/*

# 按提交校验，tag 被改指向也能发现
RUN git clone -b "v${PAHOLE_VERSION}" https://github.com/acmel/dwarves.git /tmp/dwarves \
    && test "$(git -C /tmp/dwarves rev-parse HEAD)" = "${PAHOLE_COMMIT}" \
    && mkdir -p /tmp/dwarves/build \
    && cd /tmp/dwarves/build \
    && cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local .. \
    && make -j"$(nproc)" \
    && make install \
    && ldconfig \
    && rm -rf /tmp/dwarves \
    && test "$(pahole --version)" = "v${PAHOLE_VERSION}"

RUN pahole --help 2>&1 | grep -q -- '--btf_encode_detached' \
    && pahole --supported_btf_features | grep -q decl_tag_kfuncs

WORKDIR /builder
