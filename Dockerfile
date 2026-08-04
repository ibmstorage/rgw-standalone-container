FROM registry.redhat.io/ubi10/ubi-minimal:latest

USER root

# Copy entire submodule once
COPY zgw-posix /opt/zgw-posix
WORKDIR /opt/zgw-posix/

# Register with subscription manager
RUN microdnf install -y subscription-manager
RUN --mount=type=secret,id=org-id --mount=type=secret,id=activation-key subscription-manager register --activationkey=$(cat /run/secrets/activation-key) --org=$(cat /run/secrets/org-id)
RUN subscription-manager repos --enable=codeready-builder-for-rhel-10-$(arch)-rpms
#======================================================

# Install AWS CLI for in-container debugging
RUN microdnf install -y awscli unzip \
    && microdnf clean all

RUN rm -f /etc/yum.repos.d/ubi.repo
COPY ceph.repo /etc/yum.repos.d

COPY <<EOF /etc/yum.conf
[main]
gpgcheck=1
installonly_limit=3
clean_requirements_on_remove=True
best=False
skip_if_unavailable=False
cachedir=/var/cache/dnf
install_weak_deps=0
keepcache=True
tsflags=nodocs
EOF

# Install Arrow dependencies from IBM-CEPH repo first
RUN microdnf install -y --enablerepo=IBM-CEPH \
    libarrow-glib-libs \
    libarrow

# Create ceph user/group matching the conventional UID/GID 167
RUN getent group ceph > /dev/null  || groupadd -r -g 167 ceph \
    && getent passwd ceph > /dev/null || useradd -r -u 167 -g ceph \
       -d /var/lib/ceph -s /sbin/nologin -c "Ceph daemons" ceph

# Install ceph-rgw-standalone
RUN microdnf install -y --enablerepo=IBM-CEPH \
    --setopt=install_weak_deps=0 \
    ceph-rgw-standalone

# Copy files from submodule
COPY zgw-posix/docker/zgw-posix/ceph.conf /etc/ceph/ceph.conf
RUN chown ceph:ceph /etc/ceph/ceph.conf \
    && chown -R ceph:ceph /var/lib/ceph/radosgw

# Create home directory for ceph user
RUN mkdir -p /home/ceph/.aws \
    && chown -R ceph:ceph /home/ceph

ENV RGW_POSIX_BASE_PATH=/var/lib/ceph/rgw_posix_driver \
    RGW_POSIX_DATABASE_ROOT=/var/lib/ceph/rgw_posix_db \
    HOME=/home/ceph

COPY zgw-posix/docker/zgw-posix/entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# NOTE: This is a initial draft! may require changes
# Build specific labels
LABEL maintainer="Daniel Gryniewicz <dang1@ibm.com>"
LABEL com.redhat.component="rgw-standalone"
LABEL version=1.0.0
LABEL name="rgw-standalone-container"
LABEL description="IBM Storage Ceph Object Gateway Developer Edition"
LABEL summary="rgw-standalone-container for IBM Ceph Storage"
LABEL io.k8s.display-name="rgw-standalone-container"
LABEL io.openshift.tags="ibm ceph rgw-standalone-container"
