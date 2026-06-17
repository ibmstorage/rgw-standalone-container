#!/bin/bash
# =============================================================================
# deploy-cluster.sh - Deploy and test the complete zgw-posix stack with S3 Browser UI
# =============================================================================
#
# This script deploys the zgw-posix Helm chart with the S3 Browser UI enabled
# and provides instructions for local testing via port-forwarding.
#
# Usage:
#   ./scripts/deploy-cluster.sh [deploy|cleanup] [OPTIONS]
#
#   deploy  - Deploy the zgw-posix stack (default)
#   cleanup - Remove the zgw-posix stack and optionally the namespace
#
# Options:
#   --registry <server>    Container registry server (default: cp.stg.icr.io)
#   --uname <username>     Registry username
#   --password <password>  Registry password
#
# Examples:
#   ./scripts/deploy-cluster.sh deploy
#   ./scripts/deploy-cluster.sh deploy --registry my.registry.com --uname user --password pass
#   ./scripts/deploy-cluster.sh cleanup
#
# Prerequisites:
#   - kubectl configured and connected to your cluster
#   - helm 3.x installed
#
# =============================================================================

set -e
set -o pipefail

# -----------------------------------------------------------------------------
# Configuration Variables
# -----------------------------------------------------------------------------
NAMESPACE="zgw"
RELEASE_NAME="zgw-local"
CHART_DIR="./examples/helm/zgw-posix"

# Deployment names (following Helm naming conventions)
BACKEND_DEPLOYMENT="${RELEASE_NAME}-zgw-posix"
UI_DEPLOYMENT="${RELEASE_NAME}-zgw-posix-browser-ui"

# Registry configuration (defaults)
REGISTRY_SERVER="cp.stg.icr.io"
REGISTRY_USERNAME=""
REGISTRY_PASSWORD=""

# -----------------------------------------------------------------------------
# Color codes for terminal output
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

# Print banner
print_banner() {
    echo -e "${BOLD}${BLUE}"
    echo "============================================================================="
    echo "  ZGW-POSIX + S3 Browser UI - $1"
    echo "============================================================================="
    echo -e "${NC}"
}

# Cleanup function
cleanup_deployment() {
    print_banner "Cleanup"
    
    echo -e "${BOLD}${BLUE}Removing Helm release '${RELEASE_NAME}' from namespace '${NAMESPACE}'...${NC}"
    echo ""
    
    if helm list -n "${NAMESPACE}" | grep -q "${RELEASE_NAME}"; then
        helm uninstall "${RELEASE_NAME}" --namespace "${NAMESPACE}"
        echo ""
        echo -e "${GREEN}✓ Helm release removed successfully${NC}"
    else
        echo -e "${YELLOW}⚠️  Helm release '${RELEASE_NAME}' not found${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}Do you want to delete the namespace '${NAMESPACE}' and all its resources?${NC}"
    echo -e "${RED}${BOLD}WARNING: This will delete ALL resources in the namespace, including PVCs and data!${NC}"
    read -p "Delete namespace? (yes/no): " DELETE_NS
    
    if [[ "${DELETE_NS}" == "yes" ]]; then
        echo ""
        echo -e "${BOLD}${BLUE}Deleting namespace '${NAMESPACE}'...${NC}"
        kubectl delete namespace "${NAMESPACE}" --ignore-not-found=true
        echo ""
        echo -e "${GREEN}✓ Namespace deleted successfully${NC}"
    else
        echo ""
        echo -e "${CYAN}Namespace '${NAMESPACE}' preserved${NC}"
        echo -e "${CYAN}To manually delete it later, run: kubectl delete namespace ${NAMESPACE}${NC}"
    fi
    
    echo ""
    echo -e "${BOLD}${GREEN}"
    echo "============================================================================="
    echo "  🧹 CLEANUP COMPLETE!"
    echo "============================================================================="
    echo -e "${NC}"
}

# Deploy function
deploy_stack() {
    print_banner "Deployment"

    # -------------------------------------------------------------------------
    # Check and create image pull secret if needed
    # -------------------------------------------------------------------------
    SECRET_NAME="browser-ui-registry-key"
    echo -e "${BOLD}${BLUE}Checking for Browser UI image pull secret...${NC}"
    echo ""

    # Check if the secret already exists
    if kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" &>/dev/null; then
        echo -e "${GREEN}✓ Secret '${SECRET_NAME}' already exists in namespace '${NAMESPACE}'${NC}"
        echo ""
    else
        echo -e "${YELLOW}${BOLD}⚠️  Secret '${SECRET_NAME}' not found in namespace '${NAMESPACE}'${NC}"
        echo -e "${YELLOW}   This secret is required for pulling the S3 Browser UI image.${NC}"
        echo ""
        
        # Use CLI arguments if provided, otherwise prompt
        if [[ -z "${REGISTRY_USERNAME}" ]] || [[ -z "${REGISTRY_PASSWORD}" ]]; then
            echo -e "${CYAN}Please provide your Container Registry credentials:${NC}"
            echo -e "${CYAN}Registry Server: ${REGISTRY_SERVER}${NC}"
            echo ""
            read -p "Docker Username: " REGISTRY_USERNAME
            read -sp "Docker Password: " REGISTRY_PASSWORD
            echo ""
            echo ""
        fi
        
        # Validate inputs
        if [[ -z "${REGISTRY_USERNAME}" ]] || [[ -z "${REGISTRY_PASSWORD}" ]]; then
            echo -e "${RED}${BOLD}Error: Username and password cannot be empty${NC}"
            exit 1
        fi
        
        # Create the namespace if it doesn't exist
        kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - &>/dev/null
        
        # Create the secret
        echo -e "${CYAN}Creating secret '${SECRET_NAME}' in namespace '${NAMESPACE}'...${NC}"
        kubectl create secret docker-registry "${SECRET_NAME}" \
            --docker-server="${REGISTRY_SERVER}" \
            --docker-username="${REGISTRY_USERNAME}" \
            --docker-password="${REGISTRY_PASSWORD}" \
            --namespace="${NAMESPACE}"
        
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}✓ Secret created successfully${NC}"
            echo ""
        else
            echo -e "${RED}${BOLD}Error: Failed to create secret${NC}"
            exit 1
        fi
    fi

    # -------------------------------------------------------------------------
    # Step 1: Deploy the Helm chart
    # -------------------------------------------------------------------------
    echo -e "${BOLD}${BLUE}[1/3] Deploying Helm chart...${NC}"
    echo ""

    # Detect if we're on OpenShift or vanilla Kubernetes
    if kubectl api-resources | grep -q "route.openshift.io"; then
        echo -e "${CYAN}Detected OpenShift cluster - enabling OpenShift features${NC}"
        OPENSHIFT_ENABLED="true"
    else
        echo -e "${CYAN}Detected vanilla Kubernetes cluster - disabling OpenShift features${NC}"
        OPENSHIFT_ENABLED="false"
    fi
    echo ""

    echo -e "${CYAN}Command: helm upgrade --install ${RELEASE_NAME} ${CHART_DIR} --namespace ${NAMESPACE} --create-namespace --set browserUi.enabled=true --set openshift.enabled=${OPENSHIFT_ENABLED} --set browserUi.registry.server=${REGISTRY_SERVER}${NC}"
    echo ""

    helm upgrade --install "${RELEASE_NAME}" "${CHART_DIR}" \
      --namespace "${NAMESPACE}" \
      --create-namespace \
      --set browserUi.enabled=true \
      --set openshift.enabled="${OPENSHIFT_ENABLED}" \
      --set browserUi.registry.server="${REGISTRY_SERVER}"

    echo ""
    echo -e "${GREEN}✓ Helm chart deployed successfully${NC}"
    echo ""

    # -------------------------------------------------------------------------
    # Step 2: Wait for backend deployment to be ready
    # -------------------------------------------------------------------------
    echo -e "${BOLD}${BLUE}[2/3] Waiting for zgw-posix backend deployment to be ready...${NC}"
    echo -e "${CYAN}Deployment: ${BACKEND_DEPLOYMENT}${NC}"
    echo ""

    kubectl rollout status deployment/"${BACKEND_DEPLOYMENT}" \
      --namespace "${NAMESPACE}" \
      --timeout=5m

    echo ""
    echo -e "${GREEN}✓ Backend deployment is ready${NC}"
    echo ""

    # -------------------------------------------------------------------------
    # Step 3: Wait for UI deployment to be ready
    # -------------------------------------------------------------------------
    echo -e "${BOLD}${BLUE}[3/3] Waiting for S3 Browser UI deployment to be ready...${NC}"
    echo -e "${CYAN}Deployment: ${UI_DEPLOYMENT}${NC}"
    echo ""

    kubectl rollout status deployment/"${UI_DEPLOYMENT}" \
      --namespace "${NAMESPACE}" \
      --timeout=5m

    echo ""
    echo -e "${GREEN}✓ UI deployment is ready${NC}"
    echo ""

    # -------------------------------------------------------------------------
    # Get Ingress hosts from Helm values
    # -------------------------------------------------------------------------
    echo -e "${CYAN}Retrieving Ingress configuration...${NC}"
    
    # Get all values and extract hosts using jq if available, otherwise use grep
    if command -v jq &>/dev/null; then
        UI_HOST=$(helm get values "${RELEASE_NAME}" -n "${NAMESPACE}" -o json 2>/dev/null | jq -r '.browserUi.ingress.host // empty' 2>/dev/null)
        PROXY_HOST=$(helm get values "${RELEASE_NAME}" -n "${NAMESPACE}" -o json 2>/dev/null | jq -r '.browserUi.ingress.proxyHost // empty' 2>/dev/null)
    else
        # Fallback to grep/sed if jq is not available
        HELM_VALUES=$(helm get values "${RELEASE_NAME}" -n "${NAMESPACE}" 2>/dev/null)
        UI_HOST=$(echo "${HELM_VALUES}" | grep -A 5 "ingress:" | grep "host:" | head -1 | sed 's/.*host: *//;s/ *$//')
        PROXY_HOST=$(echo "${HELM_VALUES}" | grep -A 5 "ingress:" | grep "proxyHost:" | head -1 | sed 's/.*proxyHost: *//;s/ *$//')
    fi
    
    # Fallback to default values if not found
    UI_HOST=${UI_HOST:-"object-browser.example.com"}
    PROXY_HOST=${PROXY_HOST:-"s3-api.example.com"}
    
    # Detect cluster IP for /etc/hosts instructions
    CLUSTER_IP="127.0.0.1"
    if kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null | grep -q .; then
        NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null | awk '{print $1}')
        if [[ -n "${NODE_IP}" ]]; then
            CLUSTER_IP="${NODE_IP}"
        fi
    fi
    
    echo ""

    # -------------------------------------------------------------------------
    # Success banner with testing instructions
    # -------------------------------------------------------------------------
    echo -e "${BOLD}${GREEN}"
    echo "============================================================================="
    echo "  🎉 DEPLOYMENT SUCCESSFUL!"
    echo "============================================================================="
    echo -e "${NC}"
    echo ""
    
    # -------------------------------------------------------------------------
    # Primary: Ingress-based access (production-like)
    # -------------------------------------------------------------------------
    echo -e "${BOLD}${CYAN}🌐 Normal User Access (via Ingress):${NC}"
    echo ""
    echo -e "${YELLOW}1. Configure DNS/hosts file:${NC}"
    echo ""
    echo -e "   Add these entries to your ${BOLD}/etc/hosts${NC} file (or configure DNS):"
    echo ""
    echo -e "${BOLD}${CYAN}   ${CLUSTER_IP} ${UI_HOST} ${PROXY_HOST}${NC}"
    echo ""
    echo -e "   ${CYAN}On Linux/Mac:${NC} sudo nano /etc/hosts"
    echo -e "   ${CYAN}On Windows:${NC}   notepad C:\\Windows\\System32\\drivers\\etc\\hosts (as Administrator)"
    echo ""
    echo -e "${YELLOW}2. Access the S3 Browser UI:${NC}"
    echo ""
    echo -e "   ${BOLD}UI URL:${NC}          ${GREEN}http://${UI_HOST}${NC}"
    echo ""
    echo -e "${YELLOW}3. Configure the S3 connection in the UI:${NC}"
    echo ""
    echo -e "   ${BOLD}S3 Endpoint:${NC}     ${GREEN}http://${PROXY_HOST}${NC}"
    echo -e "   ${BOLD}Access Key:${NC}      ${GREEN}zippy${NC}"
    echo -e "   ${BOLD}Secret Key:${NC}      ${GREEN}zippy${NC}"
    echo ""
    echo -e "${BOLD}${GREEN}"
    echo "============================================================================="
    echo -e "${NC}"
    echo ""
    
    # -------------------------------------------------------------------------
    # Fallback: Port-forwarding (debugging)
    # -------------------------------------------------------------------------
    echo -e "${BOLD}${YELLOW}🔧 Fallback / Debugging (via Port-Forward):${NC}"
    echo ""
    echo -e "${CYAN}If Ingress is not working, use port-forwarding instead:${NC}"
    echo ""
    echo -e "${YELLOW}1. Set up port forwarding (run in a separate terminal):${NC}"
    echo ""
    echo -e "${BOLD}${CYAN}   kubectl port-forward -n ${NAMESPACE} svc/${RELEASE_NAME}-zgw-posix-browser-ui-svc 8080:80 8081:8081${NC}"
    echo ""
    echo -e "${YELLOW}2. Access the S3 Browser UI:${NC}"
    echo ""
    echo -e "   ${BOLD}UI URL:${NC}          ${GREEN}http://localhost:8080${NC}"
    echo ""
    echo -e "${YELLOW}3. Configure the S3 connection in the UI:${NC}"
    echo ""
    echo -e "   ${BOLD}S3 Endpoint:${NC}     ${GREEN}http://localhost:8081${NC}"
    echo -e "   ${BOLD}Access Key:${NC}      ${GREEN}zippy${NC}"
    echo -e "   ${BOLD}Secret Key:${NC}      ${GREEN}zippy${NC}"
    echo ""
    echo -e "${BOLD}${YELLOW}"
    echo "============================================================================="
    echo -e "${NC}"
    echo ""
    
    # -------------------------------------------------------------------------
    # Additional information
    # -------------------------------------------------------------------------
    echo -e "${CYAN}💡 Tip: The NGINX proxy handles CORS and forwards requests to the zgw-posix${NC}"
    echo -e "${CYAN}   backend. Always use the proxy endpoint (${PROXY_HOST} or localhost:8081)${NC}"
    echo -e "${CYAN}   as your S3 endpoint in the UI.${NC}"
    echo ""
    echo -e "${CYAN}🔍 To view logs:${NC}"
    echo -e "${CYAN}   Backend: kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=zgw-posix -f${NC}"
    echo -e "${CYAN}   UI:      kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/component=browser-ui -c browser-ui -f${NC}"
    echo -e "${CYAN}   Proxy:   kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/component=browser-ui -c cors-proxy -f${NC}"
    echo ""
    
    echo -e "${CYAN}🧹 To cleanup the deployment:${NC}"
    echo -e "${CYAN}   ./scripts/deploy-cluster.sh cleanup${NC}"
    echo ""
}

# -----------------------------------------------------------------------------
# Main script logic - Parse arguments
# -----------------------------------------------------------------------------
ACTION="${1:-deploy}"
shift || true  # Remove first argument, ignore error if no args

# Parse optional flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --registry)
            REGISTRY_SERVER="$2"
            shift 2
            ;;
        --uname)
            REGISTRY_USERNAME="$2"
            shift 2
            ;;
        --password)
            REGISTRY_PASSWORD="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}${BOLD}Error: Unknown option '$1'${NC}"
            echo ""
            echo "Usage: $0 [deploy|cleanup] [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --registry <server>    Container registry server (default: cp.stg.icr.io)"
            echo "  --uname <username>     Registry username"
            echo "  --password <password>  Registry password"
            exit 1
            ;;
    esac
done

# Execute action
case "${ACTION}" in
    deploy)
        deploy_stack
        ;;
    cleanup)
        cleanup_deployment
        ;;
    *)
        echo -e "${RED}${BOLD}Error: Invalid action '${ACTION}'${NC}"
        echo ""
        echo "Usage: $0 [deploy|cleanup] [OPTIONS]"
        echo ""
        echo "Actions:"
        echo "  deploy  - Deploy the zgw-posix stack (default)"
        echo "  cleanup - Remove the zgw-posix stack"
        echo ""
        echo "Options:"
        echo "  --registry <server>    Container registry server (default: cp.stg.icr.io)"
        echo "  --uname <username>     Registry username"
        echo "  --password <password>  Registry password"
        exit 1
        ;;
esac
