#!/bin/bash
# Script to restart all API containers in correct order

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if a container is running
check_container_status() {
    local container_name=$1
    local status=$(podman inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null)
    
    if [ "$status" = "running" ]; then
        return 0
    else
        return 1
    fi
}

# Function to get container logs
get_container_logs() {
    local container_name=$1
    echo -e "${YELLOW}Last few lines of logs for $container_name:${NC}"
    podman logs --tail 10 "$container_name"
}

# Function to stop a container
stop_container() {
    local container_name=$1
    echo -e "${YELLOW}Stopping $container_name...${NC}"
    podman stop "$container_name" >/dev/null 2>&1
    sleep 2
}

# Function to start a container and verify it's running
start_container() {
    local container_name=$1
    local max_retries=3
    local retry_count=0
    echo -e "${YELLOW}Starting $container_name...${NC}"
    
    while [ $retry_count -lt $max_retries ]; do
        podman start "$container_name" >/dev/null 2>&1
        
        # Wait for container to start (with timeout)
        local wait_count=0
        while [ $wait_count -lt 10 ]; do
            if check_container_status "$container_name"; then
                echo -e "${GREEN}✓ Successfully started $container_name${NC}"
                return 0
            fi
            sleep 1
            ((wait_count++))
        done
        
        # If container failed to start, get logs
        get_container_logs "$container_name"
        
        ((retry_count++))
        if [ $retry_count -lt $max_retries ]; then
            echo -e "${YELLOW}Retrying to start $container_name (attempt $retry_count of $max_retries)${NC}"
        fi
    done
    
    echo -e "${RED}✗ Failed to start $container_name after $max_retries attempts${NC}"
    return 1
}

# Function to check if container exists
container_exists() {
    local container_name=$1
    podman container exists "$container_name"
    return $?
}

# Function to restart a service group
restart_service() {
    local service_name=$1
    local port=$2
    
    echo -e "\n${YELLOW}Restarting $service_name service...${NC}"
    
    # Find the infra container for this service
    local INFRA_CONTAINER=$(podman ps -a --format "{{if eq .Ports \"0.0.0.0:$port->$port/tcp\"}}{{.Names}}{{end}}" | grep -E ".*-infra$")
    if [ -z "$INFRA_CONTAINER" ]; then
        echo -e "${RED}Error: Could not find infrastructure container for port $port${NC}"
        return 1
    fi
    
    # Define containers for this service
    local containers=(
        "$INFRA_CONTAINER"
        "$service_name-container"
        "$service_name-nginx"
    )
    
    # Verify all containers exist
    for container in "${containers[@]}"; do
        if ! container_exists "$container"; then
            echo -e "${RED}Error: Container $container does not exist${NC}"
            return 1
        fi
    done
    
    # Stop containers in reverse order
    for ((i=${#containers[@]}-1; i>=0; i--)); do
        stop_container "${containers[i]}"
    done
    
    # Prune logs for this service
    echo -e "${YELLOW}Pruning logs for $service_name containers...${NC}"
    for container in "${containers[@]}"; do
        podman logs --truncate 0 "$container" >/dev/null 2>&1
    done
    
    # Start containers in order
    for container in "${containers[@]}"; do
        if ! start_container "$container"; then
            echo -e "${RED}Error: Failed to start $container. Stopping script.${NC}"
            get_container_logs "$container"
            return 1
        fi
        sleep 5
    done
    
    return 0
}

# Main script
echo "Starting service restart process..."

# Array of services and their ports
declare -A services
services=(
    ["signsanctum"]="1443"
    ["signportal"]="8443"
    ["mintrootapi"]="6443"
    ["mintserverapi"]="2443"
    ["mintclientapi"]="4443"
    ["servertestapi"]="3443"
    ["clienttestapi"]="3444"
)

# Restart each service
all_successful=true
for service in "${!services[@]}"; do
    if ! restart_service "$service" "${services[$service]}"; then
        all_successful=false
        echo -e "${RED}Failed to restart $service service${NC}"
    fi
done

# Final status report
echo -e "\n${YELLOW}Final status report:${NC}"
for service in "${!services[@]}"; do
    echo -e "\n${YELLOW}$service service containers:${NC}"
    INFRA_CONTAINER=$(podman ps -a --format "{{if eq .Ports \"0.0.0.0:${services[$service]}->${services[$service]}/tcp\"}}{{.Names}}{{end}}" | grep -E ".*-infra$")
    containers=(
        "$INFRA_CONTAINER"
        "$service-container"
        "$service-nginx"
    )
    
    for container in "${containers[@]}"; do
        if check_container_status "$container"; then
            echo -e "${GREEN}✓ $container is running${NC}"
        else
            echo -e "${RED}✗ $container is not running${NC}"
            get_container_logs "$container"
            all_successful=false
        fi
    done
done

if [ "$all_successful" = true ]; then
    echo -e "\n${GREEN}All services restarted successfully!${NC}"
    echo -e "Services should now be accessible on their respective ports:"
    for service in "${!services[@]}"; do
        echo -e "${GREEN}$service: ${services[$service]}${NC}"
    done
    exit 0
else
    echo -e "\n${RED}Some services failed to restart. Please check the logs for more information.${NC}"
    exit 1
fi
