FROM registry.access.redhat.com/ubi9/ubi:latest

# Override at build time: --build-arg RPM_URL=https://...
ARG RPM_URL=https://2.chacra.ceph.com/r/ceph/wip-dang-standalone/d494ddeb57b4790420f4a7fe604b28296df1a552/centos/9/flavors/debug/x86_64/ceph-rgw-standalone-21.0.0-332.gd494ddeb.el9.x86_64.rpm

USER root

# Replace curl-minimal with full curl, add base tools, enable EPEL9 + CRB,
# and add CentOS Stream 9 AppStream (for librabbitmq which is not in EPEL9)
RUN dnf install -y --allowerasing python3 curl unzip \
    && dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm \
    && /usr/bin/crb enable \
    && printf '[cs9-baseos]\nname=CentOS Stream 9 BaseOS\nbaseurl=https://mirror.stream.centos.org/9-stream/BaseOS/x86_64/os/\nenabled=1\ngpgcheck=0\n[cs9-appstream]\nname=CentOS Stream 9 AppStream\nbaseurl=https://mirror.stream.centos.org/9-stream/AppStream/x86_64/os/\nenabled=1\ngpgcheck=0\n' \
       > /etc/yum.repos.d/centos-stream9.repo \
    && dnf clean all

# Install RGW runtime deps:
#   EPEL9:    libarrow/parquet (Arrow 9), librdkafka, lttng-ust, liboath, gperftools-libs
#   UBI9 CRB: libicu (libicuuc.so.67)
#   CS9 AS:   librabbitmq
RUN dnf install -y \
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
    && dnf clean all \
    && rm -f /etc/yum.repos.d/centos-stream9.repo

# Download the standalone RGW RPM and its librados2 companion from the same chacra tree.
# Installed together so rpm can satisfy their circular libceph-common dependency.
# --nodeps skips the ceph-selinux package dep (SELinux policy is host-managed in containers)
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
