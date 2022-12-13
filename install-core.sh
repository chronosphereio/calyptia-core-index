#!/usr/bin/env bash
set -eu

# Configuration variables, all of these should use the INSTALL_CALYPTIA_ prefix to make it simple and clear.
# Each handles a specific option that may also then be overridden via a command line argument too.

# Optionally install the Kubeshark tool, it is disabled by default, by setting to 'no'.
# See https://github.com/kubeshark/kubeshark for more detail.
DISABLE_KUBESHARK=${INSTALL_CALYPTIA_DISABLE_KUBESHARK:-yes}
# Optionally install the Kubernetes dashboard for k3s. Disabled by default so enable by setting to 'no'.
DISABLE_KUBEDASHBOARD=${INSTALL_CALYPTIA_DISABLE_KUBEDASHBOARD:-yes}

# The user to install Calyptia Core as, it must pre-exist.
PROVISIONED_USER=${INSTALL_CALYPTIA_PROVISIONED_USER:-$USER}
# The group to install Calyptia Core as, it must pre-exist.
PROVISIONED_GROUP=${INSTALL_CALYPTIA_PROVISIONED_GROUP:-$(id -gn)}
# The version of Calyptia Core to install.
RELEASE_VERSION=${INSTALL_CALYPTIA_RELEASE_VERSION:-0.4.6}
# Optionally just run the checks and do not install by setting to 'yes'.
DRY_RUN=${INSTALL_CALYPTIA_DRY_RUN:-no}

# The architecture to install.
ARCH=${ARCH:-$(uname -m)}
# Provide a local package to use in preference by setting this, otherwise the package will be downloaded for RELEASE_VERSION.
# This can also be a local directory to cope with packages for different OS/arch types.
LOCAL_PACKAGE=${LOCAL_PACKAGE:-}
# Base URL to download packages from if required
BASE_URL=${BASE_URL:-https://storage.googleapis.com/calyptia_aggregator_bucket/packages/$RELEASE_VERSION}

# Internal variables
IGNORE_ERRORS=no
CURL_PARAMETERS=""
# TODO: make this relocatable
CALYPTIA_CORE_DIR="/opt/calyptia"
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

    # Detect if running as root or not provisioning extra users
    if [[ $(id -u) -eq 0 ]]; then
        error_ignorable "Running as root"
    fi

    if [[ -z "${PROVISIONED_USER:-}" || "${PROVISIONED_USER:-}" == "root" ]]; then
        error_ignorable "Not provisioning additional user"
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

# The bucket set up for the aggregator is strange so requires a specific URL that exists
declare -a ALLOWED_URLS=("https://cloud-api.calyptia.com" 
                         "https://core-packages.calyptia.com"
                         "https://ghcr.io/calyptia/core" 
                        )

function verify_urls_reachable() {
    for i in "${ALLOWED_URLS[@]}"
    do
        # shellcheck disable=SC2086
        if curl -o /dev/null -sSfl $CURL_PARAMETERS "$i" &> /dev/null ; then
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
            --core-version=*)
                RELEASE_VERSION="${i#*=}"
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
}

setup "$@"

info "==================================="
info " Calyptia Core Installation Script "
info "==================================="
info "This script requires superuser access to install packages."
info "You will be prompted for your password by sudo."
info "==================================="
info "Installing for: $ARCH"
info "Installing Calyptia ${RELEASE_VERSION} to: $CALYPTIA_CORE_DIR"
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
# TODO: handle upgrade
if command -v dpkg &> /dev/null ; then
    # If we provide a directory then attempt to select the package within that directory
    if [[ -d "$LOCAL_PACKAGE" ]]; then
        info "Using local package directory: $LOCAL_PACKAGE"
        LOCAL_PACKAGE="${LOCAL_PACKAGE}/calyptia-core_${RELEASE_VERSION}_${ARCH}.deb"
    fi

    # Now check if we have a package or not, if not we download one
    if [[ -f "$LOCAL_PACKAGE" ]]; then
        info "Using local package: $LOCAL_PACKAGE"
    else
        URL="${BASE_URL}/calyptia-core_${RELEASE_VERSION}_${ARCH}.deb"
        info "Downloading $URL"
        # shellcheck disable=SC2086
        curl -o "/tmp/calyptia-core_${RELEASE_VERSION}_${ARCH}.deb" -sSfL $CURL_PARAMETERS "$URL"
        LOCAL_PACKAGE="/tmp/calyptia-core_${RELEASE_VERSION}_${ARCH}.deb"
    fi
    info "Installing Debian-derived OS dependencies"
    "$SUDO" dpkg --install "${LOCAL_PACKAGE}"
elif command -v rpm &> /dev/null ; then
    # RPMs use the other defaults
    case $ARCH in
        amd64)
            PACKAGE_ARCH=x86_64
            ;;
        arm64)
            PACKAGE_ARCH=aarch64
            ;;
        *)
            fatal "Unknown architecture: $ARCH"
    esac

    if [[ -d "$LOCAL_PACKAGE" ]]; then
        info "Using local package directory: $LOCAL_PACKAGE"
        LOCAL_PACKAGE="${LOCAL_PACKAGE}/calyptia-core-${RELEASE_VERSION}.${PACKAGE_ARCH}.rpm"
    fi

    if [[ -f "$LOCAL_PACKAGE" ]]; then
        info "Using local package: $LOCAL_PACKAGE"
    else
        URL="${BASE_URL}/calyptia-core-${RELEASE_VERSION}.${PACKAGE_ARCH}.rpm"
        info "Downloading $URL"
        # shellcheck disable=SC2086
        curl -o "/tmp/calyptia-core-${RELEASE_VERSION}.${PACKAGE_ARCH}.rpm" -sSfL $CURL_PARAMETERS "$URL"
        LOCAL_PACKAGE="/tmp/calyptia-core-${RELEASE_VERSION}.${PACKAGE_ARCH}.rpm"
    fi
    info "Installing RHEL-derived OS dependencies"
    "$SUDO" rpm -ivh "${LOCAL_PACKAGE}"
elif command -v apk &> /dev/null ; then
    if [[ -d "$LOCAL_PACKAGE" ]]; then
        info "Using local package directory: $LOCAL_PACKAGE"
        LOCAL_PACKAGE="${LOCAL_PACKAGE}/calyptia-core_${RELEASE_VERSION}_${ARCH}.apk"
    fi

    if [[ -f "$LOCAL_PACKAGE" ]]; then
        info "Using local package: $LOCAL_PACKAGE"
    else
        URL="${BASE_URL}/calyptia-core_${RELEASE_VERSION}_${ARCH}.apk"
        info "Downloading $URL"
        # shellcheck disable=SC2086
        curl -o "/tmp/calyptia-core_${RELEASE_VERSION}_${ARCH}.apk" -sSfL $CURL_PARAMETERS "$URL"
        LOCAL_PACKAGE="/tmp/calyptia-core_${RELEASE_VERSION}_${ARCH}.apk"
    fi
    info "Installing APK-derived OS dependencies"
    "$SUDO" apk add --allow-untrusted "${LOCAL_PACKAGE}"
else
    fatal "Unsupported platform"
fi

# Ensure our various directories are correctly set up to allow users to access everything
export KUBECONFIG="$CALYPTIA_CORE_DIR"/kubeconfig
"$SUDO" mkdir -p "/home/${PROVISIONED_USER}/.kube"
"$SUDO" cp -fv "$KUBECONFIG" "/home/${PROVISIONED_USER}/.kube/config"
"$SUDO" chown -R "${PROVISIONED_USER}:${PROVISIONED_GROUP}" "/home/${PROVISIONED_USER}/.kube" "$CALYPTIA_CORE_DIR"/
"$SUDO" chmod -R a+r "$CALYPTIA_CORE_DIR"/

info "Calyptia Core installation completed: $("$CALYPTIA_CORE_DIR"/calyptia-core -v)"
info "Calyptia CLI installation completed: $(calyptia --version)"
info "K3S cluster info: $(kubectl cluster-info)"

if [[ -e "/usr/local/bin/jq" ]]; then
    info "Existing jq detected so not updating"
else
    info "Creating jq symlink"
    "$SUDO" ln -s /opt/calyptia/jq /usr/local/bin/jq
fi

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
