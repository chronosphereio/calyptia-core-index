#!/usr/bin/env bash
set -eu

# Configuration variables, all of these should use the INSTALL_CALYPTIA_ prefix to make it simple and clear.
# Each handles a specific option that may also then be overridden via a command line argument too.

# By default we install kubectl as part of this process, set this to 'yes' to prevent that.
DISABLE_KUBECTL=${INSTALL_CALYPTIA_DISABLE_KUBECTL:-no}
# By default we install K3S as part of this process, set this to 'yes' to prevent that.
# This is not recommended as Calyptia Core is intended to be used with K3S but it can be used to run with
# another K8S provider.
DISABLE_K3S=${INSTALL_CALYPTIA_DISABLE_K3S:-no}
# Optionally install the Kubeshark tool, it is disabled by default, by setting to 'no'.
# See https://github.com/kubeshark/kubeshark for more detail.
DISABLE_KUBESHARK=${INSTALL_CALYPTIA_DISABLE_KUBESHARK:-yes}
# Optionally install the Kubernetes dashboard for k3s. Disabled by default so enable by setting to 'no'.
DISABLE_KUBEDASHBOARD=${INSTALL_CALYPTIA_DISABLE_KUBEDASHBOARD:-yes}

# The user to install Calyptia Core as, it must pre-exist.
PROVISIONED_USER=${INSTALL_CALYPTIA_PROVISIONED_USER:-$USER}
# The group to install Calyptia Core as, it must pre-exist.
PROVISIONED_GROUP=${INSTALL_CALYPTIA_PROVISIONED_GROUP:-$(id -gn)}
# The location to install Calyptia Core, it will be created during installation.
# Upgrading of existing versions is not supported.
CALYPTIA_CORE_DIR=${INSTALL_CALYPTIA_CORE_DIR:-/opt/calyptia-core}
# The version of Calyptia Core to install.
RELEASE_VERSION=${INSTALL_CALYPTIA_RELEASE_VERSION:-0.4.6}
# The version of Calyptia CLI to install.
CLI_RELEASE_VERSION=${INSTALL_CALYPTIA_CLI_RELEASE_VERSION:-0.48.0}
# Optionally just run the checks and do not install by setting to 'yes'.
DRY_RUN=${INSTALL_CALYPTIA_DRY_RUN:-no}

# The version of K3S to install.
K3S_VERSION=${INSTALL_CALYPTIA_K3S_VERSION:-v1.25.3+k3s1}
# The location of the kubeconfig for K3S
K3S_KUBECONFIG_OUTPUT=${INSTALL_CALYPTIA_K3S_KUBECONFIG_OUTPUT:-/etc/rancher/k3s/k3s.yaml}

# Internal variables
IGNORE_ERRORS=no
CURL_PARAMETERS=""
SSL_VERIFY="1"
# Output variables - set to empty if disabled
Color_Off='\033[0m'
Red='\033[0;31m'
Green='\033[0;32m'
Yellow='\033[0;33m'

function info()
{
    echo -e "$Green"'[INFO]  ' "$@" "$Color_Off"
}

function warn()
{
    echo -e "$Yellow"'[WARN]  ' "$@" "$Color_Off" >&2
}

function fatal()
{
    echo -e "$Red"'[ERROR] ' "$@" "$Color_Off" >&2
    exit 1
}

function error_ignorable() {
    if [[ "$IGNORE_ERRORS" == "yes" ]]; then
        warn "$@"
    else
        fatal "$@"
    fi
}

function verify_system() {
    if command -v curl &> /dev/null; then
        info "Found curl"
    else
        fatal 'No curl command present'
    fi

    if [ -x /bin/systemctl ] || type systemctl &> /dev/null; then
        info "Found systemctl"
    else
        fatal 'Can not find systemctl'
    fi

    if id "$PROVISIONED_USER" &> /dev/null; then
        info "$PROVISIONED_USER user found"
    else
        error_ignorable "$PROVISIONED_USER user not found"
    fi

    if getent group "$PROVISIONED_GROUP" &> /dev/null; then
        info "$PROVISIONED_GROUP group found"
    else
        error_ignorable "$PROVISIONED_GROUP group not found"
    fi

    if [[ -d "$CALYPTIA_CORE_DIR" ]]; then
        error_ignorable "Found existing directory: $CALYPTIA_CORE_DIR"
    fi

    info "Basic system checks complete"
}

function verify_selinux() {
    if command -v getenforce &> /dev/null ; then
        if getenforce | grep -qi "Disabled"; then
            info "SELinux disabled"
        elif getenforce | grep -qi "Enforcing"; then
            error_ignorable "SELinux enabled in enforcing mode"
        else
            warn "SELinux enabled but not in enforcing mode"
        fi
    else
        if grep '^\s*SELINUX=enforcing' /etc/selinux/config &>/dev/null ; then 
            error_ignorable "SELinux enabled in enforcing mode"
        else
            info "SELinux disabled"
        fi
    fi
}

function verify_crypto() {
    if command -v update-crypto-policies &> /dev/null ; then
        local current_policy
        current_policy=$(update-crypto-policies --show)
        case $current_policy in
            DEFAULT*)
                info "Crypto policy set to $current_policy"
                ;;
            LEGACY*)
                info "Crypto policy set to $current_policy"
                ;;
            *)
                error_ignorable "Crypto policy set to $current_policy, may fail to download components"
                ;;
        esac
    fi
}

function verify_fips() {
    if [[ ! -f /proc/sys/crypto/fips_enabled ]]; then
        info "FIPS mode not enabled"
    elif grep -q "1" /proc/sys/crypto/fips_enabled; then
        error_ignorable "FIPS mode enabled"
    else 
        info "FIPS mode not enabled"
    fi
}

function verify_firewall() {
    if command -v ufw &> /dev/null ; then
        if "$SUDO" ufw status | grep -qi "inactive"; then
            info "Firewall disabled"
        else
            error_ignorable "Firewall is enabled, this may prevent traffic without the correct rules"
        fi
    elif systemctl is-enabled firewalld &> /dev/null || systemctl is-enabled netfilter-persistent &> /dev/null; then 
        error_ignorable "Firewall is enabled, this may prevent traffic without the correct rules"
    else
        info "Firewall not detected"
    fi
}

function verify_k3s_reqs() {
    if [[ -r /etc/redhat-release ]] || [[ -r /etc/centos-release ]] || [[ -r /etc/oracle-release ]]; then
        # https://docs.k3s.io/advanced#additional-preparation-for-red-hatcentos-enterprise-linux
        if systemctl is-enabled nm-cloud-setup.service nm-cloud-setup.timer &> /dev/null ; then
            error_ignorable "nm-cloud-setup enabled: # https://docs.k3s.io/advanced#additional-preparation-for-red-hatcentos-enterprise-linux"
        else
            info "RHEL-compatible OS checks complete"
        fi
    elif [[ -r /etc/os-release ]]; then
        # https://docs.k3s.io/advanced#additional-preparation-for-debian-buster-based-distributions
        if grep -q 'ID=debian' /etc/os-release && grep -q 'VERSION_CODENAME=buster' /etc/os-release; then
            if [[ -x /usr/sbin/iptables ]]; then
                local iptables_version
                # extract the version number from e.g. 'iptables v1.8.7 (nf_tables)'
                iptables_version=$(/usr/sbin/iptables --version 2>&1 | sed -n 's/^.*v\(.*\) .*/\1/p')
                if dpkg --compare-versions "$iptables_version" "lt" "1.8.4" &> /dev/null ; then 
                    error_ignorable "iptables version is too low: https://docs.k3s.io/advanced#additional-preparation-for-debian-buster-based-distributions"
                else 
                    info "iptables version acceptable: $iptables_version"
                fi
            fi
        fi
    fi
}

declare -a ALLOWED_URLS=("https://github.com/k3s-io/k3s/releases" 
                         "https://dl.k8s.io/release" 
                         "https://storage.googleapis.com/k3s-ci-builds" 
                         "https://cloud-api.calyptia.com" 
                         "https://github.com/calyptia/cli/releases" 
                         "https://ghcr.io/calyptia/core" 
                        )

function verify_urls_reachable() {
    for i in "${ALLOWED_URLS[@]}"
    do
        # shellcheck disable=SC2086
        if curl -sSfl $CURL_PARAMETERS "$i" &> /dev/null ; then
            info "$i - OK"
        else
            error_ignorable "$i - Failed"
        fi
    done
}

function check_prerequisites() {
    verify_system
    verify_selinux
    verify_crypto
    verify_fips
    verify_firewall
    verify_k3s_reqs
    verify_urls_reachable
}

function setup() {
    # Handle command line arguments
    # We use equals-separated arguments, i.e. --key=value, and not space separated, i.e. --key value
    for i in "$@"; do
        case $i in
            -f|--force)
                IGNORE_ERRORS=yes
                shift
                ;;
            -k|--disable-tls-verify)
                CURL_PARAMETERS="$CURL_PARAMETERS --insecure"
                SSL_VERIFY="0"
                shift
                ;;
            --disable-k3s)
                DISABLE_K3S=yes
                shift
                ;;
            --disable-kubectl)
                DISABLE_KUBECTL=yes
                shift
                ;;
            --enable-kubeshark)
                DISABLE_KUBESHARK=no
                shift
                ;;
            --enable-kubedashboard)
                DISABLE_KUBEDASHBOARD=no
                shift
                ;;
            -u=*|--user=*)
                PROVISIONED_USER="${i#*=}"
                shift
                ;;
            -g=*|--group=*)
                PROVISIONED_GROUP="${i#*=}"
                shift
                ;;
            --core-dir=*)
                CALYPTIA_CORE_DIR="${i#*=}"
                shift
                ;;
            --core-version=*)
                RELEASE_VERSION="${i#*=}"
                shift
                ;;
            --cli-version=*)
                CLI_RELEASE_VERSION="${i#*=}"
                shift
                ;;
            --dry-run)
                DRY_RUN=yes
                shift
                ;;
            --disable-colour|--disable-color)
                Color_Off=''
                Red=''
                Green=''
                Yellow=''
                shift
                ;;
            *)
                warn "Ignoring unknown option '$i', ensure to use equal-separated key-value pairs: --key=value"
                shift
                ;;
        esac
    done

    # use sudo if we are not already root
    SUDO=sudo
    if [[ $(id -u) -eq 0 ]]; then
        SUDO=''
    fi

    # setup the architecture variable to use for downloads, etc.
    if [[ -z "${ARCH:-}" ]]; then
        ARCH=$(uname -m)
    fi
    case $ARCH in
        amd64)
            ARCH=amd64
            ;;
        x86_64)
            ARCH=amd64
            ;;
        arm64)
            ARCH=arm64
            ;;
        aarch64)
            ARCH=arm64
            ;;
        *)
            fatal "Unsupported architecture $ARCH"
    esac

    # Determine OS type: https://unix.stackexchange.com/a/6348
    if [ -f /etc/os-release ]; then
        # Debian uses Dash which does not support source
        # shellcheck source=/dev/null
        . /etc/os-release
        OS=$( echo "${ID}" | tr '[:upper:]' '[:lower:]')
    elif lsb_release &>/dev/null; then
        OS=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
    else
        OS=$(uname -s)
    fi
}

setup "$@"

info "==================================="
info " Calyptia Core Installation Script "
info "==================================="
info "This script requires superuser access to install packages."
info "You will be prompted for your password by sudo."
info "==================================="
info "Detected: $OS, $ARCH"
info "Installing Calyptia Core ${RELEASE_VERSION} to: $CALYPTIA_CORE_DIR"
info "Installing Calyptia CLI ${CLI_RELEASE_VERSION}"
info "Installing as ${PROVISIONED_USER}:${PROVISIONED_GROUP}"

if [[ "$IGNORE_ERRORS" == "yes" ]]; then
    warn "Ignoring any errors during preflight checks"
fi

check_prerequisites

if [[ "$DRY_RUN" == "yes" ]]; then
    info "Dry run only"
    info "==================================="
    exit 0
fi

# Do any OS-specific stuff first
case ${OS} in
    centos|centoslinux|rhel|redhatenterpriselinuxserver|fedora|rocky|almalinux)
        info "Installing RHEL-derived OS dependencies"
        "$SUDO" yum install -yq jq
    ;;
    ubuntu|debian)
        info "Installing Debian-derived OS dependencies"
        "$SUDO" sh -e <<SCRIPT
export DEBIAN_FRONTEND=noninteractive
apt-get -o DPkg::Lock::Timeout=-1 -qq update
apt-get -o DPkg::Lock::Timeout=-1 -qq install -y jq || snap install jq

SCRIPT
    ;;
    *)
        fatal "${OS} not supported."
    ;;
esac

# Do any common stuff now
"$SUDO" mkdir -p /home/"${PROVISIONED_USER}"/.kube/ /root/.kube/ "$CALYPTIA_CORE_DIR" /etc/systemd/system/

if [[ "$DISABLE_KUBECTL" = "no" ]]; then
    info "Installing kubectl"
    # shellcheck disable=SC2086
    curl -sLO $CURL_PARAMETERS "https://dl.k8s.io/release/$(curl -sSfL $CURL_PARAMETERS https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"
    "$SUDO" install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
else
    warn "Disabled kubectl installation, ensure it is present."
fi

if [[ "$DISABLE_K3S" = "no" ]]; then
    info "Installing k3s, ensure pre-reqs are met: https://docs.k3s.io/advanced#additional-os-preparations"
    "$SUDO" sh -e <<SCRIPT
    # Only RHEL-based repos deal with SELinux currently so we set up sslverify for those
    curl -sfL $CURL_PARAMETERS https://get.k3s.io | \
        sed "/^gpgcheck=1.*/a sslverify=$SSL_VERIFY" | sed "s/sslverify=.*/sslverify=$SSL_VERIFY/g" | \
        INSTALL_K3S_VERSION="$K3S_VERSION" INSTALL_K3S_SELINUX_WARN=true sh -s - --write-kubeconfig-mode 644 \
        --kubelet-arg='eviction-hard=imagefs.available<1%,nodefs.available<1%' \
        --kubelet-arg='eviction-minimum-reclaim=imagefs.available=1%,nodefs.available=1%'
    # Note we drop disk pressure eviction to <1% above
    
    cp -fv "$K3S_KUBECONFIG_OUTPUT" "$CALYPTIA_CORE_DIR"/kubeconfig
    cp -fv "$K3S_KUBECONFIG_OUTPUT" /home/${PROVISIONED_USER}/.kube/config
    cp -fv "$K3S_KUBECONFIG_OUTPUT" /root/.kube/config
    
    echo 'export KUBECONFIG=$CALYPTIA_CORE_DIR/kubeconfig' >> /etc/profile.d/calyptia-core.sh
SCRIPT

else
    warn "Disabled k3s installation, not recommended."
fi

info "Installing Calyptia Core and CLI"
"$SUDO" sh -e <<SCRIPT
curl -sSfL $CURL_PARAMETERS https://storage.googleapis.com/calyptia_aggregator_bucket/releases/${RELEASE_VERSION}/core_${RELEASE_VERSION}_linux_${ARCH}.tar.gz | tar -xzC "$CALYPTIA_CORE_DIR"/
echo 'export PATH=\$PATH:$CALYPTIA_CORE_DIR/' >> /etc/profile.d/calyptia-core.sh

curl -sSfL $CURL_PARAMETERS https://github.com/calyptia/cli/releases/download/v${CLI_RELEASE_VERSION}/cli_${CLI_RELEASE_VERSION}_linux_${ARCH}.tar.gz | tar -xzC "/usr/local/bin"

chown -R ${PROVISIONED_USER}:${PROVISIONED_GROUP} /home/"${PROVISIONED_USER}"/.kube/ "$CALYPTIA_CORE_DIR"/
chmod -R a+r "$CALYPTIA_CORE_DIR"/

SCRIPT

info "Calyptia Core installation completed: $("$CALYPTIA_CORE_DIR"/calyptia-core -v)"
info "Calyptia CLI installation completed: $(calyptia --version)"

# Optional extras now
if [[ "$DISABLE_KUBESHARK" = "no" ]]; then
    info "Installing Kubeshark, see docs for more details: https://kubeshark.co/"
    "$SUDO" sh -e <<SCRIPT
    curl -sSfL $CURL_PARAMETERS -o /usr/local/bin/kubeshark https://github.com/kubeshark/kubeshark/releases/latest/download/kubeshark_linux_${ARCH}
    chmod 755 /usr/local/bin/kubeshark
SCRIPT
fi

if [[ "$DISABLE_KUBEDASHBOARD" = "no" ]]; then
    if ! "$SUDO" k3s kubectl cluster-info &> /dev/null; then
        warn "Unable to install kube-dashboard as k3s is not running, follow docs to manually install: https://docs.k3s.io/installation"
    else
        info "Installing Kubedashboard, see docs for more details: https://docs.k3s.io/installation/kube-dashboard"
        GITHUB_URL=https://github.com/kubernetes/dashboard/releases
        # shellcheck disable=SC2086
        VERSION_KUBE_DASHBOARD=$(curl -w '%{url_effective}' -I -L -s -S $CURL_PARAMETERS "${GITHUB_URL}"/latest -o /dev/null | sed -e 's|.*/||')
        "$SUDO" k3s kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/"${VERSION_KUBE_DASHBOARD}"/aio/deploy/recommended.yaml
        cat << K8S_DASH_EOF | "$SUDO" k3s kubectl apply -f dashboard -
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
K8S_DASH_EOF
    fi
fi

info "==================================="
