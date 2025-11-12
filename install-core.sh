#!/usr/bin/env bash
set -eu

# Configuration variables, all of these should use the INSTALL_CALYPTIA_ prefix to make it simple and clear.
# Each handles a specific option that may also then be overridden via a command line argument too.

# The user to install Calyptia Core as, it must pre-exist.
PROVISIONED_USER=${INSTALL_CALYPTIA_PROVISIONED_USER:-$(id -un)}
# The group to install Calyptia Core as, it must pre-exist.
PROVISIONED_GROUP=${INSTALL_CALYPTIA_PROVISIONED_GROUP:-$(id -gn)}
# The version of Calyptia Core to install.
RELEASE_VERSION=${INSTALL_CALYPTIA_RELEASE_VERSION:-3.77.0}
# Optionally just run the checks and do not install by setting to 'yes'.
DRY_RUN=${INSTALL_CALYPTIA_DRY_RUN:-no}
# Equivalent to '--force' to ignore errors as warnings and continue after checks even if they fail.
IGNORE_ERRORS=${INSTALL_CALYPTIA_IGNORE_ERRORS:-no}
# Skip post-install checks
SKIP_POST_INSTALL=${INSTALL_CALYPTIA_SKIP_POST_INSTALL:-no}
# Custom CIDR ranges for K3S and their defaults: https://docs.k3s.io/reference/server-config#networking
CLUSTER_CIDR=${INSTALL_CALYPTIA_CLUSTER_CIDR:-10.42.0.0/16}
SERVICE_CIDR=${INSTALL_CALYPTIA_SERVICE_CIDR:-10.43.0.0/16}
CLUSTER_DNS=${INSTALL_CALYPTIA_CLUSTER_DNS:-10.43.0.10}
SERVICE_NODE_PORT_RANGE=${INSTALL_CALYPTIA_SERVICE_NODE_PORT_RANGE:-30000-32767}
CLUSTER_DOMAIN=${INSTALL_CALYPTIA_CLUSTER_DOMAIN:-cluster.local}

# Determine whether to use the operator package or the legacy one
# Set to calyptia-core-operator for operator
# Set to calyptia-core for "classic" Core
PACKAGE_NAME_PREFIX=${INSTALL_CALYPTIA_PACKAGE_NAME_PREFIX:-calyptia-core-operator}

# Disable package download (force it to use local)
SKIP_DOWNLOAD=${INSTALL_CALYPTIA_SKIP_DOWNLOAD:-no}

# The architecture to install.
ARCH=${INSTALL_CALYPTIA_ARCH:-$(uname -m)}
# Provide a local package to use in preference by setting this, otherwise the package will be downloaded for RELEASE_VERSION.
# This can also be a local directory to cope with packages for different OS/arch types.
LOCAL_PACKAGE=${INSTALL_CALYPTIA_LOCAL_PACKAGE:-}
# Base URL to download packages from if required
BASE_URL=${INSTALL_CALYPTIA_BASE_URL:-https://core-packages.calyptia.com/core/$RELEASE_VERSION}
# Custom SUDO command override
SUDO_OVERRIDE=${INSTALL_CALYPTIA_SUDO_OVERRIDE:-}

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
    if [[ "$IGNORE_ERRORS" != "no" ]]; then
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
        warn "Running as root is not generally recommended."
    fi

    if [[ -z "${PROVISIONED_USER:-}" || "${PROVISIONED_USER:-}" == "root" ]]; then
        warn "Not provisioning any additional user, suggestion is to provide a dedicated user."
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
        if $SUDO ufw status | grep -qi "inactive"; then
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
            error_ignorable "nm-cloud-setup enabled: # https://docs.k3s.io/advanced#red-hat-enterprise-linux--centos"
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

function verify_cidr() {
    if ! command -v nslookup &> /dev/null ; then
        warn "Unable to find nslookup to check resolution of 8.8.8.8 for Core DNS - only relevant in some situations (see k3s docs)"
    elif ! nslookup 8.8.8.8 &> /dev/null ; then
        # This can be ignored if we have internal DNS servers that function
        warn "Unable to use 8.8.8.8 as a DNS server for Core DNS - only relevant in some situations (see k3s docs)"
    fi

    # Assumption is we provide a /16 address range for all checks
    # Assumption is we only check for first two groups in IP range, i.e. a.b.*.*
    CLUSTER_CIDR_PREFIX=''
    if [[ "$CLUSTER_CIDR" =~ ([0-9])+\.([0-9])+\.* ]]; then
        CLUSTER_CIDR_PREFIX="${BASH_REMATCH[0]}"
    else
        error_ignorable "Invalid cluster CIDR: $CLUSTER_CIDR"
    fi

    SERVICE_CIDR_PREFIX=''
    if [[ "$SERVICE_CIDR" =~ ([0-9])+\.([0-9])+\.* ]]; then
        SERVICE_CIDR_PREFIX="${BASH_REMATCH[0]}"
    else
        error_ignorable "Invalid service CIDR: $SERVICE_CIDR"
    fi

    # Need to check for conflicts between our address ranges and the local DNS resolver
    if grep -q "$CLUSTER_CIDR_PREFIX" /etc/resolv.conf ; then
        error_ignorable "Detected conflicting address range for cluster cidr ($CLUSTER_CIDR_PREFIX) in /etc/resolv.conf"
    fi
    if grep -q "$SERVICE_CIDR_PREFIX" /etc/resolv.conf ; then
        error_ignorable "Detected conflicting address range for service cidr ($SERVICE_CIDR_PREFIX) in /etc/resolv.conf"
    fi

    # Verify our cluster DNS value is within the range of the cluster CIDR
    if [[ "$CLUSTER_DNS" =~ ([0-9])+\.([0-9])+\.([0-9])+\.([0-9])+ ]]; then
        # Now check the first two IPs
        if [[ "$CLUSTER_DNS" =~ ([0-9])+\.([0-9])+\.* ]]; then
            if [[ "$SERVICE_CIDR_PREFIX" != "${BASH_REMATCH[0]}" ]]; then
                error_ignorable "Cluster DNS ($CLUSTER_DNS) is not in the service CIDR range ($SERVICE_CIDR)"
            fi
        fi
    else
        error_ignorable "Invalid cluster DNS: $CLUSTER_DNS"
    fi
}

function verify_local_packages() {
    if [[ -f "${LOCAL_PACKAGE}" ]]; then
        info "Local package file found: $LOCAL_PACKAGE"
    elif [[ -d "${LOCAL_PACKAGE}" ]]; then
        info "Local package directory found: $LOCAL_PACKAGE"
        # Check we have the relevant files inside the directory

        local expected_file="${LOCAL_PACKAGE}/${PACKAGE_NAME_PREFIX}_${RELEASE_VERSION}_${ARCH}.deb"
        if command -v dpkg &> /dev/null ; then
            expected_file="${LOCAL_PACKAGE}/${PACKAGE_NAME_PREFIX}_${RELEASE_VERSION}_${ARCH}.deb"
        elif command -v rpm &> /dev/null ; then
            local package_arch=x86_64
            case $ARCH in
                amd64)
                    package_arch=x86_64
                    ;;
                arm64)
                    package_arch=aarch64
                    ;;
                *)
                    fatal "Unknown architecture: $ARCH"
                    ;;
            esac
            local package_release_version=${RPM_RELEASE_VERSION:-"-1"}
            expected_file="${LOCAL_PACKAGE}/${PACKAGE_NAME_PREFIX}-${RELEASE_VERSION}${package_release_version}.${package_arch}.rpm"
        elif command -v apk &> /dev/null ; then
            expected_file="${LOCAL_PACKAGE}/${PACKAGE_NAME_PREFIX}_${RELEASE_VERSION}_${ARCH}.apk"
        else
            fatal "Unknown OS, no dpkg, rpm or apk tool"
        fi

        if [[ -f "$expected_file" ]]; then
            info "Local package file found: $expected_file"
        else
            info "Unable to find local package file: $expected_file"
        fi
    fi
}

function check_prerequisites() {
    verify_system
    verify_selinux
    verify_crypto
    verify_fips
    verify_firewall
    verify_k3s_reqs
    verify_urls_reachable
    verify_cidr
    verify_local_packages
}

# After install, wait for the cluster to be minimally ready
function wait_for_cluster() {
    if ! command -v kubectl &> /dev/null ; then
        warn "Unable to use kubectl so skipping wait for cluster ready"
    else
        # Ensure the cluster is stable for DNS checks
        until kubectl rollout status -n kube-system deployment/coredns &> /dev/null; do
            info "Waiting for Core DNS to be running"
            sleep 10
        done
        info "Core DNS running"

        until kubectl rollout status -n kube-system deployment/traefik &> /dev/null; do
            info "Waiting for Traefik to be running"
            sleep 10
        done
        info "Traefik running"

        # Ensure we have a service account in the default namespace to run the pod
        until kubectl get serviceaccount default &> /dev/null; do
            info "Waiting for ServiceAccount default to be created"
            sleep 10
        done
        info "ServiceAccount default available"
    fi
}

# After installation, check if we require SELinux configuration to execute commands as root
function verify_binaries() {
    if $SUDO kubectl version &> /dev/null ; then
        info "Verified kubectl is available to root"
    else
        warn "Missing kubectl for root - update path and/or SELinux configuration"
    fi
    if $SUDO calyptia version &> /dev/null ; then
        info "Verified Calyptia CLI is available to root"
    else
        warn "Missing Calyptia CLI for root - update path and/or SELinux configuration"
    fi
}

# After installation, verify DNS resolution
function verify_cluster_dns() {
    if ! command -v kubectl &> /dev/null ; then
        warn "Unable to use kubectl so skipping checks for cluster DNS"
    else
        # Later versions fail: https://github.com/coredns/coredns/issues/2026
        local nslookup_image="busybox:1.28"

        for i in "${ALLOWED_URLS[@]}"
        do
            # Skipping container registry for resolution checks as it will fail regardless
            [[ "$i" == "https://ghcr.io/calyptia/core" ]] && continue

            local count=0
            until kubectl run -i --rm --restart=Never --timeout=30s --image="$nslookup_image" nslookup-test-$RANDOM -- nslookup "${i#*//}" &> /dev/null ; do
                count=$((count + 1))
                if [[ $count -gt 3 ]]; then
                    # Get logs
                    kubectl get pods --all-namespaces
                    kubectl logs deployment/coredns -n kube-system
                    kubectl run -i --rm --restart=Never --timeout=30s --image="$nslookup_image" nslookup-test-$RANDOM -- nslookup "${i#*//}"
                    fatal "${i#*//} - Failed"
                fi

                warn "Retrying DNS resolution for: ${i#*//}"
                sleep 10
            done
            info "${i#*//} - OK"
        done

        info "Verify cluster DNS - OK"
    fi
}

function usage() {
    echo "usage: $0 [--force|--disable-tls-verify] "
    echo "Optional parameters:"
    echo "--force|-f : treat errors as warnings for pre-installation checks, only use once errors are understood to not be an issue"
    echo "--disable-tls-verify|-k : disable TLS verification for downloads via curl"
    echo "--user=<UID/username>|-u=<UID/username> : provision as specific user, defaults to the user who invokes this script"
    echo "--group=<GID/groupname>|-g=<GID/groupname> : provision as specific group, defaults to $(id -gn)"
    echo "--core-version=<release> : install specific Calyptia Core version, defaults to $RELEASE_VERSION"
    echo "--dry-run : run pre-installation checks only"
    echo "--disable-colour|--disable-color : disable ANSI control codes in output"
    echo "--disable-download : disable remote package download, must use local"
    echo "--disable-post-install-checks : do not run post-installation checks"
    echo "--package=<package file/dir> : pick up the package to install locally, implies --disable-download. A directory can be specified if it includes the relevant package (useful for multi-arch/OS install)."
    echo "--package-name-prefix=<prefix> : the prefix name for the package to use."
    echo "--operator: install the Calyptia Core Operator"
    echo "--legacy: install the legacy Calyptia Core version"
    echo
    exit 0
}

function setup() {
    # Handle command line arguments
    # We use equals-separated arguments, i.e. --key=value, and not space separated, i.e. --key value
    for i in "$@"; do
        case $i in
            --operator)
                PACKAGE_NAME_PREFIX=calyptia-core-operator
                shift
                ;;
            --legacy)
                PACKAGE_NAME_PREFIX=calyptia-core
                shift
                ;;
            --package-name-prefix=*)
                PACKAGE_NAME_PREFIX="${i#*=}"
                shift
                ;;
            --package=*)
                LOCAL_PACKAGE="${i#*=}"
                SKIP_DOWNLOAD=yes
                shift
                ;;
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
            --dryrun|--dry-run)
                DRY_RUN=yes
                shift
                ;;
            --no-colour|--no-color|--disable-colour|--disable-color)
                Color_Off=''
                Red=''
                Green=''
                Yellow=''
                shift
                ;;
            --disable-post-install-checks|--disablepostinstallchecks)
                SKIP_POST_INSTALL=yes
                shift
                ;;
            --disable-download|--disabledownload|--no-download|--nodownload)
                SKIP_DOWNLOAD=yes
                shift
                ;;
            --help|-h)
                usage
                ;;
            *)
                warn "Ignoring unknown option '$i', ensure to use equal-separated key-value pairs: --key=value"
                shift
                ;;
        esac
    done

    # use sudo if we are not already root
    SUDO=sudo
    if [[ "${SUDO_OVERRIDE:-}" != "" ]]; then
        SUDO="$SUDO_OVERRIDE"
    elif [[ $(id -u) -eq 0 ]]; then
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

function handle_installer_config() {
    # We detain any configuration the package can pick up in its pre/post install/uninstall helpers
    local config="$CALYPTIA_CORE_DIR/.install/settings.conf"

    if [[ -f "$config" ]]; then
        info "Existing installation configuration file found: $config"
    else
        info "Creating installation configuration file: $config"
        $SUDO mkdir -p "$(dirname "$config")"
        # Beware of sudo redirection failures so use a temporary file and copy it
        tempConfig=$(mktemp)
        cat > "$tempConfig" <<EOF
NO_PREFLIGHT_CHECKS=yes
IGNORE_ERRORS=${IGNORE_ERRORS}
PROVISIONED_USER=${PROVISIONED_USER}
PROVISIONED_GROUP=${PROVISIONED_GROUP}
CLUSTER_CIDR=${CLUSTER_CIDR}
SERVICE_CIDR=${SERVICE_CIDR}
CLUSTER_DNS=${CLUSTER_DNS}
SERVICE_NODE_PORT_RANGE=${SERVICE_NODE_PORT_RANGE}
CLUSTER_DOMAIN=${CLUSTER_DOMAIN}
EOF
        $SUDO mv -f "$tempConfig" "$config"
        $SUDO chown -R "${PROVISIONED_USER}:${PROVISIONED_GROUP}" "$(dirname "$config")"
        $SUDO chmod -R a+r "$(dirname "$config")"
    fi
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

# Detain installer configuration (or load existing)
handle_installer_config

# Do any OS-specific stuff first
if command -v dpkg &> /dev/null ; then
    # If we provide a directory then attempt to select the package within that directory
    if [[ -d "$LOCAL_PACKAGE" ]]; then
        info "Using local package directory: $LOCAL_PACKAGE"
        LOCAL_PACKAGE="${LOCAL_PACKAGE}/${PACKAGE_NAME_PREFIX}_${RELEASE_VERSION}_${ARCH}.deb"
    fi

    # Now check if we have a package or not, if not we download one
    if [[ -f "$LOCAL_PACKAGE" ]]; then
        info "Using local package: $LOCAL_PACKAGE"
    elif [[ "$SKIP_DOWNLOAD" != "no" ]]; then
        fatal "Missing package and unable to download: $LOCAL_PACKAGE"
    else
        URL="${BASE_URL}/${PACKAGE_NAME_PREFIX}_${RELEASE_VERSION}_${ARCH}.deb"
        info "Downloading $URL"
        # shellcheck disable=SC2086
        curl -o "/tmp/${PACKAGE_NAME_PREFIX}_${RELEASE_VERSION}_${ARCH}.deb" -sSfL $CURL_PARAMETERS "$URL"
        LOCAL_PACKAGE="/tmp/${PACKAGE_NAME_PREFIX}_${RELEASE_VERSION}_${ARCH}.deb"
    fi
    info "Installing Debian-derived OS dependencies"
    $SUDO dpkg --install "${LOCAL_PACKAGE}"
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
        LOCAL_PACKAGE="${LOCAL_PACKAGE}/${PACKAGE_NAME_PREFIX}-${RELEASE_VERSION}${RPM_RELEASE_VERSION:-"-1"}.${PACKAGE_ARCH}.rpm"
    fi

    if [[ -f "$LOCAL_PACKAGE" ]]; then
        info "Using local package: $LOCAL_PACKAGE"
    elif [[ "$SKIP_DOWNLOAD" != "no" ]]; then
        fatal "Missing package and unable to download: $LOCAL_PACKAGE"
    else
        URL="${BASE_URL}/${PACKAGE_NAME_PREFIX}-${RELEASE_VERSION}${RPM_RELEASE_VERSION:-"-1"}.${PACKAGE_ARCH}.rpm"
        info "Downloading $URL"
        # shellcheck disable=SC2086
        curl -o "/tmp/${PACKAGE_NAME_PREFIX}-${RELEASE_VERSION}${RPM_RELEASE_VERSION:-"-1"}.${PACKAGE_ARCH}.rpm" -sSfL $CURL_PARAMETERS "$URL"
        LOCAL_PACKAGE="/tmp/${PACKAGE_NAME_PREFIX}-${RELEASE_VERSION}${RPM_RELEASE_VERSION:-"-1"}.${PACKAGE_ARCH}.rpm"
    fi

    info "Installing RHEL-derived OS dependencies"

    if grep -q '^\s*SELINUX=enforcing' /etc/selinux/config &> /dev/null; then
        warn "SELinux enabled, ensure we have met the requirements to allow for it: install container-selinux and k3s SELinux config"
    fi

    $SUDO rpm -ivh "${LOCAL_PACKAGE}"

elif command -v apk &> /dev/null ; then
    if [[ -d "$LOCAL_PACKAGE" ]]; then
        info "Using local package directory: $LOCAL_PACKAGE"
        LOCAL_PACKAGE="${LOCAL_PACKAGE}/${PACKAGE_NAME_PREFIX}_${RELEASE_VERSION}_${ARCH}.apk"
    fi

    if [[ -f "$LOCAL_PACKAGE" ]]; then
        info "Using local package: $LOCAL_PACKAGE"
    elif [[ "$SKIP_DOWNLOAD" != "no" ]]; then
        fatal "Missing package and unable to download: $LOCAL_PACKAGE"
    else
        URL="${BASE_URL}/${PACKAGE_NAME_PREFIX}_${RELEASE_VERSION}_${ARCH}.apk"
        info "Downloading $URL"
        # shellcheck disable=SC2086
        curl -o "/tmp/${PACKAGE_NAME_PREFIX}_${RELEASE_VERSION}_${ARCH}.apk" -sSfL $CURL_PARAMETERS "$URL"
        LOCAL_PACKAGE="/tmp/${PACKAGE_NAME_PREFIX}_${RELEASE_VERSION}_${ARCH}.apk"
    fi
    info "Installing APK-derived OS dependencies"
    $SUDO apk add --allow-untrusted "${LOCAL_PACKAGE}"
else
    fatal "Unsupported platform"
fi

# Ensure our various directories are correctly set up to allow users to access everything
export KUBECONFIG="$CALYPTIA_CORE_DIR"/kubeconfig
if [[ "$PROVISIONED_USER" != "root" ]]; then
    $SUDO mkdir -p "/home/${PROVISIONED_USER}/.kube"
    $SUDO cp -fv "$KUBECONFIG" "/home/${PROVISIONED_USER}/.kube/config"
    $SUDO chown -R "${PROVISIONED_USER}:${PROVISIONED_GROUP}" "/home/${PROVISIONED_USER}/.kube" "$CALYPTIA_CORE_DIR"/
fi
$SUDO chmod -R a+r "$CALYPTIA_CORE_DIR"/

wait_for_cluster
if [[ "$SKIP_POST_INSTALL" != "no" ]]; then
    warn "Skipping post installation checks"
else
    verify_binaries
    verify_cluster_dns
fi

if [[ -x "$CALYPTIA_CORE_DIR"/calyptia-core ]]; then
    info "Calyptia Core (legacy) installation completed: $("$CALYPTIA_CORE_DIR"/calyptia-core -v)"
else
    info 'Calyptia Core Operator installation completed.'
fi
if calyptia --version &> /dev/null; then
    info "Calyptia CLI installation completed: $(calyptia --version)"
else
    info "Calyptia CLI installation completed: $(calyptia version)"
fi
info "K3S cluster info: $(kubectl cluster-info)"
info "Provisioned as: $PROVISIONED_USER"

if command -v jq &>/dev/null ; then
    info "Existing jq detected so not updating"
elif [[ -f '/opt/calyptia/jq' ]]; then
    info "Installing jq"
    $SUDO install -D -v -m 755 /opt/calyptia/jq /usr/local/bin/jq
fi

info "Completed Calyptia Core provisioning successfully"
info "==================================="
