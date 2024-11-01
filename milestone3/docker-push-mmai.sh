#!/bin/bash

# Define registry URL and port
REGISTRY_URL="localhost:5000"

# Check if registry is running
if ! docker ps --filter "name=registry" --format "{{.Ports}}" | grep -q "$REGISTRY_URL"; then
    echo "Docker registry not running on $REGISTRY_URL. Starting registry..."
    docker run -d -p 5000:5000 --name registry registry:2
else
    echo "Docker registry is already running on $REGISTRY_URL."
fi

# Get list of Docker images
images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -v '<none>')

if [[ -z "$images" ]]; then
    echo "No Docker images found to push."
    exit 0
fi

# Loop through images and push them to localhost registry
for image in $images; do
    # Tag the image with the localhost registry prefix
    tagged_image="${REGISTRY_URL}/${image}"
    docker tag "$image" "$tagged_image"

    # Push the image to the localhost registry
    echo "Pushing $tagged_image to $REGISTRY_URL..."
    docker push "$tagged_image"

    # Optionally, remove the tagged image to keep things clean
    docker rmi "$tagged_image"
done

echo "All images have been pushed to $REGISTRY_URL."

# Check if dist/ directory exists and install .tgz charts with Helm
if [[ -d "dist" ]]; then
    echo "Installing Helm charts from dist/ directory..."
    for chart in dist/*.tgz; do
        if [[ -f "$chart" ]]; then
            chart_name=$(basename "$chart" .tgz)
            echo "Installing Helm chart $chart_name with image.repository override..."
            helm install "$chart_name" "$chart" --set image.repository="$REGISTRY_URL"
        fi
    done
else
    echo "No dist/ directory found. Skipping Helm installation."
fi