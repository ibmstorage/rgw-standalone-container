FROM quay.io/centos/centos:stream9

# Override at build time: --build-arg RPM_URL=https://...
ARG RPM_URL=https://2.chacra.ceph.com/r/ceph/wip-dang-standalone/d494ddeb57b4790420f4a7fe604b28296df1a552/centos/9/flavors/debug/x86_64/ceph-rgw-standalone-21.0.0-332.gd494ddeb.el9.x86_64.rpm

USER root

# Enable EPEL9 for libarrow, parquet-libs, gperftools-libs, liboath, lmdb-libs.
# Everything else (snappy, librabbitmq, libibverbs, lttng-ust, libicu, librdkafka)
# resolves from native CentOS Stream 9 repos — no repo grafting needed.
RUN dnf install -y epel-release && dnf clean all

# Install all RGW runtime deps
RUN dnf install -y --allowerasing \
        python3 \
        curl \
        unzip \
        snappy \
        lmdb-libs \
        libibverbs \
        librdmacm \
        libarrow \
        parquet-libs \
        librdkafka \
        lttng-ust \
        liboath \
        gperftools-libs \
        libicu \
        librabbitmq \
    && dnf clean all

# Derive the librados2 URL from the standalone RPM URL (same chacra tree, same version).
# Both are installed together so rpm resolves their mutual libceph-common dependency.
# --nodeps skips the ceph-selinux package dep (SELinux policy not needed in containers).
RUN CHACRA_BASE="$(dirname "${RPM_URL}")" \
    && LIBRADOS2_URL="${CHACRA_BASE}/$(basename "${RPM_URL}" | sed 's/ceph-rgw-standalone-/librados2-/')" \
    && curl -fsSL "${RPM_URL}" -o /tmp/ceph-rgw-standalone.rpm \
    && curl -fsSL "${LIBRADOS2_URL}" -o /tmp/librados2.rpm \
    && rpm -ivh --nodeps /tmp/librados2.rpm /tmp/ceph-rgw-standalone.rpm \
    && echo "/usr/lib64/ceph" > /etc/ld.so.conf.d/ceph.conf \
    && ldconfig \
    && rm -f /tmp/librados2.rpm /tmp/ceph-rgw-standalone.rpm

# AWS CLI v2 and s5cmd for in-container debugging
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws \
    && S5CMD_VERSION="2.2.2" \
    && curl -fsSL "https://github.com/peak/s5cmd/releases/download/v${S5CMD_VERSION}/s5cmd_${S5CMD_VERSION}_Linux-64bit.tar.gz" \
       | tar xzf - -C /usr/local/bin s5cmd \
    && chmod +x /usr/local/bin/s5cmd

# Create ceph user/group matching the conventional UID/GID 167
RUN groupadd -r -g 167 ceph \
    && useradd -r -u 167 -g ceph -d /home/ceph -s /sbin/nologin -c "Ceph daemons" ceph

# Create all required directories and set ownership
RUN mkdir -p /etc/ceph \
             /var/lib/ceph/radosgw \
             /var/lib/ceph/rgw_posix_driver \
             /var/lib/ceph/rgw_posix_db \
             /var/run/ceph \
             /home/ceph/.aws \
    && chown -R ceph:ceph /etc/ceph \
                          /var/lib/ceph \
                          /var/run/ceph \
                          /home/ceph

COPY ceph.conf /etc/ceph/ceph.conf
RUN chown ceph:ceph /etc/ceph/ceph.conf

ENV RGW_POSIX_BASE_PATH=/var/lib/ceph/rgw_posix_driver \
    RGW_POSIX_DATABASE_ROOT=/var/lib/ceph/rgw_posix_db \
    HOME=/home/ceph

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
