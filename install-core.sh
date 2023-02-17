#!/usr/bin/env bash
set -eu

# Configuration variables, all of these should use the INSTALL_CALYPTIA_ prefix to make it simple and clear.
# Each handles a specific option that may also then be overridden via a command line argument too.

# The user to install Calyptia Core as, it must pre-exist.
PROVISIONED_USER=${INSTALL_CALYPTIA_PROVISIONED_USER:-$USER}
# The group to install Calyptia Core as, it must pre-exist.
PROVISIONED_GROUP=${INSTALL_CALYPTIA_PROVISIONED_GROUP:-$(id -gn)}
# The version of Calyptia Core to install.
RELEASE_VERSION=${INSTALL_CALYPTIA_RELEASE_VERSION:-1.1.0}
# Optionally just run the checks and do not install by setting to 'yes'.
DRY_RUN=${INSTALL_CALYPTIA_DRY_RUN:-no}
# Equivalent to '--force' to ignore errors as warnings and continue after checks even if they fail.
IGNORE_ERRORS=${INSTALL_CALYPTIA_IGNORE_ERRORS:-no}

# The architecture to install.
ARCH=${ARCH:-$(uname -m)}
# Provide a local package to use in preference by setting this, otherwise the package will be downloaded for RELEASE_VERSION.
# This can also be a local directory to cope with packages for different OS/arch types.
LOCAL_PACKAGE=${LOCAL_PACKAGE:-}
# Base URL to download packages from if required
BASE_URL=${BASE_URL:-https://core-packages.calyptia.com/core/$RELEASE_VERSION}

# Internal variables
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
        fatal "$@" "(ignore with '--force' or set 'INSTALL_CALYPTIA_IGNORE_ERRORS=yes')"
    fi
}

function verify_system() {
    case $(uname | tr '[:upper:]' '[:lower:]') in
        linux*)
            info "Linux OS detected"
            ;;
        darwin*)
            fatal 'macOS system detected, please use Docker Desktop with the Calyptia Core extension'
            ;;
        msys*)
            fatal 'Windows OS detected, not supported by this installation method'
            ;;
        *)
            error_ignorable "Unknown OS detected, confirm it is supported."
            ;;
    esac

    if command -v curl &> /dev/null; then
        info "Found curl"
    else
        fatal 'No curl command present, please install.'
    fi

    if [ -x /bin/systemctl ] || type systemctl &> /dev/null; then
        info "Found systemctl"
    else
        fatal 'Can not find systemctl, unsupported platform.'
    fi

    # Detect if running as root or not provisioning extra users
    if [[ $(id -u) -eq 0 ]]; then
        error_ignorable "Running as root is not generally recommended."
    fi

    if [[ -z "${PROVISIONED_USER:-}" || "${PROVISIONED_USER:-}" == "root" ]]; then
        error_ignorable "Not provisioning any additional user, suggestion is to provide a dedicated user."
    fi

    if id "$PROVISIONED_USER" &> /dev/null; then
        info "$PROVISIONED_USER user found"
    else
        error_ignorable "$PROVISIONED_USER user not found, please create in advance."
    fi

    if getent group "$PROVISIONED_GROUP" &> /dev/null; then
        info "$PROVISIONED_GROUP group found"
    else
        error_ignorable "$PROVISIONED_GROUP group not found, please create in advance."
    fi

    if [[ -d "$CALYPTIA_CORE_DIR" ]]; then
        error_ignorable "Found existing Calyptia Core directory: $CALYPTIA_CORE_DIR"
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
                error_ignorable "Crypto policy set to $current_policy, may fail to download components."
                ;;
        esac
    fi
}

function verify_fips() {
    if [[ ! -f /proc/sys/crypto/fips_enabled ]]; then
        info "FIPS mode not enabled"
    elif grep -q "1" /proc/sys/crypto/fips_enabled; then
        error_ignorable "FIPS mode enabled."
    else 
        info "FIPS mode not enabled"
    fi
}

function verify_firewall() {
    if command -v ufw &> /dev/null ; then
        if "$SUDO" ufw status | grep -qi "inactive"; then
            info "Firewall disabled"
        else
            error_ignorable "Firewall is enabled, please ensure outbound rules are correctly configured from docs."
        fi
    elif systemctl is-enabled firewalld &> /dev/null || \
         systemctl is-enabled netfilter-persistent &> /dev/null || \
         systemctl is-active firewalld &> /dev/null || \
         systemctl is-active netfilter-persistent &> /dev/null ; then 
        error_ignorable "Firewall is enabled, please ensure outbound rules are correctly configured from docs."
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

info "==================================="
